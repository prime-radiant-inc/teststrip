import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class AppModelTests: XCTestCase {
    func testAppModelStartsWithStudioLayoutSections() {
        let model = AppModel.demo()

        XCTAssertTrue(model.sidebarSections.map(\.title).contains("Library"))
        XCTAssertTrue(model.sidebarSections.map(\.title).contains("Work"))
        XCTAssertEqual(model.selectedView, .grid)
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

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-app-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
