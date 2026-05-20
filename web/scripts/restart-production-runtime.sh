#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${COCXY_WEB_APP_NAME:-cocxy-web}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/server.js" ]; then
  APP_DIR="$SCRIPT_DIR"
else
  APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
PORT="${PORT:-3000}"
PID_FILE="${COCXY_WEB_PID_FILE:-.cocxy-web.pid}"
LOG_FILE="${COCXY_WEB_LOG_FILE:-cocxy-web.log}"
ERROR_LOG_FILE="${COCXY_WEB_ERROR_LOG_FILE:-cocxy-web.err.log}"

cd "$APP_DIR"

resolve_pm2() {
  if command -v pm2 >/dev/null 2>&1; then
    command -v pm2
    return 0
  fi

  for candidate in \
    ./node_modules/.bin/pm2 \
    "$HOME/.npm-global/bin/pm2" \
    "$HOME/.npm/bin/pm2" \
    "$HOME/.local/bin/pm2" \
    /usr/local/bin/pm2 \
    /opt/homebrew/bin/pm2 \
    /usr/bin/pm2
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  for candidate in "$HOME"/.nvm/versions/node/*/bin/pm2; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

stop_pid() {
  local pid="$1"
  if ! kill -0 "$pid" >/dev/null 2>&1; then
    return 0
  fi

  kill "$pid" >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  kill -KILL "$pid" >/dev/null 2>&1 || true
}

matching_node_server_pids() {
  if ! command -v ps >/dev/null 2>&1; then
    return 0
  fi

  ps -eo pid=,args= | awk '/[n]ode .*server\.js/ {print $1}' | while read -r pid; do
    [ -n "$pid" ] || continue
    [ "$pid" != "$$" ] || continue
    if [ -d "/proc/$pid" ]; then
      cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null || true)"
      if [ "$cwd" = "$APP_DIR" ]; then
        printf '%s\n' "$pid"
      fi
    fi
  done
}

matching_port_pids() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true
  elif command -v fuser >/dev/null 2>&1; then
    fuser "${PORT}/tcp" 2>/dev/null || true
  fi | while read -r pid; do
    [ -n "$pid" ] || continue
    [ "$pid" != "$$" ] || continue
    if [ -d "/proc/$pid" ]; then
      cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null || true)"
      if [ "$cwd" = "$APP_DIR" ]; then
        printf '%s\n' "$pid"
      fi
    fi
  done
}

local_health_is_ready() {
  if ! command -v curl >/dev/null 2>&1; then
    return 0
  fi

  curl -fsS "http://127.0.0.1:${PORT}/health" >/dev/null
}

wait_for_health() {
  if ! command -v curl >/dev/null 2>&1; then
    return 0
  fi

  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if local_health_is_ready; then
      return 0
    fi
    sleep 1
  done

  echo "cocxy-web did not pass local health check on port ${PORT}" >&2
  tail -80 "$ERROR_LOG_FILE" >&2 2>/dev/null || true
  tail -80 "$LOG_FILE" >&2 2>/dev/null || true
  return 1
}

PM2_BIN="$(resolve_pm2 || true)"
if [ -n "$PM2_BIN" ]; then
  if "$PM2_BIN" describe "$APP_NAME" >/dev/null 2>&1; then
    "$PM2_BIN" reload "$APP_NAME" --update-env
  else
    "$PM2_BIN" start ecosystem.config.js --only "$APP_NAME"
  fi
  "$PM2_BIN" save
  wait_for_health
  exit 0
fi

NODE_BIN="$(command -v node || true)"
if [ -z "$NODE_BIN" ]; then
  echo "node not found in deploy environment and pm2 is unavailable" >&2
  exit 127
fi

if [ -f "$PID_FILE" ]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -n "$old_pid" ]; then
    stop_pid "$old_pid"
  fi
  rm -f "$PID_FILE"
fi

for pid in $(matching_node_server_pids); do
  stop_pid "$pid"
done

for pid in $(matching_port_pids); do
  stop_pid "$pid"
done

if local_health_is_ready; then
  echo "Existing cocxy-web runtime is healthy on port ${PORT}; leaving it in place."
  exit 0
fi

umask 077
if command -v setsid >/dev/null 2>&1; then
  nohup setsid env NODE_ENV=production PORT="$PORT" "$NODE_BIN" server.js \
    >>"$LOG_FILE" 2>>"$ERROR_LOG_FILE" < /dev/null &
else
  nohup env NODE_ENV=production PORT="$PORT" "$NODE_BIN" server.js \
    >>"$LOG_FILE" 2>>"$ERROR_LOG_FILE" < /dev/null &
fi
new_pid="$!"
printf '%s\n' "$new_pid" > "$PID_FILE"

sleep 1
if ! kill -0 "$new_pid" >/dev/null 2>&1; then
  echo "cocxy-web failed to stay running after fallback start" >&2
  tail -80 "$ERROR_LOG_FILE" >&2 2>/dev/null || true
  tail -80 "$LOG_FILE" >&2 2>/dev/null || true
  exit 1
fi

wait_for_health
