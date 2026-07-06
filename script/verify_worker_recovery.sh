#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/worker_recovery_verifier_metrics.sh"

COUNT="${1:-24}"
MAX_SECONDS="${TESTSTRIP_WORKER_RECOVERY_MAX_SECONDS:-${2:-5}}"

output="$(cd "$ROOT_DIR" && swift run TeststripBench worker-recovery-smoke "$COUNT")"
printf '%s\n' "$output"

summary_payload="$(extract_benchmark_summary_payload "$output")"
assert_worker_recovery_summary "$summary_payload" "$COUNT" "$MAX_SECONDS"

emit_worker_recovery_metric "requested_recovery_items" "$COUNT"
emit_worker_recovery_metric "expected_running" "$((COUNT > 0 ? 1 : 0))"
emit_worker_recovery_metric "expected_queued" "$((COUNT > 0 ? COUNT - 1 : 0))"
emit_worker_recovery_metric "max_seconds" "$MAX_SECONDS"

metric_keys=(
  catalog_assets
  recovered_preview_work
  running_work
  queued_work
  dispatched_commands
  pending_previews
  worker_process_started
)

for key in "${metric_keys[@]}"; do
  value="$(benchmark_summary_number "$summary_payload" "metrics.$key")"
  emit_worker_recovery_metric "$key" "$value"
done

worker_recovery_seconds="$(benchmark_summary_number "$summary_payload" measurements.worker_recovery_smoke)"
emit_worker_recovery_metric "worker_recovery_seconds" "$worker_recovery_seconds"
