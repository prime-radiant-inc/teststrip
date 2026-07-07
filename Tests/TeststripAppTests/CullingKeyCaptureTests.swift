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

    func testCullingShortcutMapsSpaceAndReturnKeyEvents() throws {
        let space = try makeKeyEvent(characters: " ", charactersIgnoringModifiers: " ", keyCode: 49)
        let returnKey = try makeKeyEvent(characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 36)
        let keypadEnter = try makeKeyEvent(characters: "\r", charactersIgnoringModifiers: "\r", keyCode: 76)

        XCTAssertEqual(CullingShortcut(event: space), .nextPhoto)
        XCTAssertEqual(CullingShortcut(event: returnKey), .acceptStackSelection)
        XCTAssertEqual(CullingShortcut(event: keypadEnter), .acceptStackSelection)
    }

    func testCullingShortcutMapsZoomToggleKeyEvent() throws {
        let lowercase = try makeKeyEvent(characters: "z", charactersIgnoringModifiers: "z")
        let uppercase = try makeKeyEvent(characters: "Z", charactersIgnoringModifiers: "z", modifierFlags: .shift)

        XCTAssertEqual(CullingShortcut(event: lowercase), .toggleZoom)
        XCTAssertEqual(CullingShortcut(event: uppercase), .toggleZoom)
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
