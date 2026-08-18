import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class ImportSheetWiringTests: XCTestCase {

    func testSupportedExtensionsReturnsCatalogableExtensions() {
        let model = AppModel.demo()
        XCTAssertEqual(
            model.supportedExtensions,
            ImageIODecodeProvider.catalogableExtensions
        )
    }

    @MainActor
    func testPendingImportFoldersInitiallyEmpty() {
        let model = AppModel.demo()
        XCTAssertTrue(model.pendingImportFolders.isEmpty)
        XCTAssertEqual(model.pendingImportFolders.count, 0)
    }

    @MainActor
    func testBeginImportFoldersQueuesRemainingFoldersBeyondFirst() {
        let model = AppModel.demo()
        let urls = [
            URL(fileURLWithPath: "/tmp/import-sheet/a", isDirectory: true),
            URL(fileURLWithPath: "/tmp/import-sheet/b", isDirectory: true),
            URL(fileURLWithPath: "/tmp/import-sheet/c", isDirectory: true)
        ]
        model.beginImportFolders(urls)
        XCTAssertEqual(model.pendingImportFolders.count, 2)
        XCTAssertEqual(
            model.pendingImportFolders.map(\.url),
            [urls[1], urls[2]]
        )
    }

    @MainActor
    func testBeginImportFoldersWithSingleFolderQueuesNothing() {
        let model = AppModel.demo()
        model.beginImportFolders([
            URL(fileURLWithPath: "/tmp/import-sheet/only", isDirectory: true)
        ])
        XCTAssertTrue(model.pendingImportFolders.isEmpty)
    }
}
