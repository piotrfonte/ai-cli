#!/bin/bash
# W20 server lifecycle — same flags ai.sh uses, on port 10082.
#
# Port 10082, not 10081, for the reason W14 gives: a stray opencode elsewhere on
# this box runs opencode-mem, whose summarizer targets 10081. On 10082 it cannot
# reach this server and cannot load a second model mid-measurement.
#
# Unlike W14 this script does NOT restart between models for every mode. M3
# deliberately puts two models under one guard — that is the thing being
# measured. M1 and M2 restart, so each model is measured alone.
set -u

SCRATCH="${W20_SCRATCH:-/private/tmp/claude-501/-Users-p-Development-ai-cli/33b59783-fea4-449d-a1c3-52f65283aceb/scratchpad/w20}"
PORT="${W20_PORT:-10082}"
OMLX="${OMLX_BIN:-$HOME/.omlx/venv/bin/omlx}"

mkdir -p "$SCRATCH"

start_server() {
  local tag=${1:-run}
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

case "${1:-}" in
  start) start_server "${2:-run}" ;;
  stop)  stop_server ;;
  *)     echo "usage: server.sh start [tag] | stop" >&2; exit 2 ;;
esac
