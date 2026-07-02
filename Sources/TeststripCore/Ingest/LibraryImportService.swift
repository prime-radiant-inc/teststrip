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

    public func addFolderInPlace(_ root: URL, repository: CatalogRepository) throws -> LibraryImportResult {
        let assets = try ingestService.ingest(plan: IngestPlanner.addFolder(root), repository: repository)
        var failures: [LibraryPreviewFailure] = []

        for asset in assets {
            do {
                try renderer.render(
                    sourceURL: asset.originalURL,
                    level: .grid,
                    destinationURL: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
                )
            } catch {
                failures.append(LibraryPreviewFailure(
                    assetID: asset.id,
                    sourceURL: asset.originalURL,
                    message: error.localizedDescription
                ))
            }
        }

        return LibraryImportResult(importedAssets: assets, previewFailures: failures)
    }
}
