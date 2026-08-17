import XCTest
import SwiftUI
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

/// F14.2 — the bare-key/menu double-dispatch landmine — has two sides:
/// 1. Culling keys must not carry menu key equivalents (tested above).
/// 2. Lens shortcuts (⌘1–⌘6) must be modifier-bearing. If the `.command`
///    modifier were stripped from `main.swift`'s binding, the key equivalent
///    would fire through AppKit's `performKeyEquivalent` path independently of
///    the in-view monitor — one keypress would dispatch twice.
///    We pin the key-equivalent values here; the modifier is applied at the
///    call site (`main.swift`'s `LibraryCommands`) and documented by the
///    comment on `LibraryLens.keyEquivalent`.
final class LensShortcutModifierTests: XCTestCase {
    func testLensKeyEquivalentsAreOneThroughSixInDeclarationOrder() {
        let equivalents = LibraryLens.allCases.map(\.keyEquivalent)
        let expected: [KeyEquivalent] = ["1", "2", "3", "4", "5", "6"].map { KeyEquivalent($0) }
        XCTAssertEqual(equivalents, expected,
                       "Lens shortcuts must be ⌘1–⌘6 in declaration order — a bare (modifier-less) equivalent double-dispatches (F14.2)")
    }

    func testLensKeyEquivalentsAreUnique() {
        let equivalents = LibraryLens.allCases.map(\.keyEquivalent)
        XCTAssertEqual(Set(equivalents).count, equivalents.count,
                       "Two lenses sharing a key equivalent would conflict in the menu")
    }
}
