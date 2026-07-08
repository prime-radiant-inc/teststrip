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

# screencapture "succeeds" (exit 0) but writes nothing when the driving process
# lacks the Screen Recording (TCC) permission — a silent gap that leaves an
# agent "reading the screenshot" dead in the water. Detect it and advise.
if [[ ! -s "$OUTPUT_PATH" ]]; then
  echo "screencapture produced no image for $APP_NAME (window $window_id)." >&2
  echo "Most likely the Screen Recording permission is missing for the process driving this script." >&2
  echo "Grant it in System Settings > Privacy & Security > Screen Recording (add the terminal/driver), then retry." >&2
  echo "Until then, read the UI from the accessibility tree instead of screenshots (see test/scenarios/README.md)." >&2
  exit 1
fi
echo "$OUTPUT_PATH"
