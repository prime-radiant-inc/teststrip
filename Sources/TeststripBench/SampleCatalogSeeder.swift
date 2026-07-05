import Foundation
import TeststripCore

public struct SampleCatalogSeederResult: Equatable {
    public var catalogURL: URL
    public var previewCacheRoot: URL
    public var sourceImageCount: Int
    public var assetCount: Int
    public var cachedPreviewCount: Int

    public init(
        catalogURL: URL,
        previewCacheRoot: URL,
        sourceImageCount: Int,
        assetCount: Int,
        cachedPreviewCount: Int
    ) {
        self.catalogURL = catalogURL
        self.previewCacheRoot = previewCacheRoot
        self.sourceImageCount = sourceImageCount
        self.assetCount = assetCount
        self.cachedPreviewCount = cachedPreviewCount
    }
}

public struct SampleCatalogSeeder {
    public var applicationSupportDirectory: URL
    public var photoDirectory: URL

    public init(applicationSupportDirectory: URL, photoDirectory: URL) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.photoDirectory = photoDirectory
    }

    public func run() throws -> SampleCatalogSeederResult {
        let appRoot = applicationSupportDirectory.appendingPathComponent("Teststrip", isDirectory: true)
        let catalogURL = appRoot.appendingPathComponent("catalog.sqlite")
        let previewCache = PreviewCache(root: appRoot.appendingPathComponent("Previews", isDirectory: true))

        if FileManager.default.fileExists(atPath: catalogURL.path) {
            throw TeststripError.invalidState("refusing to seed sample catalog over existing catalog: \(catalogURL.path)")
        }
        guard FileManager.default.fileExists(atPath: photoDirectory.path) else {
            throw TeststripError.invalidState("sample photo directory does not exist: \(photoDirectory.path)")
        }

        try FileManager.default.createDirectory(at: previewCache.root, withIntermediateDirectories: true)

        let database = try CatalogDatabase.open(at: catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let decodeProvider = ImageIODecodeProvider()
        let importService = LibraryImportService(
            ingestService: IngestService(
                scanner: FolderScanner(supportedExtensions: ImageIODecodeProvider.catalogableExtensions),
                decodeRegistry: DecodeRegistry(providers: [decodeProvider])
            ),
            previewCache: previewCache
        )
        let result = try importService.addFolderInPlace(
            photoDirectory,
            repository: repository,
            previewPolicy: .generateImmediately
        )
        if let failure = result.previewFailures.first {
            throw TeststripError.io("sample preview generation failed for \(failure.sourceURL.lastPathComponent): \(failure.message)")
        }

        return SampleCatalogSeederResult(
            catalogURL: catalogURL,
            previewCacheRoot: previewCache.root,
            sourceImageCount: result.importedAssets.count,
            assetCount: try repository.assetCount(),
            cachedPreviewCount: try PreviewCacheFileCounter.count(root: previewCache.root)
        )
    }
}
