import XCTest
import TeststripCore

final class LibraryImportServiceTests: XCTestCase {
    func testAddFolderCatalogsSupportedImagesAndGeneratesGridPreview() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import")
        let image = root.appendingPathComponent("one.jpg")
        try TestDirectories.writeTestJPEG(to: image, width: 1200, height: 800)
        try Data("notes".utf8).write(to: root.appendingPathComponent("notes.txt"))
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)

        let result = try service.addFolderInPlace(root, repository: repository)

        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertEqual(result.previewFailures, [])
        let asset = result.importedAssets[0]
        let fetched = try repository.asset(id: asset.id)
        XCTAssertEqual(fetched.originalURL, image)
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: asset.id, level: .grid))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        let dimensions = try PreviewRenderer().dimensions(of: previewURL)
        XCTAssertLessThanOrEqual(max(dimensions.width, dimensions.height), PreviewLevel.grid.maxPixelDimension!)
    }

    func testAddFolderKeepsCatalogedAssetWhenPreviewRenderFails() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-preview-failure")
        let invalidImage = root.appendingPathComponent("broken.jpg")
        try Data("not an image".utf8).write(to: invalidImage)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)

        let result = try service.addFolderInPlace(root, repository: repository)

        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertEqual(result.previewFailures.count, 1)
        XCTAssertEqual(result.previewFailures[0].assetID, result.importedAssets[0].id)
        XCTAssertEqual(result.previewFailures[0].sourceURL, invalidImage)
        XCTAssertEqual(try repository.allAssets(limit: 10).map(\.originalURL), [invalidImage])
    }

    func testReimportPreservesAssetIdentityMetadataAndRefreshesPreview() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-import-reimport")
        let image = root.appendingPathComponent("one.jpg")
        try TestDirectories.writeTestJPEG(to: image, width: 1200, height: 800)
        let repository = try makeRepository(in: root)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)
        let firstResult = try service.addFolderInPlace(root, repository: repository)
        let assetID = firstResult.importedAssets[0].id
        try repository.updateMetadata(assetID: assetID) { metadata in
            metadata.rating = 4
            metadata.keywords = ["keeper"]
        }
        let previewURL = previewCache.url(for: PreviewCacheKey(assetID: assetID, level: .grid))
        try FileManager.default.removeItem(at: previewURL)
        try TestDirectories.writeTestJPEG(to: image, width: 640, height: 480)

        let secondResult = try service.addFolderInPlace(root, repository: repository)

        XCTAssertEqual(secondResult.importedAssets.map(\.id), [assetID])
        let fetched = try repository.asset(id: assetID)
        XCTAssertEqual(fetched.metadata.rating, 4)
        XCTAssertEqual(fetched.metadata.keywords, ["keeper"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
    }

    private func makeRepository(in root: URL) throws -> CatalogRepository {
        let database = try CatalogDatabase.open(at: root.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        return CatalogRepository(database: database)
    }

    private func makeService(previewCache: PreviewCache) -> LibraryImportService {
        LibraryImportService(
            ingestService: IngestService(scanner: FolderScanner(supportedExtensions: ["jpg"])),
            previewCache: previewCache,
            renderer: PreviewRenderer()
        )
    }
}
