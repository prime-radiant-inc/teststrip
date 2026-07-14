import Foundation

public struct IngestProgress: Equatable, Sendable {
    public var completedUnitCount: Int
    public var totalUnitCount: Int
    public var originalURL: URL
    public var catalogedAssetIDs: [AssetID]

    public init(
        completedUnitCount: Int,
        totalUnitCount: Int,
        originalURL: URL,
        catalogedAssetIDs: [AssetID] = []
    ) {
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.originalURL = originalURL
        self.catalogedAssetIDs = catalogedAssetIDs
    }
}

public typealias IngestProgressHandler = @Sendable (IngestProgress) -> Void

public struct IngestSkippedSourceFile: Equatable, Sendable {
    public var sourceURL: URL
    public var message: String

    public init(sourceURL: URL, message: String) {
        self.sourceURL = sourceURL
        self.message = message
    }
}

public typealias IngestSkippedSourceFileHandler = (IngestSkippedSourceFile) -> Void

public struct IngestService: Sendable {
    private static let eagerCatalogPersistenceLimit = 10
    private static let catalogPersistenceBatchSize = 500
    // A copy import must never run a destination volume to exactly zero; this
    // margin keeps headroom for the SQLite catalog and other system writes.
    private static let spaceSafetyMarginBytes: Int64 = 256 * 1024 * 1024

    public var scanner: FolderScanner
    public var decodeRegistry: DecodeRegistry?
    public var contentHasher: @Sendable (URL) throws -> String
    public var availableCapacityForImportantUsage: @Sendable (URL) -> Int64?

    public init(
        scanner: FolderScanner,
        decodeRegistry: DecodeRegistry? = nil,
        contentHasher: @escaping @Sendable (URL) throws -> String = { try ContentHash.compute(forFileAt: $0) },
        availableCapacityForImportantUsage: @escaping @Sendable (URL) -> Int64? = { url in
            (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                .volumeAvailableCapacityForImportantUsage
        }
    ) {
        self.scanner = scanner
        self.decodeRegistry = decodeRegistry
        self.contentHasher = contentHasher
        self.availableCapacityForImportantUsage = availableCapacityForImportantUsage
    }

    public func files(
        for plan: IngestPlan,
        progress: FolderScanProgressHandler? = nil,
        skipped: FolderScanSkippedFileHandler? = nil
    ) throws -> [URL] {
        try Task.checkCancellation()
        try validate(plan: plan)
        return try scanner.scan(root: plan.sourceRoot, progress: progress, skipped: skipped)
    }

    public func ingest(plan: IngestPlan, repository: CatalogRepository) throws -> [Asset] {
        let sourceFiles = try files(for: plan)
        return try ingest(files: sourceFiles, plan: plan, repository: repository)
    }

    public func ingest(
        files sourceFiles: [URL],
        plan: IngestPlan,
        repository: CatalogRepository,
        skippedSourceFile: IngestSkippedSourceFileHandler? = nil,
        secondCopyFailure: IngestSkippedSourceFileHandler? = nil,
        alreadyInCatalog: IngestSkippedSourceFileHandler? = nil,
        progress: IngestProgressHandler? = nil
    ) throws -> [Asset] {
        try validate(plan: plan)
        try validateAvailableSpace(sourceFiles: sourceFiles, plan: plan)
        var assets: [Asset] = []
        var pendingCatalogAssets: [Asset] = []
        var importedSidecars: [ImportedSidecarSync] = []
        var sidecarConflicts: [SidecarSyncConflict] = []
        var claimedDestinationPaths: Set<String> = []
        // Assets can sit unflushed past the eager persistence limit, so a
        // catalog lookup alone misses in-run claims; identical duplicates of
        // one destination path must reuse the pending asset ID or the flush
        // violates the unique original_path index.
        var assetIDsByClaimedPath: [String: AssetID] = [:]
        // Content already accepted earlier in this same batch, keyed by content
        // hash to the source file that carried it, so a shot appearing twice on
        // one card collapses even before the first copy is flushed to catalog.
        var acceptedContentSources: [String: URL] = [:]
        let sidecarStore = XMPSidecarStore()
        for (sourceIndex, sourceFile) in sourceFiles.enumerated() {
            try Task.checkCancellation()
            do {
                let originalURL = try originalURL(for: sourceFile, plan: plan)
                // Dedup must decide before any copy, so it hashes the source
                // itself. Import-all needs no such decision and lets the
                // fingerprint hash the finished original instead.
                var sourceContentHash: String?
                if plan.duplicateHandling == .skipCatalogedContent {
                    let hash = try contentHash(for: sourceFile)
                    sourceContentHash = hash
                    if try isAlreadyInCatalog(
                        sourceFile: sourceFile,
                        contentHash: hash,
                        acceptedContentSources: acceptedContentSources,
                        repository: repository
                    ) {
                        alreadyInCatalog?(IngestSkippedSourceFile(
                            sourceURL: sourceFile,
                            message: "already in catalog"
                        ))
                        progress?(IngestProgress(
                            completedUnitCount: sourceIndex + 1,
                            totalUnitCount: sourceFiles.count,
                            originalURL: sourceFile
                        ))
                        continue
                    }
                }
                let existingAsset = try repository.asset(originalURL: originalURL)
                let assetID = existingAsset?.id ?? assetIDsByClaimedPath[originalURL.path] ?? .new()
                if plan.mode == .copyToDestination,
                   !claimedDestinationPaths.insert(originalURL.path).inserted,
                   !FileManager.default.contentsEqual(atPath: sourceFile.path, andPath: originalURL.path) {
                    throw TeststripError.io("ingest destination already exists \(originalURL.path)")
                }
                assetIDsByClaimedPath[originalURL.path] = assetID
                try prepareOriginalFile(sourceFile: sourceFile, originalURL: originalURL, plan: plan, existingAsset: existingAsset)
                if let secondCopyIssue = secondCopyIssue(for: sourceFile, plan: plan) {
                    secondCopyFailure?(secondCopyIssue)
                }
                let fingerprint = try fingerprint(for: originalURL, precomputedContentHash: sourceContentHash)
                var metadata = existingAsset?.metadata ?? AssetMetadata()
                let sidecarURL = sidecarStore.sidecarURL(forOriginalAt: originalURL)
                if FileManager.default.fileExists(atPath: sidecarURL.path) {
                    let sidecarData = try Data(contentsOf: sidecarURL)
                    let sidecarModificationDate = try sidecarStore.modificationDate(forSidecarAt: sidecarURL)
                    let catalogGeneration: Int
                    let lastSynced: MetadataSyncItem?
                    if existingAsset != nil {
                        catalogGeneration = try repository.catalogGeneration(assetID: assetID)
                        lastSynced = try repository.metadataSyncItem(assetID: assetID)
                    } else {
                        catalogGeneration = 1
                        lastSynced = nil
                    }
                    do {
                        let decision = try MetadataSyncPlanner().decision(
                            catalogMetadata: metadata,
                            catalogGeneration: catalogGeneration,
                            lastSynced: lastSynced,
                            sidecarData: sidecarData,
                            sidecarModificationDate: sidecarModificationDate
                        )
                        if case .importSidecar(let sidecarMetadata) = decision {
                            metadata = metadata.mergingConfirmedSidecar(sidecarMetadata)
                            importedSidecars.append(ImportedSidecarSync(
                                assetID: assetID,
                                sidecarURL: sidecarURL,
                                sidecarData: sidecarData
                            ))
                        } else if case .conflict = decision {
                            sidecarConflicts.append(SidecarSyncConflict(
                                assetID: assetID,
                                sidecarURL: sidecarURL,
                                catalogGeneration: catalogGeneration,
                                lastSyncedFingerprint: try repository.lastMetadataSyncFingerprint(assetID: assetID)
                            ))
                        }
                    } catch {
                        // An unparsable sidecar must not abort the whole
                        // import: catalog the asset with its catalog metadata
                        // and route the sidecar into XMP Conflicts review,
                        // mirroring the worker sync path. Unrelated failures
                        // keep their current handling.
                        guard (try? XMPPacket.parse(sidecarData)) == nil else {
                            throw error
                        }
                        sidecarConflicts.append(SidecarSyncConflict(
                            assetID: assetID,
                            sidecarURL: sidecarURL,
                            catalogGeneration: catalogGeneration,
                            lastSyncedFingerprint: try repository.lastMetadataSyncFingerprint(assetID: assetID)
                        ))
                    }
                }
                let asset = Asset(
                    id: assetID,
                    originalURL: originalURL,
                    volumeIdentifier: volumeIdentifier(for: originalURL),
                    fingerprint: fingerprint,
                    availability: .online,
                    metadata: metadata,
                    technicalMetadata: technicalMetadata(for: originalURL) ?? existingAsset?.technicalMetadata
                )
                assets.append(asset)
                pendingCatalogAssets.append(asset)
                if let sourceContentHash {
                    acceptedContentSources[sourceContentHash] = sourceFile
                }
                let catalogedAssetIDs = try flushCatalogAssetsIfNeeded(
                    pendingCatalogAssets: &pendingCatalogAssets,
                    importedAssetCount: assets.count,
                    isFinalAsset: sourceIndex == sourceFiles.indices.last,
                    repository: repository
                )
                progress?(IngestProgress(
                    completedUnitCount: sourceIndex + 1,
                    totalUnitCount: sourceFiles.count,
                    originalURL: originalURL,
                    catalogedAssetIDs: catalogedAssetIDs
                ))
            } catch TeststripError.io(let message) {
                guard let skippedSourceFile else {
                    throw TeststripError.io(message)
                }
                skippedSourceFile(IngestSkippedSourceFile(sourceURL: sourceFile, message: message))
            }
        }
        _ = try flushCatalogAssets(&pendingCatalogAssets, repository: repository)
        for importedSidecar in importedSidecars {
            try repository.markMetadataSynced(
                assetID: importedSidecar.assetID,
                sidecarURL: importedSidecar.sidecarURL,
                catalogGeneration: repository.catalogGeneration(assetID: importedSidecar.assetID),
                fingerprint: XMPSidecarStore.fingerprint(for: importedSidecar.sidecarData)
            )
        }
        for sidecarConflict in sidecarConflicts {
            try repository.recordMetadataSyncConflict(MetadataSyncItem(
                assetID: sidecarConflict.assetID,
                sidecarURL: sidecarConflict.sidecarURL,
                catalogGeneration: sidecarConflict.catalogGeneration,
                lastSyncedFingerprint: sidecarConflict.lastSyncedFingerprint
            ))
        }
        return assets
    }

    private func validate(plan: IngestPlan) throws {
        guard plan.mode == .copyToDestination else { return }
        guard let destinationRoot = plan.destinationRoot else {
            throw TeststripError.invalidState("copy ingest requires destination root")
        }
        if let blockingReason = CardImportDestinationPreflight.blockingReason(
            source: plan.sourceRoot,
            destinationRoot: destinationRoot
        ) {
            throw TeststripError.invalidState(blockingReason)
        }
        if let secondCopyDestination = plan.secondCopyDestination,
           let blockingReason = CardImportDestinationPreflight.secondCopyBlockingReason(
               source: plan.sourceRoot,
               destinationRoot: destinationRoot,
               secondCopyDestination: secondCopyDestination
           ) {
            throw TeststripError.invalidState(blockingReason)
        }
    }

    // A copy import that runs its destination volume out of space mid-copy can
    // brick the app: once the volume hits zero free bytes, the SQLite catalog
    // can no longer even open. Checking every source file's size against the
    // destination's free space before the first byte is copied fails fast
    // instead, so a full card never leaves a half-copied import behind.
    private func validateAvailableSpace(sourceFiles: [URL], plan: IngestPlan) throws {
        guard plan.mode == .copyToDestination, let destinationRoot = plan.destinationRoot else { return }
        let requiredBytes = requiredBytes(for: sourceFiles)
        try validateVolumeHasRoom(requiredBytes: requiredBytes, destination: destinationRoot)
        if let secondCopyDestination = plan.secondCopyDestination {
            try validateVolumeHasRoom(requiredBytes: requiredBytes, destination: secondCopyDestination)
        }
    }

    // An upper bound on the bytes a copy import will write: dedup may skip
    // some source files, but never more than this, so this sum is always
    // safe to check against free space. An unreadable size counts as zero
    // rather than aborting the preflight itself.
    private func requiredBytes(for sourceFiles: [URL]) -> Int64 {
        sourceFiles.reduce(into: Int64(0)) { total, sourceFile in
            let size = (try? sourceFile.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
    }

    private func validateVolumeHasRoom(requiredBytes: Int64, destination: URL) throws {
        guard let available = availableCapacityForImportantUsage(destination) else { return }
        guard available >= requiredBytes + Self.spaceSafetyMarginBytes else {
            let volumeName = (try? destination.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
                ?? destination.lastPathComponent
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let requiredText = formatter.string(fromByteCount: requiredBytes)
            let availableText = formatter.string(fromByteCount: available)
            throw TeststripError.io(
                "Not enough space to import: needs about \(requiredText) on \(volumeName), only \(availableText) free. "
                    + "Free space or choose a different destination."
            )
        }
    }

    private func flushCatalogAssetsIfNeeded(
        pendingCatalogAssets: inout [Asset],
        importedAssetCount: Int,
        isFinalAsset: Bool,
        repository: CatalogRepository
    ) throws -> [AssetID] {
        guard isFinalAsset
            || importedAssetCount <= Self.eagerCatalogPersistenceLimit
            || pendingCatalogAssets.count >= Self.catalogPersistenceBatchSize else {
            return []
        }
        return try flushCatalogAssets(&pendingCatalogAssets, repository: repository)
    }

    private func flushCatalogAssets(
        _ pendingCatalogAssets: inout [Asset],
        repository: CatalogRepository
    ) throws -> [AssetID] {
        guard !pendingCatalogAssets.isEmpty else { return [] }
        let catalogedAssetIDs = pendingCatalogAssets.map(\.id)
        try repository.upsert(pendingCatalogAssets)
        pendingCatalogAssets.removeAll(keepingCapacity: true)
        return catalogedAssetIDs
    }

    func originalURL(for sourceFile: URL, plan: IngestPlan) throws -> URL {
        switch plan.mode {
        case .addInPlace:
            return sourceFile
        case .copyToDestination:
            guard let destinationRoot = plan.destinationRoot else {
                throw TeststripError.invalidState("copy ingest requires destination root")
            }
            return try destinationURL(for: sourceFile, plan: plan, destinationRoot: destinationRoot)
        }
    }

    private func destinationURL(for sourceFile: URL, plan: IngestPlan, destinationRoot: URL) throws -> URL {
        switch plan.destinationPolicy {
        case .flat:
            return try flatDestinationURL(for: sourceFile, sourceRoot: plan.sourceRoot, destinationRoot: destinationRoot)
        case .capturedDate:
            try validateSourceFileInsideRoot(sourceFile, sourceRoot: plan.sourceRoot)
            let destinationDate = try destinationDate(for: sourceFile)
            let folderNames = Self.capturedDateFolderNames(for: destinationDate.date, in: destinationDate.timeZone)
            return destinationRoot
                .appendingPathComponent(folderNames.year, isDirectory: true)
                .appendingPathComponent(folderNames.day, isDirectory: true)
                .appendingPathComponent(sourceFile.lastPathComponent)
        }
    }

    // Prefers the capture date from the existing decode metadata path (EXIF
    // DateTimeOriginal, falling back to TIFF DateTime inside the provider) and
    // falls back to the file modification date when no capture date is readable,
    // matching the fingerprint's modification-date handling. Each date carries
    // the time zone that recovers its wall-clock day: EXIF strings have no
    // timezone and are parsed as GMT, so GMT round-trips the camera's own date
    // string; a modification date is a real instant, so the user's local zone
    // yields the day they saw when the file was made.
    private func destinationDate(for sourceFile: URL) throws -> (date: Date, timeZone: TimeZone) {
        if let decodeRegistry,
           let provider = try? decodeRegistry.provider(for: sourceFile),
           let metadata = try? provider.metadata(for: sourceFile),
           let capturedAt = metadata.capturedAt {
            return (capturedAt, TimeZone(secondsFromGMT: 0) ?? .current)
        }
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: sourceFile.path)
        } catch {
            throw TeststripError.io("could not read modification date for \(sourceFile.path): \(error.localizedDescription)")
        }
        return (attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0), .current)
    }

    static func capturedDateFolderNames(for date: Date, in timeZone: TimeZone) -> (year: String, day: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 1970
        let month = components.month ?? 1
        let day = components.day ?? 1
        return (
            year: String(format: "%04d", year),
            day: String(format: "%04d-%02d-%02d", year, month, day)
        )
    }

    private func prepareOriginalFile(
        sourceFile: URL,
        originalURL: URL,
        plan: IngestPlan,
        existingAsset: Asset?
    ) throws {
        switch plan.mode {
        case .addInPlace:
            return
        case .copyToDestination:
            // A cataloged destination only counts as already imported when the
            // bytes match the source; a distinct file colliding with it must
            // surface as a conflict, never a silent drop.
            if existingAsset != nil,
               FileManager.default.fileExists(atPath: originalURL.path),
               FileManager.default.contentsEqual(atPath: sourceFile.path, andPath: originalURL.path) {
                return
            }
            try copyOriginalFile(from: sourceFile, to: originalURL)
        }
    }

    private func copyOriginalFile(from sourceFile: URL, to destinationURL: URL) throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            guard FileManager.default.contentsEqual(atPath: sourceFile.path, andPath: destinationURL.path) else {
                throw TeststripError.io("ingest destination already exists \(destinationURL.path)")
            }
            try copyAdjacentSidecar(sourceFile: sourceFile, originalURL: destinationURL)
            return
        }

        let destinationDirectory = destinationURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        } catch {
            throw TeststripError.io("could not create ingest directory \(destinationDirectory.path): \(error.localizedDescription)")
        }
        do {
            try FileManager.default.copyItem(at: sourceFile, to: destinationURL)
        } catch {
            throw TeststripError.io("could not copy \(sourceFile.path) to \(destinationURL.path): \(error.localizedDescription)")
        }
        try copyAdjacentSidecar(sourceFile: sourceFile, originalURL: destinationURL)
    }

    // Backup failures never fail the primary import; they surface per file
    // through the second-copy failure handler instead.
    private func secondCopyIssue(for sourceFile: URL, plan: IngestPlan) -> IngestSkippedSourceFile? {
        guard plan.mode == .copyToDestination, let secondCopyDestination = plan.secondCopyDestination else {
            return nil
        }
        do {
            let backupURL = try destinationURL(for: sourceFile, plan: plan, destinationRoot: secondCopyDestination)
            try copyOriginalFile(from: sourceFile, to: backupURL)
            return nil
        } catch TeststripError.io(let message) {
            return IngestSkippedSourceFile(sourceURL: sourceFile, message: "backup copy failed: \(message)")
        } catch {
            return IngestSkippedSourceFile(sourceURL: sourceFile, message: "backup copy failed: \(error.localizedDescription)")
        }
    }

    private func copyAdjacentSidecar(sourceFile: URL, originalURL: URL) throws {
        let sidecarStore = XMPSidecarStore()
        let sourceSidecarURL = sidecarStore.sidecarURL(forOriginalAt: sourceFile)
        guard FileManager.default.fileExists(atPath: sourceSidecarURL.path) else {
            return
        }

        let destinationSidecarURL = sidecarStore.sidecarURL(forOriginalAt: originalURL)
        if FileManager.default.fileExists(atPath: destinationSidecarURL.path) {
            guard FileManager.default.contentsEqual(atPath: sourceSidecarURL.path, andPath: destinationSidecarURL.path) else {
                throw TeststripError.io("ingest sidecar destination already exists \(destinationSidecarURL.path)")
            }
            return
        }
        do {
            try FileManager.default.copyItem(at: sourceSidecarURL, to: destinationSidecarURL)
        } catch {
            throw TeststripError.io("could not copy \(sourceSidecarURL.path) to \(destinationSidecarURL.path): \(error.localizedDescription)")
        }
    }

    private func flatDestinationURL(for sourceFile: URL, sourceRoot: URL, destinationRoot: URL) throws -> URL {
        let relativePath = try validateSourceFileInsideRoot(sourceFile, sourceRoot: sourceRoot)
        return destinationRoot.appendingPathComponent(relativePath)
    }

    @discardableResult
    private func validateSourceFileInsideRoot(_ sourceFile: URL, sourceRoot: URL) throws -> String {
        let sourceRootPath = sourceRoot.resolvingSymlinksInPath().path
        let sourceFilePath = sourceFile.resolvingSymlinksInPath().path
        let sourceRootPrefix = sourceRootPath == "/" ? sourceRootPath : sourceRootPath + "/"
        guard sourceFilePath.hasPrefix(sourceRootPrefix) else {
            throw TeststripError.io("source file \(sourceFile.path) is outside ingest root \(sourceRoot.path)")
        }
        return String(sourceFilePath.dropFirst(sourceRootPrefix.count))
    }

    // Reads attributes before hashing so a file that vanished mid-import is
    // reported as a fingerprint failure, not a hash failure. When the dedup
    // pass already hashed the source, that hash is reused; copy imports produce
    // byte-identical originals, so the source and destination hashes match.
    private func fingerprint(for url: URL, precomputedContentHash: String?) throws -> FileFingerprint {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw TeststripError.io("could not fingerprint \(url.path): \(error.localizedDescription)")
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        let contentHash = try precomputedContentHash ?? contentHash(for: url)
        return FileFingerprint(size: size, modificationDate: modificationDate, contentHash: contentHash)
    }

    private func contentHash(for url: URL) throws -> String {
        do {
            return try contentHasher(url)
        } catch let error as TeststripError {
            throw error
        } catch {
            throw TeststripError.io("could not hash \(url.path): \(error.localizedDescription)")
        }
    }

    // A source file is already in the catalog when its content matches either a
    // file accepted earlier in this same batch or a previously cataloged asset.
    // The bounded content hash narrows the candidate; an exact byte comparison
    // confirms it before any copy is skipped, so a partial-hash collision can
    // never silently drop a distinct file. When the matched cataloged original
    // is unreachable (an offline drive) the byte comparison is impossible, so
    // the content hash is trusted — re-inserting a card still skips.
    private func isAlreadyInCatalog(
        sourceFile: URL,
        contentHash: String,
        acceptedContentSources: [String: URL],
        repository: CatalogRepository
    ) throws -> Bool {
        guard !contentHash.isEmpty else { return false }
        if let batchTwin = acceptedContentSources[contentHash],
           FileManager.default.contentsEqual(atPath: sourceFile.path, andPath: batchTwin.path) {
            return true
        }
        guard let catalogedTwin = try repository.asset(contentHash: contentHash) else {
            return false
        }
        let catalogedPath = catalogedTwin.originalURL.path
        guard FileManager.default.fileExists(atPath: catalogedPath) else {
            return true
        }
        return FileManager.default.contentsEqual(atPath: sourceFile.path, andPath: catalogedPath)
    }

    private func volumeIdentifier(for url: URL) -> String? {
        guard let identifier = try? url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier else {
            return nil
        }
        if let data = identifier as? Data {
            return data.base64EncodedString()
        }
        if let data = identifier as? NSData {
            return data.base64EncodedString()
        }
        if let string = identifier as? String {
            return string
        }
        return String(describing: identifier)
    }

    private func technicalMetadata(for url: URL) -> AssetTechnicalMetadata? {
        guard let decodeRegistry,
              let provider = try? decodeRegistry.provider(for: url),
              let metadata = try? provider.metadata(for: url) else {
            return nil
        }
        return metadata.assetTechnicalMetadata
    }

    /// Re-reads technical metadata (including GPS coordinates) from an online
    /// original for the Task-10 backfill. Read-only; returns nil when the file
    /// is unavailable or the decode fails, so a per-asset miss is skippable
    /// rather than fatal.
    public func reReadTechnicalMetadata(for url: URL) -> AssetTechnicalMetadata? {
        technicalMetadata(for: url)
    }
}

private struct ImportedSidecarSync {
    var assetID: AssetID
    var sidecarURL: URL
    var sidecarData: Data
}

private struct SidecarSyncConflict {
    var assetID: AssetID
    var sidecarURL: URL
    var catalogGeneration: Int
    var lastSyncedFingerprint: String?
}
