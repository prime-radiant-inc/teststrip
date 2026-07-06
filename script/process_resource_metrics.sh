#!/usr/bin/env bash

process_cpu_percent() {
  local pid="$1"
  if [[ -z "$pid" ]]; then
    echo "unknown"
    return 1
  fi
  /bin/ps -p "$pid" -o %cpu= 2>/dev/null | /usr/bin/awk 'NF { print $1; found = 1 } END { if (!found) print "unknown" }'
}

process_rss_kb() {
  local pid="$1"
  if [[ -z "$pid" ]]; then
    echo "unknown"
    return 1
  fi
  /bin/ps -p "$pid" -o rss= 2>/dev/null | /usr/bin/awk 'NF { print $1; found = 1 } END { if (!found) print "unknown" }'
}

process_resource_snapshot() {
  local namespace="$1"
  local process_label="$2"
  local pid="${3:-}"
  local reported_pid="$pid"
  if [[ -z "$reported_pid" ]]; then
    reported_pid="unknown"
  fi

  printf 'teststrip_%s_resource %s_pid=%s\n' "$namespace" "$process_label" "$reported_pid"
  printf 'teststrip_%s_resource %s_cpu_percent=%s\n' "$namespace" "$process_label" "$(process_cpu_percent "$pid")"
  printf 'teststrip_%s_resource %s_rss_kb=%s\n' "$namespace" "$process_label" "$(process_rss_kb "$pid")"
}
