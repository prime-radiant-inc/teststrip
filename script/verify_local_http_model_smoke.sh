#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/local_http_model_smoke_verifier_metrics.sh"

MAX_SECONDS="${TESTSTRIP_LOCAL_HTTP_MODEL_SMOKE_MAX_SECONDS:-${1:-5}}"
MIN_SIGNALS="${TESTSTRIP_LOCAL_HTTP_MODEL_SMOKE_MIN_SIGNALS:-${2:-3}}"
EXPECTED_VISUAL_SIMILARITY_VECTOR="${TESTSTRIP_LOCAL_HTTP_MODEL_SMOKE_VISUAL_SIMILARITY_VECTOR:-${3:-1}}"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/teststrip-local-http-smoke.XXXXXX")"
PORT_FILE="$WORK_DIR/port"
SERVER_LOG="$WORK_DIR/server.log"
IMAGE_FILE="$WORK_DIR/stub.jpg"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

printf '\xff\xd8\xff\xd9' >"$IMAGE_FILE"

/usr/bin/python3 - "$PORT_FILE" >"$SERVER_LOG" 2>&1 <<'PY' &
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

port_file = Path(sys.argv[1])

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length))
            content = payload["messages"][0]["content"]
            image_url = content[1]["image_url"]["url"]
            if not image_url.startswith("data:"):
                self.send_error(422, "missing image data URL")
                return
        except Exception as exc:
            self.send_error(400, str(exc))
            return

        model_payload = {
            "signals": [
                {"kind": "aesthetics", "label": "keeper", "confidence": 0.91},
                {"kind": "framing", "label": "balanced composition", "confidence": 0.84},
                {"kind": "visualSimilarity", "vector": [0.12, 0.24, 0.48], "confidence": 1.0},
            ]
        }
        response = {
            "choices": [
                {"message": {"content": json.dumps(model_payload)}}
            ]
        }
        data = json.dumps(response).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format, *args):
        return

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
port_file.write_text(str(server.server_address[1]))
server.serve_forever()
PY
SERVER_PID="$!"

for _ in {1..50}; do
  if [[ -s "$PORT_FILE" ]]; then
    break
  fi
  if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    cat "$SERVER_LOG" >&2 || true
    echo "local HTTP smoke stub exited before publishing its port" >&2
    exit 1
  fi
  sleep 0.1
done

if [[ ! -s "$PORT_FILE" ]]; then
  cat "$SERVER_LOG" >&2 || true
  echo "local HTTP smoke stub did not publish a port" >&2
  exit 1
fi

PORT="$(cat "$PORT_FILE")"
ENDPOINT="http://127.0.0.1:$PORT/v1/chat/completions"

output="$(cd "$ROOT_DIR" && swift run TeststripBench local-http-smoke "$ENDPOINT" "teststrip-stub" "$IMAGE_FILE" "$MAX_SECONDS")"
printf '%s\n' "$output"

summary_payload="$(extract_benchmark_summary_payload "$output")"
assert_local_http_model_smoke_summary "$summary_payload" "$MIN_SIGNALS" "$EXPECTED_VISUAL_SIMILARITY_VECTOR" "$MAX_SECONDS"

emit_local_http_model_smoke_metric "min_signals" "$MIN_SIGNALS"
emit_local_http_model_smoke_metric "expected_visual_similarity_vector" "$EXPECTED_VISUAL_SIMILARITY_VECTOR"
emit_local_http_model_smoke_metric "max_seconds" "$MAX_SECONDS"

metric_keys=(
  signals
  vector_signals
  visual_similarity_vector
)

for key in "${metric_keys[@]}"; do
  value="$(benchmark_summary_number "$summary_payload" "metrics.$key")"
  emit_local_http_model_smoke_metric "$key" "$value"
done

local_http_model_smoke_seconds="$(benchmark_summary_number "$summary_payload" measurements.local_http_model_smoke)"
emit_local_http_model_smoke_metric "local_http_model_smoke_seconds" "$local_http_model_smoke_seconds"
