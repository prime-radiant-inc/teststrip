#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_DIR="${TESTSTRIP_RAW_FIXTURE_DIRECTORY:-$ROOT_DIR/sample-data/photos/raw-fixtures-local}"

echo "RAW fixture directory: $FIXTURE_DIR"
(
  cd "$ROOT_DIR"
  TESTSTRIP_RAW_FIXTURE_DIRECTORY="$FIXTURE_DIR" swift test --filter DecodeRegistryTests/testRawFixtureCoverageUsesReal
)
