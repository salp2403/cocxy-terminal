#!/usr/bin/env bash
set -euo pipefail

# Manual local OpenSSH smoke for SSH-backed Cocxy Cells.
#
# Starts a temporary localhost sshd with a generated key, then verifies the
# real Cocxy app socket can create, exec, list, status, and destroy an SSH Cell.
# It does not touch system sshd config, external hosts, or persistent keys.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_CLI="${PROJECT_ROOT}/build/CocxyTerminal.app/Contents/Resources/cocxy"
DEBUG_CLI="${PROJECT_ROOT}/.build/debug/cocxy"
CLI="${COCXY_CELLS_CLI:-}"
SOCKET_PATH="${HOME}/.config/cocxy/cocxy.sock"
PROVIDER="${COCXY_CELLS_SSH_PROVIDER:-ssh}"
case "$PROVIDER" in
  ssh)
    DEFAULT_ARTIFACT_DIR="${PROJECT_ROOT}/build/cells-local-ssh"
    RESULT_MARKER="cells-ssh-ok"
    ;;
  self-hosted)
    DEFAULT_ARTIFACT_DIR="${PROJECT_ROOT}/build/cells-self-hosted-ssh"
    RESULT_MARKER="cells-self-hosted-ok"
    ;;
  *)
    echo "status=failed"
    echo "reason=unsupported COCXY_CELLS_SSH_PROVIDER: ${PROVIDER}"
    echo "supported=ssh,self-hosted"
    exit 2
    ;;
esac
ARTIFACT_ROOT="${COCXY_CELLS_SSH_ARTIFACTS:-${DEFAULT_ARTIFACT_DIR}/$(date +%Y%m%d-%H%M%S)}"
ROOT=""
SSHD_PORT=""
CELL_ID=""
PROFILE="cells-${PROVIDER}-smoke-$$"

write_summary() {
  local status="$1"
  local reason="${2:-}"
  mkdir -p "$ARTIFACT_ROOT"
  {
    echo "status=${status}"
    echo "artifactRoot=${ARTIFACT_ROOT}"
    echo "provider=${PROVIDER}"
    [ -n "$SSHD_PORT" ] && echo "sshPort=${SSHD_PORT}"
    [ -n "$PROFILE" ] && echo "cellProfile=${PROFILE}"
    [ -n "$reason" ] && echo "reason=${reason}"
    if [ "$status" = "ok" ]; then
      echo "result=${RESULT_MARKER}"
    fi
  } | tee "$ARTIFACT_ROOT/summary.txt"
}

skip() {
  write_summary "skipped" "$1"
  exit 2
}

require_tool() {
  local tool="$1"
  if ! command -v "$tool" >/dev/null 2>&1; then
    skip "required tool not found: ${tool}"
  fi
}

pick_port() {
  local port
  local attempts=0
  while [ "$attempts" -lt 100 ]; do
    port=$((25000 + (RANDOM % 24000)))
    if ! nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      echo "$port"
      return 0
    fi
    attempts=$((attempts + 1))
  done
  echo "status=failed"
  echo "reason=could not find a free local port"
  write_summary "failed" "could not find a free local port"
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
  write_summary "failed" "${label} did not open on 127.0.0.1:${port}"
  [ -f "$log_file" ] && sed -n '1,220p' "$log_file"
  exit 1
}

fail_with_output() {
  local reason="$1"
  local file="${2:-}"
  write_summary "failed" "${reason}"
  if [ -n "$file" ] && [ -f "$file" ]; then
    echo "output=${file}"
    sed -n '1,220p' "$file"
  fi
  exit 1
}

cleanup() {
  set +e
  if [ -n "$CELL_ID" ] && [ -x "$CLI" ]; then
    "$CLI" cell destroy "$CELL_ID" --force > "${ARTIFACT_ROOT}/cleanup-cell-destroy.out" 2> "${ARTIFACT_ROOT}/cleanup-cell-destroy.err"
  fi
  if [ -n "$ROOT" ] && [ -f "$ROOT/sshd.pid" ]; then
    local sshd_pid
    sshd_pid="$(cat "$ROOT/sshd.pid")"
    kill "$sshd_pid" >/dev/null 2>&1
    wait "$sshd_pid" 2>/dev/null
  fi
  [ -n "$ROOT" ] && rm -rf "$ROOT"
}
trap cleanup EXIT

require_tool ssh
require_tool ssh-keygen
require_tool nc
if [ ! -x /usr/sbin/sshd ]; then
  skip "/usr/sbin/sshd is not executable"
fi

if [ -z "$CLI" ]; then
  if [ -x "$BUNDLE_CLI" ]; then
    CLI="$BUNDLE_CLI"
  elif [ -x "$DEBUG_CLI" ]; then
    CLI="$DEBUG_CLI"
  else
    skip "no bundle-local or debug Cocxy CLI found"
  fi
elif [ ! -x "$CLI" ]; then
  skip "configured Cocxy CLI is not executable: ${CLI}"
fi

if [ ! -S "$SOCKET_PATH" ]; then
  skip "Cocxy app socket is missing: ${SOCKET_PATH}"
fi

mkdir -p "$ARTIFACT_ROOT"
if ! "$CLI" status > "${ARTIFACT_ROOT}/cocxy-status.out" 2> "${ARTIFACT_ROOT}/cocxy-status.err"; then
  skip "Cocxy app socket is not responding"
fi

ROOT="$(mktemp -d /tmp/cocxy-cells-ssh.XXXXXX)"
SSHD_PORT="$(pick_port)"
USER_NAME="$(id -un)"

ssh-keygen -q -t ed25519 -N '' -f "$ROOT/client_key"
ssh-keygen -q -t ed25519 -N '' -f "$ROOT/host_key"
cat "$ROOT/client_key.pub" > "$ROOT/authorized_keys"
chmod 700 "$ROOT"
chmod 600 "$ROOT/client_key" "$ROOT/authorized_keys"

cat > "$ROOT/sshd_config" <<EOF
Port $SSHD_PORT
ListenAddress 127.0.0.1
HostKey $ROOT/host_key
PidFile $ROOT/sshd.pid
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

/usr/sbin/sshd -f "$ROOT/sshd_config" -E "${ARTIFACT_ROOT}/sshd.log"
wait_for_port "$SSHD_PORT" "temporary sshd" "${ARTIFACT_ROOT}/sshd.log"

if ! "$CLI" cell create --provider "$PROVIDER" --profile "$PROFILE" --host 127.0.0.1 \
  --user "$USER_NAME" --port "$SSHD_PORT" --identity "$ROOT/client_key" \
  --known-hosts "$ROOT/known_hosts" --strict-host-key-checking no \
  > "${ARTIFACT_ROOT}/cell-create.out" 2> "${ARTIFACT_ROOT}/cell-create.err"; then
  fail_with_output "cell create failed" "${ARTIFACT_ROOT}/cell-create.err"
fi
CELL_ID="$(sed -n 's/^Cell created: //p' "${ARTIFACT_ROOT}/cell-create.out" | head -1)"
if [ -z "$CELL_ID" ]; then
  fail_with_output "cell create did not return a cell id" "${ARTIFACT_ROOT}/cell-create.out"
fi

if ! "$CLI" cell status "$CELL_ID" > "${ARTIFACT_ROOT}/cell-status.out" 2> "${ARTIFACT_ROOT}/cell-status.err"; then
  fail_with_output "cell status failed" "${ARTIFACT_ROOT}/cell-status.err"
fi
if ! grep -q '"status" : "running"' "${ARTIFACT_ROOT}/cell-status.out"; then
  fail_with_output "cell did not report running status" "${ARTIFACT_ROOT}/cell-status.out"
fi

if ! "$CLI" cell exec "$CELL_ID" -- printf "$RESULT_MARKER" \
  > "${ARTIFACT_ROOT}/cell-exec.out" 2> "${ARTIFACT_ROOT}/cell-exec.err"; then
  fail_with_output "cell exec failed" "${ARTIFACT_ROOT}/cell-exec.err"
fi
if ! grep -q "$RESULT_MARKER" "${ARTIFACT_ROOT}/cell-exec.out"; then
  fail_with_output "cell exec did not return expected output" "${ARTIFACT_ROOT}/cell-exec.out"
fi

if ! "$CLI" cell list > "${ARTIFACT_ROOT}/cell-list.out" 2> "${ARTIFACT_ROOT}/cell-list.err"; then
  fail_with_output "cell list failed" "${ARTIFACT_ROOT}/cell-list.err"
fi
if ! grep -q "$CELL_ID" "${ARTIFACT_ROOT}/cell-list.out"; then
  fail_with_output "cell list did not include created SSH cell" "${ARTIFACT_ROOT}/cell-list.out"
fi

if ! "$CLI" cell destroy "$CELL_ID" --force > "${ARTIFACT_ROOT}/cell-destroy.out" 2> "${ARTIFACT_ROOT}/cell-destroy.err"; then
  fail_with_output "cell destroy failed" "${ARTIFACT_ROOT}/cell-destroy.err"
fi
CELL_ID=""

write_summary "ok"
