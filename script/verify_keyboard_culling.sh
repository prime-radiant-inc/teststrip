#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="${1:-Teststrip}"
TARGET_ASSET="${2:-}"
TIMEOUT_SECONDS="${TESTSTRIP_AX_TIMEOUT_SECONDS:-8}"

run_frontmost_app_keyboard_step() {
    /usr/bin/osascript - "$APP_NAME" "$1" <<'APPLESCRIPT' >/dev/null
on run argv
    set appName to item 1 of argv
    set stepName to item 2 of argv
    set becameFrontmost to false
    tell application appName to activate
    tell application "System Events"
        repeat 50 times
            if exists process appName then
                tell process appName to set frontmost to true
                if frontmost of process appName then
                    set becameFrontmost to true
                    exit repeat
                end if
            end if
            delay 0.1
        end repeat
        if becameFrontmost is false then error appName & " did not become frontmost"
        if stepName is "clear-rating" then
            tell process appName to click menu item "Clear Rating" of menu "Culling" of menu bar 1
        else if stepName is "rate-five" then
            tell process appName to keystroke "5"
        else
            error "Unknown keyboard culling step " & stepName
        end if
    end tell
end run
APPLESCRIPT
}

selection_output="$("$SCRIPT_DIR/verify_grid_activation.sh" "$APP_NAME" "$TARGET_ASSET")"
selected_asset="${selection_output#selected }"

run_frontmost_app_keyboard_step "clear-rating"

"$SCRIPT_DIR/verify_grid_activation.sh" "$APP_NAME" "$selected_asset" >/dev/null

run_frontmost_app_keyboard_step "rate-five"

"$SCRIPT_DIR/verify_grid_activation.sh" "$APP_NAME" "$selected_asset" >/dev/null

TESTSTRIP_AX_APP_NAME="$APP_NAME" \
TESTSTRIP_AX_TARGET_ASSET="$selected_asset" \
TESTSTRIP_AX_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
/usr/bin/swift -e '
import AppKit
import ApplicationServices
import Foundation

let appName = ProcessInfo.processInfo.environment["TESTSTRIP_AX_APP_NAME"] ?? "Teststrip"
let timeout = TimeInterval(ProcessInfo.processInfo.environment["TESTSTRIP_AX_TIMEOUT_SECONDS"] ?? "8") ?? 8

guard AXIsProcessTrusted(),
      let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else {
    exit(1)
}

let root = AXUIElementCreateApplication(app.processIdentifier)

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return result == .success ? value : nil
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
}

func children(of element: AXUIElement) -> [AXUIElement] {
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func accessibleText(_ element: AXUIElement) -> String? {
    stringAttribute(element, kAXTitleAttribute)
        ?? stringAttribute(element, kAXDescriptionAttribute)
        ?? stringAttribute(element, kAXValueAttribute)
}

func walk(_ element: AXUIElement, visit: (AXUIElement) -> Bool) -> AXUIElement? {
    if visit(element) {
        return element
    }
    for child in children(of: element) {
        if let found = walk(child, visit: visit) {
            return found
        }
    }
    return nil
}

let deadline = Date().addingTimeInterval(timeout)
while Date() < deadline {
    if walk(root, visit: { element in
        stringAttribute(element, kAXRoleAttribute) == kAXStaticTextRole
            && accessibleText(element) == "Rating: 5"
    }) != nil {
        print("keyboard rating applied to \(ProcessInfo.processInfo.environment["TESTSTRIP_AX_TARGET_ASSET"] ?? "selected asset")")
        exit(0)
    }
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
}

fputs("Rating did not change to 5 within \(timeout)s\n", stderr)
exit(1)
'
