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

wait_for_catalog_rating "$selected_asset" 5
