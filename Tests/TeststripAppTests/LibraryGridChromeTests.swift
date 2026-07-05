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

    func testPendingMetadataSyncRetryActionShowsOnlyForPendingFilter() {
        XCTAssertTrue(LibraryGridChromePolicy.shouldShowPendingMetadataSyncRetryAction(
            isPendingFilterActive: true
        ))
        XCTAssertFalse(LibraryGridChromePolicy.shouldShowPendingMetadataSyncRetryAction(
            isPendingFilterActive: false
        ))
    }

    func testPendingMetadataSyncRetryActionDisablesDuringImportOrWithoutRetryableWork() {
        XCTAssertFalse(LibraryGridChromePolicy.isPendingMetadataSyncRetryActionDisabled(
            isImporting: false,
            canRetry: true
        ))
        XCTAssertTrue(LibraryGridChromePolicy.isPendingMetadataSyncRetryActionDisabled(
            isImporting: true,
            canRetry: true
        ))
        XCTAssertTrue(LibraryGridChromePolicy.isPendingMetadataSyncRetryActionDisabled(
            isImporting: false,
            canRetry: false
        ))
    }

    func testMetadataSyncFilterOptionMapsPendingAndConflictFlags() {
        XCTAssertEqual(MetadataSyncFilterOption(pending: false, conflict: false), .any)
        XCTAssertEqual(MetadataSyncFilterOption(pending: true, conflict: false), .pending)
        XCTAssertEqual(MetadataSyncFilterOption(pending: false, conflict: true), .conflicts)
        XCTAssertEqual(MetadataSyncFilterOption(pending: true, conflict: true), .conflicts)
        XCTAssertEqual(MetadataSyncFilterOption.pending.pendingFilter, true)
        XCTAssertEqual(MetadataSyncFilterOption.pending.conflictFilter, false)
        XCTAssertEqual(MetadataSyncFilterOption.conflicts.pendingFilter, false)
        XCTAssertEqual(MetadataSyncFilterOption.conflicts.conflictFilter, true)
    }
}
