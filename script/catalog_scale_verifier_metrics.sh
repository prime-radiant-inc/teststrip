#!/usr/bin/env bash

extract_benchmark_summary_payload() {
  /usr/bin/awk -F '\t' '
    $1 == "benchmark-summary" {
      print $2
      found = 1
      exit
    }
    END {
      if (!found) exit 1
    }
  ' <<< "$1"
}

benchmark_summary_number() {
  local payload="$1"
  local path="$2"
  TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD="$payload" \
  TESTSTRIP_BENCHMARK_SUMMARY_PATH="$path" \
  /usr/bin/python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD"])
value = payload
for component in os.environ["TESTSTRIP_BENCHMARK_SUMMARY_PATH"].split("."):
    value = value[component]

if isinstance(value, bool) or not isinstance(value, (int, float)):
    print(f"{value!r} is not numeric", file=sys.stderr)
    sys.exit(1)
print(value)
PY
}

assert_benchmark_summary_number_at_most() {
  local payload="$1"
  local path="$2"
  local threshold="$3"
  TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD="$payload" \
  TESTSTRIP_BENCHMARK_SUMMARY_PATH="$path" \
  TESTSTRIP_BENCHMARK_SUMMARY_THRESHOLD="$threshold" \
  /usr/bin/python3 - <<'PY'
import json
import os
import sys

payload = json.loads(os.environ["TESTSTRIP_BENCHMARK_SUMMARY_PAYLOAD"])
path = os.environ["TESTSTRIP_BENCHMARK_SUMMARY_PATH"]
threshold = float(os.environ["TESTSTRIP_BENCHMARK_SUMMARY_THRESHOLD"])
value = payload
for component in path.split("."):
    value = value[component]

if isinstance(value, bool) or not isinstance(value, (int, float)):
    print(f"{path} is not numeric: {value!r}", file=sys.stderr)
    sys.exit(1)
if float(value) > threshold:
    print(f"{path}={value} exceeded threshold {threshold}", file=sys.stderr)
    sys.exit(1)
PY
}

emit_catalog_scale_metric() {
  local key="$1"
  local value="$2"
  printf 'teststrip_catalog_scale_metric %s=%s\n' "$key" "$value"
}

catalog_scale_default_max_seconds() {
  local count="$1"
  if [[ "$count" -ge 1000000 ]]; then
    printf '1.5\n'
  elif [[ "$count" -ge 500000 ]]; then
    printf '0.65\n'
  else
    printf '0.2\n'
  fi
}
