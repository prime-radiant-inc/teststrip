#!/usr/bin/env bash
set -euo pipefail

# Covers ax_drive.sh's argument handling — the layer that runs before any
# accessibility call, so it is testable without a live app. The live driving
# verbs (find/wait/press against a running Teststrip) are exercised by the
# scenario cards, which need a frontmost GUI and Accessibility trust.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER="$SCRIPT_DIR/ax_drive.sh"

failures=0
assert_exit() {
  local expected="$1"; shift
  local message="$1"; shift
  local status=0
  "$@" >/dev/null 2>&1 || status=$?
  if [[ "$status" != "$expected" ]]; then
    echo "FAIL: $message: expected exit $expected, got $status" >&2
    failures=$((failures + 1))
  else
    echo "ok: $message"
  fi
}

# Usage errors exit 2 before touching accessibility.
assert_exit 2 "no verb prints usage" "$DRIVER"
assert_exit 2 "help verb prints usage" "$DRIVER" --help
assert_exit 2 "unknown verb rejected" "$DRIVER" bogus-verb
assert_exit 2 "unknown option rejected" "$DRIVER" find Teststrip --nope value

if [[ "$failures" -ne 0 ]]; then
  echo "$failures test(s) failed" >&2
  exit 1
fi
echo "all ax_drive argument tests passed"
