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
}
