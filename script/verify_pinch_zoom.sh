#!/usr/bin/env bash
set -euo pipefail

# End-to-end pinch-to-zoom scenario for the loupe, driven through the live
# macOS UI in the Tart VM. Synthesizes real NSEventTypeMagnify (type 30)
# gesture events using Hammerspoon's libeventtapevent.dylib and posts them
# via kCGSessionEventTap, then verifies zoom state transitions through AX.
#
# This is the automated replacement for the "manual verification" steps
# (15–17) in test/scenarios/pinch-zoom-loupe.md. It proves that
# MagnificationGesture is wired at the stage level (fires from the fitted
# state, not only on the already-zoomed image) and that pinching back to
# ~1.0 resets to fit.
#
# Prerequisites:
#   1. VM is set up:    script/vm_scenario_run.sh setup
#   2. Gesture toolchain deployed: script/pinch_deploy.sh
#   3. App synced+launched:  script/vm_scenario_run.sh sync smoke && script/vm_scenario_run.sh launch smoke
#
# Usage: script/verify_pinch_zoom.sh
# Exit: 0 all assertions pass, 1 an assertion failed, 2 setup/driveability error.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VM="$SCRIPT_DIR/vm_scenario_run.sh"
GESTURE_DIR="/Users/admin/teststrip-vm/gesture"
APP=Teststrip

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# Check that the gesture toolchain is deployed
check_toolchain() {
  "$VM" shell "test -x $GESTURE_DIR/pinch_post && test -f $GESTURE_DIR/libeventtapevent.dylib && test -d $GESTURE_DIR/LuaSkin.framework" 2>/dev/null || {
    echo "Gesture toolchain not deployed. Run: script/pinch_deploy.sh" >&2
    exit 2
  }
}

# Assert an AX element is present (wait up to 15s)
assert_present() {
  local desc="$1"; shift
  "$VM" ax wait --contains "$@" 2>/dev/null || fail "$desc: element not found (contains: $*)"
}

# Assert an AX element is absent (quick check, 3s timeout via env var)
assert_absent() {
  local desc="$1"; shift
  # ax_drive.sh reads TESTSTRIP_AX_TIMEOUT_SECONDS; use shell to set it
  if "$VM" shell "cd /Users/admin/teststrip-vm && TESTSTRIP_AX_TIMEOUT_SECONDS=3 ./script/ax_drive.sh find --contains $1" 2>/dev/null; then
    fail "$desc: element should be absent but was found (contains: $1)"
  fi
  pass "$desc: absent as expected (contains: $1)"
}

# Post a pinch gesture and wait for UI to settle
pinch() {
  local from="$1" to="$2"
  local pid
  pid=$("$VM" shell "pgrep -x $APP" 2>&1 | tail -1)
  [ -n "$pid" ] || fail "Teststrip not running"
  "$VM" ax wait-vended "$APP" 2>/dev/null
  "$VM" shell "$GESTURE_DIR/pinch_post $pid $from $to 30 20" 2>&1 | tail -1
  sleep 1
  "$VM" ax wait-vended "$APP" 2>/dev/null
}

echo "=== Pinch-to-Zoom E2E Scenario ==="
echo ""

# 0. Prerequisites
echo "--- Checking prerequisites ---"
check_toolchain
"$VM" ax wait-vended "$APP" 2>/dev/null || { echo "App not frontmost/drivable" >&2; exit 2; }
pass "Prerequisites OK"

# 1. Open loupe via ⌘3
echo ""
echo "--- Opening loupe (⌘3) ---"
"$VM" key 'keystroke "3" using command down' 2>/dev/null
sleep 1
"$VM" ax wait-vended "$APP" 2>/dev/null
assert_present "Loupe fitted" "Zoom to 100%"
pass "Loupe open in fitted state"

# 2. Verify fitted state indicators
echo ""
echo "--- Verifying fitted state ---"
assert_present  "Fitted: Zoom to 100% label" "Zoom to 100%"
assert_absent   "Fitted: Return to fit absent" "Return to fit"
assert_absent   "Fitted: Loupe zoom HUD absent" "Loupe zoom"

# 3. Pinch out from 1.0 to 2.0 — the core test
echo ""
echo "--- Pinch out: 1.0 → 2.0 (from fitted state) ---"
pinch 1.0 2.0
assert_absent   "Zoomed: Zoom to 100% gone" "Zoom to 100%"
assert_present  "Zoomed: Return to fit label" "Return to fit"
assert_present  "Zoomed: Loupe zoom HUD" "Loupe zoom"
pass "Pinch from fitted entered zoom mode (HUD appeared)"

# 4. Pinch back from 2.0 to 1.0 — reverse pinch
echo ""
echo "--- Pinch back: 2.0 → 1.0 (return to fit) ---"
pinch 2.0 1.0
assert_present  "Fitted again: Zoom to 100% label" "Zoom to 100%"
assert_absent   "Fitted again: Return to fit gone" "Return to fit"
assert_absent   "Fitted again: Loupe zoom HUD gone" "Loupe zoom"
pass "Pinch back returned to fitted state (HUD disappeared)"

# 5. Catalog assertions — zooming doesn't mutate the catalog
echo ""
echo "--- Catalog assertions ---"
asset_count=$("$VM" sql smoke 'SELECT COUNT(*) FROM assets' 2>&1 | tail -1)
[ "$asset_count" = "24" ] || fail "Expected 24 assets, got $asset_count"
pass "Catalog intact: 24 assets"

session_count=$("$VM" sql smoke 'SELECT COUNT(*) FROM work_sessions' 2>&1 | tail -1)
[ "$session_count" = "0" ] || fail "Expected 0 work sessions, got $session_count"
pass "No work sessions created by zooming"

# 6. Return to grid
echo ""
echo "--- Returning to grid (Escape) ---"
"$VM" key 'key code 53' 2>/dev/null
sleep 1
"$VM" ax wait-vended "$APP" 2>/dev/null
pass "Escape sent"

echo ""
echo "=========================================="
echo "ALL PINCH-TO-ZOOM E2E TESTS PASSED"
echo "=========================================="
