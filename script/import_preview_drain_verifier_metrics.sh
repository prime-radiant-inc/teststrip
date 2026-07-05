#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/catalog_scale_verifier_metrics.sh"

assert_import_preview_drain_summary() {
  local payload="$1"
  local expected_count="$2"
  local max_import_seconds="$3"
  local max_drain_seconds="$4"

  TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD="$payload" \
  TESTSTRIP_IMPORT_PREVIEW_DRAIN_EXPECTED_COUNT="$expected_count" \
  /usr/bin/python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD"])
expected_count = int(os.environ["TESTSTRIP_IMPORT_PREVIEW_DRAIN_EXPECTED_COUNT"])
expected_preview_count = expected_count * 2

checks = {
    "benchmark": "import_preview_drain",
    "count": expected_count,
    "metrics.imported_assets": expected_count,
    "metrics.catalog_assets": expected_count,
    "metrics.pending_previews_before_drain": expected_preview_count,
    "metrics.generated_previews": expected_preview_count,
    "metrics.preview_failures": 0,
    "metrics.pending_previews_after_drain": 0,
    "metrics.cached_previews": expected_preview_count,
}

def value_at(path):
    value = payload
    for component in path.split("."):
        value = value[component]
    return value

for path, expected in checks.items():
    actual = value_at(path)
    if actual != expected:
        print(f"{path} expected {expected}, got {actual}", file=sys.stderr)
        sys.exit(1)
PY
  local invariant_status=$?
  if [[ "$invariant_status" -ne 0 ]]; then
    return "$invariant_status"
  fi

  assert_benchmark_summary_number_at_most "$payload" measurements.import_deferred "$max_import_seconds" || return $?
  assert_benchmark_summary_number_at_most "$payload" measurements.preview_drain "$max_drain_seconds"
}

emit_import_preview_drain_metric() {
  local key="$1"
  local value="$2"
  printf 'teststrip_import_preview_drain_metric %s=%s\n' "$key" "$value"
}
