import XCTest
@testable import TeststripApp

// Jesse's ruling (2026-07-11): hover-revealed P/X/star controls in the cull
// loupe. State machine: appears on pointer move, hides after ~1.5s idle,
// hides on any keystroke, hides when the pointer leaves the stage.
final class CullLoupeHoverControlsTests: XCTestCase {
    func testHiddenByDefault() {
        let state = CullLoupeHoverControlsPresentation()
        XCTAssertFalse(state.isVisible)
        XCTAssertNil(state.hideDeadline)
    }

    func testAppearsOnPointerMoveWithIdleDeadline() {
        var state = CullLoupeHoverControlsPresentation()
        let now = Date(timeIntervalSince1970: 1000)
        state.pointerMoved(at: now)
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.hideDeadline, now.addingTimeInterval(1.5))
    }

    func testContinuedMovementExtendsTheIdleWindow() {
        var state = CullLoupeHoverControlsPresentation()
        let now = Date(timeIntervalSince1970: 1000)
        state.pointerMoved(at: now)
        state.pointerMoved(at: now.addingTimeInterval(1.0))
        // The old deadline has passed but movement pushed it out.
        state.idleCheck(at: now.addingTimeInterval(1.6))
        XCTAssertTrue(state.isVisible)
        state.idleCheck(at: now.addingTimeInterval(2.5))
        XCTAssertFalse(state.isVisible)
    }

    func testHidesAfterIdleTimeoutOnlyOnceDeadlinePasses() {
        var state = CullLoupeHoverControlsPresentation()
        let now = Date(timeIntervalSince1970: 1000)
        state.pointerMoved(at: now)
        state.idleCheck(at: now.addingTimeInterval(1.4))
        XCTAssertTrue(state.isVisible)
        state.idleCheck(at: now.addingTimeInterval(1.5))
        XCTAssertFalse(state.isVisible)
        XCTAssertNil(state.hideDeadline)
    }

    func testHidesOnAnyKeystroke() {
        var state = CullLoupeHoverControlsPresentation()
        state.pointerMoved(at: Date(timeIntervalSince1970: 1000))
        state.keyPressed()
        XCTAssertFalse(state.isVisible)
        XCTAssertNil(state.hideDeadline)
    }

    func testHidesWhenPointerExits() {
        var state = CullLoupeHoverControlsPresentation()
        state.pointerMoved(at: Date(timeIntervalSince1970: 1000))
        state.pointerExited()
        XCTAssertFalse(state.isVisible)
    }

    func testControlTooltipsTeachTheKeyboardKeys() {
        // Persona-8: P/X are the whole workflow but nothing on the loupe
        // taught them. The hover controls' tooltips must name the keys.
        XCTAssertEqual(CullLoupeHoverControlsPresentation.pickHelp, "Pick this photo (P)")
        XCTAssertEqual(CullLoupeHoverControlsPresentation.rejectHelp, "Reject this photo (X)")
        XCTAssertEqual(CullLoupeHoverControlsPresentation.ratingHelp(star: 1), "Rate 1 star (1)")
        XCTAssertEqual(CullLoupeHoverControlsPresentation.ratingHelp(star: 3), "Rate 3 stars (3)")
    }

    func testIdleCheckWhileHiddenStaysHidden() {
        var state = CullLoupeHoverControlsPresentation()
        state.idleCheck(at: Date(timeIntervalSince1970: 5000))
        XCTAssertFalse(state.isVisible)
    }
}
