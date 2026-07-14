import AppKit
import SwiftUI

// Direction of a keyboard-driven move through the library grid.
public enum GridMoveDirection: Equatable, Sendable {
    case left
    case right
    case up
    case down
    case home
    case end
}

// A physical key press translated into a grid intent, independent of AppKit.
public enum GridKeyInput: Equatable, Sendable {
    case leftArrow
    case rightArrow
    case upArrow
    case downArrow
    case home
    case end
    case returnKey
    case space
    case escape
    case character(String)
}

// A grid keyboard command, decoded from a key press and routed to AppModel.
public enum GridKeyCommand: Equatable, Sendable {
    case move(GridMoveDirection)
    case rating(Int)
    case pick
    case reject
    case clearFlag
    case openLoupe
    case returnToGrid
    /// Cull sub-view switch (Task 18), fired only while in `.cullGrid`: "g"/
    /// Escape return to `.loupe`, "c"/"b" jump straight to Compare/A-B.
    case switchCullSubView(LibraryViewMode)

    // Only meaningful while `mode == .cullGrid`; constructed directly by
    // GridKeyCaptureNSView.command(for:) rather than through `init?(input:)`
    // since it needs mode context the plain initializer doesn't have.
    static func cullSubViewSwitch(for input: GridKeyInput) -> GridKeyCommand? {
        switch input {
        case .escape:
            return .switchCullSubView(.loupe)
        case .character(let character):
            switch character.lowercased() {
            case "g": return .switchCullSubView(.loupe)
            case "c": return .switchCullSubView(.compare)
            case "b": return .switchCullSubView(.abCompare)
            default: return nil
            }
        default:
            return nil
        }
    }

    public init?(input: GridKeyInput) {
        switch input {
        case .leftArrow:
            self = .move(.left)
        case .rightArrow:
            self = .move(.right)
        case .upArrow:
            self = .move(.up)
        case .downArrow:
            self = .move(.down)
        case .home:
            self = .move(.home)
        case .end:
            self = .move(.end)
        case .returnKey, .space:
            self = .openLoupe
        case .escape:
            self = .returnToGrid
        case .character(let character):
            switch character.lowercased() {
            case "0": self = .rating(0)
            case "1": self = .rating(1)
            case "2": self = .rating(2)
            case "3": self = .rating(3)
            case "4": self = .rating(4)
            case "5": self = .rating(5)
            case "p": self = .pick
            case "x": self = .reject
            case "u": self = .clearFlag
            default: return nil
            }
        }
    }

    // Grid keys navigate and rate while browsing; only Escape acts from the
    // culling loupe. The Library loupe additionally allows left/right
    // stepping since it has no culling-shortcut monitor of its own.
    public func isAllowed(in mode: LibraryViewMode) -> Bool {
        switch mode {
        case .grid, .cullGrid:
            return self != .returnToGrid
        case .loupe:
            return self == .returnToGrid
        case .libraryLoupe:
            switch self {
            case .move(.left), .move(.right), .returnToGrid:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
}

// Pure movement arithmetic for the library grid, clamped at its edges.
public enum GridSelectionMovement {
    public static func nextIndex(
        from index: Int,
        direction: GridMoveDirection,
        count: Int,
        columns: Int
    ) -> Int? {
        guard count > 0 else { return nil }
        let columns = max(1, columns)
        switch direction {
        case .left:
            return max(index - 1, 0)
        case .right:
            return min(index + 1, count - 1)
        case .up:
            let target = index - columns
            return target >= 0 ? target : index
        case .down:
            let target = index + columns
            return target < count ? target : index
        case .home:
            return 0
        case .end:
            return count - 1
        }
    }
}

// Matches SwiftUI's adaptive grid: as many whole items as the width admits.
public enum LibraryGridColumnCount {
    public static func columns(availableWidth: CGFloat, minimumItemWidth: CGFloat, spacing: CGFloat) -> Int {
        guard availableWidth > 0, minimumItemWidth > 0 else { return 1 }
        let count = Int((availableWidth + spacing) / (minimumItemWidth + spacing))
        return max(1, count)
    }
}

struct GridKeyCaptureView: NSViewRepresentable {
    var mode: LibraryViewMode
    var focusRequest: Int
    var onCommand: (GridKeyCommand) -> Void

    func makeNSView(context: Context) -> GridKeyCaptureNSView {
        let view = GridKeyCaptureNSView()
        view.mode = mode
        view.onCommand = onCommand
        return view
    }

    func updateNSView(_ nsView: GridKeyCaptureNSView, context: Context) {
        nsView.mode = mode
        nsView.onCommand = onCommand
        guard nsView.lastFocusRequest != focusRequest else { return }
        nsView.lastFocusRequest = focusRequest
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView else { return }
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class GridKeyCaptureNSView: NSView {
    var lastFocusRequest = 0
    var mode: LibraryViewMode = .grid
    var onCommand: ((GridKeyCommand) -> Void)?
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
        guard eventTargetsWindow(event, targetWindowNumber: targetWindowNumber, targetWindowIsKey: targetWindowIsKey),
              !firstResponder.isTextEditor,
              let command = command(for: event) else {
            return event
        }
        onCommand?(command)
        return nil
    }

    private func command(for event: NSEvent) -> GridKeyCommand? {
        guard let input = GridKeyInput(event: event) else { return nil }
        if mode == .cullGrid, let cullSwitch = GridKeyCommand.cullSubViewSwitch(for: input) {
            return cullSwitch
        }
        guard let command = GridKeyCommand(input: input),
              command.isAllowed(in: mode) else {
            return nil
        }
        return command
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

extension GridKeyInput {
    init?(event: NSEvent) {
        let disallowedModifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard disallowedModifiers.isEmpty else { return nil }

        switch event.keyCode {
        case GridMacKeyCode.leftArrow:
            self = .leftArrow
        case GridMacKeyCode.rightArrow:
            self = .rightArrow
        case GridMacKeyCode.upArrow:
            self = .upArrow
        case GridMacKeyCode.downArrow:
            self = .downArrow
        case GridMacKeyCode.home:
            self = .home
        case GridMacKeyCode.end:
            self = .end
        case GridMacKeyCode.returnKey, GridMacKeyCode.keypadEnter:
            self = .returnKey
        case GridMacKeyCode.escape:
            self = .escape
        case GridMacKeyCode.space:
            self = .space
        default:
            guard
                let character = event.charactersIgnoringModifiers,
                character.count == 1
            else {
                return nil
            }
            self = .character(character)
        }
    }
}

private enum GridMacKeyCode {
    static let returnKey: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let escape: UInt16 = 53
    static let space: UInt16 = 49
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126
    static let home: UInt16 = 115
    static let end: UInt16 = 119
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
