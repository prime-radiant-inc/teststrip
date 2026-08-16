import XCTest
@testable import TeststripApp

/// `LensChromePolicy` is keyed on the selected `LibraryViewMode` through its
/// lens: the browse lenses (Grid/Loupe/Timeline/Map) carry the full browse
/// chrome; the focused lenses (Cull and People) carry none of it.
final class LensChromePolicyTests: XCTestCase {
    private static let browseViews: [LibraryViewMode] = [.grid, .libraryLoupe, .timeline, .map]
    private static let focusedViews: [LibraryViewMode] = [.people, .loupe, .compare, .abCompare, .cullGrid]

    func testBrowseLensesShowAllBrowseChrome() {
        for view in Self.browseViews {
            XCTAssertTrue(LensChromePolicy.showsSearchField(view), "\(view)")
            XCTAssertTrue(LensChromePolicy.showsFilterTokens(view), "\(view)")
            XCTAssertTrue(LensChromePolicy.showsImportButton(view), "\(view)")
            XCTAssertTrue(LensChromePolicy.showsFooter(view), "\(view)")
            XCTAssertTrue(LensChromePolicy.showsImportMenu(view), "\(view)")
            XCTAssertTrue(LensChromePolicy.showsCullButton(view), "\(view)")
            XCTAssertTrue(LensChromePolicy.showsExportButton(view), "\(view)")
            XCTAssertTrue(LensChromePolicy.showsMoreMenu(view), "\(view)")
            XCTAssertTrue(LensChromePolicy.showsInspector(view), "\(view)")
        }
    }

    func testFocusedLensesHideBrowseChromeButKeepTheInspector() {
        for view in Self.focusedViews {
            XCTAssertFalse(LensChromePolicy.showsSearchField(view), "\(view)")
            XCTAssertFalse(LensChromePolicy.showsFilterTokens(view), "\(view)")
            XCTAssertFalse(LensChromePolicy.showsImportButton(view), "\(view)")
            XCTAssertFalse(LensChromePolicy.showsFooter(view), "\(view)")
            XCTAssertFalse(LensChromePolicy.showsImportMenu(view), "\(view)")
            XCTAssertFalse(LensChromePolicy.showsCullButton(view), "\(view)")
            XCTAssertFalse(LensChromePolicy.showsExportButton(view), "\(view)")
            XCTAssertFalse(LensChromePolicy.showsMoreMenu(view), "\(view)")
            // ⌘I is reachable in every lens.
            XCTAssertTrue(LensChromePolicy.showsInspector(view), "\(view)")
        }
    }

    func testToolbarActionChromeMatrixCoversEveryViewMode() {
        for view in LibraryViewMode.allCases {
            let expected = Self.browseViews.contains(view)
            XCTAssertEqual(LensChromePolicy.showsImportMenu(view), expected, "\(view)")
            XCTAssertEqual(LensChromePolicy.showsCullButton(view), expected, "\(view)")
            XCTAssertEqual(LensChromePolicy.showsExportButton(view), expected, "\(view)")
            XCTAssertEqual(LensChromePolicy.showsMoreMenu(view), expected, "\(view)")
        }
    }
}
