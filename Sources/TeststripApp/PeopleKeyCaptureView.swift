import AppKit
import SwiftUI

// A People-queue keyboard command, decoded from a key press. Monitor-only:
// none of these have menu equivalents, mirroring CullingKeyCaptureView's
// arrow/Return handling in the culling loupe.
enum PeopleQueueCommand: Equatable, Sendable {
    case moveFocus(PeopleQueueFocusDirection)
    case confirmFocused
    case dismissFocused
}

struct PeopleKeyCaptureView: NSViewRepresentable {
    var focusRequest: Int
    var isActive: Bool = true
    var onCommand: (PeopleQueueCommand) -> Void

    func makeNSView(context: Context) -> PeopleKeyCaptureNSView {
        let view = PeopleKeyCaptureNSView()
        view.isActive = isActive
        view.onCommand = onCommand
        return view
    }

    func updateNSView(_ nsView: PeopleKeyCaptureNSView, context: Context) {
        nsView.isActive = isActive
        nsView.onCommand = onCommand
        guard nsView.lastFocusRequest != focusRequest else { return }
        nsView.lastFocusRequest = focusRequest
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView else { return }
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class PeopleKeyCaptureNSView: NSView {
    var lastFocusRequest = 0
    var isActive = true
    var onCommand: ((PeopleQueueCommand) -> Void)?
    private var localKeyMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeLocalKeyMonitor()
        } else {
            installLocalKeyMonitor()
        }
    }

    func handleLocalKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let window else { return event }
        return handleLocalKeyDown(
            event,
            targetWindowNumber: window.windowNumber,
            targetWindowIsKey: window.isKeyWindow,
            firstResponder: window.firstResponder
        )
    }

    func handleLocalKeyDown(
        _ event: NSEvent,
        targetWindowNumber: Int,
        targetWindowIsKey: Bool,
        firstResponder: NSResponder?
    ) -> NSEvent? {
        guard isActive,
              eventTargetsWindow(event, targetWindowNumber: targetWindowNumber, targetWindowIsKey: targetWindowIsKey),
              !firstResponder.isTextEditor,
              let command = PeopleQueueCommand(event: event) else {
            return event
        }
        onCommand?(command)
        return nil
    }

    private func installLocalKeyMonitor() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            KeyMonitorForwarding.result(
                viewIsAlive: self != nil,
                handlerVerdict: self?.handleLocalKeyDown(event),
                event: event
            )
        }
    }

    private func removeLocalKeyMonitor() {
        guard let localKeyMonitor else { return }
        NSEvent.removeMonitor(localKeyMonitor)
        self.localKeyMonitor = nil
    }

    private func eventTargetsWindow(
        _ event: NSEvent,
        targetWindowNumber: Int,
        targetWindowIsKey: Bool
    ) -> Bool {
        if event.windowNumber == targetWindowNumber {
            return true
        }
        return targetWindowIsKey
    }
}

extension PeopleQueueCommand {
    init?(event: NSEvent) {
        guard event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            return nil
        }
        switch event.keyCode {
        case PeopleMacKeyCode.leftArrow:
            self = .moveFocus(.previous)
        case PeopleMacKeyCode.rightArrow:
            self = .moveFocus(.next)
        case PeopleMacKeyCode.returnKey, PeopleMacKeyCode.keypadEnter:
            self = .confirmFocused
        case PeopleMacKeyCode.escape:
            self = .dismissFocused
        default:
            // Space deliberately does nothing here: Return is the sole
            // confirm gesture (see CLAUDE.md confirm-before-write invariant).
            return nil
        }
    }
}

private enum PeopleMacKeyCode {
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let escape: UInt16 = 53
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
}

private extension Optional where Wrapped == NSResponder {
    var isTextEditor: Bool {
        switch self {
        case .some(let responder):
            return responder is NSTextView
        case .none:
            return false
        }
    }
}
