import XCTest
@testable import TeststripApp

final class CullingCommandMenuPresentationTests: XCTestCase {
    func testNavigationSectionExposesWithinStackAndCrossStackShortcuts() {
        let navigation = CullingCommandMenuPresentation.sections.first

        XCTAssertEqual(navigation?.items, [
            CullingCommandMenuItem(title: "Previous Frame in Stack", shortcut: .previousCandidateInStack, key: .character("↑ / K")),
            CullingCommandMenuItem(title: "Next Frame in Stack", shortcut: .nextCandidateInStack, key: .character("↓ / J")),
            CullingCommandMenuItem(title: "Previous Stack", shortcut: .previousStack, key: .character("← / H")),
            CullingCommandMenuItem(title: "Next Stack", shortcut: .nextStack, key: .character("→ / L")),
            CullingCommandMenuItem(title: "Promote Frame & Reject Siblings", shortcut: .promoteAndRejectSiblings, key: .returnKey)
        ])
    }

    // Task 5: the `/` faces-panel toggle is loupe chrome, so its menu row
    // sits with the other loupe view toggles.
    func testLoupeSectionExposesZoomExifFacesPanelAndKeyMapShortcuts() {
        let loupe = CullingCommandMenuPresentation.sections.first { $0.title == "Loupe" }

        XCTAssertEqual(loupe?.items, [
            CullingCommandMenuItem(title: "Toggle 1:1 Zoom", shortcut: .toggleZoom, key: .character("z")),
            CullingCommandMenuItem(title: "Zoom to Nearest Face", shortcut: .zoomToNearestFace, key: .character("Z")),
            CullingCommandMenuItem(title: "Cycle EXIF Overlay", shortcut: .cycleExifOverlay, key: .character("i")),
            CullingCommandMenuItem(title: "Toggle Faces Panel", shortcut: .toggleFacesPanel, key: .character("/")),
            CullingCommandMenuItem(title: "Show Key Map", shortcut: .showKeyMap, key: .character("?"))
        ])
    }

    // Task 2: the `A` auto-advance toggle sits alongside `S` cycle-filter —
    // both are run-control mode toggles, not decisions or navigation.
    // T7.5: the land-on-recommended-frame preference joins them here for the
    // same reason — a run-control mode toggle, not a decision or navigation
    // shortcut — but unlike its neighbors it has no keyboard shortcut at all
    // (see testLandOnRecommendedFrameToggleHasNoKeyDecodePath below).
    func testFilterSectionExposesCycleFilterAutoAdvanceAndLandOnRecommendedFrameToggles() {
        let filter = CullingCommandMenuPresentation.sections.first { $0.title == "Filter" }

        XCTAssertEqual(filter?.items, [
            CullingCommandMenuItem(title: "Cycle Filter", shortcut: .cycleScope, key: .character("s")),
            CullingCommandMenuItem(title: "Toggle Auto-Advance", shortcut: .toggleAutoAdvance, key: .character("a")),
            CullingCommandMenuItem(title: "Toggle Land on Recommended Frame", shortcut: .toggleLandOnRecommendedFrame, key: .character("—"))
        ])
    }

    // T7.5: unlike every other row (which also has a real key decoded by
    // CullingShortcut.init(key:), just not bound as an NSMenu key
    // equivalent — see CullingMenuSingleKeyOwnerTests below), this
    // preference toggle has no keyboard path at all: it's reachable by menu
    // click only, by construction.
    func testLandOnRecommendedFrameToggleHasNoKeyDecodePath() {
        XCTAssertNil(CullingShortcut(key: .character("—")))
    }
}

// The CullingKeyCaptureView local monitor is the single owner of every bare
// (modifier-less) culling key. A bare menu key equivalent fires through
// AppKit's performKeyEquivalent path independently of the monitor — the
// monitor consuming the NSEvent does not stop it — so any live bare menu
// equivalent double-dispatches the shortcut (one keypress writes two assets
// and advances twice; run-cull-iter2 cull-003/005/007).
final class CullingMenuSingleKeyOwnerTests: XCTestCase {
    func testNoCullingMenuItemCarriesAKeyEquivalent() {
        for section in CullingCommandMenuPresentation.sections {
            for item in section.items {
                XCTAssertNil(
                    item.key.menuKeyboardShortcut,
                    "\(item.title) (\(item.key.displayText)) must not bind a menu key equivalent — the culling key monitor is the single dispatch owner"
                )
            }
        }
    }
}
