import AppKit
import SwiftUI

// Task C1 fix: the culling monitor (P/X/U flags, ratings, Return-promote,
// arrow/stack navigation) must only fire in the Cull workspace, and only in
// its loupe/compare/A-B sub-views — never in .cullGrid (which has its own
// GridKeyCaptureView monitor) and never in the other workspaces' views
// (.people, .timeline, .map, .grid, .libraryLoupe), where its Return/rating/
// pick/reject shortcuts would write metadata or navigate behind chrome that
// doesn't show them.
enum CullingKeyCaptureGate {
    static func isActive(workspace: Workspace, selectedView: LibraryViewMode) -> Bool {
        workspace == .cull && selectedView != .cullGrid
    }
}

struct CullingKeyCaptureView: NSViewRepresentable {
    var focusRequest: Int
    var isActive: Bool = true
    // Esc only exits .compare/.abCompare (item 1's modal-trap fix); it's left
    // alone in .loupe, which already has its own (differently-scoped)
    // Escape-to-library-grid behavior via GridKeyCaptureView.
    var isCompareLikeMode: Bool = false
    var onShortcut: (CullingShortcut) -> Void

    func makeNSView(context: Context) -> CullingKeyCaptureNSView {
        let view = CullingKeyCaptureNSView()
        view.isActive = isActive
        view.isCompareLikeMode = isCompareLikeMode
        view.onShortcut = onShortcut
        return view
    }

    func updateNSView(_ nsView: CullingKeyCaptureNSView, context: Context) {
        nsView.isActive = isActive
        nsView.isCompareLikeMode = isCompareLikeMode
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
    var isActive = true
    var isCompareLikeMode = false
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
              !firstResponder.isTextEditor else {
            return event
        }
        // Esc is a modal-trap escape hatch scoped to .compare/.abCompare
        // (item 1); .loupe keeps its existing Escape-to-library-grid path via
        // GridKeyCaptureView, so this view must not swallow Esc there.
        if event.keyCode == MacKeyCode.escape {
            guard isCompareLikeMode else { return event }
            onShortcut?(.exitCullSubView)
            return nil
        }
        guard let shortcut = CullingShortcut(event: event) else {
            return event
        }
        onShortcut?(shortcut)
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

extension CullingShortcut {
    init?(event: NSEvent) {
        let relevantModifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard relevantModifiers.isEmpty else { return nil }

        // Shift+Z (zoom to nearest face) and Shift+/ ("?", key map) need
        // explicit shift-aware detection: charactersIgnoringModifiers strips
        // Shift along with the other modifiers (see
        // testCullingShortcutMapsShiftedPickKeyEvent), so it never reports
        // the shifted character or case — only the modifier flag does.
        if event.modifierFlags.contains(.shift), let base = event.charactersIgnoringModifiers {
            switch base {
            case "z":
                self = .zoomToNearestFace
                return
            case "/":
                self = .showKeyMap
                return
            default:
                break
            }
        }

        switch event.keyCode {
        case MacKeyCode.leftArrow:
            self = .previousStack
        case MacKeyCode.rightArrow:
            self = .nextStack
        case MacKeyCode.upArrow:
            self = .previousCandidateInStack
        case MacKeyCode.downArrow:
            self = .nextCandidateInStack
        case MacKeyCode.space:
            self = .nextPhoto
        case MacKeyCode.returnKey, MacKeyCode.keypadEnter:
            self = .promoteAndRejectSiblings
        case MacKeyCode.pageUp:
            self = .keyMapPageUp
        case MacKeyCode.pageDown:
            self = .keyMapPageDown
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
    static let escape: UInt16 = 53
    static let space: UInt16 = 49
    static let keypadEnter: UInt16 = 76
    static let pageUp: UInt16 = 116
    static let pageDown: UInt16 = 121
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
