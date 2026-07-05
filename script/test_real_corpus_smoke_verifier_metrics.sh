#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/real_corpus_smoke_verifier_metrics.sh"

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

summary_payload='{"benchmark":"real_corpus_smoke","count":0,"measurements":{"real_corpus_smoke":0.3},"metrics":{"adjacent_sidecars":1,"adjacent_sidecars_not_imported":1,"best_effort_raws":2,"candidate_photos":194,"catalog_assets":3,"full_image_decode_assets":1,"imported_assets":3,"imported_sidecar_sync_items":0,"pending_previews":6,"preview_eligible_assets":3,"selected_dng_files":1,"selected_jpg_files":1,"selected_photos":3,"selected_raf_files":1,"unchanged_originals":3,"unchanged_sidecars":1,"unsupported_files":0,"working_stills":1}}'
overclaimed_preview_payload='{"benchmark":"real_corpus_smoke","count":0,"measurements":{"real_corpus_smoke":0.3},"metrics":{"adjacent_sidecars":1,"adjacent_sidecars_not_imported":1,"best_effort_raws":2,"candidate_photos":194,"catalog_assets":3,"full_image_decode_assets":1,"imported_assets":3,"imported_sidecar_sync_items":0,"pending_previews":7,"preview_eligible_assets":3,"selected_dng_files":1,"selected_jpg_files":1,"selected_photos":3,"selected_raf_files":1,"unchanged_originals":3,"unchanged_sidecars":1,"unsupported_files":0,"working_stills":1}}'
mutated_original_payload='{"benchmark":"real_corpus_smoke","count":0,"measurements":{"real_corpus_smoke":0.3},"metrics":{"adjacent_sidecars":1,"adjacent_sidecars_not_imported":1,"best_effort_raws":2,"candidate_photos":194,"catalog_assets":3,"full_image_decode_assets":1,"imported_assets":3,"imported_sidecar_sync_items":0,"pending_previews":6,"preview_eligible_assets":3,"selected_dng_files":1,"selected_jpg_files":1,"selected_photos":3,"selected_raf_files":1,"unchanged_originals":2,"unchanged_sidecars":1,"unsupported_files":0,"working_stills":1}}'

assert_real_corpus_smoke_summary "$summary_payload"

if assert_real_corpus_smoke_summary "$overclaimed_preview_payload" >/tmp/teststrip-real-corpus-preview.out 2>/tmp/teststrip-real-corpus-preview.err; then
  echo "expected preview overclaim failure" >&2
  exit 1
fi
if ! grep -q "pending_previews" /tmp/teststrip-real-corpus-preview.err; then
  echo "preview failure should name pending_previews" >&2
  exit 1
fi

if assert_real_corpus_smoke_summary "$mutated_original_payload" >/tmp/teststrip-real-corpus-original.out 2>/tmp/teststrip-real-corpus-original.err; then
  echo "expected mutated original failure" >&2
  exit 1
fi
if ! grep -q "unchanged_originals" /tmp/teststrip-real-corpus-original.err; then
  echo "original mutation failure should name unchanged_originals" >&2
  exit 1
fi

assert_equal \
  "teststrip_real_corpus_smoke_metric imported_assets=3" \
  "$(emit_real_corpus_smoke_metric imported_assets 3)" \
  "real corpus smoke metric line"

echo "real corpus smoke verifier metric tests passed"
