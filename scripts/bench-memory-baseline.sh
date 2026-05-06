#!/usr/bin/env zsh
# Copyright (c) 2026 Said Arturo Lopez. MIT License.

set -euo pipefail

APP_PATH="${APP_PATH:-build/CocxyTerminal.app}"
BUDGET_MB="${BUDGET_MB:-250}"
STABILIZE_SECONDS="${STABILIZE_SECONDS:-1.0}"
MEASURE_TIMEOUT_SECONDS="${MEASURE_TIMEOUT_SECONDS:-60}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-1.0}"
ENFORCE="${COCXY_ENFORCE_MEMORY_BASELINE:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP_PATH="$2"; shift 2 ;;
    --budget-mb) BUDGET_MB="$2"; shift 2 ;;
    --stabilize-seconds) STABILIZE_SECONDS="$2"; shift 2 ;;
    --measure-timeout-seconds) MEASURE_TIMEOUT_SECONDS="$2"; shift 2 ;;
    --poll-interval-seconds) POLL_INTERVAL_SECONDS="$2"; shift 2 ;;
    --enforce) ENFORCE="1"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 2
fi

CLI="$APP_PATH/Contents/Resources/cocxy"
if [[ ! -x "$CLI" ]]; then
  echo "CLI helper not found in bundle: $CLI" >&2
  exit 2
fi

quit_existing_app() {
  /usr/bin/osascript -e 'quit app "Cocxy Terminal"' >/dev/null 2>&1 &
  local quit_pid=$!
  local deadline=$((SECONDS + 2))
  while kill -0 "$quit_pid" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      kill "$quit_pid" >/dev/null 2>&1 || true
      break
    fi
    sleep 0.05
  done
  wait "$quit_pid" >/dev/null 2>&1 || true

  local shutdown_deadline=$((SECONDS + 2))
  while pgrep -x CocxyTerminal >/dev/null 2>&1; do
    if (( SECONDS >= shutdown_deadline )); then
      pkill -x CocxyTerminal >/dev/null 2>&1 || true
      break
    fi
    sleep 0.05
  done
}

quit_existing_app
/usr/bin/open -n "$APP_PATH"

deadline=$((SECONDS + 10))
until "$CLI" status >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for Cocxy status" >&2
    exit 1
  fi
  sleep 0.05
done

pid="$(pgrep -x CocxyTerminal | head -n 1 || true)"
if [[ -z "$pid" ]]; then
  echo "CocxyTerminal process not found after launch" >&2
  exit 1
fi

read_memory_snapshot() {
  local target_pid="$1"
  local rss_kb footprint_raw

  rss_kb="$(ps -o rss= -p "$target_pid" | tr -d '[:space:]')"
  if [[ -z "$rss_kb" ]]; then
    echo "Unable to read RSS for CocxyTerminal pid $target_pid" >&2
    return 1
  fi

  footprint_raw="$(vmmap -summary "$target_pid" | awk '/Physical footprint:/ { print $3; exit }')"
  if [[ -z "$footprint_raw" ]]; then
    echo "Unable to read physical footprint for CocxyTerminal pid $target_pid" >&2
    return 1
  fi

  awk -v rss_kb="$rss_kb" -v raw="$footprint_raw" '
    BEGIN {
      value = raw
      unit = substr(value, length(value), 1)
      sub(/[KMG]$/, "", value)
      if (unit == "G") {
        value *= 1024
      } else if (unit == "K") {
        value /= 1024
      }
      printf "%.2f %.2f", rss_kb / 1024, value
    }
  '
}

sleep "$STABILIZE_SECONDS"

started_at="$SECONDS"
deadline="$(awk -v now="$SECONDS" -v timeout="$MEASURE_TIMEOUT_SECONDS" 'BEGIN { printf "%d", now + timeout }')"
rss_mb="0"
footprint_mb="0"
best_footprint_mb=""
samples=0
within="0"

while (( SECONDS <= deadline )); do
  snapshot="$(read_memory_snapshot "$pid")"
  rss_mb="${snapshot%% *}"
  footprint_mb="${snapshot##* }"
  samples=$((samples + 1))

  if [[ -z "$best_footprint_mb" ]] || awk "BEGIN { exit !($footprint_mb < $best_footprint_mb) }"; then
    best_footprint_mb="$footprint_mb"
  fi

  within="$(awk "BEGIN { print ($footprint_mb <= $BUDGET_MB) ? 1 : 0 }")"
  if [[ "$within" == "1" ]]; then
    break
  fi

  sleep "$POLL_INTERVAL_SECONDS"
done

elapsed_seconds="$(awk -v now="$SECONDS" -v start="$started_at" 'BEGIN { printf "%.0f", now - start }')"

printf '{\n'
printf '  "app": "%s",\n' "$APP_PATH"
printf '  "benchmark_kind": "memory-baseline",\n'
printf '  "pid": %s,\n' "$pid"
printf '  "warmup_seconds": %s,\n' "$STABILIZE_SECONDS"
printf '  "measure_timeout_seconds": %s,\n' "$MEASURE_TIMEOUT_SECONDS"
printf '  "elapsed_measure_seconds": %s,\n' "$elapsed_seconds"
printf '  "samples": %s,\n' "$samples"
printf '  "rss_mb": %s,\n' "$rss_mb"
printf '  "physical_footprint_mb": %s,\n' "$footprint_mb"
printf '  "best_physical_footprint_mb": %s,\n' "$best_footprint_mb"
printf '  "budget_mb": %s,\n' "$BUDGET_MB"
printf '  "within_budget": %s\n' "$([[ "$within" == "1" ]] && echo true || echo false)"
printf '}\n'

if [[ "$ENFORCE" == "1" && "$within" != "1" ]]; then
  exit 1
fi
