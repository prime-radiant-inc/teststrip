#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/import_verifier_metrics.sh"

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

test_extract_worker_catalog_path() {
  local listing="12345 /Users/jesse/git/projects/teststrip/dist/Teststrip.app/Contents/Helpers/TeststripWorker --catalog /tmp/teststrip-app-support.abc/Teststrip/catalog.sqlite --preview-cache /tmp/teststrip-app-support.abc/Teststrip/Previews"

  assert_equal \
    "/tmp/teststrip-app-support.abc/Teststrip/catalog.sqlite" \
    "$(extract_worker_catalog_path "$listing")" \
    "worker catalog path"
}

test_select_worker_listing_for_catalog_path() {
  local listings
  listings=$'111 /other/TeststripWorker --catalog /tmp/other.sqlite --preview-cache /tmp/other-previews\n222 /Users/jesse/git/projects/teststrip/dist/Teststrip.app/Contents/Helpers/TeststripWorker --catalog /tmp/teststrip-app-support.abc/Teststrip/catalog.sqlite --preview-cache /tmp/teststrip-app-support.abc/Teststrip/Previews'

  assert_equal \
    "222 /Users/jesse/git/projects/teststrip/dist/Teststrip.app/Contents/Helpers/TeststripWorker --catalog /tmp/teststrip-app-support.abc/Teststrip/catalog.sqlite --preview-cache /tmp/teststrip-app-support.abc/Teststrip/Previews" \
    "$(select_worker_listing_for_catalog_path "/tmp/teststrip-app-support.abc/Teststrip/catalog.sqlite" "$listings")" \
    "worker listing by catalog path"
}

test_select_latest_helper_worker_listing() {
  local listings
  listings=$'111 /tmp/TeststripWorker --catalog /tmp/other.sqlite --preview-cache /tmp/other-previews\n222 /Users/jesse/git/projects/teststrip/dist/Teststrip.app/Contents/Helpers/TeststripWorker --catalog /tmp/first.sqlite --preview-cache /tmp/first-previews\n333 /Users/jesse/git/projects/teststrip/dist/Teststrip.app/Contents/Helpers/TeststripWorker --catalog /tmp/latest.sqlite --preview-cache /tmp/latest-previews'

  assert_equal \
    "333 /Users/jesse/git/projects/teststrip/dist/Teststrip.app/Contents/Helpers/TeststripWorker --catalog /tmp/latest.sqlite --preview-cache /tmp/latest-previews" \
    "$(select_latest_helper_worker_listing "$listings")" \
    "latest helper worker listing"
}

test_elapsed_seconds_from_ms() {
  assert_equal "1.234" "$(elapsed_seconds_from_ms 1000 2234)" "elapsed seconds"
}

test_metric_now_ms_uses_wall_time() {
  local now_ms
  now_ms="$(metric_now_ms)"
  if [[ "$now_ms" -lt 1000000000000 ]]; then
    echo "metric_now_ms should use wall-clock milliseconds, got '$now_ms'" >&2
    exit 1
  fi
}

test_extract_app_support_directory() {
  local command="/Applications/Teststrip.app/Contents/MacOS/Teststrip TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=/tmp/teststrip-app-support.xyz LANG=C.UTF-8"

  assert_equal \
    "/tmp/teststrip-app-support.xyz" \
    "$(extract_app_support_directory "$command")" \
    "app support directory"
}

test_catalog_path_for_app_support_directory() {
  assert_equal \
    "/tmp/teststrip-app-support.xyz/Teststrip/catalog.sqlite" \
    "$(catalog_path_for_app_support_directory "/tmp/teststrip-app-support.xyz")" \
    "catalog path for app support directory"
}

test_preview_pending_count() {
  local root
  root="$(mktemp -d /tmp/teststrip-import-metrics.XXXXXX)"
  local catalog="$root/catalog.sqlite"
  /usr/bin/sqlite3 "$catalog" "create table preview_generation_queue (asset_id text not null); insert into preview_generation_queue values ('one'), ('two');"

  assert_equal "2" "$(preview_pending_count "$catalog")" "pending preview count"
}

test_wait_until_preview_drained_returns_when_empty() {
  local root
  root="$(mktemp -d /tmp/teststrip-import-metrics.XXXXXX)"
  local catalog="$root/catalog.sqlite"
  /usr/bin/sqlite3 "$catalog" "create table preview_generation_queue (asset_id text not null);"

  wait_until_preview_drained "$catalog" 1 0.05
}

test_active_import_count() {
  local root
  root="$(mktemp -d /tmp/teststrip-import-metrics.XXXXXX)"
  local catalog="$root/catalog.sqlite"
  /usr/bin/sqlite3 "$catalog" "
    create table work_sessions (kind text not null, status text not null);
    insert into work_sessions values ('ingest', 'running');
    insert into work_sessions values ('ingest', 'queued');
    insert into work_sessions values ('ingest', 'completed');
    insert into work_sessions values ('previewGeneration', 'running');
  "

  assert_equal "2" "$(active_import_count "$catalog")" "active import count"
}

test_extract_worker_catalog_path
test_select_worker_listing_for_catalog_path
test_select_latest_helper_worker_listing
test_elapsed_seconds_from_ms
test_metric_now_ms_uses_wall_time
test_extract_app_support_directory
test_catalog_path_for_app_support_directory
test_preview_pending_count
test_wait_until_preview_drained_returns_when_empty
test_active_import_count

echo "import verifier metric tests passed"
