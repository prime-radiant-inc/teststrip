#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/source_availability_verifier_metrics.sh"

COUNT="${1:-1000}"
MAX_SECONDS="${TESTSTRIP_SOURCE_AVAILABILITY_MAX_SECONDS:-${2:-5}}"

output="$(cd "$ROOT_DIR" && swift run TeststripBench source-availability "$COUNT")"
printf '%s\n' "$output"

summary_payload="$(extract_benchmark_summary_payload "$output")"
assert_source_availability_summary "$summary_payload" "$COUNT" "$MAX_SECONDS"

emit_source_availability_metric "asset_count" "$COUNT"
emit_source_availability_metric "expected_online" "$(((COUNT + 2) / 3))"
emit_source_availability_metric "expected_missing" "$(((COUNT + 1) / 3))"
emit_source_availability_metric "expected_stale" "$((COUNT / 3))"
emit_source_availability_metric "max_seconds" "$MAX_SECONDS"

metric_keys=(
  catalog_assets
  refreshed_assets
  online_assets
  missing_assets
  stale_assets
)

for key in "${metric_keys[@]}"; do
  value="$(benchmark_summary_number "$summary_payload" "metrics.$key")"
  emit_source_availability_metric "$key" "$value"
done

refresh_seconds="$(benchmark_summary_number "$summary_payload" measurements.refresh_source_availability)"
emit_source_availability_metric "refresh_source_availability_seconds" "$refresh_seconds"
