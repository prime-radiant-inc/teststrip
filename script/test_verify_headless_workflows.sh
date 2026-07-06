#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/teststrip-headless-workflows-test.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

SCRIPT_DIR="$TMP_DIR/script"
mkdir -p "$SCRIPT_DIR/bin"
cp "$ROOT_DIR/script/verify_headless_workflows.sh" "$SCRIPT_DIR/verify_headless_workflows.sh"
chmod +x "$SCRIPT_DIR/verify_headless_workflows.sh"

CALL_LOG="$TMP_DIR/calls.log"
export TESTSTRIP_HEADLESS_CALL_LOG="$CALL_LOG"

cat > "$SCRIPT_DIR/bin/swift" <<'SH'
#!/usr/bin/env bash
printf 'swift %s\n' "$*" >> "$TESTSTRIP_HEADLESS_CALL_LOG"
SH
chmod +x "$SCRIPT_DIR/bin/swift"

write_fake_script() {
  local name="$1"
  cat > "$SCRIPT_DIR/$name" <<'SH'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "$0")" "$*" >> "$TESTSTRIP_HEADLESS_CALL_LOG"
SH
  chmod +x "$SCRIPT_DIR/$name"
}

write_fake_script build_and_run.sh
write_fake_script verify_metadata_write.sh
write_fake_script verify_card_import_smoke.sh
write_fake_script verify_import_preview_drain.sh
write_fake_script verify_source_availability.sh
write_fake_script verify_offline_reconnect_smoke.sh
write_fake_script verify_preview_render.sh
write_fake_script verify_local_http_model_smoke.sh
write_fake_script verify_worker_recovery.sh
write_fake_script verify_real_corpus_smoke.sh

PATH="$SCRIPT_DIR/bin:$PATH" "$SCRIPT_DIR/verify_headless_workflows.sh"

assert_called() {
  local pattern="$1"
  local label="$2"
  if ! grep -q "$pattern" "$CALL_LOG"; then
    echo "expected $label call" >&2
    cat "$CALL_LOG" >&2
    exit 1
  fi
}

assert_called '^swift test$' "swift test"
assert_called '^build_and_run.sh --build-sandboxed$' "sandboxed build"
assert_called '^verify_real_corpus_smoke.sh' "real corpus smoke"

echo "verify_headless_workflows tests passed"
