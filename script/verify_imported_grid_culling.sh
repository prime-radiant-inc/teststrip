#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="${1:-Teststrip}"
IMPORT_COUNT="${TESTSTRIP_AX_IMPORTED_GRID_COUNT:-4}"
TARGET_INDEX="${TESTSTRIP_AX_IMPORTED_GRID_TARGET_INDEX:-2}"

if [[ ! "$IMPORT_COUNT" =~ ^[0-9]+$ ]] || [[ "$IMPORT_COUNT" -lt 1 ]]; then
  echo "TESTSTRIP_AX_IMPORTED_GRID_COUNT must be a positive integer" >&2
  exit 2
fi

if [[ ! "$TARGET_INDEX" =~ ^[0-9]+$ ]] || [[ "$TARGET_INDEX" -ge "$IMPORT_COUNT" ]]; then
  echo "TESTSTRIP_AX_IMPORTED_GRID_TARGET_INDEX must be a zero-based index below TESTSTRIP_AX_IMPORTED_GRID_COUNT" >&2
  exit 2
fi

IMPORT_DIR="$(mktemp -d /tmp/teststrip-imported-grid.XXXXXX)"
trap 'rm -rf "$IMPORT_DIR"' EXIT

PNG_BYTES='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII='
for ((index = 0; index < IMPORT_COUNT; index++)); do
  asset_name="$(printf 'imported-grid-%04d.png' "$index")"
  printf '%s' "$PNG_BYTES" | base64 -D > "$IMPORT_DIR/$asset_name"
done

TARGET_ASSET="$(printf 'imported-grid-%04d.png' "$TARGET_INDEX")"

TESTSTRIP_AX_IMPORT_SOURCE_DIR="$IMPORT_DIR" \
TESTSTRIP_AX_TARGET_ASSET="$TARGET_ASSET" \
"$SCRIPT_DIR/verify_import_path.sh" "$APP_NAME"

"$SCRIPT_DIR/verify_grid_selection_feedback.sh" "$APP_NAME" "$TARGET_ASSET"
"$SCRIPT_DIR/verify_keyboard_culling.sh" "$APP_NAME" "$TARGET_ASSET"

echo "imported grid culling verified $TARGET_ASSET"
