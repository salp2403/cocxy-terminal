#!/usr/bin/env bash
set -euo pipefail

# Local OpenSSH smoke for Remote Browser routing.
#
# This is the no-Docker fallback for development machines. It starts a temporary
# localhost sshd, serves an HTTP fixture behind an SSH -L forward, opens the
# shipped Cocxy app, and verifies the bundle-local browser can load the page
# through that forwarded port. It does not touch system sshd config or external
# network services.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${COCXY_REMOTE_BROWSER_APP:-${PROJECT_ROOT}/build/CocxyTerminal.app}"
CLI="${APP}/Contents/Resources/cocxy"
ARTIFACT_ROOT="${COCXY_REMOTE_BROWSER_ARTIFACTS:-${PROJECT_ROOT}/build/remote-browser-local-ssh/$(date +%Y%m%d-%H%M%S)}"

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "status=skipped"
    echo "reason=required tool not found: ${tool}"
    exit 2
  fi
}

pick_port() {
  local port
  local attempts=0
  while [ "$attempts" -lt 100 ]; do
    port=$((23000 + (RANDOM % 25000)))
    if ! nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      echo "$port"
      return 0
    fi
    attempts=$((attempts + 1))
  done
  echo "status=failed"
  echo "reason=could not find a free local port"
  exit 1
}

wait_for_port() {
  local port="$1"
  local label="$2"
  local log_file="$3"
  local attempt
  for attempt in $(seq 1 30); do
    if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "status=failed"
  echo "reason=${label} did not open on 127.0.0.1:${port}"
  echo "artifactRoot=${ARTIFACT_ROOT}"
  [ -f "$log_file" ] && sed -n '1,200p' "$log_file"
  exit 1
}

json_field() {
  local field="$1"
  local file="$2"
  sed -n "s/.*\"${field}\" : \"\\([^\"]*\\)\".*/\\1/p" "$file" | head -1 | sed 's#\\/#/#g'
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

require_tool ssh
require_tool ssh-keygen
require_tool sshd
require_tool nc
require_tool curl
require_tool python3
require_tool open

if [ ! -d "$APP" ]; then
  fail_with_output "app bundle not found: ${APP}"
fi
if [ ! -x "$CLI" ]; then
  fail_with_output "bundle-local CLI not executable: ${CLI}"
fi

ROOT="$(mktemp -d /tmp/cocxy-remote-browser.XXXXXX)"
SSHD_PORT="$(pick_port)"
HTTP_PORT="$(pick_port)"
FORWARD_PORT="$(pick_port)"
SERVER_PID=""

cleanup() {
  set +e
  pkill -x CocxyTerminal >/dev/null 2>&1
  if [ -f "$ROOT/forward.pid" ]; then
    local forward_pid
    forward_pid="$(cat "$ROOT/forward.pid")"
    kill "$forward_pid" >/dev/null 2>&1
    wait "$forward_pid" 2>/dev/null
  fi
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" >/dev/null 2>&1
    wait "$SERVER_PID" 2>/dev/null
  fi
  if [ -f "$ROOT/sshd_target.pid" ]; then
    local sshd_pid
    sshd_pid="$(cat "$ROOT/sshd_target.pid")"
    kill "$sshd_pid" >/dev/null 2>&1
    wait "$sshd_pid" 2>/dev/null
  fi
  rm -rf "$ROOT"
}
trap cleanup EXIT

mkdir -p "$ARTIFACT_ROOT" "$ROOT/www"
USER_NAME="$(id -un)"

ssh-keygen -q -t ed25519 -N '' -f "$ROOT/client_key"
ssh-keygen -q -t ed25519 -N '' -f "$ROOT/target_host_key"
cat "$ROOT/client_key.pub" > "$ROOT/authorized_keys"
chmod 700 "$ROOT"
chmod 600 "$ROOT/client_key" "$ROOT/authorized_keys"

cat > "$ROOT/target_sshd_config" <<EOF
Port $SSHD_PORT
ListenAddress 127.0.0.1
HostKey $ROOT/target_host_key
PidFile $ROOT/sshd_target.pid
AuthorizedKeysFile $ROOT/authorized_keys
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
UsePAM no
StrictModes no
AllowUsers $USER_NAME
Subsystem sftp internal-sftp
LogLevel ERROR
EOF

/usr/sbin/sshd -f "$ROOT/target_sshd_config" -E "$ROOT/target.log"
wait_for_port "$SSHD_PORT" "target sshd" "$ROOT/target.log"

cat > "$ROOT/ssh_config" <<EOF
Host cocxy-remote-browser-target
  HostName 127.0.0.1
  Port $SSHD_PORT
  User $USER_NAME
  IdentityFile $ROOT/client_key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile $ROOT/known_hosts
  BatchMode yes
  LogLevel ERROR
EOF

cat > "$ROOT/www/index.html" <<'HTML'
<!doctype html>
<meta charset="utf-8">
<title>Remote Browser Smoke</title>
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<script src="/asset.js"></script>
<main id="remote-browser-smoke" data-smoke="remote-browser-ok">
  remote-browser-ok
  <img id="remote-browser-asset" src="/asset.svg" alt="remote asset">
  <img id="remote-browser-favicon-probe" src="/favicon.svg" alt="remote favicon">
</main>
HTML
cat > "$ROOT/www/asset.js" <<'JS'
window.__remoteBrowserAsset = 'asset-js-ok';
JS
cat > "$ROOT/www/asset.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16">
  <rect width="16" height="16" fill="#89b4fa"/>
</svg>
SVG
cat > "$ROOT/www/favicon.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16">
  <circle cx="8" cy="8" r="7" fill="#a6e3a1"/>
</svg>
SVG

python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 --directory "$ROOT/www" > "$ARTIFACT_ROOT/http.log" 2>&1 &
SERVER_PID="$!"
wait_for_port "$HTTP_PORT" "HTTP fixture" "$ARTIFACT_ROOT/http.log"

ssh -F "$ROOT/ssh_config" -N -L "$FORWARD_PORT:127.0.0.1:$HTTP_PORT" cocxy-remote-browser-target \
  > "$ARTIFACT_ROOT/forward.log" 2>&1 &
echo $! > "$ROOT/forward.pid"

forward_result=""
for _ in $(seq 1 30); do
  forward_result="$(curl -fsS "http://127.0.0.1:${FORWARD_PORT}/index.html" 2>/dev/null || true)"
  if printf '%s' "$forward_result" | grep -q "remote-browser-ok"; then
    break
  fi
  sleep 1
done
if ! printf '%s' "$forward_result" | grep -q "remote-browser-ok"; then
  fail_with_output "SSH local forward did not serve the fixture" "$ARTIFACT_ROOT/forward.log"
fi
if ! curl -fsS "http://127.0.0.1:${FORWARD_PORT}/asset.js" | grep -q "asset-js-ok"; then
  fail_with_output "SSH local forward did not serve remote asset script" "$ARTIFACT_ROOT/forward.log"
fi
if ! curl -fsS "http://127.0.0.1:${FORWARD_PORT}/favicon.svg" | grep -q "#a6e3a1"; then
  fail_with_output "SSH local forward did not serve remote favicon asset" "$ARTIFACT_ROOT/forward.log"
fi

pkill -x CocxyTerminal >/dev/null 2>&1 || true
open -n "$APP"
for attempt in $(seq 1 30); do
  if "$CLI" status >/dev/null 2>&1; then
    break
  fi
  sleep 1
  if [ "$attempt" = "30" ]; then
    fail_with_output "app did not respond to bundle-local CLI status"
  fi
done

REMOTE_URL="http://127.0.0.1:${FORWARD_PORT}/index.html"
"$CLI" browser navigate "$REMOTE_URL" > "$ARTIFACT_ROOT/navigate.json"
sleep 1
"$CLI" browser eval "[
  document.querySelector('[data-smoke]')?.dataset.smoke || 'missing',
  window.__remoteBrowserAsset || 'asset-missing',
  document.getElementById('remote-browser-asset')?.naturalWidth > 0 ? 'image-ok' : 'image-missing',
  document.getElementById('remote-browser-favicon-probe')?.naturalWidth > 0 ? 'favicon-ok' : 'favicon-missing'
].join('|');" \
  > "$ARTIFACT_ROOT/eval.json"
result="$(json_field result "$ARTIFACT_ROOT/eval.json")"
if [ "$result" != "remote-browser-ok|asset-js-ok|image-ok|favicon-ok" ]; then
  fail_with_output "browser did not load forwarded remote fixture assets and favicon" "$ARTIFACT_ROOT/eval.json"
fi
if ! grep -q 'GET /asset.svg ' "$ARTIFACT_ROOT/http.log" || ! grep -q 'GET /favicon.svg ' "$ARTIFACT_ROOT/http.log"; then
  fail_with_output "browser did not request remote asset and favicon through forwarded port" "$ARTIFACT_ROOT/http.log"
fi

"$CLI" browser screenshot --output "$ARTIFACT_ROOT/remote-browser.png" > "$ARTIFACT_ROOT/screenshot.json"
if [ ! -s "$ARTIFACT_ROOT/remote-browser.png" ]; then
  fail_with_output "browser screenshot was not written" "$ARTIFACT_ROOT/screenshot.json"
fi

echo "status=ok"
echo "artifactRoot=${ARTIFACT_ROOT}"
echo "sshPort=${SSHD_PORT}"
echo "httpPort=${HTTP_PORT}"
echo "forwardPort=${FORWARD_PORT}"
echo "url=${REMOTE_URL}"
echo "screenshot=${ARTIFACT_ROOT}/remote-browser.png"
