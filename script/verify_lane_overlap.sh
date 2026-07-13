#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lane_overlap_verifier_metrics.sh"

COUNT="${1:-24}"
MAX_SECONDS="${TESTSTRIP_LANE_OVERLAP_MAX_SECONDS:-${2:-30}}"

# lane-overlap drives the real TeststripWorker binary out of process, so it
# must be built (not just TeststripBench, which `swift run` builds on its
# own) before the bench runs.
(cd "$ROOT_DIR" && swift build --product TeststripWorker)

output="$(cd "$ROOT_DIR" && swift run TeststripBench lane-overlap "$COUNT")"
printf '%s\n' "$output"

summary_payload="$(extract_benchmark_summary_payload "$output")"
assert_lane_overlap_summary "$summary_payload" "$COUNT" "$MAX_SECONDS"

emit_lane_overlap_metric "requested_count" "$COUNT"
emit_lane_overlap_metric "max_seconds" "$MAX_SECONDS"

metric_keys=(
  catalog_assets
  previewed_assets
  deferred_assets
  preview_work_items
  evaluation_work_items
  overlap_observed
  overlap_sample_count
  sample_count
  pending_previews_after_drain
  cached_previews
  evaluation_signal_assets
  evaluation_signals
  worker_process_started
)

for key in "${metric_keys[@]}"; do
  value="$(benchmark_summary_number "$summary_payload" "metrics.$key")"
  emit_lane_overlap_metric "$key" "$value"
done

lane_overlap_seconds="$(benchmark_summary_number "$summary_payload" measurements.lane_overlap_smoke)"
emit_lane_overlap_metric "lane_overlap_seconds" "$lane_overlap_seconds"
