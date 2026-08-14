#!/bin/bash
# W15: run the six measurements twice -- DFlash off, then DFlash on.
#
# The server restarts between runs and settings are written between restarts,
# because oMLX reads model_settings.json at MODEL LOAD, not per request.
#
# Port 10082, not 10081: a live opencode session on this box runs opencode-mem,
# whose summarizer would load a second model into this guard mid-measurement.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRATCH="${W15_SCRATCH:-/private/tmp/claude-501/-Users-p-Development-ai-cli/b9d15e93-8835-4386-b90a-a7d0102108ee/scratchpad/w15}"
PORT="${W15_PORT:-10082}"
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

rss_sampler() {
  # Process RSS every 2s while a run is in flight -- the peak is what the guard sees.
  local tag=$1
  while true; do
    local pid
    pid=$(lsof -ti "tcp:$PORT" -sTCP:LISTEN 2>/dev/null | head -1)
    [ -n "${pid:-}" ] && ps -o rss= -p "$pid" 2>/dev/null | awk -v t="$(date +%s)" '{print t, $1}' >> "$SCRATCH/rss-$tag.txt"
    sleep 2
  done
}

run_phase() {
  local tag=$1
  echo "=== phase $tag ==="
  du -sh "$HOME/.omlx/cache" | sed 's/^/  kv cache before: /'
  start_server "$tag" || return 1
  rss_sampler "$tag" & local sampler=$!
  python3 "$HERE/measure.py" "$tag" "$PORT" 2>&1 | tee "$SCRATCH/measure-$tag.log"
  kill "$sampler" 2>/dev/null
  echo "  peak RSS: $(sort -k2 -n "$SCRATCH/rss-$tag.txt" 2>/dev/null | tail -1 | awk '{printf "%.2f GB", $2/1048576}')"
  stop_server
  du -sh "$HOME/.omlx/cache" | sed 's/^/  kv cache after: /'
}

case "${1:-both}" in
  off)  python3 "$HERE/set-dflash.py" off && run_phase baseline ;;
  on)   python3 "$HERE/set-dflash.py" on  && run_phase dflash ;;
  both) python3 "$HERE/set-dflash.py" off && run_phase baseline
        python3 "$HERE/set-dflash.py" on  && run_phase dflash ;;
  *)    echo "usage: run-all.sh [off|on|both]"; exit 2 ;;
esac
