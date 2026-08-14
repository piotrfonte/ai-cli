#!/bin/bash
# W21 Stage 2 — the trimmed W14 suite (T1, T2, T4) with ~17k tokens of repository
# source in the system prompt. Same server conditions as W14 and as Stage 1.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRATCH="${W21_SCRATCH:-/private/tmp/claude-501/-Users-p-Development-ai-cli/acea0ec4-aa67-47a9-83cc-4f312579437d/scratchpad/w21}"
PORT="${W21_PORT:-10082}"
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
    --log-level info > "$SCRATCH/server-long-$tag.log" 2>&1 &
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
  python3 "$HERE/run_long.py" --model "$model" --out "results-long-$tag.json" \
    --base "http://127.0.0.1:$PORT/v1" --scratch "$SCRATCH" 2>&1 \
    | tee "$SCRATCH/$tag-long.log"
  echo "=== $tag done ==="
done

stop_server
echo "ALL DONE"
