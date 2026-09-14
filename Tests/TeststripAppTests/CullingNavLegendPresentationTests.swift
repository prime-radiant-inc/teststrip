import XCTest
@testable import TeststripApp

final class CullingNavLegendPresentationTests: XCTestCase {
    // H/L and J/K are bound vim-style aliases for the arrow keys
    // (CullingShortcut.init(key:)'s ".character" arm) — the legend must name
    // them alongside the arrows so they're discoverable, not just the arrows.
    func testLegendShowsBaseNavigationWithoutStack() {
        let presentation = CullingNavLegendPresentation(isStackActive: false)

        XCTAssertEqual(
            presentation.legendText,
            "← → / H L navigate · Space advances · P pick · X reject · U unflag · 0–5 rate · S filter · Z 1:1"
        )
    }

    func testLegendAddsStackNavigationWhenStackIsActive() {
        let presentation = CullingNavLegendPresentation(isStackActive: true)

        XCTAssertEqual(
            presentation.legendText,
            "← → / H L navigate · Space advances · P pick · X reject · U unflag · 0–5 rate · S filter · Z 1:1 · ↑↓ / J K stacks · ↵ accept best"
        )
    }

    // The always-visible legend must name the core culling decisions, not just
    // navigation — the ? keymap already carried them but was not discoverable.
    func testLegendNamesFlagRatingAndFilterKeys() {
        let presentation = CullingNavLegendPresentation(isStackActive: false)

        for fragment in ["P pick", "X reject", "U unflag", "0–5 rate", "S filter"] {
            XCTAssertTrue(
                presentation.legendText.contains(fragment),
                "legend must include \(fragment)"
            )
        }
    }
}
