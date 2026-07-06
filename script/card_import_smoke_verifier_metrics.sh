#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/catalog_scale_verifier_metrics.sh"

assert_card_import_smoke_summary() {
  local payload="$1"
  local expected_count="$2"
  local max_seconds="$3"

  TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD="$payload" \
  TESTSTRIP_CARD_IMPORT_SMOKE_EXPECTED_COUNT="$expected_count" \
  /usr/bin/python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD"])
expected_count = int(os.environ["TESTSTRIP_CARD_IMPORT_SMOKE_EXPECTED_COUNT"])
expected_preview_count = expected_count * 2

checks = {
    "benchmark": "card_import_smoke",
    "count": expected_count,
    "metrics.imported_assets": expected_count,
    "metrics.catalog_assets": expected_count,
    "metrics.destination_originals": expected_count,
    "metrics.cached_previews": expected_preview_count,
    "metrics.source_originals_unchanged": expected_count,
    "metrics.source_roots": 1,
    "metrics.destination_catalog_assets": expected_count,
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

  assert_benchmark_summary_number_at_most "$payload" measurements.card_import_smoke "$max_seconds"
}

emit_card_import_smoke_metric() {
  local key="$1"
  local value="$2"
  printf 'teststrip_card_import_smoke_metric %s=%s\n' "$key" "$value"
}
