import AppKit
import XCTest
@testable import TeststripApp

final class CullingKeyCaptureTests: XCTestCase {
    func testCullingShortcutMapsRatingKeyEvent() throws {
        let event = try makeKeyEvent(characters: "5", charactersIgnoringModifiers: "5")

        XCTAssertEqual(CullingShortcut(event: event), .rating(5))
    }

    func testCullingShortcutMapsShiftedPickKeyEvent() throws {
        let event = try makeKeyEvent(characters: "P", charactersIgnoringModifiers: "p", modifierFlags: .shift)

        XCTAssertEqual(CullingShortcut(event: event), .pick)
    }

    func testCullingShortcutMapsArrowKeyEvents() throws {
        let left = try makeKeyEvent(
            characters: arrowCharacter(NSLeftArrowFunctionKey),
            charactersIgnoringModifiers: arrowCharacter(NSLeftArrowFunctionKey),
            keyCode: 123
        )
        let right = try makeKeyEvent(
            characters: arrowCharacter(NSRightArrowFunctionKey),
            charactersIgnoringModifiers: arrowCharacter(NSRightArrowFunctionKey),
            keyCode: 124
        )
        let up = try makeKeyEvent(
            characters: arrowCharacter(NSUpArrowFunctionKey),
            charactersIgnoringModifiers: arrowCharacter(NSUpArrowFunctionKey),
            keyCode: 126
        )
        let down = try makeKeyEvent(
            characters: arrowCharacter(NSDownArrowFunctionKey),
            charactersIgnoringModifiers: arrowCharacter(NSDownArrowFunctionKey),
            keyCode: 125
        )

        XCTAssertEqual(CullingShortcut(event: left), .previousPhoto)
        XCTAssertEqual(CullingShortcut(event: right), .nextPhoto)
        XCTAssertEqual(CullingShortcut(event: up), .previousStack)
        XCTAssertEqual(CullingShortcut(event: down), .nextStack)
    }

    func testCullingShortcutMapsOptionArrowKeyEventsToStackNavigation() throws {
        let optionLeft = try makeKeyEvent(
            characters: arrowCharacter(NSLeftArrowFunctionKey),
            charactersIgnoringModifiers: arrowCharacter(NSLeftArrowFunctionKey),
            modifierFlags: .option,
            keyCode: 123
        )
        let optionRight = try makeKeyEvent(
            characters: arrowCharacter(NSRightArrowFunctionKey),
            charactersIgnoringModifiers: arrowCharacter(NSRightArrowFunctionKey),
            modifierFlags: .option,
            keyCode: 124
        )

        XCTAssertEqual(CullingShortcut(event: optionLeft), .previousStack)
        XCTAssertEqual(CullingShortcut(event: optionRight), .nextStack)
    }

    func testCullingShortcutIgnoresOptionModifiedNonArrowKeyEvents() throws {
        let event = try makeKeyEvent(characters: "5", charactersIgnoringModifiers: "5", modifierFlags: .option)

        XCTAssertNil(CullingShortcut(event: event))
    }

    func testCullingShortcutMapsSpaceAndReturnKeyEvents() throws {
        let space = try makeKeyEvent(characters: " ", charactersIgnoringModifiers: " ", keyCode: 49)
        let returnKey = try makeKeyEvent(characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36)
        let keypadEnter = try makeKeyEvent(characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 76)

        XCTAssertEqual(CullingShortcut(event: space), .nextPhoto)
        XCTAssertEqual(CullingShortcut(event: returnKey), .promoteAndRejectSiblings)
        XCTAssertEqual(CullingShortcut(event: keypadEnter), .promoteAndRejectSiblings)
    }

    func testCullingShortcutMapsZoomToggleKeyEvent() throws {
        let lowercase = try makeKeyEvent(characters: "z", charactersIgnoringModifiers: "z")

        XCTAssertEqual(CullingShortcut(event: lowercase), .toggleZoom)
    }

    // Shift-Z is a distinct shortcut (zoom to nearest face) from plain z
    // (toggle 1:1 zoom). charactersIgnoringModifiers strips Shift along with
    // the other modifiers (real hardware reports the base "z", not "Z" —
    // see testCullingShortcutMapsShiftedPickKeyEvent above), so this must be
    // detected from the modifier flag, not character case.
    func testCullingShortcutMapsShiftZKeyEventToZoomToNearestFace() throws {
        let event = try makeKeyEvent(characters: "Z", charactersIgnoringModifiers: "z", modifierFlags: .shift)

        XCTAssertEqual(CullingShortcut(event: event), .zoomToNearestFace)
    }

    func testCullingShortcutMapsShiftSlashKeyEventToShowKeyMap() throws {
        let event = try makeKeyEvent(characters: "?", charactersIgnoringModifiers: "/", modifierFlags: .shift)

        XCTAssertEqual(CullingShortcut(event: event), .showKeyMap)
    }

    func testCullingShortcutIgnoresCommandModifiedKeyEvents() throws {
        let event = try makeKeyEvent(characters: "5", charactersIgnoringModifiers: "5", modifierFlags: .command)

        XCTAssertNil(CullingShortcut(event: event))
    }

    @MainActor
    func testKeyCaptureHandlesShortcutWhenAnotherControlHasFocus() throws {
        let view = CullingKeyCaptureNSView()
        let button = NSButton(title: "Focused", target: nil, action: nil)
        var shortcuts: [CullingShortcut] = []
        view.onShortcut = { shortcuts.append($0) }

        let event = try makeKeyEvent(characters: "3", charactersIgnoringModifiers: "3", windowNumber: 42)

        XCTAssertNil(view.handleLocalKeyDown(event, targetWindowNumber: 42, targetWindowIsKey: true, firstResponder: button))
        XCTAssertEqual(shortcuts, [.rating(3)])
    }

    @MainActor
    func testKeyCaptureHandlesWindowlessShortcutWhenTargetWindowIsKey() throws {
        let view = CullingKeyCaptureNSView()
        var shortcuts: [CullingShortcut] = []
        view.onShortcut = { shortcuts.append($0) }

        let event = try makeKeyEvent(characters: "3", charactersIgnoringModifiers: "3", windowNumber: 0)

        XCTAssertNil(view.handleLocalKeyDown(event, targetWindowNumber: 42, targetWindowIsKey: true, firstResponder: nil))
        XCTAssertEqual(shortcuts, [.rating(3)])
    }

    @MainActor
    func testKeyCaptureHandlesSyntheticShortcutWhenTargetWindowIsKey() throws {
        let view = CullingKeyCaptureNSView()
        let button = NSButton(title: "Focused", target: nil, action: nil)
        var shortcuts: [CullingShortcut] = []
        view.onShortcut = { shortcuts.append($0) }

        let event = try makeKeyEvent(characters: "3", charactersIgnoringModifiers: "3", windowNumber: 777)

        XCTAssertNil(view.handleLocalKeyDown(event, targetWindowNumber: 42, targetWindowIsKey: true, firstResponder: button))
        XCTAssertEqual(shortcuts, [.rating(3)])
    }

    @MainActor
    func testKeyCaptureLeavesWindowlessShortcutAloneWhenTargetWindowIsNotKey() throws {
        let view = CullingKeyCaptureNSView()
        var shortcuts: [CullingShortcut] = []
        view.onShortcut = { shortcuts.append($0) }

        let event = try makeKeyEvent(characters: "3", charactersIgnoringModifiers: "3", windowNumber: 0)

        XCTAssertIdentical(view.handleLocalKeyDown(event, targetWindowNumber: 42, targetWindowIsKey: false, firstResponder: nil), event)
        XCTAssertEqual(shortcuts, [])
    }

    @MainActor
    func testKeyCaptureLeavesTextEditingEventsAlone() throws {
        let view = CullingKeyCaptureNSView()
        let textView = NSTextView(frame: .zero)
        var shortcuts: [CullingShortcut] = []
        view.onShortcut = { shortcuts.append($0) }

        let event = try makeKeyEvent(characters: "3", charactersIgnoringModifiers: "3", windowNumber: 42)

        XCTAssertIdentical(view.handleLocalKeyDown(event, targetWindowNumber: 42, targetWindowIsKey: true, firstResponder: textView), event)
        XCTAssertEqual(shortcuts, [])
    }

    // C1: the culling monitor must be scoped to the Cull workspace's
    // loupe/compare/A-B sub-views only — never People/Timeline/Map (hidden
    // chrome hazard: Return would promote-and-reject-siblings, P/X/ratings
    // would write metadata, g/c/b would teleport the view), and never
    // .cullGrid (which owns GridKeyCaptureView instead).
    func testCullingKeyCaptureGateInactiveOutsideCullWorkspace() {
        XCTAssertFalse(CullingKeyCaptureGate.isActive(workspace: .people, selectedView: .people))
        XCTAssertFalse(CullingKeyCaptureGate.isActive(workspace: .library, selectedView: .timeline))
        XCTAssertFalse(CullingKeyCaptureGate.isActive(workspace: .library, selectedView: .map))
        XCTAssertFalse(CullingKeyCaptureGate.isActive(workspace: .library, selectedView: .grid))
        XCTAssertFalse(CullingKeyCaptureGate.isActive(workspace: .library, selectedView: .libraryLoupe))
    }

    func testCullingShortcutMapsPageUpAndPageDownKeyEvents() throws {
        let pageUp = try makeKeyEvent(characters: "", charactersIgnoringModifiers: "", keyCode: 116)
        let pageDown = try makeKeyEvent(characters: "", charactersIgnoringModifiers: "", keyCode: 121)

        XCTAssertEqual(CullingShortcut(event: pageUp), .keyMapPageUp)
        XCTAssertEqual(CullingShortcut(event: pageDown), .keyMapPageDown)
    }

    // Persona-3 item 1: Esc only exits the A/B-compare modal trap in
    // .compare/.abCompare — .loupe keeps its own (untouched) Escape path via
    // GridKeyCaptureView, so this view must let Esc pass through there.
    @MainActor
    func testEscapeExitsCompareLikeModeAsExitCullSubViewShortcut() throws {
        let view = CullingKeyCaptureNSView()
        view.isCompareLikeMode = true
        var shortcuts: [CullingShortcut] = []
        view.onShortcut = { shortcuts.append($0) }

        let event = try makeKeyEvent(characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53, windowNumber: 42)

        XCTAssertNil(view.handleLocalKeyDown(event, targetWindowNumber: 42, targetWindowIsKey: true, firstResponder: nil))
        XCTAssertEqual(shortcuts, [.exitCullSubView])
    }

    @MainActor
    func testEscapePassesThroughWhenNotCompareLikeMode() throws {
        let view = CullingKeyCaptureNSView()
        view.isCompareLikeMode = false
        var shortcuts: [CullingShortcut] = []
        view.onShortcut = { shortcuts.append($0) }

        let event = try makeKeyEvent(characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", keyCode: 53, windowNumber: 42)

        XCTAssertIdentical(view.handleLocalKeyDown(event, targetWindowNumber: 42, targetWindowIsKey: true, firstResponder: nil), event)
        XCTAssertEqual(shortcuts, [])
    }

    func testCullingKeyCaptureGateActiveInCullSubViewsExceptGrid() {
        XCTAssertTrue(CullingKeyCaptureGate.isActive(workspace: .cull, selectedView: .loupe))
        XCTAssertTrue(CullingKeyCaptureGate.isActive(workspace: .cull, selectedView: .compare))
        XCTAssertTrue(CullingKeyCaptureGate.isActive(workspace: .cull, selectedView: .abCompare))
        XCTAssertFalse(CullingKeyCaptureGate.isActive(workspace: .cull, selectedView: .cullGrid))
    }

    private func makeKeyEvent(
        characters: String,
        charactersIgnoringModifiers: String,
        modifierFlags: NSEvent.ModifierFlags = [],
        keyCode: UInt16 = 0,
        windowNumber: Int = 0
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func arrowCharacter(_ key: Int) -> String {
        guard let scalar = UnicodeScalar(key) else { return "" }
        return String(scalar)
    }
}
