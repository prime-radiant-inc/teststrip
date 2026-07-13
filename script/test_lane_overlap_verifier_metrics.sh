#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lane_overlap_verifier_metrics.sh"

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

summary_payload='{"benchmark":"lane_overlap_smoke","count":4,"measurements":{"lane_overlap_smoke":0.121},"metrics":{"catalog_assets":4,"previewed_assets":2,"deferred_assets":2,"preview_work_items":4,"evaluation_work_items":2,"overlap_observed":1,"overlap_sample_count":3,"sample_count":10,"pending_previews_after_drain":0,"cached_previews":8,"evaluation_signal_assets":2,"evaluation_signals":2,"worker_process_started":1}}'
overlap_not_observed_payload='{"benchmark":"lane_overlap_smoke","count":4,"measurements":{"lane_overlap_smoke":0.121},"metrics":{"catalog_assets":4,"previewed_assets":2,"deferred_assets":2,"preview_work_items":4,"evaluation_work_items":2,"overlap_observed":0,"overlap_sample_count":3,"sample_count":10,"pending_previews_after_drain":0,"cached_previews":8,"evaluation_signal_assets":2,"evaluation_signals":2,"worker_process_started":1}}'
pending_previews_payload='{"benchmark":"lane_overlap_smoke","count":4,"measurements":{"lane_overlap_smoke":0.121},"metrics":{"catalog_assets":4,"previewed_assets":2,"deferred_assets":2,"preview_work_items":4,"evaluation_work_items":2,"overlap_observed":1,"overlap_sample_count":3,"sample_count":10,"pending_previews_after_drain":1,"cached_previews":8,"evaluation_signal_assets":2,"evaluation_signals":2,"worker_process_started":1}}'
slow_payload='{"benchmark":"lane_overlap_smoke","count":4,"measurements":{"lane_overlap_smoke":9.5},"metrics":{"catalog_assets":4,"previewed_assets":2,"deferred_assets":2,"preview_work_items":4,"evaluation_work_items":2,"overlap_observed":1,"overlap_sample_count":3,"sample_count":10,"pending_previews_after_drain":0,"cached_previews":8,"evaluation_signal_assets":2,"evaluation_signals":2,"worker_process_started":1}}'

test_assert_lane_overlap_summary_passes() {
  assert_lane_overlap_summary "$summary_payload" 4 2
}

test_assert_lane_overlap_summary_fails_when_overlap_not_observed() {
  if assert_lane_overlap_summary "$overlap_not_observed_payload" 4 2 >/tmp/teststrip-lane-overlap-observed.out 2>/tmp/teststrip-lane-overlap-observed.err; then
    echo "expected overlap-not-observed failure" >&2
    exit 1
  fi
  if ! grep -q "metrics.overlap_observed expected 1" /tmp/teststrip-lane-overlap-observed.err; then
    echo "overlap-not-observed failure should name overlap_observed" >&2
    exit 1
  fi
}

test_assert_lane_overlap_summary_fails_with_pending_previews_after_drain() {
  if assert_lane_overlap_summary "$pending_previews_payload" 4 2 >/tmp/teststrip-lane-overlap-pending.out 2>/tmp/teststrip-lane-overlap-pending.err; then
    echo "expected pending previews after drain failure" >&2
    exit 1
  fi
  if ! grep -q "metrics.pending_previews_after_drain expected 0" /tmp/teststrip-lane-overlap-pending.err; then
    echo "pending previews after drain failure should name pending_previews_after_drain" >&2
    exit 1
  fi
}

test_assert_lane_overlap_summary_fails_when_slow() {
  if assert_lane_overlap_summary "$slow_payload" 4 2 >/tmp/teststrip-lane-overlap-slow.out 2>/tmp/teststrip-lane-overlap-slow.err; then
    echo "expected slow lane overlap failure" >&2
    exit 1
  fi
  if ! grep -q "measurements.lane_overlap_smoke" /tmp/teststrip-lane-overlap-slow.err; then
    echo "slow failure should name lane_overlap_smoke measurement" >&2
    exit 1
  fi
}

test_emit_lane_overlap_metric() {
  assert_equal \
    "teststrip_lane_overlap_metric overlap_observed=1" \
    "$(emit_lane_overlap_metric overlap_observed 1)" \
    "lane overlap metric line"
}

test_assert_lane_overlap_summary_passes
test_assert_lane_overlap_summary_fails_when_overlap_not_observed
test_assert_lane_overlap_summary_fails_with_pending_previews_after_drain
test_assert_lane_overlap_summary_fails_when_slow
test_emit_lane_overlap_metric

echo "lane overlap verifier metric tests passed"
