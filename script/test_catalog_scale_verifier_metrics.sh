#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/catalog_scale_verifier_metrics.sh"

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

summary_output=$'human line\nbenchmark-summary\t{"benchmark":"catalog_scale","count":100000,"measurements":{"load_first_page":0.012,"count_picked":0.043,"seed_assets":3.4},"metrics":{"asset_count":100000,"picked_count":33334}}\n'
summary_payload='{"benchmark":"catalog_scale","count":100000,"measurements":{"load_first_page":0.012,"count_picked":0.043,"seed_assets":3.4},"metrics":{"asset_count":100000,"picked_count":33334}}'

test_extract_benchmark_summary_payload() {
  assert_equal "$summary_payload" "$(extract_benchmark_summary_payload "$summary_output")" "summary payload"
}

test_benchmark_summary_number() {
  assert_equal "100000" "$(benchmark_summary_number "$summary_payload" count)" "summary count"
  assert_equal "0.012" "$(benchmark_summary_number "$summary_payload" measurements.load_first_page)" "summary measurement"
  assert_equal "33334" "$(benchmark_summary_number "$summary_payload" metrics.picked_count)" "summary metric"
}

test_assert_benchmark_summary_number_at_most_passes_at_threshold() {
  assert_benchmark_summary_number_at_most "$summary_payload" measurements.count_picked 0.043
}

test_assert_benchmark_summary_number_at_most_fails_above_threshold() {
  if assert_benchmark_summary_number_at_most "$summary_payload" measurements.seed_assets 0.2 >/tmp/teststrip-catalog-scale-threshold.out 2>/tmp/teststrip-catalog-scale-threshold.err; then
    echo "expected threshold failure" >&2
    exit 1
  fi
  if ! grep -q "measurements.seed_assets" /tmp/teststrip-catalog-scale-threshold.err; then
    echo "threshold failure should name the slow measurement" >&2
    exit 1
  fi
}

test_emit_catalog_scale_metric() {
  assert_equal \
    "teststrip_catalog_scale_metric count_picked=0.043" \
    "$(emit_catalog_scale_metric count_picked 0.043)" \
    "catalog scale metric line"
}

test_extract_benchmark_summary_payload
test_benchmark_summary_number
test_assert_benchmark_summary_number_at_most_passes_at_threshold
test_assert_benchmark_summary_number_at_most_fails_above_threshold
test_emit_catalog_scale_metric

echo "catalog scale verifier metric tests passed"
