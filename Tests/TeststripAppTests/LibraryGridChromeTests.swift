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

    func testImportCompletionSummaryShowsOnlyAfterImportFinishes() {
        XCTAssertTrue(LibraryGridChromePolicy.shouldShowImportCompletionSummary(
            isImporting: false,
            summaryID: "import-1",
            dismissedSummaryID: nil
        ))

        XCTAssertFalse(LibraryGridChromePolicy.shouldShowImportCompletionSummary(
            isImporting: true,
            summaryID: "import-1",
            dismissedSummaryID: nil
        ))
    }

    func testImportCompletionSummaryHidesAfterDismissal() {
        XCTAssertFalse(LibraryGridChromePolicy.shouldShowImportCompletionSummary(
            isImporting: false,
            summaryID: "import-1",
            dismissedSummaryID: "import-1"
        ))
    }
}
