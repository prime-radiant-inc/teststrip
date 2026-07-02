import XCTest
import TeststripApp

final class AppCatalogTests: XCTestCase {
    func testDefaultPathsLiveUnderApplicationSupportTeststrip() throws {
        let applicationSupport = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)

        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: applicationSupport)

        XCTAssertEqual(paths.root, applicationSupport.appendingPathComponent("Teststrip", isDirectory: true))
        XCTAssertEqual(paths.catalogURL, paths.root.appendingPathComponent("catalog.sqlite"))
        XCTAssertEqual(paths.previewCacheRoot, paths.root.appendingPathComponent("Previews", isDirectory: true))
    }

    func testLoadModelCreatesEmptyCatalogAndPreviewCache() throws {
        let root = try makeTemporaryDirectory(named: "app-catalog")
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: root)

        let model = try AppCatalog.loadModel(paths: paths)

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.catalogURL.path))
        XCTAssertTrue(directoryExists(at: paths.previewCacheRoot))
        XCTAssertEqual(model.assets, [])
        XCTAssertNil(model.selectedAssetID)
        XCTAssertNil(model.selectedAsset)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-app-catalog-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
