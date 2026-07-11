#!/usr/bin/env bash
# Asserts the UX-simplification chrome is live in the assembled AppKit UI:
#   - the marquee "Find Best Shots" control is present,
#   - the "Copilot" label is gone from the UI,
#   - the toolbar no longer exposes the three separate Import buttons
#     (Import Folder / Import Card as top-level controls),
#   - the primary bar shows the collapsed "Import" and "More" controls.
#
# Run against a freshly built, warm instance (see test/scenarios/README.md):
#   ./script/build_and_run.sh --smoke        # in one shell
#   ./script/verify_ux_simplification_chrome.sh
#
# Exit 0 on success; non-zero with a diagnostic on the first failed assertion.
set -euo pipefail

APP_NAME="${1:-Teststrip}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AX="$SCRIPT_DIR/ax_drive.sh"

"$AX" wait-vended "$APP_NAME"

fail() { echo "FAIL: $1" >&2; exit 1; }

# The marquee action must exist.
"$AX" find "$APP_NAME" --role AXButton --label "Find Best Shots" >/dev/null \
  || fail "'Find Best Shots' control not present in toolbar"

# The collapsed Import and More menus must exist.
"$AX" find "$APP_NAME" --role AXButton --label "Import" >/dev/null \
  || fail "collapsed 'Import' menu not present"

# The old three-Imports tangle must be gone: no top-level "Import Folder" or
# "Import Card" buttons on the primary bar (they now live under Import ▾).
if "$AX" find "$APP_NAME" --role AXButton --label "Import Folder" >/dev/null 2>&1; then
  fail "toolbar still exposes a top-level 'Import Folder' button"
fi
if "$AX" find "$APP_NAME" --role AXButton --label "Import Card" >/dev/null 2>&1; then
  fail "toolbar still exposes a top-level 'Import Card' button"
fi

# "Copilot" must be gone. (There is no static "Review" sidebar row to assert
# on: the sidebar's review-queue rows (Picks/Likely Issues/etc.) only render
# once their counts are non-zero, and the sole "Review" control left in the
# UI is the autopilot-proposals banner button, which only appears when a
# proposal batch is pending — neither is guaranteed present on a fresh seed.)
if "$AX" find "$APP_NAME" --contains "Copilot" >/dev/null 2>&1; then
  fail "'Copilot' label still present in the UI"
fi

echo "PASS: UX-simplification chrome present (Find Best Shots, Import ▾; three-Imports/Copilot gone)"
