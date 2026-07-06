#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/catalog_scale_verifier_metrics.sh"

assert_local_http_model_smoke_summary() {
  local payload="$1"
  local min_signals="$2"
  local expected_visual_similarity_vector="$3"
  local max_seconds="$4"

  TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD="$payload" \
  TESTSTRIP_LOCAL_HTTP_SMOKE_MIN_SIGNALS="$min_signals" \
  TESTSTRIP_LOCAL_HTTP_SMOKE_EXPECTED_VISUAL_SIMILARITY_VECTOR="$expected_visual_similarity_vector" \
  /usr/bin/python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD"])
min_signals = int(os.environ["TESTSTRIP_LOCAL_HTTP_SMOKE_MIN_SIGNALS"])
expected_visual_similarity_vector = int(os.environ["TESTSTRIP_LOCAL_HTTP_SMOKE_EXPECTED_VISUAL_SIMILARITY_VECTOR"])

def value_at(path):
    value = payload
    for component in path.split("."):
        value = value[component]
    return value

checks = {
    "benchmark": "local_http_model_smoke",
    "count": 1,
}

for path, expected in checks.items():
    actual = value_at(path)
    if actual != expected:
        print(f"{path} expected {expected}, got {actual}", file=sys.stderr)
        sys.exit(1)

signals = value_at("metrics.signals")
if signals < min_signals:
    print(f"metrics.signals expected at least {min_signals}, got {signals}", file=sys.stderr)
    sys.exit(1)

visual_similarity_vector = value_at("metrics.visual_similarity_vector")
if visual_similarity_vector != expected_visual_similarity_vector:
    print(f"metrics.visual_similarity_vector expected {expected_visual_similarity_vector}, got {visual_similarity_vector}", file=sys.stderr)
    sys.exit(1)

vector_signals = value_at("metrics.vector_signals")
if vector_signals < expected_visual_similarity_vector:
    print(f"metrics.vector_signals expected at least {expected_visual_similarity_vector}, got {vector_signals}", file=sys.stderr)
    sys.exit(1)
PY
  local invariant_status=$?
  if [[ "$invariant_status" -ne 0 ]]; then
    return "$invariant_status"
  fi

  assert_benchmark_summary_number_at_most "$payload" measurements.local_http_model_smoke "$max_seconds"
}

emit_local_http_model_smoke_metric() {
  local key="$1"
  local value="$2"
  printf 'teststrip_local_http_model_smoke_metric %s=%s\n' "$key" "$value"
}
