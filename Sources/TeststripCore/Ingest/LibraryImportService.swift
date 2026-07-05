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

public struct LibrarySkippedSourceFile: Equatable, Sendable {
    public var sourceURL: URL
    public var message: String

    public init(sourceURL: URL, message: String) {
        self.sourceURL = sourceURL
        self.message = message
    }
}

public struct LibraryImportResult: Sendable {
    public var importedAssets: [Asset]
    public var previewFailures: [LibraryPreviewFailure]
    public var skippedSourceFiles: [LibrarySkippedSourceFile]
    public var newAssetCount: Int
    public var existingAssetCount: Int

    public init(
        importedAssets: [Asset],
        previewFailures: [LibraryPreviewFailure],
        skippedSourceFiles: [LibrarySkippedSourceFile] = [],
        newAssetCount: Int? = nil,
        existingAssetCount: Int = 0
    ) {
        self.importedAssets = importedAssets
        self.previewFailures = previewFailures
        self.skippedSourceFiles = skippedSourceFiles
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
        progress: LibraryImportProgressHandler? = nil
    ) throws -> LibraryImportResult {
        try importAssets(
            plan: IngestPlanner.addFolder(root),
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
        repository: CatalogRepository,
        previewPolicy: LibraryImportPreviewPolicy,
        progress: LibraryImportProgressHandler? = nil
    ) throws -> LibraryImportResult {
        try importAssets(
            plan: IngestPlanner.copyFromCard(source: source, destinationRoot: destinationRoot),
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
        let scanProgressCoalescer = ScanProgressCoalescer(interval: Self.scanProgressInterval)
        let scannedSourceFiles = try ingestService.files(for: plan) { scanProgress in
            if scanProgressCoalescer.shouldReportScanCount(scanProgress.supportedFileCount) {
                reportScanProgress(
                    count: scanProgress.supportedFileCount,
                    rootName: scanRootName,
                    progress: progress
                )
            }
        }
        let sourceFiles = scannedSourceFiles.filter { !isPreviewCacheFile($0) }
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
            eagerLimit: Self.eagerIngestProgressLimit
        )
        var skippedSourceFiles: [LibrarySkippedSourceFile] = []
        let skippedSourceFileHandler: IngestSkippedSourceFileHandler? = plan.mode == .addInPlace ? { skippedSourceFile in
            skippedSourceFiles.append(LibrarySkippedSourceFile(
                sourceURL: skippedSourceFile.sourceURL,
                message: skippedSourceFile.message
            ))
        } : nil
        let assets = try ingestService.ingest(
            files: sourceFiles,
            plan: plan,
            repository: repository,
            skippedSourceFile: skippedSourceFileHandler
        ) { ingestProgress in
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
        if !assets.isEmpty {
            try repository.recordSourceRoot(Self.catalogSourceRoot(for: plan))
        }
        let existingAssetCount = assets.filter { existingPreviewStates[$0.id] != nil }.count
        let newAssetCount = assets.count - existingAssetCount
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
        guard let existingState else {
            return true
        }
        return !existingState.hasCachedPreview || !existingState.fingerprint.matches(asset.fingerprint)
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
}

private struct ExistingGridPreviewState {
    var fingerprint: FileFingerprint
    var hasCachedPreview: Bool
}

private final class ScanProgressCoalescer: @unchecked Sendable {
    private let interval: Int
    private let lock = NSLock()
    private var lastReportedCount = 0

    init(interval: Int) {
        self.interval = interval
    }

    func shouldReportScanCount(_ count: Int) -> Bool {
        lock.withLock {
            guard count == 1 || count.isMultiple(of: interval) else {
                return false
            }
            lastReportedCount = count
            return true
        }
    }

    func shouldReportFinalScanCount(_ count: Int) -> Bool {
        lock.withLock {
            guard count > 0, count != lastReportedCount else {
                return false
            }
            lastReportedCount = count
            return true
        }
    }
}

private final class IngestProgressCoalescer: @unchecked Sendable {
    private let interval: Int
    private let eagerLimit: Int
    private let lock = NSLock()
    private var lastReportedCount = 0

    init(interval: Int, eagerLimit: Int) {
        self.interval = interval
        self.eagerLimit = eagerLimit
    }

    func shouldReport(completedCount: Int, totalCount: Int) -> Bool {
        lock.withLock {
            guard totalCount <= eagerLimit ||
                completedCount.isMultiple(of: interval) ||
                completedCount == totalCount else {
                return false
            }
            guard completedCount != lastReportedCount else {
                return false
            }
            lastReportedCount = completedCount
            return true
        }
    }
}
