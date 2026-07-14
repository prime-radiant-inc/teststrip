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
}
