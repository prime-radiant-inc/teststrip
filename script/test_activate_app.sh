#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STUB_DIR="$(mktemp -d /tmp/teststrip-activate-app-test.XXXXXX)"
trap 'rm -rf "$STUB_DIR"' EXIT

# Stub osascript: "set frontmost" calls succeed silently; "get name" calls
# report the process name configured through TEST_STUB_FRONTMOST_NAME.
cat > "$STUB_DIR/osascript" <<'STUB'
#!/usr/bin/env bash
expression="${2:-}"
if [[ "$expression" == *"set frontmost"* ]]; then
  exit 0
fi
if [[ "$expression" == *"get name of first process"* ]]; then
  printf '%s\n' "${TEST_STUB_FRONTMOST_NAME:-}"
  exit 0
fi
exit 1
STUB
chmod +x "$STUB_DIR/osascript"

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

test_activation_succeeds_when_app_becomes_frontmost() {
  local status=0
  TESTSTRIP_ACTIVATE_OSASCRIPT_BIN="$STUB_DIR/osascript" \
  TEST_STUB_FRONTMOST_NAME="Teststrip" \
    "$SCRIPT_DIR/activate_app.sh" Teststrip 2 || status=$?
  assert_equal "0" "$status" "activation success exit status"
}

test_activation_fails_when_another_app_keeps_focus() {
  local status=0
  local output
  output="$(
    TESTSTRIP_ACTIVATE_OSASCRIPT_BIN="$STUB_DIR/osascript" \
    TEST_STUB_FRONTMOST_NAME="Arc" \
      "$SCRIPT_DIR/activate_app.sh" Teststrip 1 2>&1
  )" || status=$?
  assert_equal "1" "$status" "activation failure exit status"
  case "$output" in
    *"Teststrip"*"Arc"*) ;;
    *)
      echo "activation failure message should name the app and the actual frontmost process, got '$output'" >&2
      exit 1
      ;;
  esac
}

test_usage_error_without_app_name() {
  local status=0
  "$SCRIPT_DIR/activate_app.sh" >/dev/null 2>&1 || status=$?
  assert_equal "2" "$status" "usage error exit status"
}

test_activation_succeeds_when_app_becomes_frontmost
test_activation_fails_when_another_app_keeps_focus
test_usage_error_without_app_name

echo "test_activate_app.sh passed"
