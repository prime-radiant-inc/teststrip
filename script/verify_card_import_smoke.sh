#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/card_import_smoke_verifier_metrics.sh"

COUNT="${1:-12}"
MAX_SECONDS="${TESTSTRIP_CARD_IMPORT_SMOKE_MAX_SECONDS:-${2:-5}}"

output="$(cd "$ROOT_DIR" && swift run TeststripBench card-import-smoke "$COUNT")"
printf '%s\n' "$output"

summary_payload="$(extract_benchmark_summary_payload "$output")"
assert_card_import_smoke_summary "$summary_payload" "$COUNT" "$MAX_SECONDS"

emit_card_import_smoke_metric "asset_count" "$COUNT"
emit_card_import_smoke_metric "expected_previews" "$((COUNT * 2))"
emit_card_import_smoke_metric "max_seconds" "$MAX_SECONDS"

metric_keys=(
  imported_assets
  catalog_assets
  destination_originals
  cached_previews
  source_originals_unchanged
  source_roots
  destination_catalog_assets
)

for key in "${metric_keys[@]}"; do
  value="$(benchmark_summary_number "$summary_payload" "metrics.$key")"
  emit_card_import_smoke_metric "$key" "$value"
done

card_import_seconds="$(benchmark_summary_number "$summary_payload" measurements.card_import_smoke)"
emit_card_import_smoke_metric "card_import_seconds" "$card_import_seconds"
