import XCTest
@testable import TeststripApp

final class CullingNavLegendPresentationTests: XCTestCase {
    func testLegendShowsBaseNavigationWithoutStack() {
        let presentation = CullingNavLegendPresentation(isStackActive: false)

        XCTAssertEqual(presentation.legendText, "← → navigate · Space advances · Z 1:1")
    }

    func testLegendAddsStackNavigationWhenStackIsActive() {
        let presentation = CullingNavLegendPresentation(isStackActive: true)

        XCTAssertEqual(presentation.legendText, "← → navigate · Space advances · Z 1:1 · ↑↓ stacks · ↵ accept best")
    }
}
