import XCTest
@testable import TeststripApp

final class CullingNavLegendPresentationTests: XCTestCase {
    func testLegendShowsBaseNavigationWithoutStack() {
        let presentation = CullingNavLegendPresentation(isStackActive: false)

        XCTAssertEqual(presentation.legendText, "← → navigate · Space advances")
    }

    func testLegendAddsStackNavigationWhenStackIsActive() {
        let presentation = CullingNavLegendPresentation(isStackActive: true)

        XCTAssertEqual(presentation.legendText, "← → navigate · Space advances · ↑↓ stacks · ↵ accept best")
    }
}
