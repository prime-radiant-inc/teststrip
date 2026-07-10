import XCTest
@testable import TeststripApp

final class WorkspaceChromePolicyTests: XCTestCase {
    func testLibraryShowsAllChrome() {
        XCTAssertTrue(WorkspaceChromePolicy.showsSearchField(.library))
        XCTAssertTrue(WorkspaceChromePolicy.showsFilterTokens(.library))
        XCTAssertTrue(WorkspaceChromePolicy.showsImportButton(.library))
        XCTAssertTrue(WorkspaceChromePolicy.showsFooter(.library))
        XCTAssertTrue(WorkspaceChromePolicy.showsInspector(.library))
    }

    func testCullHidesAllBrowseChromeIncludingInspector() {
        XCTAssertFalse(WorkspaceChromePolicy.showsSearchField(.cull))
        XCTAssertFalse(WorkspaceChromePolicy.showsFilterTokens(.cull))
        XCTAssertFalse(WorkspaceChromePolicy.showsImportButton(.cull))
        XCTAssertFalse(WorkspaceChromePolicy.showsFooter(.cull))
        XCTAssertFalse(WorkspaceChromePolicy.showsInspector(.cull))
    }

    func testPeopleHidesBrowseChromeButAllowsTheOnDemandInspector() {
        XCTAssertFalse(WorkspaceChromePolicy.showsSearchField(.people))
        XCTAssertFalse(WorkspaceChromePolicy.showsFilterTokens(.people))
        XCTAssertFalse(WorkspaceChromePolicy.showsImportButton(.people))
        XCTAssertFalse(WorkspaceChromePolicy.showsFooter(.people))
        // ⌘I is reachable in People (Task 11); only Cull has no inspector.
        XCTAssertTrue(WorkspaceChromePolicy.showsInspector(.people))
    }

    // I2: Import ▾/Import Path/Find Best Shots/Cull/Export/More toolbar
    // items belong to Library only — Cull has no import/search chrome
    // (spec §3) and People has no browse chrome either.
    func testToolbarActionChromeMatrix() {
        for workspace in Workspace.allCases {
            let expected = workspace == .library
            XCTAssertEqual(WorkspaceChromePolicy.showsImportMenu(workspace), expected, "\(workspace)")
            XCTAssertEqual(WorkspaceChromePolicy.showsFindBestShotsButton(workspace), expected, "\(workspace)")
            XCTAssertEqual(WorkspaceChromePolicy.showsCullButton(workspace), expected, "\(workspace)")
            XCTAssertEqual(WorkspaceChromePolicy.showsExportButton(workspace), expected, "\(workspace)")
            XCTAssertEqual(WorkspaceChromePolicy.showsMoreMenu(workspace), expected, "\(workspace)")
        }
    }
}
