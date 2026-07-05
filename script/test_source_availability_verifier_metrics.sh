#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/source_availability_verifier_metrics.sh"

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

summary_payload='{"benchmark":"source_availability","count":12,"measurements":{"refresh_source_availability":0.041},"metrics":{"catalog_assets":12,"refreshed_assets":12,"online_assets":4,"missing_assets":4,"stale_assets":4}}'
stale_count_payload='{"benchmark":"source_availability","count":12,"measurements":{"refresh_source_availability":0.041},"metrics":{"catalog_assets":12,"refreshed_assets":12,"online_assets":4,"missing_assets":4,"stale_assets":3}}'
slow_payload='{"benchmark":"source_availability","count":12,"measurements":{"refresh_source_availability":9.5},"metrics":{"catalog_assets":12,"refreshed_assets":12,"online_assets":4,"missing_assets":4,"stale_assets":4}}'

test_assert_source_availability_summary_passes() {
  assert_source_availability_summary "$summary_payload" 12 2
}

test_assert_source_availability_summary_fails_with_wrong_stale_count() {
  if assert_source_availability_summary "$stale_count_payload" 12 2 >/tmp/teststrip-source-availability-stale.out 2>/tmp/teststrip-source-availability-stale.err; then
    echo "expected stale count failure" >&2
    exit 1
  fi
  if ! grep -q "metrics.stale_assets expected 4" /tmp/teststrip-source-availability-stale.err; then
    echo "stale count failure should name stale_assets" >&2
    exit 1
  fi
}

test_assert_source_availability_summary_fails_when_slow() {
  if assert_source_availability_summary "$slow_payload" 12 2 >/tmp/teststrip-source-availability-slow.out 2>/tmp/teststrip-source-availability-slow.err; then
    echo "expected slow source availability failure" >&2
    exit 1
  fi
  if ! grep -q "measurements.refresh_source_availability" /tmp/teststrip-source-availability-slow.err; then
    echo "slow failure should name refresh_source_availability measurement" >&2
    exit 1
  fi
}

test_emit_source_availability_metric() {
  assert_equal \
    "teststrip_source_availability_metric refreshed_assets=12" \
    "$(emit_source_availability_metric refreshed_assets 12)" \
    "source availability metric line"
}

test_assert_source_availability_summary_passes
test_assert_source_availability_summary_fails_with_wrong_stale_count
test_assert_source_availability_summary_fails_when_slow
test_emit_source_availability_metric

echo "source availability verifier metric tests passed"
