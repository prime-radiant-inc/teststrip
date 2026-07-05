#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/catalog_scale_verifier_metrics.sh"

COUNT="${1:-100000}"
MAX_SECONDS="${TESTSTRIP_CATALOG_SCALE_MAX_SECONDS:-${2:-0.2}}"

output="$(cd "$ROOT_DIR" && swift run TeststripBench "$COUNT")"
printf '%s\n' "$output"

summary_payload="$(extract_benchmark_summary_payload "$output")"
asset_count="$(benchmark_summary_number "$summary_payload" metrics.asset_count)"
if [[ "$asset_count" != "$COUNT" ]]; then
  echo "metrics.asset_count expected $COUNT, got $asset_count" >&2
  exit 1
fi

emit_catalog_scale_metric "asset_count" "$asset_count"
emit_catalog_scale_metric "max_filter_seconds" "$MAX_SECONDS"

measurement_keys=(
  load_first_page
  load_middle_page
  load_filtered_page
  count_filtered_rating_4_plus
  count_picked
  count_green_label
  count_keyword_batch_10
  count_offline
  count_folder
  count_camera_smokecam_2
  count_lens_50mm
  count_iso_at_least_500
  count_recent_capture
)

for key in "${measurement_keys[@]}"; do
  assert_benchmark_summary_number_at_most "$summary_payload" "measurements.$key" "$MAX_SECONDS"
  value="$(benchmark_summary_number "$summary_payload" "measurements.$key")"
  emit_catalog_scale_metric "${key}_seconds" "$value"
done
