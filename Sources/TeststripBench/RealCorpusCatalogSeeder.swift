import Foundation
import TeststripCore

public struct RealCorpusCatalogSeederResult: Equatable {
    public var catalogURL: URL
    public var previewCacheRoot: URL
    public var sourceImageCount: Int
    public var assetCount: Int
    public var cachedPreviewCount: Int
    public var workingStillCount: Int
    public var bestEffortRawCount: Int
    public var unsupportedCount: Int

    public init(
        catalogURL: URL,
        previewCacheRoot: URL,
        sourceImageCount: Int,
        assetCount: Int,
        cachedPreviewCount: Int,
        workingStillCount: Int,
        bestEffortRawCount: Int,
        unsupportedCount: Int
    ) {
        self.catalogURL = catalogURL
        self.previewCacheRoot = previewCacheRoot
        self.sourceImageCount = sourceImageCount
        self.assetCount = assetCount
        self.cachedPreviewCount = cachedPreviewCount
        self.workingStillCount = workingStillCount
        self.bestEffortRawCount = bestEffortRawCount
        self.unsupportedCount = unsupportedCount
    }
}

public struct RealCorpusCatalogSeeder {
    public var applicationSupportDirectory: URL
    public var photoDirectory: URL

    private let renderedLevels: [PreviewLevel] = [.micro, .grid]

    public init(applicationSupportDirectory: URL, photoDirectory: URL) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.photoDirectory = photoDirectory
    }

    public func run() throws -> RealCorpusCatalogSeederResult {
        let appRoot = applicationSupportDirectory.appendingPathComponent("Teststrip", isDirectory: true)
        let catalogURL = appRoot.appendingPathComponent("catalog.sqlite")
        let previewCache = PreviewCache(root: appRoot.appendingPathComponent("Previews", isDirectory: true))

        if FileManager.default.fileExists(atPath: catalogURL.path) {
            throw TeststripError.invalidState("refusing to seed real corpus catalog over existing catalog: \(catalogURL.path)")
        }
        guard FileManager.default.fileExists(atPath: photoDirectory.path) else {
            throw TeststripError.invalidState("real corpus photo directory does not exist: \(photoDirectory.path)")
        }

        let decodeProvider = ImageIODecodeProvider()
        let decodeRegistry = DecodeRegistry(providers: [decodeProvider])
        let candidates = try RealCorpusSmoke.catalogablePhotos(under: photoDirectory)
        let selectedPhotos = try RealCorpusSmoke.representativeSelection(from: candidates, decodeRegistry: decodeRegistry)
        guard !selectedPhotos.isEmpty else {
            throw TeststripError.invalidState("real corpus catalog seed found no catalogable photos under \(photoDirectory.path)")
        }
        let capabilities = selectedPhotos.compactMap { try? decodeRegistry.capability(for: $0) }

        try FileManager.default.createDirectory(at: previewCache.root, withIntermediateDirectories: true)

        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let ingestService = IngestService(
            scanner: FolderScanner(supportedExtensions: ImageIODecodeProvider.catalogableExtensions),
            decodeRegistry: decodeRegistry
        )
        let importedAssets = try ingestService.ingest(
            files: selectedPhotos,
            plan: IngestPlanner.addFolder(photoDirectory),
            repository: repository
        )
        if !importedAssets.isEmpty {
            try repository.recordSourceRoot(photoDirectory)
        }

        let renderer = PreviewRenderer()
        for asset in importedAssets where (try? decodeRegistry.capability(for: asset.originalURL).canRenderPreview) == true {
            for level in renderedLevels {
                try renderer.render(
                    sourceURL: asset.originalURL,
                    level: level,
                    destinationURL: previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: level))
                )
            }
        }

        return RealCorpusCatalogSeederResult(
            catalogURL: catalogURL,
            previewCacheRoot: previewCache.root,
            sourceImageCount: selectedPhotos.count,
            assetCount: try repository.assetCount(),
            cachedPreviewCount: try PreviewCacheFileCounter.count(root: previewCache.root),
            workingStillCount: capabilities.filter { $0.support == .working }.count,
            bestEffortRawCount: capabilities.filter { $0.support == .bestEffort }.count,
            unsupportedCount: capabilities.filter { $0.support == .unsupported }.count
        )
    }
}
