import Foundation

public struct LibraryPreviewFailure: Equatable, Sendable {
    public var assetID: AssetID
    public var sourceURL: URL
    public var message: String

    public init(assetID: AssetID, sourceURL: URL, message: String) {
        self.assetID = assetID
        self.sourceURL = sourceURL
        self.message = message
    }
}

public struct LibrarySkippedSourceFile: Codable, Equatable, Sendable {
    // A skipped file never made it into the catalog; a failed backup belongs
    // to a fully imported photo whose second copy is missing. Conflating the
    // two makes import summaries report imported photos as skipped.
    public enum Kind: String, Codable, Sendable {
        case skipped
        case backupFailed
    }

    public var sourceURL: URL
    public var message: String
    public var kind: Kind

    public init(sourceURL: URL, message: String, kind: Kind = .skipped) {
        self.sourceURL = sourceURL
        self.message = message
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceURL = try container.decode(URL.self, forKey: .sourceURL)
        message = try container.decode(String.self, forKey: .message)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .skipped
    }
}

public struct LibraryImportResult: Sendable {
    public var importedAssets: [Asset]
    public var previewFailures: [LibraryPreviewFailure]
    public var skippedSourceFiles: [LibrarySkippedSourceFile]
    public var skippedSourceFileCount: Int
    public var backupFailureCount: Int
    public var newAssetCount: Int
    public var existingAssetCount: Int

    public init(
        importedAssets: [Asset],
        previewFailures: [LibraryPreviewFailure],
        skippedSourceFiles: [LibrarySkippedSourceFile] = [],
        skippedSourceFileCount: Int? = nil,
        newAssetCount: Int? = nil,
        existingAssetCount: Int = 0
    ) {
        self.importedAssets = importedAssets
        self.previewFailures = previewFailures
        self.skippedSourceFiles = skippedSourceFiles
        self.skippedSourceFileCount = skippedSourceFileCount
            ?? skippedSourceFiles.filter { $0.kind == .skipped }.count
        self.backupFailureCount = skippedSourceFiles.filter { $0.kind == .backupFailed }.count
        self.newAssetCount = newAssetCount ?? max(importedAssets.count - existingAssetCount, 0)
        self.existingAssetCount = existingAssetCount
    }
}

public struct LibraryPreviewGenerationResult: Sendable {
    public var generatedCount: Int
    public var previewFailures: [LibraryPreviewFailure]

    public init(generatedCount: Int, previewFailures: [LibraryPreviewFailure]) {
        self.generatedCount = generatedCount
        self.previewFailures = previewFailures
    }
}

public enum LibraryImportPreviewPolicy: Equatable, Sendable {
    case generateImmediately
    case deferGeneration
}

public struct LibraryImportProgress: Equatable, Sendable {
    public var completedUnitCount: Int
    public var totalUnitCount: Int?
    public var detail: String
    public var catalogedAssetIDs: [AssetID]

    public init(
        completedUnitCount: Int,
        totalUnitCount: Int?,
        detail: String,
        catalogedAssetIDs: [AssetID] = []
    ) {
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.detail = detail
        self.catalogedAssetIDs = catalogedAssetIDs
    }
}

public typealias LibraryImportProgressHandler = @Sendable (LibraryImportProgress) -> Void

public struct LibraryImportService: Sendable {
    private static let scanProgressInterval = 100
    private static let ingestProgressInterval = 500
    private static let eagerIngestProgressLimit = 10
    // Comfortably under WorkerSupervisor's 120s per-command watchdog (~8x
    // margin) so a healthy, progressing scan/import always feeds it, even
    // when the count-based coalescing above stays quiet for a slow phase
    // (e.g. copying files off a card).
    private static let scanProgressHeartbeat: TimeInterval = 15
    private static let ingestProgressHeartbeat: TimeInterval = 15
    private static let importPreviewLevels: [PreviewLevel] = [.grid]

    public var ingestService: IngestService
    public var previewCache: PreviewCache
    public var renderer: PreviewRenderer

    public init(
        ingestService: IngestService,
        previewCache: PreviewCache,
        renderer: PreviewRenderer = PreviewRenderer()
    ) {
        self.ingestService = ingestService
        self.previewCache = previewCache
        self.renderer = renderer
    }

    public func addFolderInPlace(
        _ root: URL,
        repository: CatalogRepository,
        previewPolicy: LibraryImportPreviewPolicy,
        duplicateHandling: DuplicateHandling = .importAll,
        selectedFiles: Set<URL>? = nil,
        preIngestThumbnailCache: PreIngestThumbnailCache? = nil,
        progress: LibraryImportProgressHandler? = nil
    ) throws -> LibraryImportResult {
        try importAssets(
            plan: IngestPlanner.addFolder(root, duplicateHandling: duplicateHandling),
            scanRootName: root.lastPathComponent,
            catalogingDetail: { "Cataloging \(Self.photoCountDescription($0))" },
            perFileDetail: { completed, total in "Cataloging \(completed) of \(total) photos" },
            catalogedDetail: { "Cataloged \(Self.photoCountDescription($0))" },
            repository: repository,
            previewPolicy: previewPolicy,
            selectedFiles: selectedFiles,
            preIngestThumbnailCache: preIngestThumbnailCache,
            progress: progress
        )
    }

    public func copyFromCard(
        source: URL,
        destinationRoot: URL,
        destinationPolicy: ImportDestinationPolicy = .flat,
        secondCopyDestination: URL? = nil,
        repository: CatalogRepository,
        previewPolicy: LibraryImportPreviewPolicy,
        duplicateHandling: DuplicateHandling = .importAll,
        selectedFiles: Set<URL>? = nil,
        preIngestThumbnailCache: PreIngestThumbnailCache? = nil,
        progress: LibraryImportProgressHandler? = nil
    ) throws -> LibraryImportResult {
        try importAssets(
            plan: IngestPlanner.copyFromCard(
                source: source,
                destinationRoot: destinationRoot,
                destinationPolicy: destinationPolicy,
                secondCopyDestination: secondCopyDestination,
                duplicateHandling: duplicateHandling
            ),
            scanRootName: source.lastPathComponent,
            catalogingDetail: { "Copying \(Self.photoCountDescription($0)) to \(destinationRoot.lastPathComponent)" },
            perFileDetail: { completed, total in "Copying \(completed) of \(total) photos to \(destinationRoot.lastPathComponent)" },
            catalogedDetail: { "Copied \(Self.photoCountDescription($0)) to \(destinationRoot.lastPathComponent)" },
            repository: repository,
            previewPolicy: previewPolicy,
            selectedFiles: selectedFiles,
            preIngestThumbnailCache: preIngestThumbnailCache,
            progress: progress
        )
    }

    private func importAssets(
        plan: IngestPlan,
        scanRootName: String,
        catalogingDetail: (Int) -> String,
        perFileDetail: @escaping @Sendable (Int, Int) -> String,
        catalogedDetail: (Int) -> String,
        repository: CatalogRepository,
        previewPolicy: LibraryImportPreviewPolicy,
        selectedFiles: Set<URL>? = nil,
        preIngestThumbnailCache: PreIngestThumbnailCache? = nil,
        progress: LibraryImportProgressHandler?
    ) throws -> LibraryImportResult {
        let _signpost = DevSignpost.begin("importAssets")
        defer { DevSignpost.end(_signpost, "importAssets") }
        try Task.checkCancellation()
        progress?(LibraryImportProgress(
            completedUnitCount: 0,
            totalUnitCount: nil,
            detail: "Scanning \(scanRootName)"
        ))
        let scanProgressCoalescer = ScanProgressCoalescer(
            interval: Self.scanProgressInterval,
            heartbeat: Self.scanProgressHeartbeat
        )
        // Thread-safe buffer for streaming scan → ingest. The scan runs in a
        // background thread and appends files as they're discovered; the main
        // flow polls the buffer and processes batches through ingest, so import
        // starts before the scan finishes.
        let buffer = StreamingScanBuffer()
        let resolvedSelected = selectedFiles.map { selected in
            Set(selected.map { $0.resolvingSymlinksInPath() })
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let allFiles = try self.ingestService.files(
                    for: plan,
                    progress: { scanProgress in
                        buffer.lock.withLock {
                            buffer.scanTotalCount = scanProgress.supportedFileCount
                        }
                        if scanProgressCoalescer.shouldReportScanCount(scanProgress.supportedFileCount) {
                            self.reportScanProgress(
                                count: scanProgress.supportedFileCount,
                                rootName: scanRootName,
                                progress: progress
                            )
                        }
                    },
                    skipped: { scanSkippedFile in
                        buffer.lock.withLock {
                            buffer.scanSkippedFiles.append(scanSkippedFile)
                        }
                    },
                    fileCallback: { url in
                        guard !self.isPreviewCacheFile(url) else { return }
                        if let resolved = resolvedSelected {
                            guard resolved.contains(url.resolvingSymlinksInPath()) else { return }
                        }
                        buffer.lock.withLock {
                            buffer.pendingFiles.append(url)
                        }
                    }
                )
                buffer.lock.withLock {
                    buffer.scanTotalCount = allFiles.count
                }
                if scanProgressCoalescer.shouldReportFinalScanCount(allFiles.count) {
                    self.reportScanProgress(
                        count: allFiles.count,
                        rootName: scanRootName,
                        progress: progress
                    )
                }
            } catch {
                buffer.lock.withLock {
                    buffer.scanError = error
                }
            }
            buffer.lock.withLock {
                buffer.scanComplete = true
            }
        }
        // Process batches as they arrive from the scan
        let batchSize = 256
        var allAssets: [Asset] = []
        var skippedSourceFiles: [LibrarySkippedSourceFile] = []
        var alreadyInCatalogCount = 0
        var allExistingPreviewStates: [AssetID: ExistingGridPreviewState] = [:]
        let cumulativeIngestCount = ImportCumulativeCount()
        let ingestProgressCoalescer = IngestProgressCoalescer(
            interval: Self.ingestProgressInterval,
            eagerLimit: Self.eagerIngestProgressLimit,
            heartbeat: Self.ingestProgressHeartbeat
        )
        // Copy imports need per-file skips as much as add-in-place: without a
        // handler one dated-folder name collision aborts the whole import and
        // strands copied-but-uncataloged files, so every mode records skips.
        let skippedSourceFileHandler: IngestSkippedSourceFileHandler = { skippedSourceFile in
            skippedSourceFiles.append(LibrarySkippedSourceFile(
                sourceURL: skippedSourceFile.sourceURL,
                message: skippedSourceFile.message
            ))
        }
        let secondCopyFailureHandler: IngestSkippedSourceFileHandler? = plan.secondCopyDestination != nil ? { secondCopyFailure in
            skippedSourceFiles.append(LibrarySkippedSourceFile(
                sourceURL: secondCopyFailure.sourceURL,
                message: secondCopyFailure.message,
                kind: .backupFailed
            ))
        } : nil
        while true {
            let (batch, scanDone) = buffer.lock.withLock { () -> ([URL], Bool) in
                if buffer.pendingFiles.count >= batchSize {
                    let taken = Array(buffer.pendingFiles.prefix(batchSize))
                    buffer.pendingFiles.removeFirst(batchSize)
                    return (taken, buffer.scanComplete)
                } else if buffer.scanComplete {
                    let taken = buffer.pendingFiles
                    buffer.pendingFiles.removeAll(keepingCapacity: true)
                    return (taken, buffer.scanComplete)
                } else {
                    return ([], buffer.scanComplete)
                }
            }
            if batch.isEmpty {
                if let error = buffer.lock.withLock({ buffer.scanError }) {
                    throw error
                }
                if scanDone { break }
                Thread.sleep(forTimeInterval: 0.01)
                continue
            }
            // Check existing preview states BEFORE ingest for this batch so we
            // can distinguish new from existing (re-import) assets.
            let batchExistingStates = try DevSignpost.trace("existingGridPreviewStates") {
                try existingGridPreviewStates(
                    for: batch,
                    plan: plan,
                    repository: repository
                )
            }
            for (id, state) in batchExistingStates {
                allExistingPreviewStates[id] = state
            }
            // Emit cataloging-start progress so callers know ingest is underway.
            // Use the scan's running total as totalUnitCount so the UI shows the
            // overall library size, not the batch size (e.g. "549 of 100000").
            let scanTotal = buffer.lock.withLock { buffer.scanTotalCount }
            progress?(LibraryImportProgress(
                completedUnitCount: cumulativeIngestCount.count,
                totalUnitCount: scanTotal > 0 ? scanTotal : batch.count,
                detail: catalogingDetail(batch.count),
                catalogedAssetIDs: []
            ))
            let assets = try DevSignpost.trace("ingestBatch") {
                try ingestService.ingest(
                    files: batch,
                    plan: plan,
                    repository: repository,
                    skippedSourceFile: skippedSourceFileHandler,
                    secondCopyFailure: secondCopyFailureHandler,
                    alreadyInCatalog: { _ in alreadyInCatalogCount += 1 },
                    progress: { ingestProgress in
                        let cumulativeCompleted = cumulativeIngestCount.count + ingestProgress.completedUnitCount
                        if ingestProgressCoalescer.shouldReport(
                            completedCount: cumulativeCompleted,
                            totalCount: scanTotal > 0 ? scanTotal : ingestProgress.totalUnitCount
                        ) {
                            progress?(LibraryImportProgress(
                                completedUnitCount: cumulativeCompleted,
                                totalUnitCount: scanTotal > 0 ? scanTotal : ingestProgress.totalUnitCount,
                                detail: perFileDetail(
                                    cumulativeCompleted,
                                    scanTotal > 0 ? scanTotal : ingestProgress.totalUnitCount
                                ),
                                catalogedAssetIDs: ingestProgress.catalogedAssetIDs
                            ))
                        }
                    }
                )
            }
            allAssets.append(contentsOf: assets)
            cumulativeIngestCount.count += assets.count
        }
        // Convert scan-level skipped files (unsupported types, videos)
        let sortedScanSkipped = buffer.lock.withLock { buffer.scanSkippedFiles }
            .filter { !isPreviewCacheFile($0.url) }
            .sorted { first, second in
                first.url.path.localizedStandardCompare(second.url.path) == .orderedAscending
            }
            .map { scanSkippedFile in
                LibrarySkippedSourceFile(
                    sourceURL: scanSkippedFile.url,
                    message: Self.skippedSourceFileMessage(for: scanSkippedFile.reason)
                )
            }
        skippedSourceFiles.insert(contentsOf: sortedScanSkipped, at: 0)
        if !allAssets.isEmpty {
            try repository.recordSourceRoot(Self.catalogSourceRoot(for: plan))
        }
        // A returned asset that already sat at its path (an unchanged or changed
        // same-path re-import) is existing; a content duplicate skipped before
        // copy is existing too. New is whatever is left.
        let existingReturnedCount = allAssets.filter { allExistingPreviewStates[$0.id] != nil }.count
        let existingAssetCount = existingReturnedCount + alreadyInCatalogCount
        let newAssetCount = allAssets.count - existingReturnedCount
        let previewItems: [PreviewGenerationItem] = allAssets.flatMap { asset -> [PreviewGenerationItem] in
            guard shouldGenerateGridPreview(for: asset, existingState: allExistingPreviewStates[asset.id]) else {
                return []
            }
            return Self.importPreviewLevels.map { PreviewGenerationItem(assetID: asset.id, level: $0) }
        }
        try repository.recordPreviewGenerationPending(previewItems)
        progress?(LibraryImportProgress(
            completedUnitCount: allAssets.count,
            totalUnitCount: allAssets.count,
            detail: catalogedDetail(allAssets.count),
            catalogedAssetIDs: allAssets.map(\.id)
        ))
        guard previewPolicy == .generateImmediately else {
            return LibraryImportResult(
                importedAssets: allAssets,
                previewFailures: [],
                skippedSourceFiles: skippedSourceFiles,
                newAssetCount: newAssetCount,
                existingAssetCount: existingAssetCount
            )
        }
        progress?(LibraryImportProgress(
            completedUnitCount: 0,
            totalUnitCount: previewItems.count,
            detail: "Generating previews"
        ))
        let previewResult = try generatePreviews(
            for: previewItems,
            repository: repository,
            preIngestThumbnailCache: preIngestThumbnailCache,
            progress: progress
        )
        return LibraryImportResult(
            importedAssets: allAssets,
            previewFailures: previewResult.previewFailures,
            skippedSourceFiles: skippedSourceFiles,
            newAssetCount: newAssetCount,
            existingAssetCount: existingAssetCount
        )
    }

    private static func catalogSourceRoot(for plan: IngestPlan) -> URL {
        plan.destinationRoot ?? plan.sourceRoot
    }

    public func resumePendingPreviews(
        repository: CatalogRepository,
        progress: LibraryImportProgressHandler? = nil
    ) throws -> LibraryPreviewGenerationResult {
        let items = try repository.pendingPreviewGenerationItems()
        progress?(LibraryImportProgress(
            completedUnitCount: 0,
            totalUnitCount: items.count,
            detail: "Generating pending previews"
        ))
        return try generatePreviews(for: items, repository: repository, progress: progress)
    }

    private func generatePreviews(
        for items: [PreviewGenerationItem],
        repository: CatalogRepository,
        preIngestThumbnailCache: PreIngestThumbnailCache? = nil,
        progress: LibraryImportProgressHandler?
    ) throws -> LibraryPreviewGenerationResult {
        var generatedCount = 0
        var failures: [LibraryPreviewFailure] = []
        var failedAssetIDs: Set<AssetID> = []

        // Group items by asset so each source file is read once per asset.
        var itemsByAsset: [AssetID: [PreviewLevel]] = [:]
        var itemOrder: [AssetID] = []
        for item in items {
            if itemsByAsset[item.assetID] == nil {
                itemOrder.append(item.assetID)
                itemsByAsset[item.assetID] = []
            }
            itemsByAsset[item.assetID]?.append(item.level)
        }

        var completedCount = 0
        for assetID in itemOrder {
            try Task.checkCancellation()
            let levels = itemsByAsset[assetID] ?? []
            let asset = try repository.asset(id: assetID)
            if failedAssetIDs.contains(asset.id) {
                completedCount += levels.count
                continue
            }
            do {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(asset.originalURL.pathExtension.isEmpty ? "tmp" : asset.originalURL.pathExtension)
                try FileManager.default.copyItem(at: asset.originalURL, to: tempURL)
                defer { try? FileManager.default.removeItem(at: tempURL) }

                try renderer.renderLevels(
                    fromLocalSource: tempURL,
                    levels: levels,
                    destinationProvider: { level in
                        previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: level))
                    }
                )
                for level in PreviewCache.allLevelsServedBy(levels) {
                    try repository.markPreviewGenerated(assetID: asset.id, level: level)
                }
                generatedCount += levels.count
            } catch {
                failedAssetIDs.insert(asset.id)
                for level in levels {
                    try repository.recordPreviewGenerationFailure(
                        assetID: asset.id,
                        level: level,
                        errorMessage: error.localizedDescription
                    )
                }
                failures.append(LibraryPreviewFailure(
                    assetID: asset.id,
                    sourceURL: asset.originalURL,
                    message: error.localizedDescription
                ))
            }
            completedCount += levels.count
            progress?(LibraryImportProgress(
                completedUnitCount: completedCount,
                totalUnitCount: items.count,
                detail: "Generated \(completedCount) of \(items.count) previews"
            ))
        }

        return LibraryPreviewGenerationResult(generatedCount: generatedCount, previewFailures: failures)
    }

    private func existingGridPreviewStates(
        for sourceFiles: [URL],
        plan: IngestPlan,
        repository: CatalogRepository,
        progress: LibraryImportProgressHandler? = nil
    ) throws -> [AssetID: ExistingGridPreviewState] {
        var states: [AssetID: ExistingGridPreviewState] = [:]
        // Batch lookup: a single WHERE original_path IN (...) query replaces
        // per-file repository.asset(originalURL:) calls — 256 DB round-trips
        // per batch become 1.
        let originalPaths = try sourceFiles.map { try ingestService.originalURL(for: $0, plan: plan).path }
        let existingAssets = try repository.assets(originalPaths: originalPaths)
        for (index, sourceFile) in sourceFiles.enumerated() {
            let originalPath = originalPaths[index]
            guard let existingAsset = existingAssets[originalPath] else {
                continue
            }
            let previewURL = previewCache.url(for: PreviewCacheKey(assetID: existingAsset.id, level: .grid))
            states[existingAsset.id] = ExistingGridPreviewState(
                fingerprint: existingAsset.fingerprint,
                hasCachedPreview: FileManager.default.fileExists(atPath: previewURL.path)
            )
        }
        return states
    }

    private func shouldGenerateGridPreview(for asset: Asset, existingState: ExistingGridPreviewState?) -> Bool {
        guard canRenderPreview(for: asset.originalURL) else {
            return false
        }
        guard let existingState else {
            return true
        }
        return !existingState.hasCachedPreview || !existingState.fingerprint.matches(asset.fingerprint)
    }

    private func canRenderPreview(for url: URL) -> Bool {
        guard let decodeRegistry = ingestService.decodeRegistry else {
            return true
        }
        guard let capability = try? decodeRegistry.capability(for: url) else {
            return false
        }
        return capability.canRenderPreview
    }

    private func isPreviewCacheFile(_ url: URL) -> Bool {
        let cacheRootPath = previewCache.root.resolvingSymlinksInPath().path
        let cacheRootPrefix = cacheRootPath == "/" ? cacheRootPath : cacheRootPath + "/"
        let filePath = url.resolvingSymlinksInPath().path
        return filePath.hasPrefix(cacheRootPrefix)
    }

    private func reportScanProgress(
        count: Int,
        rootName: String,
        progress: LibraryImportProgressHandler?
    ) {
        progress?(LibraryImportProgress(
            completedUnitCount: count,
            totalUnitCount: nil,
            detail: "Scanning \(rootName): found \(Self.photoCountDescription(count))"
        ))
    }

    private static func photoCountDescription(_ count: Int) -> String {
        "\(count) \(count == 1 ? "photo" : "photos")"
    }

    private static func skippedSourceFileMessage(for reason: FolderScanSkippedFile.Reason) -> String {
        switch reason {
        case .videoFile:
            return "video file not supported"
        case .unrecognizedFile:
            return "file type not supported"
        }
    }
}

private struct ExistingGridPreviewState {
    var fingerprint: FileFingerprint
    var hasCachedPreview: Bool
}

// Both coalescers below gate progress reports on a count schedule, but a
// count schedule alone can go silent far longer than WorkerSupervisor's
// per-command watchdog on a slow phase (e.g. copying files off a card),
// killing a healthy import. `heartbeat` guarantees a report at least every
// `heartbeat` seconds whenever the count has actually advanced since the
// last report, without weakening the count-based coalescing that keeps fast
// imports from flooding progress updates.
final class ScanProgressCoalescer: @unchecked Sendable {
    private let interval: Int
    private let heartbeat: TimeInterval
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var lastReportedCount = 0
    private var lastReportedAt: Date

    init(interval: Int, heartbeat: TimeInterval, now: @escaping @Sendable () -> Date = { Date() }) {
        self.interval = interval
        self.heartbeat = heartbeat
        self.now = now
        self.lastReportedAt = now()
    }

    func shouldReportScanCount(_ count: Int) -> Bool {
        lock.withLock {
            let currentTime = now()
            let heartbeatElapsed = currentTime.timeIntervalSince(lastReportedAt) >= heartbeat
            // Heartbeat fires even when count hasn't changed — this is what
            // keeps the worker stall detector alive while scanning directories
            // that have many non-supported files between supported ones.
            if heartbeatElapsed {
                lastReportedCount = count
                lastReportedAt = currentTime
                return true
            }
            guard count != lastReportedCount else {
                return false
            }
            let countConditionMet = count == 1 || count.isMultiple(of: interval)
            guard countConditionMet else {
                return false
            }
            lastReportedCount = count
            lastReportedAt = currentTime
            return true
        }
    }

    func shouldReportFinalScanCount(_ count: Int) -> Bool {
        lock.withLock {
            guard count > 0, count != lastReportedCount else {
                return false
            }
            lastReportedCount = count
            lastReportedAt = now()
            return true
        }
    }
}

final class IngestProgressCoalescer: @unchecked Sendable {
    private let interval: Int
    private let eagerLimit: Int
    private let heartbeat: TimeInterval
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var lastReportedCount = 0
    private var lastReportedAt: Date

    init(interval: Int, eagerLimit: Int, heartbeat: TimeInterval, now: @escaping @Sendable () -> Date = { Date() }) {
        self.interval = interval
        self.eagerLimit = eagerLimit
        self.heartbeat = heartbeat
        self.now = now
        self.lastReportedAt = now()
    }

    func shouldReport(completedCount: Int, totalCount: Int) -> Bool {
        lock.withLock {
            let currentTime = now()
            let heartbeatElapsed = currentTime.timeIntervalSince(lastReportedAt) >= heartbeat
            // Heartbeat fires even when count hasn't changed — this keeps the
            // worker stall detector alive during slow per-file operations
            // (large file copies, fingerprinting) where the count is stalled
            // on a single item for a long time.
            if heartbeatElapsed {
                lastReportedCount = completedCount
                lastReportedAt = currentTime
                return true
            }
            guard completedCount != lastReportedCount else {
                return false
            }
            let countConditionMet = totalCount <= eagerLimit ||
                completedCount.isMultiple(of: interval) ||
                completedCount == totalCount
            guard countConditionMet else {
                return false
            }
            lastReportedCount = completedCount
            lastReportedAt = currentTime
            return true
        }
    }
}

/// Thread-safe buffer for streaming scan → ingest. The scan runs in a
/// background thread and appends files as they're discovered; the main flow
/// polls the buffer and processes batches through ingest, so import starts
/// before the scan finishes.
final class StreamingScanBuffer: @unchecked Sendable {
    let lock = NSLock()
    var pendingFiles: [URL] = []
    var scanSkippedFiles: [FolderScanSkippedFile] = []
    var scanComplete = false
    var scanError: Error?
    /// Running total of supported files the scanner has found so far.
    /// Used as totalUnitCount in per-batch cataloging progress so the UI
    /// shows "X of 100000" instead of "X of 256" (the batch size).
    var scanTotalCount = 0
}

/// Mutable counter captured in a @Sendable ingest progress closure. The
/// closure is called synchronously from the same thread that updates the
/// count, so no lock is needed — the @unchecked Sendable wrapper satisfies
/// Swift 6's concurrency checker.
final class ImportCumulativeCount: @unchecked Sendable {
    var count = 0
}
