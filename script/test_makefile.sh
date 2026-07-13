#!/usr/bin/env bash
set -euo pipefail

# Tests for the repo-root Makefile task runner. Uses `make -n` (dry run) so
# nothing is built, launched, or signed -- we only assert that each target
# delegates to the script we expect, and that every script the Makefile names
# actually exists on disk.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MAKEFILE="$ROOT_DIR/Makefile"

assert_exists() {
  local path="$1"
  local message="$2"
  if [[ ! -e "$path" ]]; then
    echo "$message: expected '$path' to exist" >&2
    exit 1
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "$message: expected output to contain '$needle'" >&2
    echo "$haystack" >&2
    exit 1
  fi
}

make_dry_run() {
  make -C "$ROOT_DIR" -n "$@"
}

test_default_target_is_help() {
  local output
  output="$(make -C "$ROOT_DIR" 2>&1)"
  for target in build test verify run smoke package package-dry reset clean; do
    assert_contains "$output" "$target" "default (help) target listing"
  done
}

test_targets_delegate_to_expected_commands() {
  assert_contains "$(make_dry_run build)" "swift build" "build target"
  assert_contains "$(make_dry_run test)" "swift test" "test target"
  assert_contains "$(make_dry_run verify)" "verify_headless_workflows.sh" "verify target"
  assert_contains "$(make_dry_run run)" "build_and_run.sh" "run target"
  assert_contains "$(make_dry_run smoke)" "build_and_run.sh --smoke" "smoke target"
  assert_contains "$(make_dry_run package)" "package_release.sh" "package target"
  assert_contains "$(make_dry_run package-dry)" "package_release.sh --dry-run" "package-dry target"
  assert_contains "$(make_dry_run reset)" "reset_isolated_test_data.sh" "reset target"
  assert_contains "$(make_dry_run clean)" "swift package clean" "clean target"
}

test_referenced_scripts_exist() {
  # Every script/<name>.sh mentioned in the Makefile must be present, so a
  # renamed or deleted script can't leave a target silently pointing at nothing.
  local script
  while IFS= read -r script; do
    assert_exists "$ROOT_DIR/$script" "Makefile references"
  done < <(grep -oE 'script/[A-Za-z0-9_]+\.sh' "$MAKEFILE" | sort -u)
}

test_default_target_is_help
test_targets_delegate_to_expected_commands
test_referenced_scripts_exist

echo "makefile task runner tests passed"
