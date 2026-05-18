#!/usr/bin/env bash
set -euo pipefail

# Manual bundle-local CLI smoke.
#
# Launches the shipped app bundle, verifies the bundle-local `cocxy --version`
# and `cocxy status` paths, persists the evidence to build artifacts, and only
# terminates the app process it started. Kept out of CI because it opens a real
# macOS app runtime and uses the user's app socket path.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${COCXY_BUNDLE_CLI_APP:-${PROJECT_ROOT}/build/CocxyTerminal.app}"
APP_BIN="${APP}/Contents/MacOS/CocxyTerminal"
CLI="${COCXY_BUNDLE_CLI:-${APP}/Contents/Resources/cocxy}"
ARTIFACT_ROOT="${COCXY_BUNDLE_CLI_ARTIFACTS:-${PROJECT_ROOT}/build/bundle-local-cli/$(date +%Y%m%d-%H%M%S)}"
APP_PID=""

skip() {
  echo "status=skipped"
  echo "reason=$1"
  exit 2
}

fail_with_output() {
  local reason="$1"
  local file="${2:-}"
  echo "status=failed"
  echo "reason=${reason}"
  echo "artifactRoot=${ARTIFACT_ROOT}"
  if [ -n "$file" ] && [ -f "$file" ]; then
    echo "output=${file}"
    sed -n '1,220p' "$file"
  fi
  exit 1
}

cleanup() {
  set +e
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1
    wait "$APP_PID" 2>/dev/null
  fi
}
trap cleanup EXIT

if [ ! -d "$APP" ]; then
  skip "app bundle not found: ${APP}"
fi
if [ ! -x "$APP_BIN" ]; then
  skip "app executable is not executable: ${APP_BIN}"
fi
if [ ! -x "$CLI" ]; then
  skip "bundle-local Cocxy CLI is not executable: ${CLI}"
fi
if pgrep -x CocxyTerminal >/dev/null 2>&1; then
  skip "CocxyTerminal is already running; close it before this manual smoke"
fi

mkdir -p "$ARTIFACT_ROOT"

if ! "$CLI" --version > "${ARTIFACT_ROOT}/version.out" 2> "${ARTIFACT_ROOT}/version.err"; then
  fail_with_output "bundle-local cocxy --version failed" "${ARTIFACT_ROOT}/version.err"
fi

"$APP_BIN" > "${ARTIFACT_ROOT}/app.log" 2>&1 &
APP_PID="$!"

for attempt in $(seq 1 40); do
  if "$CLI" status > "${ARTIFACT_ROOT}/status.out" 2> "${ARTIFACT_ROOT}/status.err"; then
    {
      echo "status=ok"
      echo "artifactRoot=${ARTIFACT_ROOT}"
      echo "version=$(tr -d '\n' < "${ARTIFACT_ROOT}/version.out")"
      echo "statusCheck=ok"
      echo "appPid=${APP_PID}"
      echo "result=bundle-local-cli-ok"
    } | tee "${ARTIFACT_ROOT}/summary.txt"
    exit 0
  fi

  if ! kill -0 "$APP_PID" >/dev/null 2>&1; then
    fail_with_output "CocxyTerminal exited before status became ready" "${ARTIFACT_ROOT}/app.log"
  fi
  sleep 0.5
done

fail_with_output "bundle-local cocxy status did not become ready" "${ARTIFACT_ROOT}/status.err"
