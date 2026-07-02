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

public struct LibraryImportProgress: Equatable, Sendable {
    public var completedUnitCount: Int
    public var totalUnitCount: Int?
    public var detail: String

    public init(completedUnitCount: Int, totalUnitCount: Int?, detail: String) {
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
        self.detail = detail
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
        var failures: [LibraryPreviewFailure] = []
        progress?(LibraryImportProgress(
            completedUnitCount: 0,
            totalUnitCount: assets.count,
            detail: "Generating previews"
        ))

        for (index, asset) in assets.enumerated() {
            try Task.checkCancellation()
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
            let completedCount = index + 1
            progress?(LibraryImportProgress(
                completedUnitCount: completedCount,
                totalUnitCount: assets.count,
                detail: "Generated \(completedCount) of \(assets.count) previews"
            ))
        }

        return LibraryImportResult(importedAssets: assets, previewFailures: failures)
    }
}
