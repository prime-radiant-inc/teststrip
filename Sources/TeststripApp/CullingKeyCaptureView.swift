import AppKit
import SwiftUI

struct CullingKeyCaptureView: NSViewRepresentable {
    var focusRequest: Int
    var onShortcut: (CullingShortcut) -> Void

    func makeNSView(context: Context) -> CullingKeyCaptureNSView {
        let view = CullingKeyCaptureNSView()
        view.onShortcut = onShortcut
        return view
    }

    func updateNSView(_ nsView: CullingKeyCaptureNSView, context: Context) {
        nsView.onShortcut = onShortcut
        guard nsView.lastFocusRequest != focusRequest else { return }
        nsView.lastFocusRequest = focusRequest
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView else { return }
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class CullingKeyCaptureNSView: NSView {
    var lastFocusRequest = 0
    var onShortcut: ((CullingShortcut) -> Void)?
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

    override func keyDown(with event: NSEvent) {
        guard let shortcut = CullingShortcut(event: event) else {
            super.keyDown(with: event)
            return
        }
        onShortcut?(shortcut)
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
        guard eventTargetsWindow(event, targetWindowNumber: targetWindowNumber, targetWindowIsKey: targetWindowIsKey),
              !firstResponder.isTextEditor,
              let shortcut = CullingShortcut(event: event) else {
            return event
        }
        onShortcut?(shortcut)
        return nil
    }

    private func installLocalKeyMonitor() {
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleLocalKeyDown(event) ?? event
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

extension CullingShortcut {
    init?(event: NSEvent) {
        let disallowedModifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard disallowedModifiers.isEmpty else { return nil }

        switch event.keyCode {
        case MacKeyCode.leftArrow:
            self = .previousPhoto
        case MacKeyCode.rightArrow:
            self = .nextPhoto
        case MacKeyCode.upArrow:
            self = .previousStack
        case MacKeyCode.downArrow:
            self = .nextStack
        case MacKeyCode.space:
            self = .nextPhoto
        case MacKeyCode.returnKey, MacKeyCode.keypadEnter:
            self = .acceptStackSelection
        default:
            guard
                let character = event.charactersIgnoringModifiers,
                character.count == 1
            else {
                return nil
            }
            self.init(key: .character(character))
        }
    }
}

private enum MacKeyCode {
    static let returnKey: UInt16 = 36
    static let space: UInt16 = 49
    static let keypadEnter: UInt16 = 76
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
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
