import AppKit

// Decides what an `NSEvent.addLocalMonitorForEvents` key-down monitor returns,
// keeping "the view was deallocated" distinct from "the view consumed the key".
//
// The obvious spelling — `self?.handleLocalKeyDown(event) ?? event` — is wrong:
// optional chaining flattens a nil "consume" verdict into the same nil as a
// deallocated `self`, so `?? event` re-emits the event in BOTH cases. That
// re-dispatches every *handled* key up the responder chain, where it runs its
// command and then beeps because nothing formally consumed it. Passing
// `viewIsAlive` alongside the verdict keeps the two nil cases apart.
enum KeyMonitorForwarding {
    // `handlerVerdict` is the view's `handleLocalKeyDown` result (nil = consume,
    // the event = pass through). It is ignored when the view is gone.
    static func result(viewIsAlive: Bool, handlerVerdict: NSEvent?, event: NSEvent) -> NSEvent? {
        viewIsAlive ? handlerVerdict : event
    }
}

/// Whether an in-view key monitor may consume a key-down.
///
/// The monitors (`GridKeyCaptureView`, `CullingKeyCaptureView`,
/// `PeopleKeyCaptureView`) are window-wide `NSEvent` local monitors: they run
/// before the responder chain and, without a focus gate, swallow arrow keys —
/// and Return/Space and the bare rating/flag letters — no matter which control
/// actually holds keyboard focus. That is what made the sidebar unreachable:
/// tabbing into it left the grid monitor eating every Down/Up, so the outline's
/// rows never moved even once focus was there.
///
/// The monitors own keys only while focus is in their own surface. Two kinds of
/// first responder own the key instead:
/// - a text editor (`NSTextView` — the query field's field editor), and
/// - an AppKit list/table view, which navigates its own rows with the arrow
///   keys (`NSOutlineView`, the sidebar's backing view, is an `NSTableView`
///   subclass).
enum KeyMonitorFocusPolicy {
    static func shouldYield(firstResponder: NSResponder?) -> Bool {
        guard let firstResponder else { return false }
        if firstResponder is NSTextView { return true }
        if firstResponder is NSTableView { return true }
        return false
    }
}
