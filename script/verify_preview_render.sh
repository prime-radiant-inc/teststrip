#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/preview_render_verifier_metrics.sh"

COUNT="${1:-100}"
MAX_SECONDS="${TESTSTRIP_PREVIEW_RENDER_MAX_SECONDS:-${2:-5}}"

output="$(cd "$ROOT_DIR" && swift run TeststripBench preview-render "$COUNT")"
printf '%s\n' "$output"

summary_payload="$(extract_benchmark_summary_payload "$output")"
assert_preview_render_summary "$summary_payload" "$COUNT" "$MAX_SECONDS"

emit_preview_render_metric "requested_source_images" "$COUNT"
emit_preview_render_metric "expected_previews" "$((COUNT * 4))"
emit_preview_render_metric "max_seconds" "$MAX_SECONDS"

metric_keys=(
  source_images
  rendered_previews
  cached_previews
)

for key in "${metric_keys[@]}"; do
  value="$(benchmark_summary_number "$summary_payload" "metrics.$key")"
  emit_preview_render_metric "$key" "$value"
done

preview_render_seconds="$(benchmark_summary_number "$summary_payload" measurements.preview_render)"
emit_preview_render_metric "preview_render_seconds" "$preview_render_seconds"
