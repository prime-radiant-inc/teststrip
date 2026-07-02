import Foundation
import TeststripCore

public struct AppCatalogPaths: Equatable {
    public var root: URL
    public var catalogURL: URL
    public var previewCacheRoot: URL

    public init(root: URL, catalogURL: URL, previewCacheRoot: URL) {
        self.root = root
        self.catalogURL = catalogURL
        self.previewCacheRoot = previewCacheRoot
    }
}

public struct AppCatalog {
    public var paths: AppCatalogPaths
    public var repository: CatalogRepository
    public var previewCache: PreviewCache
    public var importService: LibraryImportService

    public init(
        paths: AppCatalogPaths,
        repository: CatalogRepository,
        previewCache: PreviewCache,
        importService: LibraryImportService
    ) {
        self.paths = paths
        self.repository = repository
        self.previewCache = previewCache
        self.importService = importService
    }

    public static func defaultPaths() throws -> AppCatalogPaths {
        let applicationSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return defaultPaths(applicationSupportDirectory: applicationSupportDirectory)
    }

    public static func defaultPaths(applicationSupportDirectory: URL) -> AppCatalogPaths {
        let root = applicationSupportDirectory.appendingPathComponent("Teststrip", isDirectory: true)
        return AppCatalogPaths(
            root: root,
            catalogURL: root.appendingPathComponent("catalog.sqlite"),
            previewCacheRoot: root.appendingPathComponent("Previews", isDirectory: true)
        )
    }

    public static func open(paths: AppCatalogPaths) throws -> AppCatalog {
        try FileManager.default.createDirectory(at: paths.previewCacheRoot, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: paths.catalogURL)
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let previewCache = PreviewCache(root: paths.previewCacheRoot)
        let ingestService = IngestService(scanner: FolderScanner(supportedExtensions: ImageIODecodeProvider.supportedExtensions))
        let importService = LibraryImportService(ingestService: ingestService, previewCache: previewCache)
        return AppCatalog(paths: paths, repository: repository, previewCache: previewCache, importService: importService)
    }

    public static func loadModel(paths: AppCatalogPaths) throws -> AppModel {
        try AppModel.load(catalog: open(paths: paths))
    }
}
