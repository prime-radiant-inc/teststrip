#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/catalog_scale_verifier_metrics.sh"

assert_source_availability_summary() {
  local payload="$1"
  local expected_count="$2"
  local max_seconds="$3"

  TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD="$payload" \
  TESTSTRIP_SOURCE_AVAILABILITY_EXPECTED_COUNT="$expected_count" \
  /usr/bin/python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD"])
expected_count = int(os.environ["TESTSTRIP_SOURCE_AVAILABILITY_EXPECTED_COUNT"])
expected_online = (expected_count + 2) // 3
expected_missing = (expected_count + 1) // 3
expected_stale = expected_count // 3

checks = {
    "benchmark": "source_availability",
    "count": expected_count,
    "metrics.catalog_assets": expected_count,
    "metrics.refreshed_assets": expected_count,
    "metrics.online_assets": expected_online,
    "metrics.missing_assets": expected_missing,
    "metrics.stale_assets": expected_stale,
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

  assert_benchmark_summary_number_at_most "$payload" measurements.refresh_source_availability "$max_seconds"
}

emit_source_availability_metric() {
  local key="$1"
  local value="$2"
  printf 'teststrip_source_availability_metric %s=%s\n' "$key" "$value"
}
