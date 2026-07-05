#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/preview_render_verifier_metrics.sh"

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

summary_payload='{"benchmark":"preview_render","count":100,"measurements":{"preview_render":1.551},"metrics":{"source_images":100,"rendered_previews":400,"cached_previews":400}}'
missing_cache_payload='{"benchmark":"preview_render","count":100,"measurements":{"preview_render":1.551},"metrics":{"source_images":100,"rendered_previews":400,"cached_previews":399}}'
slow_payload='{"benchmark":"preview_render","count":100,"measurements":{"preview_render":9.5},"metrics":{"source_images":100,"rendered_previews":400,"cached_previews":400}}'

test_assert_preview_render_summary_passes() {
  assert_preview_render_summary "$summary_payload" 100 2
}

test_assert_preview_render_summary_fails_with_missing_cached_preview() {
  if assert_preview_render_summary "$missing_cache_payload" 100 2 >/tmp/teststrip-preview-render-cache.out 2>/tmp/teststrip-preview-render-cache.err; then
    echo "expected missing cached preview failure" >&2
    exit 1
  fi
  if ! grep -q "metrics.cached_previews expected 400" /tmp/teststrip-preview-render-cache.err; then
    echo "missing cached preview failure should name cached_previews" >&2
    exit 1
  fi
}

test_assert_preview_render_summary_fails_when_slow() {
  if assert_preview_render_summary "$slow_payload" 100 2 >/tmp/teststrip-preview-render-slow.out 2>/tmp/teststrip-preview-render-slow.err; then
    echo "expected slow preview render failure" >&2
    exit 1
  fi
  if ! grep -q "measurements.preview_render" /tmp/teststrip-preview-render-slow.err; then
    echo "slow failure should name preview_render measurement" >&2
    exit 1
  fi
}

test_emit_preview_render_metric() {
  assert_equal \
    "teststrip_preview_render_metric cached_previews=400" \
    "$(emit_preview_render_metric cached_previews 400)" \
    "preview render metric line"
}

test_assert_preview_render_summary_passes
test_assert_preview_render_summary_fails_with_missing_cached_preview
test_assert_preview_render_summary_fails_when_slow
test_emit_preview_render_metric

echo "preview render verifier metric tests passed"
