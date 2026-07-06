#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/local_http_model_smoke_verifier_metrics.sh"

summary_payload='{"benchmark":"local_http_model_smoke","count":1,"measurements":{"local_http_model_smoke":0.42},"metrics":{"signals":3,"vector_signals":1,"visual_similarity_vector":1}}'
missing_vector_payload='{"benchmark":"local_http_model_smoke","count":1,"measurements":{"local_http_model_smoke":0.42},"metrics":{"signals":3,"vector_signals":1,"visual_similarity_vector":0}}'
empty_payload='{"benchmark":"local_http_model_smoke","count":1,"measurements":{"local_http_model_smoke":0.42},"metrics":{"signals":0,"vector_signals":0,"visual_similarity_vector":0}}'

test_assert_local_http_model_smoke_summary_passes() {
  assert_local_http_model_smoke_summary "$summary_payload" 2 1 2
}

test_assert_local_http_model_smoke_summary_fails_without_visual_similarity_vector() {
  if assert_local_http_model_smoke_summary "$missing_vector_payload" 2 1 2 >/tmp/teststrip-local-http-missing-vector.out 2>/tmp/teststrip-local-http-missing-vector.err; then
    echo "expected missing visual similarity vector failure" >&2
    exit 1
  fi
  if ! grep -q "metrics.visual_similarity_vector expected 1" /tmp/teststrip-local-http-missing-vector.err; then
    echo "missing vector failure should name visual_similarity_vector" >&2
    exit 1
  fi
}

test_assert_local_http_model_smoke_summary_fails_without_signals() {
  if assert_local_http_model_smoke_summary "$empty_payload" 2 1 2 >/tmp/teststrip-local-http-empty.out 2>/tmp/teststrip-local-http-empty.err; then
    echo "expected missing signals failure" >&2
    exit 1
  fi
  if ! grep -q "metrics.signals expected at least 2" /tmp/teststrip-local-http-empty.err; then
    echo "empty signal failure should name signals" >&2
    exit 1
  fi
}

test_emit_local_http_model_smoke_metric() {
  local actual
  actual="$(emit_local_http_model_smoke_metric signals 3)"
  if [[ "$actual" != "teststrip_local_http_model_smoke_metric signals=3" ]]; then
    echo "local HTTP smoke metric line mismatch: $actual" >&2
    exit 1
  fi
}

test_assert_local_http_model_smoke_summary_passes
test_assert_local_http_model_smoke_summary_fails_without_visual_similarity_vector
test_assert_local_http_model_smoke_summary_fails_without_signals
test_emit_local_http_model_smoke_metric

echo "local HTTP model smoke verifier metric tests passed"
