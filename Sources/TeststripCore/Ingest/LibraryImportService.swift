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
    private static let importPreviewLevels: [PreviewLevel] = [.micro, .grid]

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
        progress: LibraryImportProgressHandler?
    ) throws -> LibraryImportResult {
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
        var scanSkippedFiles: [FolderScanSkippedFile] = []
        let scannedSourceFiles = try ingestService.files(
            for: plan,
            progress: { scanProgress in
                if scanProgressCoalescer.shouldReportScanCount(scanProgress.supportedFileCount) {
                    reportScanProgress(
                        count: scanProgress.supportedFileCount,
                        rootName: scanRootName,
                        progress: progress
                    )
                }
            },
            skipped: { scanSkippedFile in
                scanSkippedFiles.append(scanSkippedFile)
            }
        )
        let sourceFiles = scannedSourceFiles.filter { !isPreviewCacheFile($0) }
        var skippedSourceFiles = scanSkippedFiles
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
        if scanProgressCoalescer.shouldReportFinalScanCount(sourceFiles.count) {
            reportScanProgress(
                count: sourceFiles.count,
                rootName: scanRootName,
                progress: progress
            )
        }
        let existingPreviewStates = try existingGridPreviewStates(
            for: sourceFiles,
            plan: plan,
            repository: repository
        )
        progress?(LibraryImportProgress(
            completedUnitCount: 0,
            totalUnitCount: sourceFiles.count,
            detail: catalogingDetail(sourceFiles.count)
        ))
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
        // Content already in the catalog is a normal dedup outcome, not a
        // problem, so it feeds the "already in catalog" count rather than the
        // skipped-file list.
        var alreadyInCatalogCount = 0
        let assets = try ingestService.ingest(
            files: sourceFiles,
            plan: plan,
            repository: repository,
            skippedSourceFile: skippedSourceFileHandler,
            secondCopyFailure: secondCopyFailureHandler,
            alreadyInCatalog: { _ in alreadyInCatalogCount += 1 },
            progress: { ingestProgress in
                if ingestProgressCoalescer.shouldReport(
                    completedCount: ingestProgress.completedUnitCount,
                    totalCount: ingestProgress.totalUnitCount
                ) {
                    progress?(LibraryImportProgress(
                        completedUnitCount: ingestProgress.completedUnitCount,
                        totalUnitCount: ingestProgress.totalUnitCount,
                        detail: perFileDetail(ingestProgress.completedUnitCount, ingestProgress.totalUnitCount),
                        catalogedAssetIDs: ingestProgress.catalogedAssetIDs
                    ))
                }
            }
        )
        if !assets.isEmpty {
            try repository.recordSourceRoot(Self.catalogSourceRoot(for: plan))
        }
        // A returned asset that already sat at its path (an unchanged or changed
        // same-path re-import) is existing; a content duplicate skipped before
        // copy is existing too. New is whatever is left.
        let existingReturnedCount = assets.filter { existingPreviewStates[$0.id] != nil }.count
        let existingAssetCount = existingReturnedCount + alreadyInCatalogCount
        let newAssetCount = assets.count - existingReturnedCount
        let previewItems: [PreviewGenerationItem] = assets.flatMap { asset -> [PreviewGenerationItem] in
            guard shouldGenerateGridPreview(for: asset, existingState: existingPreviewStates[asset.id]) else {
                return []
            }
            return Self.importPreviewLevels.map { PreviewGenerationItem(assetID: asset.id, level: $0) }
        }
        try repository.recordPreviewGenerationPending(previewItems)

        progress?(LibraryImportProgress(
            completedUnitCount: assets.count,
            totalUnitCount: assets.count,
            detail: catalogedDetail(assets.count),
            catalogedAssetIDs: assets.map(\.id)
        ))

        guard previewPolicy == .generateImmediately else {
            return LibraryImportResult(
                importedAssets: assets,
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

        let previewResult = try generatePreviews(for: previewItems, repository: repository, progress: progress)
        return LibraryImportResult(
            importedAssets: assets,
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
        progress: LibraryImportProgressHandler?
    ) throws -> LibraryPreviewGenerationResult {
        var generatedCount = 0
        var failures: [LibraryPreviewFailure] = []
        var failedAssetIDs: Set<AssetID> = []

        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            let asset = try repository.asset(id: item.assetID)
            if !failedAssetIDs.contains(asset.id) {
                do {
                    try renderer.render(
                        sourceURL: asset.originalURL,
                        level: item.level,
                        destinationURL: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: item.level))
                    )
                    try repository.markPreviewGenerated(assetID: asset.id, level: item.level)
                    generatedCount += 1
                } catch {
                    failedAssetIDs.insert(asset.id)
                    try repository.recordPreviewGenerationFailure(
                        assetID: asset.id,
                        level: item.level,
                        errorMessage: error.localizedDescription
                    )
                    failures.append(LibraryPreviewFailure(
                        assetID: asset.id,
                        sourceURL: asset.originalURL,
                        message: error.localizedDescription
                    ))
                }
            }
            let completedCount = index + 1
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
        repository: CatalogRepository
    ) throws -> [AssetID: ExistingGridPreviewState] {
        var states: [AssetID: ExistingGridPreviewState] = [:]
        for sourceFile in sourceFiles {
            let originalURL = try ingestService.originalURL(for: sourceFile, plan: plan)
            guard let existingAsset = try repository.asset(originalURL: originalURL) else {
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
            guard count != lastReportedCount else {
                return false
            }
            let currentTime = now()
            let countConditionMet = count == 1 || count.isMultiple(of: interval)
            let heartbeatElapsed = currentTime.timeIntervalSince(lastReportedAt) >= heartbeat
            guard countConditionMet || heartbeatElapsed else {
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
            guard completedCount != lastReportedCount else {
                return false
            }
            let currentTime = now()
            let countConditionMet = totalCount <= eagerLimit ||
                completedCount.isMultiple(of: interval) ||
                completedCount == totalCount
            let heartbeatElapsed = currentTime.timeIntervalSince(lastReportedAt) >= heartbeat
            guard countConditionMet || heartbeatElapsed else {
                return false
            }
            lastReportedCount = completedCount
            lastReportedAt = currentTime
            return true
        }
    }
}
