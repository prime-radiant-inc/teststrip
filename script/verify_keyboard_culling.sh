#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="${1:-Teststrip}"
TARGET_ASSET="${2:-}"
TIMEOUT_SECONDS="${TESTSTRIP_AX_TIMEOUT_SECONDS:-8}"

running_app_support_directory() {
    local app_pid
    app_pid="$(pgrep -x "$APP_NAME" | tail -1)"
    if [[ -z "$app_pid" ]]; then
        return 1
    fi
    ps eww -p "$app_pid" | /usr/bin/awk '
        {
            for (i = 1; i <= NF; i += 1) {
                prefix = "TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY="
                if (index($i, prefix) == 1) {
                    print substr($i, length(prefix) + 1)
                    exit
                }
            }
        }
    '
}

wait_for_catalog_rating() {
    local asset_filename="$1"
    local expected_rating="$2"
    local app_support
    app_support="$(running_app_support_directory)"
    if [[ -z "$app_support" ]]; then
        echo "Could not find $APP_NAME application support directory from the running process" >&2
        return 1
    fi

    local catalog_path="${app_support%/}/Teststrip/catalog.sqlite"
    if [[ ! -f "$catalog_path" ]]; then
        echo "Could not find catalog at $catalog_path" >&2
        return 1
    fi

    TESTSTRIP_CATALOG_PATH="$catalog_path" \
    TESTSTRIP_TARGET_ASSET_FILENAME="$asset_filename" \
    TESTSTRIP_EXPECTED_RATING="$expected_rating" \
    TESTSTRIP_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
    /usr/bin/python3 - <<'PY'
import json
import os
import sqlite3
import sys
import time

catalog_path = os.environ["TESTSTRIP_CATALOG_PATH"]
target_filename = os.environ["TESTSTRIP_TARGET_ASSET_FILENAME"]
expected_rating = int(os.environ["TESTSTRIP_EXPECTED_RATING"])
deadline = time.monotonic() + float(os.environ["TESTSTRIP_TIMEOUT_SECONDS"])

while time.monotonic() < deadline:
    with sqlite3.connect(catalog_path) as connection:
        row = connection.execute(
            """
            SELECT metadata_json
            FROM assets
            WHERE original_path = ?
               OR original_path LIKE ?
            LIMIT 1
            """,
            (target_filename, f"%/{target_filename}"),
        ).fetchone()
    if row is not None:
        metadata = json.loads(row[0])
        if int(metadata.get("rating", 0)) == expected_rating:
            print(f"keyboard rating applied to {target_filename}")
            sys.exit(0)
    time.sleep(0.05)

print(f"Rating for {target_filename} did not change to {expected_rating}", file=sys.stderr)
sys.exit(1)
PY
}

wait_for_inspector_rating() {
    local asset_filename="$1"
    local expected_rating="$2"

    TESTSTRIP_AX_APP_NAME="$APP_NAME" \
    TESTSTRIP_AX_TARGET_ASSET="$asset_filename" \
    TESTSTRIP_EXPECTED_RATING="$expected_rating" \
    TESTSTRIP_AX_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
    /usr/bin/swift -e '
import AppKit
import ApplicationServices
import Foundation

let appName = ProcessInfo.processInfo.environment["TESTSTRIP_AX_APP_NAME"] ?? "Teststrip"
let targetAsset = ProcessInfo.processInfo.environment["TESTSTRIP_AX_TARGET_ASSET"]!
let expectedRating = ProcessInfo.processInfo.environment["TESTSTRIP_EXPECTED_RATING"]!
let timeout = TimeInterval(ProcessInfo.processInfo.environment["TESTSTRIP_AX_TIMEOUT_SECONDS"] ?? "8") ?? 8
let expectedValue = "Rating: \(expectedRating)"

guard AXIsProcessTrusted() else {
    fputs("Accessibility is not trusted for this process\n", stderr)
    exit(2)
}

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else {
    fputs("No running app named \(appName)\n", stderr)
    exit(1)
}
_ = app.activate(options: [.activateAllWindows])
RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))

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
    let directChildren = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    let navigationChildren = attribute(element, "AXChildrenInNavigationOrder") as? [AXUIElement] ?? []
    let visibleChildren = attribute(element, kAXVisibleChildrenAttribute) as? [AXUIElement] ?? []
    let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
    var seen = Set<ObjectIdentifier>()
    var uniqueChildren: [AXUIElement] = []
    for child in directChildren + navigationChildren + visibleChildren + windows {
        let key = ObjectIdentifier(child)
        guard seen.insert(key).inserted else { continue }
        uniqueChildren.append(child)
    }
    return uniqueChildren
}

func accessibleText(_ element: AXUIElement) -> String {
    [
        stringAttribute(element, kAXTitleAttribute),
        stringAttribute(element, kAXDescriptionAttribute),
        stringAttribute(element, kAXValueAttribute)
    ]
    .compactMap { $0 }
    .joined(separator: " ")
}

func walk(_ element: AXUIElement, visit: (AXUIElement) -> Bool) -> AXUIElement? {
    var visited = Set<ObjectIdentifier>()
    var stack = [element]
    while let current = stack.popLast() {
        let key = ObjectIdentifier(current)
        guard visited.insert(key).inserted else { continue }
        if visit(current) {
            return current
        }
        stack.append(contentsOf: children(of: current).reversed())
    }
    return nil
}

let deadline = Date().addingTimeInterval(timeout)
while Date() < deadline {
    if walk(root, visit: { element in
        let text = accessibleText(element)
        return text.contains(targetAsset) && text.contains(expectedValue)
    }) != nil {
        print("inspector rating visible for \(targetAsset)")
        exit(0)
    }
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
}

fputs("Inspector did not expose \(expectedValue) for \(targetAsset) within \(timeout)s\n", stderr)
exit(1)
'
}

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

wait_for_inspector_rating "$selected_asset" 5
wait_for_catalog_rating "$selected_asset" 5
