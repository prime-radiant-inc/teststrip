#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/real_corpus_smoke_verifier_metrics.sh"

PHOTO_DIRECTORY="${1:-$ROOT_DIR/sample-data/photos/jesse-pictures}"

output="$(cd "$ROOT_DIR" && swift run TeststripBench real-corpus-smoke "$PHOTO_DIRECTORY")"
printf '%s\n' "$output"

summary_payload="$(extract_benchmark_summary_payload "$output")"
assert_real_corpus_smoke_summary "$summary_payload"

metric_keys=(
  candidate_photos
  selected_photos
  imported_assets
  catalog_assets
  working_stills
  best_effort_raws
  unsupported_files
  preview_eligible_assets
  pending_previews
  full_image_decode_assets
  adjacent_sidecars
  imported_sidecar_sync_items
  adjacent_sidecars_not_imported
  unchanged_originals
  unchanged_sidecars
)

for key in "${metric_keys[@]}"; do
  value="$(benchmark_summary_number "$summary_payload" "metrics.$key")"
  emit_real_corpus_smoke_metric "$key" "$value"
done
