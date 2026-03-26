#!/usr/bin/env bash
# RevenueCat REST API v2 wrapper
# Requires: RC_API_KEY environment variable

set -euo pipefail

if [[ -z "${RC_API_KEY:-}" ]]; then
  echo "Error: RC_API_KEY not set" >&2
  exit 1
fi

METHOD="GET"
DATA=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -m)
      METHOD="$2"
      shift 2
      ;;
    -d)
      DATA="$2"
      shift 2
      ;;
    -*)
      echo "Error: Unknown flag $1" >&2
      echo "Usage: rc-api.sh [-m METHOD] [-d DATA] <endpoint>" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "Usage: rc-api.sh [-m METHOD] [-d DATA] <endpoint>" >&2
  echo "Example: rc-api.sh /projects" >&2
  echo "Example: rc-api.sh -m POST -d '{\"key\":\"value\"}' /projects/{id}/offerings" >&2
  exit 1
fi

ENDPOINT="$1"

if [[ ! "$ENDPOINT" =~ ^/ ]]; then
  echo "Error: Endpoint must start with / (e.g. /projects)" >&2
  exit 1
fi

# Validate endpoint contains only safe characters
if [[ ! "$ENDPOINT" =~ ^/[a-zA-Z0-9/_.-]*$ ]]; then
  echo "Error: Endpoint contains invalid characters. Only alphanumeric, /, _, ., - allowed." >&2
  exit 1
fi

# Validate HTTP method
METHOD="$(printf '%s' "$METHOD" | tr '[:lower:]' '[:upper:]')"
case "$METHOD" in
  GET|POST|PUT|PATCH|DELETE) ;;
  *)
    echo "Error: Invalid method '$METHOD'. Allowed: GET, POST, PUT, PATCH, DELETE" >&2
    exit 1
    ;;
esac

BASE_URL="https://api.revenuecat.com/v2"

CURL_ARGS=(
  -s
  --max-time 30
  -X "$METHOD"
  -H "Authorization: Bearer ${RC_API_KEY}"
  -H "Content-Type: application/json"
)

if [[ -n "$DATA" ]]; then
  CURL_ARGS+=(-d "$DATA")
fi

TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

HTTP_CODE=$(curl -o "$TMPFILE" -w '%{http_code}' "${CURL_ARGS[@]}" "${BASE_URL}${ENDPOINT}") || {
  echo "Error: Request failed" >&2
  cat "$TMPFILE" >&2
  exit 1
}

if [[ "$HTTP_CODE" -ge 400 ]]; then
  echo "Error: HTTP $HTTP_CODE" >&2
  cat "$TMPFILE" >&2
  exit 1
fi

cat "$TMPFILE"
