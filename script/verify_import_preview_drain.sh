#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/import_preview_drain_verifier_metrics.sh"

COUNT="${1:-100}"
MAX_IMPORT_SECONDS="${TESTSTRIP_IMPORT_PREVIEW_DRAIN_MAX_IMPORT_SECONDS:-${2:-5}}"
MAX_DRAIN_SECONDS="${TESTSTRIP_IMPORT_PREVIEW_DRAIN_MAX_DRAIN_SECONDS:-${3:-10}}"

output="$(cd "$ROOT_DIR" && swift run TeststripBench import-preview-drain "$COUNT")"
printf '%s\n' "$output"

summary_payload="$(extract_benchmark_summary_payload "$output")"
assert_import_preview_drain_summary "$summary_payload" "$COUNT" "$MAX_IMPORT_SECONDS" "$MAX_DRAIN_SECONDS"

emit_import_preview_drain_metric "asset_count" "$COUNT"
emit_import_preview_drain_metric "expected_previews" "$((COUNT * 2))"
emit_import_preview_drain_metric "max_import_seconds" "$MAX_IMPORT_SECONDS"
emit_import_preview_drain_metric "max_drain_seconds" "$MAX_DRAIN_SECONDS"

metric_keys=(
  imported_assets
  catalog_assets
  pending_previews_before_drain
  generated_previews
  preview_failures
  pending_previews_after_drain
  cached_previews
)

for key in "${metric_keys[@]}"; do
  value="$(benchmark_summary_number "$summary_payload" "metrics.$key")"
  emit_import_preview_drain_metric "$key" "$value"
done

import_seconds="$(benchmark_summary_number "$summary_payload" measurements.import_deferred)"
drain_seconds="$(benchmark_summary_number "$summary_payload" measurements.preview_drain)"
emit_import_preview_drain_metric "import_deferred_seconds" "$import_seconds"
emit_import_preview_drain_metric "preview_drain_seconds" "$drain_seconds"
