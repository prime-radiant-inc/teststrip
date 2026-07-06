#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/card_import_smoke_verifier_metrics.sh"

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

summary_payload='{"benchmark":"card_import_smoke","count":12,"measurements":{"card_import_smoke":1.25},"metrics":{"imported_assets":12,"catalog_assets":12,"destination_originals":12,"cached_previews":24,"source_originals_unchanged":12,"source_roots":1,"destination_catalog_assets":12}}'
missing_preview_payload='{"benchmark":"card_import_smoke","count":12,"measurements":{"card_import_smoke":1.25},"metrics":{"imported_assets":12,"catalog_assets":12,"destination_originals":12,"cached_previews":23,"source_originals_unchanged":12,"source_roots":1,"destination_catalog_assets":12}}'
slow_payload='{"benchmark":"card_import_smoke","count":12,"measurements":{"card_import_smoke":9.5},"metrics":{"imported_assets":12,"catalog_assets":12,"destination_originals":12,"cached_previews":24,"source_originals_unchanged":12,"source_roots":1,"destination_catalog_assets":12}}'

test_assert_card_import_smoke_summary_passes() {
  assert_card_import_smoke_summary "$summary_payload" 12 2
}

test_assert_card_import_smoke_summary_fails_with_missing_cached_preview() {
  if assert_card_import_smoke_summary "$missing_preview_payload" 12 2 >/tmp/teststrip-card-import-smoke-cache.out 2>/tmp/teststrip-card-import-smoke-cache.err; then
    echo "expected missing cached preview failure" >&2
    exit 1
  fi
  if ! grep -q "metrics.cached_previews expected 24" /tmp/teststrip-card-import-smoke-cache.err; then
    echo "missing cached preview failure should name cached_previews" >&2
    exit 1
  fi
}

test_assert_card_import_smoke_summary_fails_when_slow() {
  if assert_card_import_smoke_summary "$slow_payload" 12 2 >/tmp/teststrip-card-import-smoke-slow.out 2>/tmp/teststrip-card-import-smoke-slow.err; then
    echo "expected slow card import smoke failure" >&2
    exit 1
  fi
  if ! grep -q "measurements.card_import_smoke" /tmp/teststrip-card-import-smoke-slow.err; then
    echo "slow failure should name card_import_smoke measurement" >&2
    exit 1
  fi
}

test_emit_card_import_smoke_metric() {
  assert_equal \
    "teststrip_card_import_smoke_metric cached_previews=24" \
    "$(emit_card_import_smoke_metric cached_previews 24)" \
    "card import smoke metric line"
}

test_assert_card_import_smoke_summary_passes
test_assert_card_import_smoke_summary_fails_with_missing_cached_preview
test_assert_card_import_smoke_summary_fails_when_slow
test_emit_card_import_smoke_metric

echo "card import smoke verifier metric tests passed"
