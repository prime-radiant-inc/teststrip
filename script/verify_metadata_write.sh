#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/metadata_write_verifier_metrics.sh"

COUNT="${1:-1000}"
MAX_SECONDS="${TESTSTRIP_METADATA_WRITE_MAX_SECONDS:-${2:-5}}"

output="$(cd "$ROOT_DIR" && swift run TeststripBench metadata-write "$COUNT")"
printf '%s\n' "$output"

summary_payload="$(extract_benchmark_summary_payload "$output")"
assert_metadata_write_summary "$summary_payload" "$COUNT" "$MAX_SECONDS"

emit_metadata_write_metric "asset_count" "$COUNT"
emit_metadata_write_metric "max_seconds" "$MAX_SECONDS"

metric_keys=(
  updated_assets
  catalog_assets
  sidecars
  matching_sidecar_metadata
  synced_fingerprints
  pending_sync_items
  unchanged_originals
)

for key in "${metric_keys[@]}"; do
  value="$(benchmark_summary_number "$summary_payload" "metrics.$key")"
  emit_metadata_write_metric "$key" "$value"
done

metadata_write_seconds="$(benchmark_summary_number "$summary_payload" measurements.metadata_write)"
emit_metadata_write_metric "metadata_write_seconds" "$metadata_write_seconds"
