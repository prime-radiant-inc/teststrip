#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/offline_reconnect_smoke_verifier_metrics.sh"

MAX_SECONDS="${TESTSTRIP_OFFLINE_RECONNECT_SMOKE_MAX_SECONDS:-${1:-5}}"

output="$(cd "$ROOT_DIR" && swift run TeststripBench offline-reconnect-smoke)"
printf '%s\n' "$output"

summary_payload="$(extract_benchmark_summary_payload "$output")"
assert_offline_reconnect_smoke_summary "$summary_payload" "$MAX_SECONDS"

emit_offline_reconnect_smoke_metric "max_seconds" "$MAX_SECONDS"

metric_keys=(
  catalog_assets
  cached_preview_readable_before_reconnect
  cached_preview_readable_after_reconnect
  reconnected_assets
  online_assets_after_reconnect
  sidecar_path_updated
  unchanged_originals
  unchanged_sidecars
)

for key in "${metric_keys[@]}"; do
  value="$(benchmark_summary_number "$summary_payload" "metrics.$key")"
  emit_offline_reconnect_smoke_metric "$key" "$value"
done

offline_reconnect_seconds="$(benchmark_summary_number "$summary_payload" measurements.offline_reconnect_smoke)"
emit_offline_reconnect_smoke_metric "offline_reconnect_seconds" "$offline_reconnect_seconds"
