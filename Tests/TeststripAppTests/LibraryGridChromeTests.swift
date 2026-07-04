import XCTest
@testable import TeststripApp

final class LibraryGridChromeTests: XCTestCase {
    func testImportProgressBannerShowsBeforeAssetsAreVisible() {
        XCTAssertTrue(LibraryGridChromePolicy.shouldShowImportProgressBanner(
            isImporting: true,
            visibleAssetCount: 0
        ))
    }

    func testImportProgressBannerHidesWhenImportIsInactive() {
        XCTAssertFalse(LibraryGridChromePolicy.shouldShowImportProgressBanner(
            isImporting: false,
            visibleAssetCount: 12
        ))
    }
}
