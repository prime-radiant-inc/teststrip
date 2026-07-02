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

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let shortcut = CullingShortcut(event: event) else {
            super.keyDown(with: event)
            return
        }
        onShortcut?(shortcut)
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
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
}
