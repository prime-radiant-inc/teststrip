#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/catalog_scale_verifier_metrics.sh"

assert_offline_reconnect_smoke_summary() {
  local payload="$1"
  local max_seconds="$2"

  TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD="$payload" \
  /usr/bin/python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD"])

checks = {
    "benchmark": "offline_reconnect_smoke",
    "count": 1,
    "metrics.catalog_assets": 1,
    "metrics.cached_preview_readable_before_reconnect": 1,
    "metrics.cached_preview_readable_after_reconnect": 1,
    "metrics.reconnected_assets": 1,
    "metrics.online_assets_after_reconnect": 1,
    "metrics.sidecar_path_updated": 1,
    "metrics.unchanged_originals": 1,
    "metrics.unchanged_sidecars": 1,
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

  assert_benchmark_summary_number_at_most "$payload" measurements.offline_reconnect_smoke "$max_seconds"
}

emit_offline_reconnect_smoke_metric() {
  local key="$1"
  local value="$2"
  printf 'teststrip_offline_reconnect_smoke_metric %s=%s\n' "$key" "$value"
}
