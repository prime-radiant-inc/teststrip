#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/catalog_scale_verifier_metrics.sh"

assert_metadata_write_summary() {
  local payload="$1"
  local expected_count="$2"
  local max_seconds="$3"

  TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD="$payload" \
  TESTSTRIP_METADATA_WRITE_EXPECTED_COUNT="$expected_count" \
  /usr/bin/python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD"])
expected_count = int(os.environ["TESTSTRIP_METADATA_WRITE_EXPECTED_COUNT"])

checks = {
    "benchmark": "metadata_write",
    "count": expected_count,
    "metrics.updated_assets": expected_count,
    "metrics.catalog_assets": expected_count,
    "metrics.sidecars": expected_count,
    "metrics.matching_sidecar_metadata": expected_count,
    "metrics.synced_fingerprints": expected_count,
    "metrics.pending_sync_items": 0,
    "metrics.unchanged_originals": expected_count,
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

  assert_benchmark_summary_number_at_most "$payload" measurements.metadata_write "$max_seconds"
}

emit_metadata_write_metric() {
  local key="$1"
  local value="$2"
  printf 'teststrip_metadata_write_metric %s=%s\n' "$key" "$value"
}
