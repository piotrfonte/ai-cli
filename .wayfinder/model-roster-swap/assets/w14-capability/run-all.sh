#!/bin/bash
# Run the W14 suite against one or more models, restarting oMLX between them.
#
# The restart is not optional. oMLX lazy-loads whatever model a request names and
# keeps it resident, so running a second model without a restart puts two large
# models under one memory guard — the thrash the map documents. One model per
# server run, always.
#
# Port 10082, not 10081: a live opencode session elsewhere on this box runs
# opencode-mem, whose summarizer targets GLM on 10081. On 10082 it cannot reach
# this server, so it cannot load a second model mid-measurement.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRATCH="${W14_SCRATCH:-/private/tmp/claude-501/-Users-p-Development-ai-cli/36b70a77-d1ee-46fa-b432-d80eab0661ef/scratchpad/w14}"
PORT="${W14_PORT:-10082}"
OMLX="${OMLX_BIN:-$HOME/.omlx/venv/bin/omlx}"

mkdir -p "$SCRATCH"

start_server() {
  local tag=$1
  "$OMLX" serve \
    --model-dir "$HOME/.omlx/models" \
    --port "$PORT" \
    --paged-ssd-cache-dir "$HOME/.omlx/cache" \
    --paged-ssd-cache-max-size 25GB \
    --hot-cache-max-size 8GB \
    --memory-guard-gb 48 \
    --max-concurrent-requests 2 \
    --log-level info > "$SCRATCH/server-$tag.log" 2>&1 &
  echo $! > "$SCRATCH/server.pid"
  local i
  for i in $(seq 1 120); do
    if [ "$(curl -s -o /dev/null -w '%{http_code}' -m 2 "http://127.0.0.1:$PORT/v1/models" 2>/dev/null)" = "200" ]; then
      echo "  server up for $tag after ${i}s (pid $(cat "$SCRATCH/server.pid"))"
      return 0
    fi
    sleep 1
  done
  echo "  server FAILED to start for $tag"
  return 1
}

stop_server() {
  local pid
  pid=$(cat "$SCRATCH/server.pid" 2>/dev/null)
  [ -n "${pid:-}" ] && kill -TERM "$pid" 2>/dev/null
  # Wait for the port to actually free, so the next bind cannot race it.
  local i
  for i in $(seq 1 60); do
    lsof -ti "tcp:$PORT" -sTCP:LISTEN >/dev/null 2>&1 || { echo "  server down"; return 0; }
    sleep 1
  done
  pid=$(lsof -ti "tcp:$PORT" -sTCP:LISTEN 2>/dev/null | head -1)
  [ -n "${pid:-}" ] && kill -KILL "$pid" 2>/dev/null
  sleep 2
  echo "  server killed"
}

for spec in "$@"; do
  tag="${spec%%=*}"
  model="${spec#*=}"
  echo "=== $tag :: $model ==="
  df -h /System/Volumes/Data | tail -1
  stop_server
  start_server "$tag" || continue
  python3 "$HERE/run.py" --model "$model" --out "$HERE/results-$tag.json" 2>&1 \
    | tee "$SCRATCH/$tag-run.log"
  echo "=== $tag done ==="
done

stop_server
echo "ALL DONE"
