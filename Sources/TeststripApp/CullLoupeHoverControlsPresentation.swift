import Foundation

/// Visibility state machine for the cull loupe's hover-revealed decision
/// controls (Jesse's ruling 2026-07-11): P/X/star click targets fade in near
/// the bottom edge on pointer movement, fade out after ~1.5s of pointer
/// idle or on any culling keystroke. Cull loupe only — the library loupe
/// stays chrome-free.
struct CullLoupeHoverControlsPresentation: Equatable {
    static let idleTimeout: TimeInterval = 1.5

    /// Tooltip/AXHelp copy for the click targets. Each names its keyboard
    /// key — the loupe itself is where P/X have to be taught (persona-8).
    static let pickHelp = "Pick this photo (P)"
    static let rejectHelp = "Reject this photo (X)"
    static func ratingHelp(star: Int) -> String {
        "Rate \(star) star\(star == 1 ? "" : "s") (\(star))"
    }

    private(set) var isVisible = false
    /// The instant after which idle hiding kicks in; nil while hidden.
    private(set) var hideDeadline: Date?

    /// Pointer movement shows the controls and restarts the idle window.
    mutating func pointerMoved(at now: Date) {
        isVisible = true
        hideDeadline = now.addingTimeInterval(Self.idleTimeout)
    }

    /// Pointer left the stage — hide immediately.
    mutating func pointerExited() {
        hide()
    }

    /// Any culling keystroke hides the controls (keyboard flow stays clean).
    mutating func keyPressed() {
        hide()
    }

    /// Idle check: hides only once the deadline has passed.
    mutating func idleCheck(at now: Date) {
        guard let hideDeadline, now >= hideDeadline else { return }
        hide()
    }

    private mutating func hide() {
        isVisible = false
        hideDeadline = nil
    }
}
