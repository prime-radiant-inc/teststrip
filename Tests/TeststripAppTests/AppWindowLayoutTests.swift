import XCTest
@testable import TeststripApp

final class AppWindowLayoutTests: XCTestCase {
    // One window, one floor: the per-workspace 1000/800 split went away with
    // the Cull|Library split, because there is no longer a workspace whose
    // chrome another workspace was paying for.
    func testTheWindowHasASingleMinimumWidth() {
        XCTAssertEqual(AppWindowLayoutMetrics.minimumWidth, 1_000)
    }

    func testMainWindowDefaultSizeClearsTheMinimums() {
        XCTAssertGreaterThanOrEqual(AppWindowLayoutMetrics.defaultWidth, AppWindowLayoutMetrics.minimumWidth)
        XCTAssertGreaterThanOrEqual(AppWindowLayoutMetrics.defaultHeight, AppWindowLayoutMetrics.minimumHeight)
    }
}
