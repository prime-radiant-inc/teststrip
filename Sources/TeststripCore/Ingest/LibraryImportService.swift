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

public struct LibraryImportResult: Sendable {
    public var importedAssets: [Asset]
    public var previewFailures: [LibraryPreviewFailure]

    public init(importedAssets: [Asset], previewFailures: [LibraryPreviewFailure]) {
        self.importedAssets = importedAssets
        self.previewFailures = previewFailures
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
        try Task.checkCancellation()
        progress?(LibraryImportProgress(
            completedUnitCount: 0,
            totalUnitCount: nil,
            detail: "Scanning \(root.lastPathComponent)"
        ))
        let plan = IngestPlanner.addFolder(root)
        let sourceFiles = try ingestService.files(for: plan)
        progress?(LibraryImportProgress(
            completedUnitCount: 0,
            totalUnitCount: sourceFiles.count,
            detail: "Cataloging \(sourceFiles.count) \(sourceFiles.count == 1 ? "photo" : "photos")"
        ))
        let assets = try ingestService.ingest(files: sourceFiles, plan: plan, repository: repository)
        let previewItems = assets.map { PreviewGenerationItem(assetID: $0.id, level: .grid) }
        for item in previewItems {
            try repository.recordPreviewGenerationPending(item)
        }

        progress?(LibraryImportProgress(
            completedUnitCount: assets.count,
            totalUnitCount: assets.count,
            detail: "Cataloged \(assets.count) \(assets.count == 1 ? "photo" : "photos")",
            catalogedAssetIDs: assets.map(\.id)
        ))

        guard previewPolicy == .generateImmediately else {
            return LibraryImportResult(importedAssets: assets, previewFailures: [])
        }

        progress?(LibraryImportProgress(
            completedUnitCount: 0,
            totalUnitCount: assets.count,
            detail: "Generating previews"
        ))

        let previewResult = try generatePreviews(for: previewItems, repository: repository, progress: progress)
        return LibraryImportResult(importedAssets: assets, previewFailures: previewResult.previewFailures)
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

        for (index, item) in items.enumerated() {
            try Task.checkCancellation()
            let asset = try repository.asset(id: item.assetID)
            do {
                try renderer.render(
                    sourceURL: asset.originalURL,
                    level: item.level,
                    destinationURL: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: item.level))
                )
                try repository.markPreviewGenerated(assetID: asset.id, level: item.level)
                generatedCount += 1
            } catch {
                failures.append(LibraryPreviewFailure(
                    assetID: asset.id,
                    sourceURL: asset.originalURL,
                    message: error.localizedDescription
                ))
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
}
