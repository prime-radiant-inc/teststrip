#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# The real-corpus legs need an ignored local photo corpus that only exists in
# the main checkout. Point TESTSTRIP_REAL_CORPUS_DIR at it when it lives
# elsewhere; when it is absent (e.g. a fresh worktree) those legs are skipped
# with a notice rather than failing the whole gate.
REAL_CORPUS_DIR="${TESTSTRIP_REAL_CORPUS_DIR:-$ROOT_DIR/sample-data/photos/jesse-pictures}"

real_corpus_available() {
  [[ -d "$REAL_CORPUS_DIR" ]] \
    && [[ -n "$(find "$REAL_CORPUS_DIR" -type f -print -quit 2>/dev/null)" ]]
}

skip_real_corpus_legs() {
  echo "skipping real-corpus verification legs: no local photo corpus at $REAL_CORPUS_DIR" >&2
  echo "  set TESTSTRIP_REAL_CORPUS_DIR to an ignored local photo corpus to enable them" >&2
}

main() {
  swift test
  "$SCRIPT_DIR/build_and_run.sh" --build-sandboxed
  "$SCRIPT_DIR/verify_metadata_write.sh" "${TESTSTRIP_HEADLESS_METADATA_COUNT:-100}" "${TESTSTRIP_HEADLESS_METADATA_MAX_SECONDS:-5}"
  "$SCRIPT_DIR/verify_card_import_smoke.sh" "${TESTSTRIP_HEADLESS_CARD_IMPORT_COUNT:-12}" "${TESTSTRIP_HEADLESS_CARD_IMPORT_MAX_SECONDS:-5}"
  "$SCRIPT_DIR/verify_import_preview_drain.sh" "${TESTSTRIP_HEADLESS_IMPORT_COUNT:-100}" "${TESTSTRIP_HEADLESS_IMPORT_MAX_SECONDS:-5}" "${TESTSTRIP_HEADLESS_PREVIEW_DRAIN_MAX_SECONDS:-10}"
  "$SCRIPT_DIR/verify_source_availability.sh" "${TESTSTRIP_HEADLESS_SOURCE_COUNT:-120}" "${TESTSTRIP_HEADLESS_SOURCE_MAX_SECONDS:-5}"
  "$SCRIPT_DIR/verify_offline_reconnect_smoke.sh" "${TESTSTRIP_HEADLESS_OFFLINE_RECONNECT_MAX_SECONDS:-5}"
  "$SCRIPT_DIR/verify_preview_render.sh" "${TESTSTRIP_HEADLESS_PREVIEW_COUNT:-12}" "${TESTSTRIP_HEADLESS_PREVIEW_MAX_SECONDS:-5}"
  "$SCRIPT_DIR/verify_local_http_model_smoke.sh" "${TESTSTRIP_HEADLESS_LOCAL_HTTP_MODEL_MAX_SECONDS:-5}" "${TESTSTRIP_HEADLESS_LOCAL_HTTP_MODEL_MIN_SIGNALS:-3}" "${TESTSTRIP_HEADLESS_LOCAL_HTTP_MODEL_VISUAL_SIMILARITY_VECTOR:-1}"
  if real_corpus_available; then
    "$SCRIPT_DIR/verify_real_local_http_model_smoke.sh"
    "$SCRIPT_DIR/verify_real_corpus_smoke.sh" "$REAL_CORPUS_DIR"
  else
    skip_real_corpus_legs
  fi
  "$SCRIPT_DIR/verify_raw_fixtures.sh"
  "$SCRIPT_DIR/verify_worker_recovery.sh" "${TESTSTRIP_HEADLESS_WORKER_RECOVERY_COUNT:-24}" "${TESTSTRIP_HEADLESS_WORKER_RECOVERY_MAX_SECONDS:-5}"
  "$SCRIPT_DIR/verify_lane_overlap.sh" "${TESTSTRIP_HEADLESS_LANE_OVERLAP_COUNT:-24}" "${TESTSTRIP_HEADLESS_LANE_OVERLAP_MAX_SECONDS:-30}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
