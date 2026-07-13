#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/catalog_scale_verifier_metrics.sh"

assert_lane_overlap_summary() {
  local payload="$1"
  local expected_count="$2"
  local max_seconds="$3"

  TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD="$payload" \
  TESTSTRIP_LANE_OVERLAP_EXPECTED_COUNT="$expected_count" \
  /usr/bin/python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD"])
expected_count = int(os.environ["TESTSTRIP_LANE_OVERLAP_EXPECTED_COUNT"])
expected_deferred = expected_count // 2
expected_previewed = expected_count - expected_deferred

def value_at(path):
    value = payload
    for component in path.split("."):
        value = value[component]
    return value

checks = {
    "benchmark": "lane_overlap_smoke",
    "count": expected_count,
    "metrics.catalog_assets": expected_count,
    "metrics.previewed_assets": expected_previewed,
    "metrics.deferred_assets": expected_deferred,
    "metrics.preview_work_items": expected_deferred * 2,
    "metrics.evaluation_work_items": expected_previewed,
    # The core regression guard: at least one sample caught a
    # .previewGeneration item and a .recognition item both running (and both
    # actually dispatched to the worker) at once.
    "metrics.overlap_observed": 1,
    "metrics.pending_previews_after_drain": 0,
    "metrics.cached_previews": expected_count * 2,
    "metrics.evaluation_signal_assets": expected_previewed,
    "metrics.worker_process_started": 1,
}

for path, expected in checks.items():
    actual = value_at(path)
    if actual != expected:
        print(f"{path} expected {expected}, got {actual}", file=sys.stderr)
        sys.exit(1)

overlap_sample_count = value_at("metrics.overlap_sample_count")
if overlap_sample_count <= 0:
    print(f"metrics.overlap_sample_count expected > 0, got {overlap_sample_count}", file=sys.stderr)
    sys.exit(1)

evaluation_signals = value_at("metrics.evaluation_signals")
evaluation_work_items = value_at("metrics.evaluation_work_items")
if evaluation_signals < evaluation_work_items:
    print(
        f"metrics.evaluation_signals expected >= {evaluation_work_items}, got {evaluation_signals}",
        file=sys.stderr,
    )
    sys.exit(1)
PY
  local invariant_status=$?
  if [[ "$invariant_status" -ne 0 ]]; then
    return "$invariant_status"
  fi

  assert_benchmark_summary_number_at_most "$payload" measurements.lane_overlap_smoke "$max_seconds"
}

emit_lane_overlap_metric() {
  local key="$1"
  local value="$2"
  printf 'teststrip_lane_overlap_metric %s=%s\n' "$key" "$value"
}
