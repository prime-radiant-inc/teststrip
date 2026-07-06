#!/usr/bin/env bash
set -euo pipefail

# Brings a running app's process frontmost through System Events so
# accessibility probes can see its full window tree. macOS refuses
# NSRunningApplication.activate() when another app holds focus, which
# left AX probes staring at the application/menu proxy; System Events
# is allowed to set frontmost when the caller has Accessibility trust.
#
# Usage: activate_app.sh <AppName> [timeout-seconds]
# Exit: 0 once the app is frontmost, 1 on timeout, 2 on usage error.

OSASCRIPT_BIN="${TESTSTRIP_ACTIVATE_OSASCRIPT_BIN:-/usr/bin/osascript}"

activate_app_frontmost() {
  local app_name="$1"
  local timeout_seconds="${2:-10}"
  local deadline=$(( $(date +%s) + timeout_seconds ))
  local frontmost=""

  while true; do
    "$OSASCRIPT_BIN" -e "tell application \"System Events\" to set frontmost of process \"$app_name\" to true" >/dev/null 2>&1 || true
    frontmost="$("$OSASCRIPT_BIN" -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null || true)"
    if [[ "$frontmost" == "$app_name" ]]; then
      return 0
    fi
    if (( $(date +%s) >= deadline )); then
      echo "Could not bring $app_name frontmost within ${timeout_seconds}s; frontmost process is '${frontmost:-unknown}'" >&2
      return 1
    fi
    sleep 0.2
  done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -lt 1 ]]; then
    echo "Usage: $(basename "$0") <AppName> [timeout-seconds]" >&2
    exit 2
  fi
  activate_app_frontmost "$@"
fi
