import XCTest
@testable import TeststripApp

final class AppWindowLayoutTests: XCTestCase {
    func testMainWindowMinimumWidthContainsSplitContent() {
        XCTAssertGreaterThanOrEqual(
            AppWindowLayoutMetrics.minimumWidth,
            AppWindowLayoutMetrics.minimumSplitContentWidth
        )
    }

    func testMainWindowDefaultSizeIsAtLeastMinimumSize() {
        XCTAssertGreaterThanOrEqual(AppWindowLayoutMetrics.defaultWidth, AppWindowLayoutMetrics.minimumWidth)
        XCTAssertGreaterThanOrEqual(AppWindowLayoutMetrics.defaultHeight, AppWindowLayoutMetrics.minimumHeight)
    }
}
