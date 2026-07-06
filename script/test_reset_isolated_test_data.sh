#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

assert_exists() {
  local path="$1"
  local message="$2"
  if [[ ! -e "$path" ]]; then
    echo "$message: expected '$path' to exist" >&2
    exit 1
  fi
}

assert_missing() {
  local path="$1"
  local message="$2"
  if [[ -e "$path" ]]; then
    echo "$message: expected '$path' to be removed" >&2
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

make_isolated_root() {
  local root="$1"
  local name="$2"
  local candidate="$root/$name"
  mkdir -p "$candidate/Teststrip/Previews"
  touch "$candidate/Teststrip/catalog.sqlite"
  printf '%s\n' "$candidate"
}

test_dry_run_lists_without_deleting() {
  local root
  root="$(mktemp -d "${TMPDIR:-/tmp}/teststrip-reset-test.XXXXXX")"
  local candidate
  candidate="$(make_isolated_root "$root" "teststrip-app-support.dryrun")"

  local output
  output="$(TESTSTRIP_ISOLATED_TEST_DATA_ROOT="$root" "$SCRIPT_DIR/reset_isolated_test_data.sh")"

  assert_contains "$output" "would_delete $candidate" "dry run output"
  assert_exists "$candidate" "dry run should not delete"
}

test_delete_removes_marked_isolated_root() {
  local root
  root="$(mktemp -d "${TMPDIR:-/tmp}/teststrip-reset-test.XXXXXX")"
  local candidate
  candidate="$(make_isolated_root "$root" "teststrip-app-support.delete")"

  TESTSTRIP_ISOLATED_TEST_DATA_ROOT="$root" "$SCRIPT_DIR/reset_isolated_test_data.sh" --delete >/dev/null

  assert_missing "$candidate" "delete should remove isolated support root"
}

test_delete_skips_unmarked_and_unmatched_directories() {
  local root
  root="$(mktemp -d "${TMPDIR:-/tmp}/teststrip-reset-test.XXXXXX")"
  local unmarked="$root/teststrip-app-support.unmarked"
  local unmatched="$root/other-app-support.fake"
  mkdir -p "$unmarked" "$unmatched/Teststrip/Previews"

  TESTSTRIP_ISOLATED_TEST_DATA_ROOT="$root" "$SCRIPT_DIR/reset_isolated_test_data.sh" --delete >/dev/null

  assert_exists "$unmarked" "delete should skip matching directory without Teststrip markers"
  assert_exists "$unmatched" "delete should skip non-matching directory"
}

test_delete_skips_running_isolated_root() {
  local root
  root="$(mktemp -d "${TMPDIR:-/tmp}/teststrip-reset-test.XXXXXX")"
  local candidate
  candidate="$(make_isolated_root "$root" "teststrip-app-support.running")"

  local output
  output="$(
    TESTSTRIP_ISOLATED_TEST_DATA_ROOT="$root" \
    TESTSTRIP_RUNNING_APP_SUPPORT_DIRECTORIES="$candidate" \
    "$SCRIPT_DIR/reset_isolated_test_data.sh" --delete
  )"

  assert_contains "$output" "skip_running $candidate" "running root output"
  assert_exists "$candidate" "delete should skip running support root"
}

test_dry_run_lists_without_deleting
test_delete_removes_marked_isolated_root
test_delete_skips_unmarked_and_unmatched_directories
test_delete_skips_running_isolated_root

echo "isolated test data reset tests passed"
