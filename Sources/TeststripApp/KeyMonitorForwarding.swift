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
