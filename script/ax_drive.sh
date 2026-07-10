#!/usr/bin/env bash
set -euo pipefail

# Reusable accessibility driver for end-to-end scenario cards.
#
# Solves the flakiness that makes hand-rolled AX walkers unreliable in an
# interactive session: a SwiftUI app only vends its window accessibility tree
# while it is genuinely frontmost, and macOS REFUSES NSRunningApplication
# .activate() when another app holds focus. The fix is to re-assert frontmost
# through System Events (which IS permitted with Accessibility trust) on every
# poll iteration until the window subtree actually populates, and only then act.
# Every verb here does that; drivers should call this instead of re-implementing
# a walker that grabs focus once and hopes it sticks.
#
# Verbs (App defaults to Teststrip):
#   wait-vended [App]                 Return 0 once the app is frontmost and its
#                                     window subtree is non-empty (drivable).
#   find  [App] MATCHSPEC             Print matching elements' labels; exit 0 if
#                                     at least one matches, 1 otherwise.
#   wait  [App] MATCHSPEC             Poll until >=1 element matches (assert that
#                                     something appeared); exit 0/1 on timeout.
#   press [App] MATCHSPEC             AXPress the first matching element.
#                                     With --modifiers, clicks the element's
#                                     center via CGEvent with the modifier keys
#                                     held (AXPress cannot carry modifiers) —
#                                     e.g. shift-click range selection.
#                                     With --button right, opens the element's
#                                     context menu (AXShowMenu on the element or
#                                     an ancestor, falling back to a CGEvent
#                                     right-click) — needed for SwiftUI
#                                     .contextMenu, which AXPress cannot open.
#   type  [App] MATCHSPEC --text STR  Set the first matching field's value to STR
#                                     (role defaults to AXTextField for `type`).
#
# MATCHSPEC (all optional, ANDed):
#   --role  ROLE     AX role, e.g. AXButton, AXStaticText (default: any)
#   --label TEXT     exact match on title/description/value
#   --help  TEXT     exact match on AXHelp (icon-only controls carry meaning here)
#   --contains TEXT  substring match on title/description/value
#   --text  STR      (type only) the string to write into the matched field
#   --modifiers M    (press only) comma-separated shift,command,option,control
#   --button B       (press only) "left" (default) or "right" — right opens the
#                     context menu (AXShowMenu, CGEvent right-click fallback)
#                     instead of AXPress
#
# Env: TESTSTRIP_AX_TIMEOUT_SECONDS (default 20), TESTSTRIP_AX_POLL_SECONDS (0.15).
# Exit: 0 success, 1 not found / timeout, 2 usage/permission error.

usage() { sed -n '3,37p' "$0" >&2; }

VERB="${1:-}"; shift || true
case "$VERB" in
  wait-vended|find|wait|press|type) ;;
  ""|-h|--help|help) usage; exit 2 ;;
  *) echo "unknown verb: $VERB" >&2; usage; exit 2 ;;
esac

APP="Teststrip"
if [[ "${1:-}" != "" && "${1:-}" != --* ]]; then APP="$1"; shift; fi

ROLE=""; LABEL=""; HELP=""; CONTAINS=""; TEXT=""; MODIFIERS=""; BUTTON="left"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) ROLE="$2"; shift 2 ;;
    --label) LABEL="$2"; shift 2 ;;
    --help) HELP="$2"; shift 2 ;;
    --contains) CONTAINS="$2"; shift 2 ;;
    --text) TEXT="$2"; shift 2 ;;
    --modifiers) MODIFIERS="$2"; shift 2 ;;
    --button) BUTTON="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

case "$BUTTON" in
  left|right) ;;
  *) echo "unknown --button: $BUTTON (want left|right)" >&2; exit 2 ;;
esac

# `type` defaults to text fields, and needs somewhere to descend from.
if [[ "$VERB" == "type" && -z "$ROLE" ]]; then ROLE="AXTextField"; fi

TESTSTRIP_AX_VERB="$VERB" \
TESTSTRIP_AX_APP_NAME="$APP" \
TESTSTRIP_AX_ROLE="$ROLE" \
TESTSTRIP_AX_LABEL="$LABEL" \
TESTSTRIP_AX_HELP="$HELP" \
TESTSTRIP_AX_CONTAINS="$CONTAINS" \
TESTSTRIP_AX_TEXT="$TEXT" \
TESTSTRIP_AX_MODIFIERS="$MODIFIERS" \
TESTSTRIP_AX_BUTTON="$BUTTON" \
/usr/bin/swift -e '
import AppKit
import ApplicationServices
import Foundation

let env = ProcessInfo.processInfo.environment
let verb = env["TESTSTRIP_AX_VERB"] ?? ""
let appName = env["TESTSTRIP_AX_APP_NAME"] ?? "Teststrip"
let wantRole = env["TESTSTRIP_AX_ROLE"] ?? ""
let wantLabel = env["TESTSTRIP_AX_LABEL"] ?? ""
let wantHelp = env["TESTSTRIP_AX_HELP"] ?? ""
let wantContains = env["TESTSTRIP_AX_CONTAINS"] ?? ""
let wantText = env["TESTSTRIP_AX_TEXT"] ?? ""
let wantModifiers = (env["TESTSTRIP_AX_MODIFIERS"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
let wantButton = env["TESTSTRIP_AX_BUTTON"] ?? "left"
let timeout = TimeInterval(env["TESTSTRIP_AX_TIMEOUT_SECONDS"] ?? "20") ?? 20
let poll = TimeInterval(env["TESTSTRIP_AX_POLL_SECONDS"] ?? "0.15") ?? 0.15

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("Accessibility is not trusted for this process\n".utf8))
    exit(2)
}
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else {
    FileHandle.standardError.write(Data("No running app named \(appName)\n".utf8))
    exit(2)
}

// System Events set-frontmost is the primitive macOS permits under Accessibility
// trust even when another app holds focus; NSRunningApplication.activate is not.
func setFrontmost() {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", "tell application \"System Events\" to set frontmost of process \"\(appName)\" to true"]
    try? p.run()
    p.waitUntilExit()
}

func attr(_ e: AXUIElement, _ n: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, n as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ n: String) -> String? { attr(e, n) as? String }
func role(_ e: AXUIElement) -> String? { str(e, kAXRoleAttribute) }
func label(_ e: AXUIElement) -> String? {
    str(e, kAXTitleAttribute) ?? str(e, kAXDescriptionAttribute) ?? str(e, kAXValueAttribute)
}
func help(_ e: AXUIElement) -> String? { str(e, kAXHelpAttribute) }
func placeholder(_ e: AXUIElement) -> String? { str(e, kAXPlaceholderValueAttribute) }
func children(_ e: AXUIElement) -> [AXUIElement] {
    (attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [])
        + (attr(e, "AXChildrenInNavigationOrder") as? [AXUIElement] ?? [])
        + (attr(e, kAXVisibleChildrenAttribute) as? [AXUIElement] ?? [])
        + (attr(e, kAXWindowsAttribute) as? [AXUIElement] ?? [])
}
struct Key: Hashable {
    let e: AXUIElement
    static func == (l: Key, r: Key) -> Bool { CFEqual(l.e, r.e) }
    func hash(into h: inout Hasher) { h.combine(CFHash(e)) }
}
func allElements() -> [AXUIElement] {
    let root = AXUIElementCreateApplication(app.processIdentifier)
    var seen = Set<Key>(); var stack = [root]; var out = [AXUIElement]()
    while let c = stack.popLast() {
        guard seen.insert(Key(e: c)).inserted else { continue }
        out.append(c)
        stack.append(contentsOf: children(c).reversed())
    }
    return out
}
func windowSubtreePopulated() -> Bool {
    // Menu bar is always present; a vended window shows non-menu content.
    allElements().contains { r in
        let role = role(r) ?? ""
        return role != "AXMenu" && role != "AXMenuItem" && role != "AXMenuBar"
            && role != "AXMenuBarItem" && role != "AXApplication"
    }
}
func matches(_ e: AXUIElement) -> Bool {
    if !wantRole.isEmpty, role(e) != wantRole { return false }
    if !wantLabel.isEmpty, label(e) != wantLabel { return false }
    if !wantHelp.isEmpty, help(e) != wantHelp { return false }
    if !wantContains.isEmpty {
        // Empty-but-placeholdered fields (a sheet Person name field) carry
        // their meaning in the placeholder, not the value.
        let hay = (label(e) ?? "") + " " + (placeholder(e) ?? "")
        if !hay.contains(wantContains) { return false }
    }
    let anyPredicate = !wantRole.isEmpty || !wantLabel.isEmpty || !wantHelp.isEmpty || !wantContains.isEmpty
    return anyPredicate
}
func matching() -> [AXUIElement] { allElements().filter(matches) }

let deadline = Date().addingTimeInterval(timeout)
var vended = false
repeat {
    setFrontmost()
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(poll))
    if windowSubtreePopulated() {
        vended = true
        if verb == "wait-vended" {
            print("vended")
            exit(0)
        }
        let found = matching()
        if !found.isEmpty {
            switch verb {
            case "find", "wait":
                for e in found { print(label(e) ?? help(e) ?? role(e) ?? "?") }
                exit(0)
            case "press":
                if wantButton == "right" {
                    // Prefer the canonical AXShowMenu action (SwiftUI rows
                    // expose it for .contextMenu); walk up a few ancestors
                    // because the matched element is often the row label,
                    // not the row itself. Fall back to a real CGEvent
                    // right-click if nothing in the chain supports it.
                    var candidate: AXUIElement? = found[0]
                    for _ in 0..<4 {
                        guard let c = candidate else { break }
                        if AXUIElementPerformAction(c, "AXShowMenu" as CFString) == .success {
                            print("right-clicked (AXShowMenu): \(label(found[0]) ?? help(found[0]) ?? "?")")
                            exit(0)
                        }
                        candidate = attr(c, kAXParentAttribute).map { $0 as! AXUIElement }
                    }
                    guard let posValue = attr(found[0], kAXPositionAttribute),
                          let sizeValue = attr(found[0], kAXSizeAttribute) else {
                        FileHandle.standardError.write(Data("element has no AXPosition/AXSize for right click\n".utf8))
                        exit(1)
                    }
                    var pos = CGPoint.zero; var size = CGSize.zero
                    AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
                    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
                    let center = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
                    guard let down = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: center, mouseButton: .right),
                          let up = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: center, mouseButton: .right) else {
                        FileHandle.standardError.write(Data("could not create mouse events\n".utf8))
                        exit(1)
                    }
                    // SwiftUI hit-tests context menus against the real cursor
                    // location, not just the event position — move the cursor
                    // there first or the menu will not open.
                    CGWarpMouseCursorPosition(center)
                    if let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: center, mouseButton: .left) {
                        move.post(tap: .cghidEventTap)
                    }
                    usleep(60_000)
                    down.post(tap: .cghidEventTap)
                    usleep(60_000)
                    up.post(tap: .cghidEventTap)
                    print("right-clicked: \(label(found[0]) ?? help(found[0]) ?? "?")")
                    exit(0)
                }
                if !wantModifiers.isEmpty {
                    // AXPress cannot carry modifier keys, so a modifier-click
                    // posts real CGEvents at the element center with the
                    // flags held (permitted under Accessibility trust).
                    guard let posValue = attr(found[0], kAXPositionAttribute),
                          let sizeValue = attr(found[0], kAXSizeAttribute) else {
                        FileHandle.standardError.write(Data("element has no AXPosition/AXSize for modifier click\n".utf8))
                        exit(1)
                    }
                    var pos = CGPoint.zero; var size = CGSize.zero
                    AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
                    AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
                    let center = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
                    var flags = CGEventFlags()
                    for m in wantModifiers {
                        switch m {
                        case "shift": flags.insert(.maskShift)
                        case "command", "cmd": flags.insert(.maskCommand)
                        case "option", "opt", "alt": flags.insert(.maskAlternate)
                        case "control", "ctrl": flags.insert(.maskControl)
                        default:
                            FileHandle.standardError.write(Data("unknown modifier: \(m)\n".utf8))
                            exit(2)
                        }
                    }
                    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: center, mouseButton: .left),
                          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: center, mouseButton: .left) else {
                        FileHandle.standardError.write(Data("could not create mouse events\n".utf8))
                        exit(1)
                    }
                    down.flags = flags
                    up.flags = flags
                    down.post(tap: .cghidEventTap)
                    usleep(60_000)
                    up.post(tap: .cghidEventTap)
                    print("modifier-clicked (\(wantModifiers.joined(separator: "+"))): \(label(found[0]) ?? help(found[0]) ?? "?")")
                    exit(0)
                }
                let result = AXUIElementPerformAction(found[0], kAXPressAction as CFString)
                if result == .success {
                    print("pressed: \(label(found[0]) ?? help(found[0]) ?? "?")")
                    exit(0)
                }
                FileHandle.standardError.write(Data("AXPress failed: \(result.rawValue)\n".utf8))
                exit(1)
            case "type":
                // Focus the field, then set its value directly — the mechanism
                // submit_import_path.sh proved for the import-path sheet field.
                _ = AXUIElementSetAttributeValue(found[0], kAXFocusedAttribute as CFString, kCFBooleanTrue)
                let result = AXUIElementSetAttributeValue(found[0], kAXValueAttribute as CFString, wantText as CFTypeRef)
                if result == .success {
                    print("typed into: \(label(found[0]) ?? role(found[0]) ?? "?")")
                    exit(0)
                }
                FileHandle.standardError.write(Data("set value failed: \(result.rawValue)\n".utf8))
                exit(1)
            default: break
            }
        }
    }
} while Date() < deadline

if !vended {
    FileHandle.standardError.write(Data("Window never vended for \(appName) within \(Int(timeout))s (locked console, or app not launching windows?)\n".utf8))
    exit(1)
}
FileHandle.standardError.write(Data("No element matched (role=\(wantRole) label=\(wantLabel) help=\(wantHelp) contains=\(wantContains)) within \(Int(timeout))s\n".utf8))
exit(1)
'
