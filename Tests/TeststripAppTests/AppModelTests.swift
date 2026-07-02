import XCTest
import TeststripCore
import TeststripApp

final class AppModelTests: XCTestCase {
    func testAppModelStartsWithStudioLayoutSections() {
        let model = AppModel.demo()

        XCTAssertTrue(model.sidebarSections.map(\.title).contains("Library"))
        XCTAssertTrue(model.sidebarSections.map(\.title).contains("Work"))
        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertEqual(model.selectedAsset?.id, model.assets.first?.id)
    }

    func testSidebarSectionCanBeConstructedByPublicClients() {
        let section = SidebarSection(title: "Library", rows: ["All Photographs"])

        XCTAssertEqual(section.title, "Library")
        XCTAssertEqual(section.rows, ["All Photographs"])
    }

    func testSelectingAssetUpdatesInspector() {
        let first = Asset(
            id: AssetID(rawValue: "first"),
            originalURL: URL(fileURLWithPath: "/Photos/first.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let second = Asset(
            id: AssetID(rawValue: "second"),
            originalURL: URL(fileURLWithPath: "/Photos/second.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 2, modificationDate: Date(timeIntervalSince1970: 2)),
            availability: .online,
            metadata: AssetMetadata()
        )
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [first, second])

        XCTAssertEqual(model.selectedAsset?.id, first.id)

        model.select(second.id)

        XCTAssertEqual(model.selectedAsset?.id, second.id)
    }

    func testLoadsAssetsFromCatalogRepository() throws {
        let directory = try makeTemporaryDirectory(named: "app-model")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = Asset(
            id: AssetID(rawValue: "catalog-asset"),
            originalURL: URL(fileURLWithPath: "/Photos/catalog.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata(rating: 5)
        )
        try repository.upsert(asset)

        let model = try AppModel.load(repository: repository)

        XCTAssertEqual(model.assets.map(\.id), [asset.id])
        XCTAssertEqual(model.selectedAsset?.id, asset.id)
    }

    func testLoadingEmptyRepositoryLeavesSelectionEmpty() throws {
        let directory = try makeTemporaryDirectory(named: "empty-app-model")
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)

        let model = try AppModel.load(repository: repository)

        XCTAssertEqual(model.assets, [])
        XCTAssertNil(model.selectedAssetID)
        XCTAssertNil(model.selectedAsset)
    }

    func testImportFolderReloadsAssetsAndExposesGridPreviewURL() throws {
        let directory = try makeTemporaryDirectory(named: "app-model-import")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        let result = try model.importFolder(photoFolder)

        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertEqual(model.assets.map(\.originalURL), [image])
        XCTAssertEqual(model.selectedAssetID, result.importedAssets[0].id)
        let previewURL = try XCTUnwrap(model.gridPreviewURL(for: result.importedAssets[0].id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        XCTAssertEqual(model.statusMessage, "Imported 1 photo")
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testBackgroundImportReloadsAssetsAndExposesGridPreviewURL() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-background-import")
        let photoFolder = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photoFolder, withIntermediateDirectories: true)
        let image = photoFolder.appendingPathComponent("one.png")
        try writeTestPNG(to: image)
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true))
        let catalog = try AppCatalog.open(paths: paths)
        let model = try AppModel.load(catalog: catalog)

        let result = try await model.importFolderInBackground(photoFolder)

        XCTAssertEqual(result.importedAssets.count, 1)
        XCTAssertEqual(model.assets.map(\.originalURL), [image])
        XCTAssertEqual(model.selectedAssetID, result.importedAssets[0].id)
        let previewURL = try XCTUnwrap(model.gridPreviewURL(for: result.importedAssets[0].id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: previewURL.path))
        XCTAssertEqual(model.statusMessage, "Imported 1 photo")
        XCTAssertNil(model.errorMessage)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-app-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeTestPNG(to url: URL) throws {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
        try XCTUnwrap(Data(base64Encoded: base64)).write(to: url)
    }
}
