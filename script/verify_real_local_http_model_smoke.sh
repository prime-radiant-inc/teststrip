#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/local_http_model_smoke_verifier_metrics.sh"

ENDPOINT="${TESTSTRIP_LOCAL_HTTP_MODEL_ENDPOINT:-}"
MODEL="${TESTSTRIP_LOCAL_HTTP_MODEL:-llava}"
IMAGE_FILE="${TESTSTRIP_LOCAL_HTTP_MODEL_IMAGE:-}"
MAX_SECONDS="${TESTSTRIP_LOCAL_HTTP_MODEL_SMOKE_MAX_SECONDS:-30}"
MIN_SIGNALS="${TESTSTRIP_LOCAL_HTTP_MODEL_SMOKE_MIN_SIGNALS:-1}"
EXPECTED_VISUAL_SIMILARITY_VECTOR="${TESTSTRIP_LOCAL_HTTP_MODEL_SMOKE_VISUAL_SIMILARITY_VECTOR:-0}"

if [[ -z "$ENDPOINT" ]]; then
  echo "real local HTTP model smoke skipped: TESTSTRIP_LOCAL_HTTP_MODEL_ENDPOINT is not set"
  exit 0
fi

if [[ -z "$IMAGE_FILE" ]]; then
  echo "TESTSTRIP_LOCAL_HTTP_MODEL_IMAGE is required when TESTSTRIP_LOCAL_HTTP_MODEL_ENDPOINT is set" >&2
  exit 1
fi

if [[ ! -f "$IMAGE_FILE" ]]; then
  echo "TESTSTRIP_LOCAL_HTTP_MODEL_IMAGE does not exist: $IMAGE_FILE" >&2
  exit 1
fi

output="$(cd "$ROOT_DIR" && swift run TeststripBench local-http-smoke "$ENDPOINT" "$MODEL" "$IMAGE_FILE" "$MAX_SECONDS")"
printf '%s\n' "$output"

summary_payload="$(extract_benchmark_summary_payload "$output")"
assert_local_http_model_smoke_summary "$summary_payload" "$MIN_SIGNALS" "$EXPECTED_VISUAL_SIMILARITY_VECTOR" "$MAX_SECONDS"

emit_local_http_model_smoke_metric "min_signals" "$MIN_SIGNALS"
emit_local_http_model_smoke_metric "expected_visual_similarity_vector" "$EXPECTED_VISUAL_SIMILARITY_VECTOR"
emit_local_http_model_smoke_metric "max_seconds" "$MAX_SECONDS"

metric_keys=(
  signals
  vector_signals
  visual_similarity_vector
)

for key in "${metric_keys[@]}"; do
  value="$(benchmark_summary_number "$summary_payload" "metrics.$key")"
  emit_local_http_model_smoke_metric "$key" "$value"
done

local_http_model_smoke_seconds="$(benchmark_summary_number "$summary_payload" measurements.local_http_model_smoke)"
emit_local_http_model_smoke_metric "local_http_model_smoke_seconds" "$local_http_model_smoke_seconds"
