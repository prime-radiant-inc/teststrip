import XCTest
@testable import TeststripApp

final class ExportReviewPresentationTests: XCTestCase {
    func testSelectedScopeCountsSelectionAndEnablesWhenNotEmpty() {
        let presentation = ExportReviewPresentation(
            visibleAssetCount: 12,
            selectedAssetCount: 3,
            currentScopeAssetCount: 500,
            selectedScope: .selected,
            requiresAllCatalogConfirmation: false,
            isAllCatalogConfirmed: false,
            isExporting: false
        )

        XCTAssertEqual(presentation.countText, "3 selected photos")
        XCTAssertTrue(presentation.isExportEnabled)
        XCTAssertEqual(presentation.exportTitle, "Export selected batch")
        XCTAssertNil(presentation.confirmationText)
    }

    func testSelectedScopeDisablesWhenSelectionIsEmpty() {
        let presentation = ExportReviewPresentation(
            visibleAssetCount: 12,
            selectedAssetCount: 0,
            currentScopeAssetCount: 500,
            selectedScope: .selected,
            requiresAllCatalogConfirmation: false,
            isAllCatalogConfirmed: false,
            isExporting: false
        )

        XCTAssertEqual(presentation.countText, "0 selected photos")
        XCTAssertFalse(presentation.isExportEnabled)
    }

    func testVisibleScopeCountsVisiblePhotos() {
        let presentation = ExportReviewPresentation(
            visibleAssetCount: 1,
            selectedAssetCount: 0,
            currentScopeAssetCount: 500,
            selectedScope: .visible,
            requiresAllCatalogConfirmation: false,
            isAllCatalogConfirmed: false,
            isExporting: false
        )

        XCTAssertEqual(presentation.countText, "1 visible photo")
        XCTAssertTrue(presentation.isExportEnabled)
        XCTAssertEqual(presentation.exportTitle, "Export visible batch")
    }

    func testCurrentScopeWithoutFiltersRequiresAllCatalogConfirmation() {
        let unconfirmed = ExportReviewPresentation(
            visibleAssetCount: 12,
            selectedAssetCount: 0,
            currentScopeAssetCount: 500,
            selectedScope: .currentScope,
            requiresAllCatalogConfirmation: true,
            isAllCatalogConfirmed: false,
            isExporting: false
        )
        let confirmed = ExportReviewPresentation(
            visibleAssetCount: 12,
            selectedAssetCount: 0,
            currentScopeAssetCount: 500,
            selectedScope: .currentScope,
            requiresAllCatalogConfirmation: true,
            isAllCatalogConfirmed: true,
            isExporting: false
        )

        XCTAssertEqual(unconfirmed.countText, "500 photos in current scope")
        XCTAssertEqual(unconfirmed.confirmationText, "Confirm exporting all 500 catalog photos.")
        XCTAssertFalse(unconfirmed.isExportEnabled)
        XCTAssertTrue(confirmed.isExportEnabled)
        XCTAssertEqual(confirmed.exportTitle, "Export current scope")
    }

    func testRunningExportDisablesAnotherExport() {
        let presentation = ExportReviewPresentation(
            visibleAssetCount: 12,
            selectedAssetCount: 3,
            currentScopeAssetCount: 500,
            selectedScope: .visible,
            requiresAllCatalogConfirmation: false,
            isAllCatalogConfirmed: false,
            isExporting: true
        )

        XCTAssertFalse(presentation.isExportEnabled)
    }
}
