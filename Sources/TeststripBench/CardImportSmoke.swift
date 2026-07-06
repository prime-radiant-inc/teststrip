import Foundation
import TeststripCore

public struct CardImportSmokeResult: Equatable {
    public var importedAssetCount: Int
    public var catalogAssetCount: Int
    public var destinationOriginalCount: Int
    public var cachedPreviewCount: Int
    public var sourceOriginalUnchangedCount: Int
    public var sourceRootCount: Int
    public var destinationCatalogAssetCount: Int

    public init(
        importedAssetCount: Int,
        catalogAssetCount: Int,
        destinationOriginalCount: Int,
        cachedPreviewCount: Int,
        sourceOriginalUnchangedCount: Int,
        sourceRootCount: Int,
        destinationCatalogAssetCount: Int
    ) {
        self.importedAssetCount = importedAssetCount
        self.catalogAssetCount = catalogAssetCount
        self.destinationOriginalCount = destinationOriginalCount
        self.cachedPreviewCount = cachedPreviewCount
        self.sourceOriginalUnchangedCount = sourceOriginalUnchangedCount
        self.sourceRootCount = sourceRootCount
        self.destinationCatalogAssetCount = destinationCatalogAssetCount
    }
}

public struct CardImportSmoke {
    public var count: Int
    public var root: URL

    public init(count: Int, root: URL) {
        self.count = count
        self.root = root
    }

    public func run() throws -> CardImportSmokeResult {
        let sourceRoot = root.appendingPathComponent("DCIM", isDirectory: true)
        let destinationRoot = root.appendingPathComponent("Library", isDirectory: true)
        let previewRoot = root.appendingPathComponent("previews", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: previewRoot, withIntermediateDirectories: true)

        let sourceFiles = try writeSourceFiles(to: sourceRoot)
        let originalDataByPath = try Dictionary(uniqueKeysWithValues: sourceFiles.map { url in
            (url.path, try Data(contentsOf: url))
        })

        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let previewCache = PreviewCache(root: previewRoot)
        let service = LibraryImportService(
            ingestService: IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"])),
            previewCache: previewCache
        )

        let result = try service.copyFromCard(
            source: sourceRoot,
            destinationRoot: destinationRoot,
            repository: repository,
            previewPolicy: .generateImmediately
        )

        let sourceOriginalUnchangedCount = try sourceFiles.filter { sourceFile in
            try Data(contentsOf: sourceFile) == originalDataByPath[sourceFile.path]
        }.count
        let destinationOriginalCount = try destinationJPEGCount(in: destinationRoot)
        let destinationPath = destinationRoot.standardizedFileURL.path
        let destinationCatalogAssetCount = try repository.allAssets(limit: max(count + 1, 1))
            .filter { asset in
                asset.originalURL.standardizedFileURL.path.hasPrefix(destinationPath)
            }
            .count

        return CardImportSmokeResult(
            importedAssetCount: result.importedAssets.count,
            catalogAssetCount: try repository.assetCount(),
            destinationOriginalCount: destinationOriginalCount,
            cachedPreviewCount: try PreviewCacheFileCounter.count(root: previewRoot),
            sourceOriginalUnchangedCount: sourceOriginalUnchangedCount,
            sourceRootCount: try repository.sourceRoots().count,
            destinationCatalogAssetCount: destinationCatalogAssetCount
        )
    }

    private func writeSourceFiles(to sourceRoot: URL) throws -> [URL] {
        try (0..<count).map { index in
            let url = sourceRoot.appendingPathComponent("CARD_\(index).jpg")
            try BenchmarkImageFixtures.writeJPEG(to: url, index: index)
            return url
        }
    }

    private func destinationJPEGCount(in destinationRoot: URL) throws -> Int {
        try FileManager.default
            .contentsOfDirectory(at: destinationRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .count
    }
}
