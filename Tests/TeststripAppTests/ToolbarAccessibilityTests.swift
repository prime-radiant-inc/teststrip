import XCTest
import TeststripCore
@testable import TeststripApp

/// The toolbar's accessible names.
///
/// The lens switcher's segments use the same visible titles as toolbar action
/// buttons ("Cull" is both a lens and the Cull button), so the segments are
/// qualified to keep an assistive-technology user from hearing one name twice
/// in the toolbar with nothing to tell the controls apart. The Activity bell
/// carries an explicit label so it stops announcing its raw SF Symbol name.
final class ToolbarAccessibilityTests: XCTestCase {
    func testLensSegmentsAreQualified() {
        XCTAssertEqual(LensSwitcherAccessibility.segmentLabel(for: .cull), "Cull lens")
        XCTAssertEqual(LensSwitcherAccessibility.segmentLabel(for: .grid), "Grid lens")
    }

    func testLensSegmentsKeepTheirVisibleTitleInTheirAccessibleName() {
        for lens in LibraryLens.allCases {
            XCTAssertTrue(
                LensSwitcherAccessibility.segmentLabel(for: lens).hasPrefix(lens.title),
                "segment label must keep the visible title readable"
            )
        }
    }

    func testLensSegmentLabelsAreUnique() {
        let labels = LibraryLens.allCases.map(LensSwitcherAccessibility.segmentLabel(for:))
        XCTAssertEqual(Set(labels).count, labels.count)
    }

    // The collision the qualifier exists for: the Cull lens segment and the
    // Cull action button must not share an accessible name.
    func testCullLensSegmentIsNotNamedLikeTheCullToolbarButton() {
        XCTAssertNotEqual(LensSwitcherAccessibility.segmentLabel(for: .cull), "Cull")
        XCTAssertNotEqual(LensSwitcherAccessibility.segmentLabel(for: .cull), LibraryLens.cull.title)
    }
}
