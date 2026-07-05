#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/catalog_scale_verifier_metrics.sh"

assert_real_corpus_smoke_summary() {
  local payload="$1"

  TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD="$payload" /usr/bin/python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD"])
metrics = payload["metrics"]

checks = {
    "benchmark": payload["benchmark"] == "real_corpus_smoke",
    "metrics.candidate_photos >= metrics.selected_photos": metrics["candidate_photos"] >= metrics["selected_photos"],
    "metrics.selected_photos > 0": metrics["selected_photos"] > 0,
    "metrics.imported_assets == metrics.selected_photos": metrics["imported_assets"] == metrics["selected_photos"],
    "metrics.catalog_assets == metrics.selected_photos": metrics["catalog_assets"] == metrics["selected_photos"],
    "metrics.best_effort_raws >= 1": metrics["best_effort_raws"] >= 1,
    "metrics.pending_previews == metrics.preview_eligible_assets * 2": metrics["pending_previews"] == metrics["preview_eligible_assets"] * 2,
    "metrics.full_image_decode_assets < metrics.selected_photos": metrics["full_image_decode_assets"] < metrics["selected_photos"],
    "metrics.unchanged_originals == metrics.selected_photos": metrics["unchanged_originals"] == metrics["selected_photos"],
    "metrics.unchanged_sidecars == metrics.adjacent_sidecars": metrics["unchanged_sidecars"] == metrics["adjacent_sidecars"],
}

for name, passed in checks.items():
    if not passed:
        print(f"{name} failed", file=sys.stderr)
        sys.exit(1)
PY
}

emit_real_corpus_smoke_metric() {
  local key="$1"
  local value="$2"
  printf 'teststrip_real_corpus_smoke_metric %s=%s\n' "$key" "$value"
}
