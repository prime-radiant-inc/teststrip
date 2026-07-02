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

        XCTAssertEqual(CullingShortcut(event: left), .previousPhoto)
        XCTAssertEqual(CullingShortcut(event: right), .nextPhoto)
    }

    func testCullingShortcutIgnoresCommandModifiedKeyEvents() throws {
        let event = try makeKeyEvent(characters: "5", charactersIgnoringModifiers: "5", modifierFlags: .command)

        XCTAssertNil(CullingShortcut(event: event))
    }

    private func makeKeyEvent(
        characters: String,
        charactersIgnoringModifiers: String,
        modifierFlags: NSEvent.ModifierFlags = [],
        keyCode: UInt16 = 0
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
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
