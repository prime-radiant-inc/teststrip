#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${1:-Teststrip}"
OUTPUT_PATH="${2:-/tmp/teststrip-window.png}"
TIMEOUT_SECONDS="${TESTSTRIP_CAPTURE_TIMEOUT_SECONDS:-10}"

find_window_id() {
  TESTSTRIP_CAPTURE_APP_NAME="$APP_NAME" /usr/bin/swift -e '
import CoreGraphics
import Foundation

let appName = ProcessInfo.processInfo.environment["TESTSTRIP_CAPTURE_APP_NAME"] ?? "Teststrip"
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
    guard (window[kCGWindowOwnerName as String] as? String) == appName,
          let windowID = window[kCGWindowNumber as String] as? Int else {
        continue
    }
    print(windowID)
    exit(0)
}
'
}

deadline=$((SECONDS + TIMEOUT_SECONDS))
window_id=""
while [[ "$SECONDS" -le "$deadline" ]]; do
  window_id="$(find_window_id)"
  if [[ -n "$window_id" ]]; then
    break
  fi
  sleep 0.25
done

if [[ -z "$window_id" ]]; then
  echo "No $APP_NAME window found within ${TIMEOUT_SECONDS}s" >&2
  exit 1
fi

/usr/sbin/screencapture -x -l "$window_id" "$OUTPUT_PATH"
echo "$OUTPUT_PATH"
