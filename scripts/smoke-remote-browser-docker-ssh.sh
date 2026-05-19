#!/usr/bin/env bash
set -euo pipefail

# Docker SSH Remote Browser smoke.
#
# This is the reproducible Docker fixture for Remote Browser routing. It builds
# a local container that exposes only SSH to the host, serves a dev page on the
# container's loopback, then verifies Cocxy can reach that remote localhost only
# after an SSH -L forward exists. It is intentionally manual and skipped when
# Docker is not available. Use --matrix-manifest to print the required scenario
# matrix without requiring Docker.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${COCXY_REMOTE_BROWSER_APP:-${PROJECT_ROOT}/build/CocxyTerminal.app}"
CLI="${APP}/Contents/Resources/cocxy"
ARTIFACT_ROOT="${COCXY_REMOTE_BROWSER_DOCKER_ARTIFACTS:-${PROJECT_ROOT}/build/remote-browser-docker-ssh/$(date +%Y%m%d-%H%M%S)}"
BASE_IMAGE="${COCXY_REMOTE_BROWSER_DOCKER_BASE_IMAGE:-alpine:3.20}"
INSTALL_PACKAGES="${COCXY_REMOTE_BROWSER_DOCKER_INSTALL_PACKAGES:-1}"
IMAGE_TAG="cocxy-remote-browser-fixture:$(date +%Y%m%d%H%M%S)-$$"
CONTAINER_NAME="cocxy-remote-browser-fixture-$$"
ROOT=""

print_matrix_manifest() {
  printf 'scenario\tstatus\tproof\n'
  printf 'pre-forward-unreachable\timplemented\tcurl verifies container localhost is not reachable before SSH forwarding\n'
  printf 'ssh-forward-reachable\timplemented\tssh -N -L exposes the remote loopback dev server only after forwarding\n'
  printf 'browser-navigate\timplemented\tbundle-local cocxy browser navigate opens the forwarded URL\n'
  printf 'js-asset-load\timplemented\tbrowser eval verifies window.__remoteBrowserAsset\n'
  printf 'image-asset-load\timplemented\tbrowser eval verifies remote asset naturalWidth\n'
  printf 'favicon-load\timplemented\tbrowser eval verifies remote favicon probe naturalWidth\n'
  printf 'screenshot\timplemented\tbrowser screenshot writes a non-empty PNG artifact\n'
  printf 'hmac-invalid-token\timplemented\tDocker fixture /hmac rejects signatures made with the wrong secret through the SSH forward\n'
  printf 'hmac-expired-token\timplemented\tDocker fixture /hmac rejects signed tokens older than the replay window through the SSH forward\n'
  printf 'hmac-replay-token\timplemented\tDocker fixture /hmac accepts a signed token once, then rejects reuse through the SSH forward\n'
  printf 'drag-drop-upload\timplemented\tbrowser upload reads a local fixture, attaches it to a remote file input, and verifies page-side change/drop state over the SSH route\n'
  printf 'proxy-fallback\timplemented\tSmoke forces a dead proxy route, then proves the SSH forward fallback still reaches the remote page\n'
  printf 'dev-server-auto-discovery\timplemented\tSSH discovery runs the remote port scanner command and records the detected dev server port before forwarding\n'
}

if [ "${1:-}" = "--matrix-manifest" ]; then
  print_matrix_manifest
  exit 0
fi

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    skip "required tool not found: ${tool}"
  fi
}

skip() {
  local reason="$1"
  mkdir -p "$ARTIFACT_ROOT"
  {
    echo "status=skipped"
    echo "reason=${reason}"
    echo "artifactRoot=${ARTIFACT_ROOT}"
  } | tee "$ARTIFACT_ROOT/summary.txt"
  exit 2
}

pick_port() {
  local port
  local attempts=0
  while [ "$attempts" -lt 100 ]; do
    port=$((24000 + (RANDOM % 25000)))
    if ! nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      echo "$port"
      return 0
    fi
    attempts=$((attempts + 1))
  done
  fail_with_output "could not find a free local port"
}

wait_for_port() {
  local port="$1"
  local label="$2"
  local attempt
  for attempt in $(seq 1 60); do
    if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "status=failed"
  echo "reason=${label} did not open on 127.0.0.1:${port}"
  echo "artifactRoot=${ARTIFACT_ROOT}"
  docker logs "$CONTAINER_NAME" 2>/dev/null || true
  exit 1
}

json_field() {
  local field="$1"
  local file="$2"
  sed -n "s/.*\"${field}\" : \"\\([^\"]*\\)\".*/\\1/p" "$file" | head -1 | sed 's#\\/#/#g'
}

hmac_query() {
  local timestamp="$1"
  local nonce="$2"
  local secret="$3"
  python3 - "$secret" "$timestamp" "$nonce" <<'PY'
import hashlib
import hmac
import sys
import urllib.parse

secret, timestamp, nonce = sys.argv[1:4]
payload = f"{timestamp}:{nonce}".encode("utf-8")
signature = hmac.new(secret.encode("utf-8"), payload, hashlib.sha256).hexdigest()
print(
    "ts="
    + urllib.parse.quote(timestamp)
    + "&nonce="
    + urllib.parse.quote(nonce)
    + "&sig="
    + signature
)
PY
}

fail_with_output() {
  local reason="$1"
  local file="${2:-}"
  mkdir -p "$ARTIFACT_ROOT"
  {
    echo "status=failed"
    echo "reason=${reason}"
    echo "artifactRoot=${ARTIFACT_ROOT}"
    if [ -n "$file" ] && [ -f "$file" ]; then
      echo "output=${file}"
    fi
  } | tee "$ARTIFACT_ROOT/summary.txt"
  if [ -n "$file" ] && [ -f "$file" ]; then
    sed -n '1,220p' "$file"
  fi
  docker logs "$CONTAINER_NAME" 2>/dev/null || true
  exit 1
}

assert_http_status() {
  local scenario="$1"
  local expected="$2"
  local url="$3"
  local output="$4"
  local status
  status="$(curl -sS -o "$output" -w "%{http_code}" "$url" || true)"
  if [ "$status" != "$expected" ]; then
    fail_with_output "${scenario} expected HTTP ${expected}, got ${status}" "$output"
  fi
}

assert_output_contains() {
  local scenario="$1"
  local expected="$2"
  local output="$3"
  if ! grep -q "$expected" "$output"; then
    fail_with_output "${scenario} response did not contain ${expected}" "$output"
  fi
}

cleanup() {
  set +e
  pkill -x CocxyTerminal >/dev/null 2>&1
  if [ -n "$ROOT" ] && [ -f "$ROOT/forward.pid" ]; then
    local forward_pid
    forward_pid="$(cat "$ROOT/forward.pid")"
    kill "$forward_pid" >/dev/null 2>&1
    wait "$forward_pid" 2>/dev/null
  fi
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
  docker image rm "$IMAGE_TAG" >/dev/null 2>&1
  [ -n "$ROOT" ] && rm -rf "$ROOT"
}
trap cleanup EXIT

require_tool docker
require_tool ssh
require_tool ssh-keygen
require_tool nc
require_tool curl
require_tool python3
require_tool open

if ! docker info >/dev/null 2>&1; then
  skip "docker daemon is not available"
fi
if [ ! -d "$APP" ]; then
  fail_with_output "app bundle not found: ${APP}"
fi
if [ ! -x "$CLI" ]; then
  fail_with_output "bundle-local CLI not executable: ${CLI}"
fi

mkdir -p "$ARTIFACT_ROOT"
ROOT="$(mktemp -d /tmp/cocxy-remote-browser-docker.XXXXXX)"
SSHD_PORT="$(pick_port)"
REMOTE_HTTP_PORT="$(pick_port)"
FORWARD_PORT="$(pick_port)"
HMAC_SECRET="cocxy-remote-browser-docker-smoke-secret"

ssh-keygen -q -t ed25519 -N '' -f "$ROOT/client_key"
mkdir -p "$ROOT/www"
cat "$ROOT/client_key.pub" > "$ROOT/authorized_keys"
chmod 600 "$ROOT/client_key" "$ROOT/authorized_keys"

cat > "$ROOT/www/index.html" <<'HTML'
<!doctype html>
<meta charset="utf-8">
<title>Remote Browser Docker Smoke</title>
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<script src="/asset.js"></script>
<main id="remote-browser-smoke" data-smoke="remote-browser-ok">
  remote-browser-ok
  <img id="remote-browser-asset" src="/asset.svg" alt="remote asset">
  <img id="remote-browser-favicon-probe" src="/favicon.svg" alt="remote favicon">
  <input id="remote-browser-upload" type="file">
</main>
<script>
  window.__remoteBrowserUpload = 'missing';
  const uploadInput = document.getElementById('remote-browser-upload');
  const recordUpload = (files) => {
    const file = files && files[0];
    window.__remoteBrowserUpload = file ? `${file.name}:${file.size}` : 'empty';
  };
  uploadInput.addEventListener('change', (event) => recordUpload(event.target.files));
  uploadInput.addEventListener('drop', (event) => {
    event.preventDefault();
    recordUpload(event.dataTransfer && event.dataTransfer.files);
  });
</script>
HTML
printf 'remote upload fixture\n' > "$ROOT/upload-fixture.txt"
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

cat > "$ROOT/server.py" <<'PY'
import functools
import hashlib
import hmac
import http.server
import os
import sys
import time
import urllib.parse


class CocxyRemoteBrowserHandler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/hmac":
            self.handle_hmac(parsed)
            return
        super().do_GET()

    def handle_hmac(self, parsed):
        params = urllib.parse.parse_qs(parsed.query, keep_blank_values=True)
        timestamp_text = self.one(params, "ts")
        nonce = self.one(params, "nonce")
        signature = self.one(params, "sig")
        if not timestamp_text or not nonce or not signature:
            self.respond_text(400, "malformed-token\n")
            return
        try:
            timestamp = int(timestamp_text)
        except ValueError:
            self.respond_text(400, "malformed-token\n")
            return

        now = int(time.time())
        if abs(now - timestamp) > 60:
            self.respond_text(401, "expired-token\n")
            return

        secret = os.environ["COCXY_HMAC_SECRET"].encode("utf-8")
        payload = f"{timestamp_text}:{nonce}".encode("utf-8")
        expected = hmac.new(secret, payload, hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected, signature):
            self.respond_text(403, "invalid-hmac\n")
            return

        replay_key = f"{timestamp_text}:{nonce}"
        if replay_key in self.server.seen_hmac_tokens:
            self.respond_text(409, "replay-token\n")
            return
        self.server.seen_hmac_tokens.add(replay_key)
        self.respond_text(200, "hmac-ok\n")

    @staticmethod
    def one(params, key):
        values = params.get(key) or []
        return values[0] if values else ""

    def respond_text(self, status, body):
        data = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)


class CocxyRemoteBrowserServer(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, handler):
        super().__init__(address, handler)
        self.seen_hmac_tokens = set()


def main():
    port = int(sys.argv[1])
    directory = sys.argv[2]
    handler = functools.partial(CocxyRemoteBrowserHandler, directory=directory)
    server = CocxyRemoteBrowserServer(("127.0.0.1", port), handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
PY

cat > "$ROOT/Dockerfile" <<'DOCKER'
ARG BASE_IMAGE=alpine:3.20
FROM ${BASE_IMAGE}
ARG INSTALL_PACKAGES=1
RUN if [ "$INSTALL_PACKAGES" = "1" ]; then \
      if command -v apk >/dev/null 2>&1; then \
        apk add --no-cache openssh python3 iproute2 net-tools; \
      elif command -v apt-get >/dev/null 2>&1; then \
        apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y openssh-server python3 iproute2 net-tools && rm -rf /var/lib/apt/lists/*; \
      else \
        echo "no supported package manager for smoke dependencies" >&2; exit 1; \
      fi; \
    fi \
    && if ! id cocxy >/dev/null 2>&1; then \
      if adduser --help 2>&1 | grep -q -- '-D'; then \
        adduser -D -s /bin/sh cocxy; \
      else \
        useradd -m -s /bin/sh cocxy; \
      fi; \
    fi \
    && passwd -d cocxy >/dev/null \
    && mkdir -p /home/cocxy/.ssh /run/sshd \
    && ssh-keygen -A
COPY authorized_keys /home/cocxy/.ssh/authorized_keys
COPY www /srv/www
COPY server.py /srv/server.py
RUN chown -R cocxy:cocxy /home/cocxy/.ssh /srv/www \
    && chmod 700 /home/cocxy/.ssh \
    && chmod 600 /home/cocxy/.ssh/authorized_keys
EXPOSE 2222
CMD sh -c 'python3 /srv/server.py "${REMOTE_HTTP_PORT:-39117}" /srv/www >/tmp/cocxy-http.log 2>&1 & exec /usr/sbin/sshd -D -e -p 2222 -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no -o PubkeyAuthentication=yes -o AllowTcpForwarding=yes -o PermitOpen=any'
DOCKER

docker build \
  --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
  --build-arg "INSTALL_PACKAGES=${INSTALL_PACKAGES}" \
  -t "$IMAGE_TAG" "$ROOT" > "$ARTIFACT_ROOT/docker-build.log" 2>&1 \
  || fail_with_output "docker fixture build failed" "$ARTIFACT_ROOT/docker-build.log"

docker run -d \
  --name "$CONTAINER_NAME" \
  -e "REMOTE_HTTP_PORT=${REMOTE_HTTP_PORT}" \
  -e "COCXY_HMAC_SECRET=${HMAC_SECRET}" \
  -p "127.0.0.1:${SSHD_PORT}:2222" \
  "$IMAGE_TAG" > "$ARTIFACT_ROOT/docker-run.log" 2>&1 \
  || fail_with_output "docker fixture did not start" "$ARTIFACT_ROOT/docker-run.log"

wait_for_port "$SSHD_PORT" "docker sshd"

if curl -fsS "http://127.0.0.1:${REMOTE_HTTP_PORT}/index.html" 2>/dev/null | grep -q "remote-browser-ok"; then
  fail_with_output "remote fixture was reachable without SSH forwarding"
fi

cat > "$ROOT/ssh_config" <<EOF
Host cocxy-remote-browser-docker
  HostName 127.0.0.1
  Port $SSHD_PORT
  User cocxy
  IdentityFile $ROOT/client_key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile $ROOT/known_hosts
  BatchMode yes
  LogLevel ERROR
EOF

DISCOVERY_COMMAND="ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null"
if ! ssh -F "$ROOT/ssh_config" cocxy-remote-browser-docker "$DISCOVERY_COMMAND" \
  > "$ARTIFACT_ROOT/dev-server-auto-discovery.txt" \
  2> "$ARTIFACT_ROOT/dev-server-auto-discovery.stderr"; then
  cat "$ARTIFACT_ROOT/dev-server-auto-discovery.stderr" >> "$ARTIFACT_ROOT/dev-server-auto-discovery.txt"
  fail_with_output "dev-server-auto-discovery remote scan failed" "$ARTIFACT_ROOT/dev-server-auto-discovery.txt"
fi
rm -f "$ARTIFACT_ROOT/dev-server-auto-discovery.stderr"
assert_output_contains \
  "dev-server-auto-discovery" \
  ":${REMOTE_HTTP_PORT}" \
  "$ARTIFACT_ROOT/dev-server-auto-discovery.txt"

ssh -F "$ROOT/ssh_config" -N -L "$FORWARD_PORT:127.0.0.1:$REMOTE_HTTP_PORT" cocxy-remote-browser-docker \
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
  fail_with_output "SSH local forward did not serve the Docker fixture" "$ARTIFACT_ROOT/forward.log"
fi

BROKEN_PROXY_PORT="$(pick_port)"
{
  echo "brokenProxyPort=${BROKEN_PROXY_PORT}"
  if curl --max-time 2 --proxy "http://127.0.0.1:${BROKEN_PROXY_PORT}" \
    -fsS "http://127.0.0.1:${FORWARD_PORT}/index.html"; then
    echo "primaryProxy=unexpected-success"
    exit 1
  else
    echo "primaryProxy=failed-as-expected"
  fi
  if curl -fsS "http://127.0.0.1:${FORWARD_PORT}/index.html" | grep -q "remote-browser-ok"; then
    echo "fallbackForward=ok"
  else
    echo "fallbackForward=failed"
    exit 1
  fi
} > "$ARTIFACT_ROOT/proxy-fallback.txt" 2>&1 || \
  fail_with_output "proxy-fallback did not recover through SSH forward" "$ARTIFACT_ROOT/proxy-fallback.txt"

CURRENT_TS="$(date +%s)"
INVALID_QUERY="$(hmac_query "$CURRENT_TS" "invalid-token" "wrong-${HMAC_SECRET}")"
assert_http_status \
  "hmac-invalid-token" \
  "403" \
  "http://127.0.0.1:${FORWARD_PORT}/hmac?${INVALID_QUERY}" \
  "$ARTIFACT_ROOT/hmac-invalid-token.txt"
assert_output_contains "hmac-invalid-token" "invalid-hmac" "$ARTIFACT_ROOT/hmac-invalid-token.txt"

EXPIRED_TS=$((CURRENT_TS - 120))
EXPIRED_QUERY="$(hmac_query "$EXPIRED_TS" "expired-token" "$HMAC_SECRET")"
assert_http_status \
  "hmac-expired-token" \
  "401" \
  "http://127.0.0.1:${FORWARD_PORT}/hmac?${EXPIRED_QUERY}" \
  "$ARTIFACT_ROOT/hmac-expired-token.txt"
assert_output_contains "hmac-expired-token" "expired-token" "$ARTIFACT_ROOT/hmac-expired-token.txt"

REPLAY_QUERY="$(hmac_query "$CURRENT_TS" "replay-token" "$HMAC_SECRET")"
assert_http_status \
  "hmac-replay-token-initial" \
  "200" \
  "http://127.0.0.1:${FORWARD_PORT}/hmac?${REPLAY_QUERY}" \
  "$ARTIFACT_ROOT/hmac-replay-token-initial.txt"
assert_output_contains "hmac-replay-token-initial" "hmac-ok" "$ARTIFACT_ROOT/hmac-replay-token-initial.txt"
assert_http_status \
  "hmac-replay-token" \
  "409" \
  "http://127.0.0.1:${FORWARD_PORT}/hmac?${REPLAY_QUERY}" \
  "$ARTIFACT_ROOT/hmac-replay-token.txt"
assert_output_contains "hmac-replay-token" "replay-token" "$ARTIFACT_ROOT/hmac-replay-token.txt"

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
].join('|');" > "$ARTIFACT_ROOT/eval.json"
result="$(json_field result "$ARTIFACT_ROOT/eval.json")"
if [ "$result" != "remote-browser-ok|asset-js-ok|image-ok|favicon-ok" ]; then
  fail_with_output "browser did not load Docker remote fixture assets and favicon" "$ARTIFACT_ROOT/eval.json"
fi

UPLOAD_BYTES="$(wc -c < "$ROOT/upload-fixture.txt" | tr -d ' ')"
"$CLI" browser upload id-remote-browser-upload "$ROOT/upload-fixture.txt" --timeout 2000 \
  > "$ARTIFACT_ROOT/drag-drop-upload.json"
upload_status="$(json_field status "$ARTIFACT_ROOT/drag-drop-upload.json")"
upload_file="$(json_field fileName "$ARTIFACT_ROOT/drag-drop-upload.json")"
upload_bytes="$(json_field bytes "$ARTIFACT_ROOT/drag-drop-upload.json")"
if [ "$upload_status" != "uploaded" ] || [ "$upload_file" != "upload-fixture.txt" ] || [ "$upload_bytes" != "$UPLOAD_BYTES" ]; then
  fail_with_output "browser upload did not report the expected file payload" "$ARTIFACT_ROOT/drag-drop-upload.json"
fi
"$CLI" browser eval "window.__remoteBrowserUpload || 'missing';" \
  > "$ARTIFACT_ROOT/drag-drop-upload.txt"
upload_result="$(json_field result "$ARTIFACT_ROOT/drag-drop-upload.txt")"
if [ "$upload_result" != "upload-fixture.txt:${UPLOAD_BYTES}" ]; then
  fail_with_output "remote browser page did not observe the uploaded file" "$ARTIFACT_ROOT/drag-drop-upload.txt"
fi

"$CLI" browser screenshot --output "$ARTIFACT_ROOT/remote-browser-docker.png" > "$ARTIFACT_ROOT/screenshot.json"
if [ ! -s "$ARTIFACT_ROOT/remote-browser-docker.png" ]; then
  fail_with_output "browser screenshot was not written" "$ARTIFACT_ROOT/screenshot.json"
fi

{
  echo "status=ok"
  echo "artifactRoot=${ARTIFACT_ROOT}"
  echo "sshPort=${SSHD_PORT}"
  echo "remoteHttpPort=${REMOTE_HTTP_PORT}"
  echo "forwardPort=${FORWARD_PORT}"
  echo "url=${REMOTE_URL}"
  echo "discovery=ok"
  echo "hmac=ok"
  echo "proxyFallback=ok"
  echo "dragDropUpload=ok"
  echo "screenshot=${ARTIFACT_ROOT}/remote-browser-docker.png"
} | tee "$ARTIFACT_ROOT/summary.txt"
