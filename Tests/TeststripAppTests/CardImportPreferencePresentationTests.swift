import XCTest
@testable import TeststripApp
@testable import TeststripCore

final class CardImportPreferencePresentationTests: XCTestCase {
    func testDestinationDisplayShowsPathWhenSet() {
        XCTAssertEqual(
            CardImportPreferencePresentation.destinationDisplay("/Volumes/Photos/Import"),
            "/Volumes/Photos/Import"
        )
    }

    func testDestinationDisplayShowsNoneWhenEmpty() {
        XCTAssertEqual(CardImportPreferencePresentation.destinationDisplay(""), "None")
    }

    func testShowsClearIsTrueWhenPathIsSet() {
        XCTAssertTrue(CardImportPreferencePresentation.showsClear("/Volumes/Photos/Import"))
    }

    func testShowsClearIsFalseWhenPathIsEmpty() {
        XCTAssertFalse(CardImportPreferencePresentation.showsClear(""))
    }

    func testShowsClearIsFalseWhenPathIsWhitespaceOnly() {
        XCTAssertFalse(CardImportPreferencePresentation.showsClear("   "))
    }

    func testFooterCopyIsExact() {
        XCTAssertEqual(
            CardImportPreferencePresentation.footer,
            "Pre-fills the destination for new card imports. Originals are copied — never moved — into dated folders (YYYY/YYYY-MM-DD)."
        )
    }
}
