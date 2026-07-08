#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="${1:-Teststrip}"

source "$SCRIPT_DIR/process_resource_metrics.sh"

latest_exact_process_pid() {
  local process_name="$1"
  pgrep -n -x "$process_name" || true
}

emit_app_workflow_snapshot() {
  local label="$1"
  printf 'teststrip_app_workflow_resource snapshot=%s\n' "$label"
  process_resource_snapshot "app_workflow" "app" "$(latest_exact_process_pid "$APP_NAME")"
  process_resource_snapshot "app_workflow" "worker" "$(latest_exact_process_pid "TeststripWorker")"
}

TESTSTRIP_CARD_IMPORT_ROUTE=typed-path "$SCRIPT_DIR/build_and_run.sh" --verify-smoke
emit_app_workflow_snapshot "after_launch"
"$SCRIPT_DIR/verify_grid_activation.sh" "$APP_NAME" smoke-0.jpg
emit_app_workflow_snapshot "after_grid_activation"
"$SCRIPT_DIR/verify_grid_selection_feedback.sh" "$APP_NAME"
emit_app_workflow_snapshot "after_grid_selection_feedback"
"$SCRIPT_DIR/verify_keyboard_culling.sh" "$APP_NAME" smoke-0.jpg
emit_app_workflow_snapshot "after_keyboard_culling"
# KNOWN-STALE (post-UX-simplification sweep): verify_evaluation drives the
# top-level "Evaluate" button and verify_card_import_path drives "Import Card",
# both of which the sweep intentionally demoted into menus (More ▾ → Analyze ▾ →
# Evaluate; Import ▾ → From Card…). Reconcile them to the current chrome — likely
# via the ⇧⌘B "Find Best Shots" menu command and/or a dedicated automation-controls
# flag — once the persona-pass UI settles. The headless gate does not use these.
"$SCRIPT_DIR/verify_evaluation.sh" "$APP_NAME"
emit_app_workflow_snapshot "after_evaluation"
"$SCRIPT_DIR/verify_import_path.sh" "$APP_NAME"
emit_app_workflow_snapshot "after_import_path"
"$SCRIPT_DIR/verify_card_import_path.sh" "$APP_NAME"
emit_app_workflow_snapshot "after_card_import_path"
