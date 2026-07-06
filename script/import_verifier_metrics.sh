#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/process_resource_metrics.sh"

metric_now_ms() {
  /usr/bin/python3 -c 'import time; print(int(time.time() * 1000))'
}

elapsed_seconds_from_ms() {
  local start_ms="$1"
  local end_ms="$2"
  /usr/bin/python3 - "$start_ms" "$end_ms" <<'PY'
import sys
start_ms = int(sys.argv[1])
end_ms = int(sys.argv[2])
print(f"{(end_ms - start_ms) / 1000:.3f}")
PY
}

emit_import_metric() {
  local key="$1"
  local value="$2"
  printf 'teststrip_import_metric %s=%s\n' "$key" "$value"
}

extract_worker_catalog_path() {
  /usr/bin/awk '
    {
      for (i = 1; i <= NF; i += 1) {
        if ($i == "--catalog" && (i + 1) <= NF) {
          print $(i + 1)
          exit
        }
      }
    }
  ' <<< "$1"
}

select_worker_listing_for_catalog_path() {
  local catalog_path="$1"
  local listings="$2"
  while IFS= read -r listing; do
    if [[ "$(extract_worker_catalog_path "$listing")" == "$catalog_path" ]]; then
      printf '%s\n' "$listing"
      return 0
    fi
  done <<< "$listings"
}

select_latest_helper_worker_listing() {
  local listings="$1"
  /usr/bin/awk '/Contents\/Helpers\/TeststripWorker/ { latest = $0 } END { if (latest != "") print latest }' <<< "$listings"
}

extract_app_support_directory() {
  /usr/bin/awk '
    {
      for (i = 1; i <= NF; i += 1) {
        prefix = "TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY="
        if (index($i, prefix) == 1) {
          print substr($i, length(prefix) + 1)
          exit
        }
      }
    }
  ' <<< "$1"
}

catalog_path_for_app_support_directory() {
  local application_support_directory="$1"
  printf '%s/Teststrip/catalog.sqlite\n' "${application_support_directory%/}"
}

preview_pending_count() {
  local catalog_path="$1"
  if [[ -z "$catalog_path" || ! -f "$catalog_path" ]]; then
    echo "unknown"
    return 1
  fi
  /usr/bin/sqlite3 "$catalog_path" "select count(*) from preview_generation_queue;" 2>/dev/null || {
    echo "unknown"
    return 1
  }
}

active_import_count() {
  local catalog_path="$1"
  if [[ -z "$catalog_path" || ! -f "$catalog_path" ]]; then
    echo "unknown"
    return 1
  fi
  /usr/bin/sqlite3 "$catalog_path" "select count(*) from work_sessions where kind = 'ingest' and status in ('queued', 'running', 'paused');" 2>/dev/null || {
    echo "unknown"
    return 1
  }
}

wait_until_preview_drained() {
  local catalog_path="$1"
  local timeout_seconds="$2"
  local poll_seconds="$3"
  local deadline=$((SECONDS + timeout_seconds))

  while [[ "$SECONDS" -le "$deadline" ]]; do
    if [[ "$(preview_pending_count "$catalog_path")" == "0" ]]; then
      return 0
    fi
    sleep "$poll_seconds"
  done
  return 1
}

wait_until_import_finished() {
  local catalog_path="$1"
  local timeout_seconds="$2"
  local poll_seconds="$3"
  local deadline=$((SECONDS + timeout_seconds))

  while [[ "$SECONDS" -le "$deadline" ]]; do
    if [[ "$(active_import_count "$catalog_path")" == "0" ]]; then
      return 0
    fi
    sleep "$poll_seconds"
  done
  return 1
}
