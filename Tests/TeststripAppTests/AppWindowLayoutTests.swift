import XCTest
@testable import TeststripApp

final class AppWindowLayoutTests: XCTestCase {
    // Task 22: the global 1520pt floor is replaced by per-workspace minimums
    // so no workspace pays for another's chrome. Library carries the most
    // chrome (sidebar + inspector + footer), Cull's rail is narrower, People
    // has neither inspector nor filter chrome.
    func testEveryWorkspaceHasAMinimumWidth() {
        for workspace in Workspace.allCases {
            XCTAssertGreaterThan(AppWindowLayoutMetrics.minimumWidth(for: workspace), 0)
        }
    }

    func testLibraryHasTheWidestFloorAndPeopleTheNarrowest() {
        XCTAssertGreaterThan(
            AppWindowLayoutMetrics.minimumWidth(for: .library),
            AppWindowLayoutMetrics.minimumWidth(for: .cull)
        )
        XCTAssertGreaterThan(
            AppWindowLayoutMetrics.minimumWidth(for: .cull),
            AppWindowLayoutMetrics.minimumWidth(for: .people)
        )
    }

    func testMainWindowDefaultSizeIsAtLeastEveryWorkspaceMinimum() {
        for workspace in Workspace.allCases {
            XCTAssertGreaterThanOrEqual(AppWindowLayoutMetrics.defaultWidth, AppWindowLayoutMetrics.minimumWidth(for: workspace))
        }
        XCTAssertGreaterThanOrEqual(AppWindowLayoutMetrics.defaultHeight, AppWindowLayoutMetrics.minimumHeight)
    }
}
