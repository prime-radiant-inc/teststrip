#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/teststrip-real-local-http-smoke-test.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

CALL_LOG="$TMP_DIR/calls.log"
FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN"

test_skips_when_endpoint_is_not_configured() {
  local output
  output="$(TESTSTRIP_LOCAL_HTTP_MODEL_ENDPOINT= \
    TESTSTRIP_LOCAL_HTTP_MODEL_IMAGE= \
    "$ROOT_DIR/script/verify_real_local_http_model_smoke.sh")"
  if ! grep -q "skipped: TESTSTRIP_LOCAL_HTTP_MODEL_ENDPOINT is not set" <<< "$output"; then
    echo "missing endpoint skip message" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

test_runs_configured_endpoint_through_benchmark() {
  local image_file="$TMP_DIR/source.jpg"
  printf '\xff\xd8\xff\xd9' >"$image_file"
  cat > "$FAKE_BIN/swift" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TESTSTRIP_REAL_LOCAL_HTTP_CALL_LOG"
cat <<'OUT'
TeststripBench local HTTP model smoke
benchmark-summary	{"benchmark":"local_http_model_smoke","count":1,"measurements":{"local_http_model_smoke":0.25},"metrics":{"signals":3,"vector_signals":1,"visual_similarity_vector":1}}
OUT
SH
  chmod +x "$FAKE_BIN/swift"

  local output
  output="$(PATH="$FAKE_BIN:$PATH" \
    TESTSTRIP_REAL_LOCAL_HTTP_CALL_LOG="$CALL_LOG" \
    TESTSTRIP_LOCAL_HTTP_MODEL_ENDPOINT="http://127.0.0.1:1234/v1/chat/completions" \
    TESTSTRIP_LOCAL_HTTP_MODEL="llava-test" \
    TESTSTRIP_LOCAL_HTTP_MODEL_IMAGE="$image_file" \
    TESTSTRIP_LOCAL_HTTP_MODEL_SMOKE_MAX_SECONDS=2 \
    TESTSTRIP_LOCAL_HTTP_MODEL_SMOKE_MIN_SIGNALS=2 \
    TESTSTRIP_LOCAL_HTTP_MODEL_SMOKE_VISUAL_SIMILARITY_VECTOR=1 \
    "$ROOT_DIR/script/verify_real_local_http_model_smoke.sh")"

  if ! grep -q '^run TeststripBench local-http-smoke http://127.0.0.1:1234/v1/chat/completions llava-test '"$image_file"' 2$' "$CALL_LOG"; then
    echo "benchmark command did not receive configured endpoint, model, image, and timeout" >&2
    cat "$CALL_LOG" >&2
    exit 1
  fi
  if ! grep -q "teststrip_local_http_model_smoke_metric signals=3" <<< "$output"; then
    echo "real local HTTP smoke should emit parsed metrics" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

test_skips_when_endpoint_is_not_configured
test_runs_configured_endpoint_through_benchmark

echo "real local HTTP model smoke verifier tests passed"
