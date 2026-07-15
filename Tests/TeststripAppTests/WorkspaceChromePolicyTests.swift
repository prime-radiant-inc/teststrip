import XCTest
@testable import TeststripApp

/// `WorkspaceChromePolicy` is keyed on the selected `LibraryViewMode`, not the
/// workspace: People is a Library-workspace view but a focused, non-browse one,
/// so it must suppress the browse chrome the other Library views carry.
final class WorkspaceChromePolicyTests: XCTestCase {
    /// The Library *browse* views (Grid/Timeline/Map/Library Loupe) carry the
    /// full browse chrome.
    private static let browseViews: [LibraryViewMode] = [.grid, .timeline, .map, .libraryLoupe]

    /// The focused views (People + every Cull view) carry none of the browse
    /// chrome.
    private static let nonBrowseViews: [LibraryViewMode] = [.people, .loupe, .compare, .abCompare, .cullGrid]

    func testBrowseViewsShowAllBrowseChrome() {
        for view in Self.browseViews {
            XCTAssertTrue(WorkspaceChromePolicy.showsSearchField(view), "\(view)")
            XCTAssertTrue(WorkspaceChromePolicy.showsFilterTokens(view), "\(view)")
            XCTAssertTrue(WorkspaceChromePolicy.showsImportButton(view), "\(view)")
            XCTAssertTrue(WorkspaceChromePolicy.showsFooter(view), "\(view)")
            XCTAssertTrue(WorkspaceChromePolicy.showsImportMenu(view), "\(view)")
            XCTAssertTrue(WorkspaceChromePolicy.showsCullButton(view), "\(view)")
            XCTAssertTrue(WorkspaceChromePolicy.showsExportButton(view), "\(view)")
            XCTAssertTrue(WorkspaceChromePolicy.showsMoreMenu(view), "\(view)")
            XCTAssertTrue(WorkspaceChromePolicy.showsLibraryViewToggle(view), "\(view)")
            XCTAssertTrue(WorkspaceChromePolicy.showsInspector(view), "\(view)")
        }
    }

    func testPeopleShowsOnlyTheToggleAndInspector() {
        XCTAssertFalse(WorkspaceChromePolicy.showsSearchField(.people))
        XCTAssertFalse(WorkspaceChromePolicy.showsFilterTokens(.people))
        XCTAssertFalse(WorkspaceChromePolicy.showsImportButton(.people))
        XCTAssertFalse(WorkspaceChromePolicy.showsFooter(.people))
        XCTAssertFalse(WorkspaceChromePolicy.showsImportMenu(.people))
        XCTAssertFalse(WorkspaceChromePolicy.showsCullButton(.people))
        XCTAssertFalse(WorkspaceChromePolicy.showsExportButton(.people))
        XCTAssertFalse(WorkspaceChromePolicy.showsMoreMenu(.people))
        // People is a Library view, so the sub-view toggle stays visible — it's
        // the only way back to Grid — and the on-demand inspector is reachable.
        XCTAssertTrue(WorkspaceChromePolicy.showsLibraryViewToggle(.people))
        XCTAssertTrue(WorkspaceChromePolicy.showsInspector(.people))
    }

    func testCullViewsHideBrowseChromeButAllowTheInspector() {
        for view in [LibraryViewMode.loupe, .compare, .abCompare, .cullGrid] {
            XCTAssertFalse(WorkspaceChromePolicy.showsSearchField(view), "\(view)")
            XCTAssertFalse(WorkspaceChromePolicy.showsFilterTokens(view), "\(view)")
            XCTAssertFalse(WorkspaceChromePolicy.showsImportButton(view), "\(view)")
            XCTAssertFalse(WorkspaceChromePolicy.showsFooter(view), "\(view)")
            XCTAssertFalse(WorkspaceChromePolicy.showsImportMenu(view), "\(view)")
            XCTAssertFalse(WorkspaceChromePolicy.showsCullButton(view), "\(view)")
            XCTAssertFalse(WorkspaceChromePolicy.showsExportButton(view), "\(view)")
            XCTAssertFalse(WorkspaceChromePolicy.showsMoreMenu(view), "\(view)")
            XCTAssertFalse(WorkspaceChromePolicy.showsLibraryViewToggle(view), "\(view)")
            // Task 5: the single-image inspector is reachable from the Cull
            // loupe too, not just Library/People.
            XCTAssertTrue(WorkspaceChromePolicy.showsInspector(view), "\(view)")
        }
    }

    // The browse toolbar actions match the browse-chrome predicate across every
    // view: only the Library browse views carry Import ▾/Cull/Export/More.
    func testToolbarActionChromeMatrix() {
        for view in LibraryViewMode.allCases {
            let expected = Self.browseViews.contains(view)
            XCTAssertEqual(WorkspaceChromePolicy.showsImportMenu(view), expected, "\(view)")
            XCTAssertEqual(WorkspaceChromePolicy.showsCullButton(view), expected, "\(view)")
            XCTAssertEqual(WorkspaceChromePolicy.showsExportButton(view), expected, "\(view)")
            XCTAssertEqual(WorkspaceChromePolicy.showsMoreMenu(view), expected, "\(view)")
        }
    }
}
