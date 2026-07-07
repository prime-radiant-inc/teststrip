import XCTest
import TeststripCore

final class LibraryImportServiceDedupTests: XCTestCase {
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

    func testReimportCardNewOnlyCopiesNothingAndReportsAllAsExisting() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-dedup-card")
        let source = root.appendingPathComponent("DCIM", isDirectory: true)
        let destination = root.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: source.appendingPathComponent("IMG_0001.jpg"), width: 800, height: 600)
        try TestDirectories.writeTestJPEG(to: source.appendingPathComponent("IMG_0002.jpg"), width: 640, height: 480)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)
        let repository = try makeRepository(in: root)

        let firstResult = try service.copyFromCard(
            source: source,
            destinationRoot: destination,
            repository: repository,
            previewPolicy: .deferGeneration,
            duplicateHandling: .skipCatalogedContent
        )
        XCTAssertEqual(firstResult.newAssetCount, 2)
        XCTAssertEqual(firstResult.existingAssetCount, 0)

        let secondResult = try service.copyFromCard(
            source: source,
            destinationRoot: destination,
            repository: repository,
            previewPolicy: .deferGeneration,
            duplicateHandling: .skipCatalogedContent
        )

        XCTAssertEqual(secondResult.importedAssets, [])
        XCTAssertEqual(secondResult.newAssetCount, 0)
        XCTAssertEqual(secondResult.existingAssetCount, 2)
        XCTAssertEqual(try repository.allAssets(limit: 100).count, 2)
    }

    func testFolderImportNewOnlyCountsCrossPathDuplicate() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-dedup-cross-path")
        let firstFolder = root.appendingPathComponent("shoot-a", isDirectory: true)
        let secondFolder = root.appendingPathComponent("shoot-b", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: firstFolder.appendingPathComponent("original.jpg"), width: 900, height: 700)
        try FileManager.default.copyItem(
            at: firstFolder.appendingPathComponent("original.jpg"),
            to: secondFolder.appendingPathComponent("renamed.jpg")
        )
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)
        let repository = try makeRepository(in: root)

        _ = try service.addFolderInPlace(firstFolder, repository: repository, previewPolicy: .deferGeneration)
        let secondResult = try service.addFolderInPlace(
            secondFolder,
            repository: repository,
            previewPolicy: .deferGeneration,
            duplicateHandling: .skipCatalogedContent
        )

        XCTAssertEqual(secondResult.importedAssets, [])
        XCTAssertEqual(secondResult.newAssetCount, 0)
        XCTAssertEqual(secondResult.existingAssetCount, 1)
    }

    func testImportAllReimportKeepsPathBasedCounts() throws {
        let root = try TestDirectories.makeTemporaryDirectory(named: "library-dedup-import-all")
        let folder = root.appendingPathComponent("shoot", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: folder.appendingPathComponent("one.jpg"), width: 800, height: 600)
        let previewCache = PreviewCache(root: root.appendingPathComponent("previews", isDirectory: true))
        let service = makeService(previewCache: previewCache)
        let repository = try makeRepository(in: root)

        _ = try service.addFolderInPlace(folder, repository: repository, previewPolicy: .deferGeneration)
        // Default handling re-catalogs the same path: one asset returned, and
        // the path-based existing count recognizes it as already present.
        let secondResult = try service.addFolderInPlace(folder, repository: repository, previewPolicy: .deferGeneration)

        XCTAssertEqual(secondResult.importedAssets.count, 1)
        XCTAssertEqual(secondResult.newAssetCount, 0)
        XCTAssertEqual(secondResult.existingAssetCount, 1)
        XCTAssertEqual(try repository.allAssets(limit: 100).count, 1)
    }
}
