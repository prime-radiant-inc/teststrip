#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/catalog_scale_verifier_metrics.sh"

assert_worker_recovery_summary() {
  local payload="$1"
  local expected_count="$2"
  local max_seconds="$3"

  TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD="$payload" \
  TESTSTRIP_WORKER_RECOVERY_EXPECTED_COUNT="$expected_count" \
  /usr/bin/python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD"])
expected_count = int(os.environ["TESTSTRIP_WORKER_RECOVERY_EXPECTED_COUNT"])
expected_running = 1 if expected_count > 0 else 0
expected_queued = max(expected_count - expected_running, 0)

checks = {
    "benchmark": "worker_recovery_smoke",
    "count": expected_count,
    "metrics.catalog_assets": expected_count,
    "metrics.recovered_preview_work": expected_count,
    "metrics.running_work": expected_running,
    "metrics.queued_work": expected_queued,
    "metrics.dispatched_commands": expected_running,
    "metrics.pending_previews": expected_count,
    "metrics.worker_process_started": expected_running,
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

  assert_benchmark_summary_number_at_most "$payload" measurements.worker_recovery_smoke "$max_seconds"
}

emit_worker_recovery_metric() {
  local key="$1"
  local value="$2"
  printf 'teststrip_worker_recovery_metric %s=%s\n' "$key" "$value"
}
