#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/process_resource_metrics.sh"

assert_equal() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  if [[ "$actual" != "$expected" ]]; then
    echo "$message: expected '$expected', got '$actual'" >&2
    exit 1
  fi
}

test_process_rss_kb_reports_current_process_memory() {
  local rss_kb
  rss_kb="$(process_rss_kb "$$")"
  if [[ ! "$rss_kb" =~ ^[0-9]+$ ]] || [[ "$rss_kb" -le 0 ]]; then
    echo "process_rss_kb should report positive numeric RSS for current process, got '$rss_kb'" >&2
    exit 1
  fi
}

test_process_resource_snapshot_emits_pid_cpu_and_rss() {
  local output
  output="$(process_resource_snapshot "app_workflow" "app" "$$")"

  assert_equal \
    "teststrip_app_workflow_resource app_pid=$$" \
    "$(printf '%s\n' "$output" | /usr/bin/awk 'NR == 1 { print }')" \
    "snapshot pid metric"

  if ! /usr/bin/awk '/^teststrip_app_workflow_resource app_cpu_percent=/{ found = 1 } END { exit found ? 0 : 1 }' <<< "$output"; then
    echo "snapshot should include app CPU metric" >&2
    exit 1
  fi

  if ! /usr/bin/awk '/^teststrip_app_workflow_resource app_rss_kb=/{ found = 1 } END { exit found ? 0 : 1 }' <<< "$output"; then
    echo "snapshot should include app RSS metric" >&2
    exit 1
  fi
}

test_process_resource_snapshot_handles_missing_pid() {
  local output
  output="$(process_resource_snapshot "app_workflow" "worker" "")"

  assert_equal \
    "teststrip_app_workflow_resource worker_pid=unknown" \
    "$(printf '%s\n' "$output" | /usr/bin/awk 'NR == 1 { print }')" \
    "missing pid metric"
  assert_equal \
    "teststrip_app_workflow_resource worker_cpu_percent=unknown" \
    "$(printf '%s\n' "$output" | /usr/bin/awk 'NR == 2 { print }')" \
    "missing CPU metric"
  assert_equal \
    "teststrip_app_workflow_resource worker_rss_kb=unknown" \
    "$(printf '%s\n' "$output" | /usr/bin/awk 'NR == 3 { print }')" \
    "missing RSS metric"
}

test_process_rss_kb_reports_unknown_for_missing_process() {
  assert_equal "unknown" "$(process_rss_kb "")" "empty pid RSS"
}

test_process_rss_kb_reports_current_process_memory
test_process_resource_snapshot_emits_pid_cpu_and_rss
test_process_resource_snapshot_handles_missing_pid
test_process_rss_kb_reports_unknown_for_missing_process

echo "process resource metric tests passed"
