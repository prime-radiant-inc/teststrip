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

    public var scanner: FolderScanner
    public var decodeRegistry: DecodeRegistry?

    public init(scanner: FolderScanner, decodeRegistry: DecodeRegistry? = nil) {
        self.scanner = scanner
        self.decodeRegistry = decodeRegistry
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
        progress: IngestProgressHandler? = nil
    ) throws -> [Asset] {
        try validate(plan: plan)
        var assets: [Asset] = []
        var pendingCatalogAssets: [Asset] = []
        var importedSidecars: [ImportedSidecarSync] = []
        var sidecarConflicts: [SidecarSyncConflict] = []
        let sidecarStore = XMPSidecarStore()
        for (sourceIndex, sourceFile) in sourceFiles.enumerated() {
            try Task.checkCancellation()
            do {
                let originalURL = try originalURL(for: sourceFile, plan: plan)
                let existingAsset = try repository.asset(originalURL: originalURL)
                let assetID = existingAsset?.id ?? .new()
                try prepareOriginalFile(sourceFile: sourceFile, originalURL: originalURL, plan: plan, existingAsset: existingAsset)
                let fingerprint = try fingerprint(for: originalURL)
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
                    let decision = try MetadataSyncPlanner().decision(
                        catalogMetadata: metadata,
                        catalogGeneration: catalogGeneration,
                        lastSynced: lastSynced,
                        sidecarData: sidecarData,
                        sidecarModificationDate: sidecarModificationDate
                    )
                    if case .importSidecar(let sidecarMetadata) = decision {
                        metadata = sidecarMetadata
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
            return try destinationURL(for: sourceFile, sourceRoot: plan.sourceRoot, destinationRoot: destinationRoot)
        }
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
            if FileManager.default.fileExists(atPath: originalURL.path) {
                if existingAsset != nil {
                    return
                }
                guard FileManager.default.contentsEqual(atPath: sourceFile.path, andPath: originalURL.path) else {
                    throw TeststripError.io("ingest destination already exists \(originalURL.path)")
                }
                try copyAdjacentSidecar(sourceFile: sourceFile, originalURL: originalURL)
                return
            }

            let destinationDirectory = originalURL.deletingLastPathComponent()
            do {
                try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            } catch {
                throw TeststripError.io("could not create ingest directory \(destinationDirectory.path): \(error.localizedDescription)")
            }
            do {
                try FileManager.default.copyItem(at: sourceFile, to: originalURL)
            } catch {
                throw TeststripError.io("could not copy \(sourceFile.path) to \(originalURL.path): \(error.localizedDescription)")
            }
            try copyAdjacentSidecar(sourceFile: sourceFile, originalURL: originalURL)
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

    private func destinationURL(for sourceFile: URL, sourceRoot: URL, destinationRoot: URL) throws -> URL {
        let sourceRootPath = sourceRoot.resolvingSymlinksInPath().path
        let sourceFilePath = sourceFile.resolvingSymlinksInPath().path
        let sourceRootPrefix = sourceRootPath == "/" ? sourceRootPath : sourceRootPath + "/"
        guard sourceFilePath.hasPrefix(sourceRootPrefix) else {
            throw TeststripError.io("source file \(sourceFile.path) is outside ingest root \(sourceRoot.path)")
        }

        let relativePath = String(sourceFilePath.dropFirst(sourceRootPrefix.count))
        return destinationRoot.appendingPathComponent(relativePath)
    }

    private func fingerprint(for url: URL) throws -> FileFingerprint {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw TeststripError.io("could not fingerprint \(url.path): \(error.localizedDescription)")
        }
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modificationDate = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        return FileFingerprint(size: size, modificationDate: modificationDate)
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
