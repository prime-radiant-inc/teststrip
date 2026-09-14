import AppKit
import XCTest
@testable import TeststripApp

final class KeyMonitorForwardingTests: XCTestCase {
    private func makeEvent() throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "3",
            charactersIgnoringModifiers: "3",
            isARepeat: false,
            keyCode: 20
        ))
    }

    // The regression: a live view that consumed the key (handler verdict nil)
    // must forward nil, so the monitor drops the event instead of re-dispatching
    // it up the responder chain (which fires the command AND beeps).
    func testLiveViewForwardsConsumeVerdict() throws {
        let event = try makeEvent()

        XCTAssertNil(KeyMonitorForwarding.result(viewIsAlive: true, handlerVerdict: nil, event: event))
    }

    // A live view that did not handle the key forwards the event so it keeps
    // travelling the responder chain.
    func testLiveViewForwardsPassthroughVerdict() throws {
        let event = try makeEvent()

        XCTAssertIdentical(
            KeyMonitorForwarding.result(viewIsAlive: true, handlerVerdict: event, event: event),
            event
        )
    }

    // A deallocated view passes the event through unchanged.
    func testDeallocatedViewPassesEventThrough() throws {
        let event = try makeEvent()

        XCTAssertIdentical(
            KeyMonitorForwarding.result(viewIsAlive: false, handlerVerdict: nil, event: event),
            event
        )
    }

    // MARK: - KeyMonitorFocusPolicy

    // Nothing focused (or a plain content view) still belongs to the grid: the
    // monitor keeps consuming, which is how arrow keys move the grid after a
    // click in the content area.
    func testMonitorOwnsKeysWhenNoControlHasFocus() {
        XCTAssertFalse(KeyMonitorFocusPolicy.shouldYield(firstResponder: nil))
        XCTAssertFalse(KeyMonitorFocusPolicy.shouldYield(firstResponder: NSView()))
    }

    // The sidebar's SwiftUI List is backed by an NSOutlineView (an NSTableView
    // subclass). Its arrow keys must reach the outline, which is the whole
    // point of the fix: before this the window-wide monitor ate every Down/Up
    // no matter where focus was.
    func testMonitorYieldsWhenAListOwnsFocus() {
        XCTAssertTrue(KeyMonitorFocusPolicy.shouldYield(firstResponder: NSTableView()))
        XCTAssertTrue(KeyMonitorFocusPolicy.shouldYield(firstResponder: NSOutlineView()))
    }

    // The query field's field editor still owns its keystrokes.
    func testMonitorYieldsWhenATextEditorOwnsFocus() {
        XCTAssertTrue(KeyMonitorFocusPolicy.shouldYield(firstResponder: NSTextView()))
    }
}
