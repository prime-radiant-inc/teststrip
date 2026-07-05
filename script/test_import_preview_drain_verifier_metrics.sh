#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/import_preview_drain_verifier_metrics.sh"

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

summary_payload='{"benchmark":"import_preview_drain","count":100,"measurements":{"import_deferred":0.451,"preview_drain":1.551},"metrics":{"imported_assets":100,"catalog_assets":100,"pending_previews_before_drain":200,"generated_previews":200,"preview_failures":0,"pending_previews_after_drain":0,"cached_previews":200}}'
pending_payload='{"benchmark":"import_preview_drain","count":100,"measurements":{"import_deferred":0.451,"preview_drain":1.551},"metrics":{"imported_assets":100,"catalog_assets":100,"pending_previews_before_drain":200,"generated_previews":199,"preview_failures":0,"pending_previews_after_drain":1,"cached_previews":199}}'
slow_import_payload='{"benchmark":"import_preview_drain","count":100,"measurements":{"import_deferred":9.5,"preview_drain":1.551},"metrics":{"imported_assets":100,"catalog_assets":100,"pending_previews_before_drain":200,"generated_previews":200,"preview_failures":0,"pending_previews_after_drain":0,"cached_previews":200}}'
slow_drain_payload='{"benchmark":"import_preview_drain","count":100,"measurements":{"import_deferred":0.451,"preview_drain":9.5},"metrics":{"imported_assets":100,"catalog_assets":100,"pending_previews_before_drain":200,"generated_previews":200,"preview_failures":0,"pending_previews_after_drain":0,"cached_previews":200}}'

test_assert_import_preview_drain_summary_passes() {
  assert_import_preview_drain_summary "$summary_payload" 100 2 2
}

test_assert_import_preview_drain_summary_fails_with_pending_previews() {
  if assert_import_preview_drain_summary "$pending_payload" 100 2 2 >/tmp/teststrip-import-preview-drain-pending.out 2>/tmp/teststrip-import-preview-drain-pending.err; then
    echo "expected pending preview failure" >&2
    exit 1
  fi
  if ! grep -q "metrics.generated_previews expected 200" /tmp/teststrip-import-preview-drain-pending.err; then
    echo "pending preview failure should name generated_previews" >&2
    exit 1
  fi
}

test_assert_import_preview_drain_summary_fails_when_import_is_slow() {
  if assert_import_preview_drain_summary "$slow_import_payload" 100 2 2 >/tmp/teststrip-import-preview-drain-import.out 2>/tmp/teststrip-import-preview-drain-import.err; then
    echo "expected slow import failure" >&2
    exit 1
  fi
  if ! grep -q "measurements.import_deferred" /tmp/teststrip-import-preview-drain-import.err; then
    echo "slow import failure should name import_deferred measurement" >&2
    exit 1
  fi
}

test_assert_import_preview_drain_summary_fails_when_drain_is_slow() {
  if assert_import_preview_drain_summary "$slow_drain_payload" 100 2 2 >/tmp/teststrip-import-preview-drain-drain.out 2>/tmp/teststrip-import-preview-drain-drain.err; then
    echo "expected slow drain failure" >&2
    exit 1
  fi
  if ! grep -q "measurements.preview_drain" /tmp/teststrip-import-preview-drain-drain.err; then
    echo "slow drain failure should name preview_drain measurement" >&2
    exit 1
  fi
}

test_emit_import_preview_drain_metric() {
  assert_equal \
    "teststrip_import_preview_drain_metric generated_previews=200" \
    "$(emit_import_preview_drain_metric generated_previews 200)" \
    "import preview drain metric line"
}

test_assert_import_preview_drain_summary_passes
test_assert_import_preview_drain_summary_fails_with_pending_previews
test_assert_import_preview_drain_summary_fails_when_import_is_slow
test_assert_import_preview_drain_summary_fails_when_drain_is_slow
test_emit_import_preview_drain_metric

echo "import preview drain verifier metric tests passed"
