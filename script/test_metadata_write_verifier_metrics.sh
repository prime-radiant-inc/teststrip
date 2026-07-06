#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/metadata_write_verifier_metrics.sh"

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

summary_payload='{"benchmark":"metadata_write","count":1000,"measurements":{"metadata_write":1.451},"metrics":{"updated_assets":1000,"catalog_assets":1000,"sidecars":1000,"matching_sidecar_metadata":1000,"synced_fingerprints":1000,"pending_sync_items":0,"unchanged_originals":1000}}'
mismatched_sidecar_payload='{"benchmark":"metadata_write","count":1000,"measurements":{"metadata_write":1.451},"metrics":{"updated_assets":1000,"catalog_assets":1000,"sidecars":1000,"matching_sidecar_metadata":999,"synced_fingerprints":1000,"pending_sync_items":0,"unchanged_originals":1000}}'
pending_payload='{"benchmark":"metadata_write","count":1000,"measurements":{"metadata_write":1.451},"metrics":{"updated_assets":1000,"catalog_assets":1000,"sidecars":1000,"matching_sidecar_metadata":1000,"synced_fingerprints":1000,"pending_sync_items":1,"unchanged_originals":1000}}'
slow_payload='{"benchmark":"metadata_write","count":1000,"measurements":{"metadata_write":9.5},"metrics":{"updated_assets":1000,"catalog_assets":1000,"sidecars":1000,"matching_sidecar_metadata":1000,"synced_fingerprints":1000,"pending_sync_items":0,"unchanged_originals":1000}}'

test_assert_metadata_write_summary_passes() {
  assert_metadata_write_summary "$summary_payload" 1000 2
}

test_assert_metadata_write_summary_fails_with_mismatched_sidecar_metadata() {
  if assert_metadata_write_summary "$mismatched_sidecar_payload" 1000 2 >/tmp/teststrip-metadata-write-mismatched.out 2>/tmp/teststrip-metadata-write-mismatched.err; then
    echo "expected mismatched sidecar metadata failure" >&2
    exit 1
  fi
  if ! grep -q "metrics.matching_sidecar_metadata expected 1000" /tmp/teststrip-metadata-write-mismatched.err; then
    echo "mismatched sidecar failure should name matching_sidecar_metadata" >&2
    exit 1
  fi
}

test_assert_metadata_write_summary_fails_with_pending_sync() {
  if assert_metadata_write_summary "$pending_payload" 1000 2 >/tmp/teststrip-metadata-write-pending.out 2>/tmp/teststrip-metadata-write-pending.err; then
    echo "expected pending sync failure" >&2
    exit 1
  fi
  if ! grep -q "metrics.pending_sync_items expected 0" /tmp/teststrip-metadata-write-pending.err; then
    echo "pending sync failure should name pending_sync_items" >&2
    exit 1
  fi
}

test_assert_metadata_write_summary_fails_when_slow() {
  if assert_metadata_write_summary "$slow_payload" 1000 2 >/tmp/teststrip-metadata-write-slow.out 2>/tmp/teststrip-metadata-write-slow.err; then
    echo "expected slow metadata write failure" >&2
    exit 1
  fi
  if ! grep -q "measurements.metadata_write" /tmp/teststrip-metadata-write-slow.err; then
    echo "slow failure should name metadata_write measurement" >&2
    exit 1
  fi
}

test_emit_metadata_write_metric() {
  assert_equal \
    "teststrip_metadata_write_metric sidecars=1000" \
    "$(emit_metadata_write_metric sidecars 1000)" \
    "metadata write metric line"
}

test_assert_metadata_write_summary_passes
test_assert_metadata_write_summary_fails_with_mismatched_sidecar_metadata
test_assert_metadata_write_summary_fails_with_pending_sync
test_assert_metadata_write_summary_fails_when_slow
test_emit_metadata_write_metric

echo "metadata write verifier metric tests passed"
