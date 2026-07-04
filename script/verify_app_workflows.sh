#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="${1:-Teststrip}"

"$SCRIPT_DIR/build_and_run.sh" --verify-smoke
"$SCRIPT_DIR/verify_grid_activation.sh" "$APP_NAME" smoke-0.jpg
"$SCRIPT_DIR/verify_grid_selection_feedback.sh" "$APP_NAME"
"$SCRIPT_DIR/verify_keyboard_culling.sh" "$APP_NAME" smoke-0.jpg
"$SCRIPT_DIR/verify_evaluation.sh" "$APP_NAME"
"$SCRIPT_DIR/verify_import_path.sh" "$APP_NAME"
