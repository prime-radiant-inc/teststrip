#!/usr/bin/env bash
set -euo pipefail

# End-to-end scenario for keyboard navigation of the library grid, driven
# through the real UI. Launches the smoke catalog (24 synthetic photos), then:
#   * presses RIGHT (N-1) times from the first asset and asserts the selection
#     visits N DISTINCT assets in order — a single-step walk that reaches every
#     photo (the regression double-stepped, skipping every other one), and
#   * presses DOWN then UP and asserts DOWN moves to a different asset (one row)
#     and UP returns to the original — proving up/down move by exactly one row.
#
# The selected asset is read from the accessibility tree: each grid cell is an
# AXButton whose AXValue begins with "Selected" when it is the current pick and
# whose AXLabel is the asset filename (smoke-N.jpg). This is the app's own view
# of selection, not a guess from pixels.
#
# The app parks its accessibility tree when it loses focus (the idle-wedge), so
# every read and keypress re-asserts frontmost through System Events first.
#
# Usage: script/verify_grid_keyboard_nav.sh
# Exit: 0 all assertions pass, 1 an assertion failed, 2 setup/driveability error.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP=Teststrip
AX="$SCRIPT_DIR/ax_drive.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

warm() { "$AX" wait-vended "$APP" >/dev/null 2>&1; }

# Set the app frontmost (the primitive macOS permits without focus), then send a
# single key by its virtual key code.
send_key_code() {
    local code="$1"
    /usr/bin/osascript - "$APP" "$code" <<'APPLESCRIPT' >/dev/null
on run argv
    set appName to item 1 of argv
    set keyCode to (item 2 of argv) as integer
    tell application "System Events"
        repeat 50 times
            if exists process appName then
                tell process appName to set frontmost to true
                if frontmost of process appName then exit repeat
            end if
            delay 0.1
        end repeat
        key code keyCode
    end tell
end run
APPLESCRIPT
}

# Print the filename of the currently selected grid cell. When a first argument
# is given, polls until the selection differs from it (defeating the stale-read
# race where the AX tree still shows the pre-keypress selection). Exits non-zero
# if no (changed) selected image cell is exposed before the timeout.
read_selected_asset() {
    TESTSTRIP_AX_APP_NAME="$APP" \
    TESTSTRIP_AX_DIFFERENT_FROM="${1:-}" \
    TESTSTRIP_AX_TIMEOUT_SECONDS="${TESTSTRIP_AX_TIMEOUT_SECONDS:-6}" \
    /usr/bin/swift -e '
import AppKit
import ApplicationServices
import Foundation

let env = ProcessInfo.processInfo.environment
let appName = env["TESTSTRIP_AX_APP_NAME"] ?? "Teststrip"
let differentFrom = env["TESTSTRIP_AX_DIFFERENT_FROM"] ?? ""
let timeout = TimeInterval(env["TESTSTRIP_AX_TIMEOUT_SECONDS"] ?? "6") ?? 6

guard AXIsProcessTrusted() else {
    FileHandle.standardError.write(Data("Accessibility is not trusted for this process\n".utf8))
    exit(2)
}
guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else {
    FileHandle.standardError.write(Data("No running app named \(appName)\n".utf8))
    exit(2)
}

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
func isAssetFilename(_ text: String) -> Bool {
    text.lowercased().hasSuffix(".jpg")
}

let deadline = Date().addingTimeInterval(timeout)
repeat {
    setFrontmost()
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.15))
    let selected = allElements().first { e in
        guard str(e, kAXRoleAttribute) == kAXButtonRole,
              let label = str(e, kAXTitleAttribute) ?? str(e, kAXDescriptionAttribute),
              isAssetFilename(label),
              let value = str(e, kAXValueAttribute) else {
            return false
        }
        return value.hasPrefix("Selected")
    }
    if let selected, let label = str(selected, kAXTitleAttribute) ?? str(selected, kAXDescriptionAttribute) {
        if differentFrom.isEmpty || label != differentFrom {
            print(label)
            exit(0)
        }
    }
} while Date() < deadline

FileHandle.standardError.write(Data("No selected grid cell exposed within \(Int(timeout))s\n".utf8))
exit(1)
'
}

KEY_RIGHT=124
KEY_DOWN=125
KEY_UP=126

# Press a key and return the new selection once it moves off $2.
#
# The subtlety: re-sending the key while a read is merely slow would over-advance
# the selection (each extra press is another real move). So each attempt presses
# EXACTLY ONCE, then waits a full generous window for the change inside a single
# reader process. A real move always lands within that window, so if the window
# expires with the selection still on $2 the key was genuinely dropped (System
# Events silently drops a key code when the app is not truly frontmost at the
# instant of delivery) and it is safe to re-press. Bounded retries make an
# occasional dropped key a non-event without ever double-stepping.
press_until_change() {
    local key="$1" prev="$2" got
    for _ in 1 2 3 4; do
        warm
        send_key_code "$key"
        if got="$(TESTSTRIP_AX_TIMEOUT_SECONDS=6 read_selected_asset "$prev")"; then
            echo "$got"
            return 0
        fi
    done
    return 1
}

echo "== launch smoke catalog =="
pkill -x Teststrip 2>/dev/null || true
pkill -x TeststripWorker 2>/dev/null || true
sleep 1
"$SCRIPT_DIR/build_and_run.sh" --smoke >/dev/null 2>&1
sleep 3
warm || { echo "app never vended (locked console?)" >&2; exit 2; }

ISO="$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)"
DB="$ISO/Teststrip/catalog.sqlite"
[ -f "$DB" ] || { echo "no catalog at $DB" >&2; exit 2; }

N="$(sqlite3 "$DB" "SELECT count(*) FROM assets;" 2>/dev/null || echo 0)"
[ "${N:-0}" -ge 4 ] || fail "expected >= 4 assets in smoke catalog, found $N"
echo "catalog has $N assets"

# Anchor the selection on the first asset (top-left) by clicking its cell, so
# the rightward walk starts from a known edge and can reach every asset.
anchor_first_asset() {
    warm
    "$AX" press "$APP" --role AXButton --label "smoke-0.jpg" >/dev/null 2>&1 \
        || fail "could not select the first asset (smoke-0.jpg)"
    local got
    got="$(read_selected_asset)" || fail "no asset selected after anchoring on smoke-0.jpg"
    [ "$got" = "smoke-0.jpg" ] || fail "expected smoke-0.jpg selected after anchor, got $got"
}

echo "== up/down move by exactly one row =="
anchor_first_asset
down_asset="$(press_until_change "$KEY_DOWN" "smoke-0.jpg")" \
    || fail "DOWN did nothing (still smoke-0.jpg) — up/down navigation is broken"
echo "down moved smoke-0.jpg -> $down_asset"
up_asset="$(press_until_change "$KEY_UP" "$down_asset")" || fail "no asset selected after Up"
[ "$up_asset" = "smoke-0.jpg" ] || fail "UP did not return to smoke-0.jpg (landed on $up_asset)"
pass "DOWN then UP returns to the same asset (smoke-0.jpg)"

echo "== select the first asset =="
anchor_first_asset
first="smoke-0.jpg"
echo "first selected: $first"

echo "== walk RIGHT $((N - 1)) times, recording the selection each press =="
visited="$first"
prev="$first"
for _ in $(seq 1 $((N - 1))); do
    cur="$(press_until_change "$KEY_RIGHT" "$prev")" \
        || fail "RIGHT did not advance the selection (stuck on $prev)"
    visited="$visited"$'\n'"$cur"
    prev="$cur"
done

total="$(printf '%s\n' "$visited" | wc -l | tr -d ' ')"
distinct="$(printf '%s\n' "$visited" | sort -u | wc -l | tr -d ' ')"
echo "visited $total selections, $distinct distinct:"
printf '  %s\n' $(printf '%s\n' "$visited")
[ "$total" -eq "$N" ] || fail "expected $N selections, recorded $total"
[ "$distinct" -eq "$N" ] || fail "rightward walk skipped assets: only $distinct distinct of $N (double-step regression?)"
pass "RIGHT single-steps through all $N assets with no skipping"

echo "ALL PASSED"
