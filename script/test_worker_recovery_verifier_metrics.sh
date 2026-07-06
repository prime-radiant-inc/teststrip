#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/worker_recovery_verifier_metrics.sh"

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

summary_payload='{"benchmark":"worker_recovery_smoke","count":4,"measurements":{"worker_recovery_smoke":0.121},"metrics":{"catalog_assets":4,"recovered_preview_work":4,"running_work":1,"queued_work":3,"dispatched_commands":1,"pending_previews":4,"worker_process_started":1}}'
missing_dispatch_payload='{"benchmark":"worker_recovery_smoke","count":4,"measurements":{"worker_recovery_smoke":0.121},"metrics":{"catalog_assets":4,"recovered_preview_work":4,"running_work":1,"queued_work":3,"dispatched_commands":0,"pending_previews":4,"worker_process_started":1}}'
slow_payload='{"benchmark":"worker_recovery_smoke","count":4,"measurements":{"worker_recovery_smoke":9.5},"metrics":{"catalog_assets":4,"recovered_preview_work":4,"running_work":1,"queued_work":3,"dispatched_commands":1,"pending_previews":4,"worker_process_started":1}}'

test_assert_worker_recovery_summary_passes() {
  assert_worker_recovery_summary "$summary_payload" 4 2
}

test_assert_worker_recovery_summary_fails_with_missing_dispatch() {
  if assert_worker_recovery_summary "$missing_dispatch_payload" 4 2 >/tmp/teststrip-worker-recovery-dispatch.out 2>/tmp/teststrip-worker-recovery-dispatch.err; then
    echo "expected missing dispatch failure" >&2
    exit 1
  fi
  if ! grep -q "metrics.dispatched_commands expected 1" /tmp/teststrip-worker-recovery-dispatch.err; then
    echo "missing dispatch failure should name dispatched_commands" >&2
    exit 1
  fi
}

test_assert_worker_recovery_summary_fails_when_slow() {
  if assert_worker_recovery_summary "$slow_payload" 4 2 >/tmp/teststrip-worker-recovery-slow.out 2>/tmp/teststrip-worker-recovery-slow.err; then
    echo "expected slow worker recovery failure" >&2
    exit 1
  fi
  if ! grep -q "measurements.worker_recovery_smoke" /tmp/teststrip-worker-recovery-slow.err; then
    echo "slow failure should name worker_recovery_smoke measurement" >&2
    exit 1
  fi
}

test_emit_worker_recovery_metric() {
  assert_equal \
    "teststrip_worker_recovery_metric recovered_preview_work=4" \
    "$(emit_worker_recovery_metric recovered_preview_work 4)" \
    "worker recovery metric line"
}

test_assert_worker_recovery_summary_passes
test_assert_worker_recovery_summary_fails_with_missing_dispatch
test_assert_worker_recovery_summary_fails_when_slow
test_emit_worker_recovery_metric

echo "worker recovery verifier metric tests passed"
