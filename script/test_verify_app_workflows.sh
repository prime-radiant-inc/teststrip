#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/teststrip-app-workflows-test.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SCRIPT_DIR="$TMP_DIR/script"
mkdir -p "$SCRIPT_DIR"
cp "$ROOT_DIR/script/verify_app_workflows.sh" "$SCRIPT_DIR/verify_app_workflows.sh"
chmod +x "$SCRIPT_DIR/verify_app_workflows.sh"

CALL_LOG="$TMP_DIR/calls.log"
export TESTSTRIP_APP_WORKFLOW_CALL_LOG="$CALL_LOG"

cat > "$SCRIPT_DIR/process_resource_metrics.sh" <<'SH'
#!/usr/bin/env bash
process_resource_snapshot() {
  printf 'process_resource_snapshot %s\n' "$*" >> "$TESTSTRIP_APP_WORKFLOW_CALL_LOG"
}
SH

write_fake_script() {
  local name="$1"
  cat > "$SCRIPT_DIR/$name" <<'SH'
#!/usr/bin/env bash
if [[ "$(basename "$0")" == "build_and_run.sh" ]]; then
  printf '%s %s card_route=%s\n' "$(basename "$0")" "$*" "${TESTSTRIP_CARD_IMPORT_ROUTE:-}" >> "$TESTSTRIP_APP_WORKFLOW_CALL_LOG"
else
  printf '%s %s\n' "$(basename "$0")" "$*" >> "$TESTSTRIP_APP_WORKFLOW_CALL_LOG"
fi
SH
  chmod +x "$SCRIPT_DIR/$name"
}

write_fake_script build_and_run.sh
write_fake_script verify_grid_activation.sh
write_fake_script verify_grid_selection_feedback.sh
write_fake_script verify_keyboard_culling.sh
write_fake_script verify_evaluation.sh
write_fake_script verify_import_path.sh
write_fake_script verify_card_import_path.sh

"$SCRIPT_DIR/verify_app_workflows.sh" Teststrip

assert_called() {
  local pattern="$1"
  local label="$2"
  if ! grep -q "$pattern" "$CALL_LOG"; then
    echo "expected $label call" >&2
    cat "$CALL_LOG" >&2
    exit 1
  fi
}

assert_called '^build_and_run.sh --verify-smoke card_route=typed-path$' "typed card smoke launch"
assert_called '^verify_import_path.sh Teststrip$' "folder import path verifier"
assert_called '^verify_card_import_path.sh Teststrip$' "card import path verifier"

folder_line="$(grep -n '^verify_import_path.sh Teststrip$' "$CALL_LOG" | head -n1 | cut -d: -f1)"
card_line="$(grep -n '^verify_card_import_path.sh Teststrip$' "$CALL_LOG" | head -n1 | cut -d: -f1)"
if [[ "$card_line" -le "$folder_line" ]]; then
  echo "expected card import path verifier after folder import path verifier" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi

echo "verify_app_workflows tests passed"
