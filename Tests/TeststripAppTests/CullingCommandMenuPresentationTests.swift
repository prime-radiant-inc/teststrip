import XCTest
@testable import TeststripApp

final class CullingCommandMenuPresentationTests: XCTestCase {
    func testNavigationSectionExposesPhotoAndStackShortcuts() {
        let navigation = CullingCommandMenuPresentation.sections.first

        XCTAssertEqual(navigation?.items.filter { !$0.isMonitorOnly }, [
            CullingCommandMenuItem(title: "Previous Photo", shortcut: .previousPhoto, key: .leftArrow),
            CullingCommandMenuItem(title: "Next Photo", shortcut: .nextPhoto, key: .rightArrow),
            CullingCommandMenuItem(title: "Previous Stack", shortcut: .previousStack, key: .upArrow),
            CullingCommandMenuItem(title: "Next Stack", shortcut: .nextStack, key: .downArrow),
            CullingCommandMenuItem(title: "Promote Frame & Reject Siblings", shortcut: .promoteAndRejectSiblings, key: .returnKey)
        ])
    }

    func testNavigationSectionExposesMonitorOnlyOptionArrowAlternates() {
        let navigation = CullingCommandMenuPresentation.sections.first

        XCTAssertEqual(navigation?.items.filter(\.isMonitorOnly), [
            CullingCommandMenuItem(title: "Previous Stack (Option)", shortcut: .previousStack, key: .optionLeftArrow, isMonitorOnly: true),
            CullingCommandMenuItem(title: "Next Stack (Option)", shortcut: .nextStack, key: .optionRightArrow, isMonitorOnly: true)
        ])
    }

    func testLoupeSectionExposesZoomExifAndKeyMapShortcuts() {
        let loupe = CullingCommandMenuPresentation.sections.first { $0.title == "Loupe" }

        XCTAssertEqual(loupe?.items, [
            CullingCommandMenuItem(title: "Toggle 1:1 Zoom", shortcut: .toggleZoom, key: .character("z")),
            CullingCommandMenuItem(title: "Zoom to Nearest Face", shortcut: .zoomToNearestFace, key: .character("Z")),
            CullingCommandMenuItem(title: "Cycle EXIF Overlay", shortcut: .cycleExifOverlay, key: .character("i")),
            CullingCommandMenuItem(title: "Show Key Map", shortcut: .showKeyMap, key: .character("?"))
        ])
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
