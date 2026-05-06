#!/bin/bash
# smoke-local-ssh.sh - Local OpenSSH smoke for Remote Workspace gates.
#
# Starts two temporary localhost sshd instances on high ports, then verifies:
#   1. direct key-based SSH
#   2. ProxyJump through a second sshd
#   3. local port forwarding to an HTTP server
#
# No external network, system service changes, or persistent keys are used.

set -euo pipefail

require_tool() {
    local tool="$1"
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "error: required tool not found: $tool" >&2
        exit 2
    fi
}

pick_port() {
    local port
    local attempts=0
    while [ "$attempts" -lt 100 ]; do
        port=$((22000 + (RANDOM % 20000)))
        if ! nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
            echo "$port"
            return 0
        fi
        attempts=$((attempts + 1))
    done
    echo "error: could not find a free local port" >&2
    exit 2
}

wait_for_port() {
    local port="$1"
    local label="$2"
    local log_file="$3"
    local i
    for i in 1 2 3 4 5; do
        if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    echo "error: $label did not open on 127.0.0.1:$port" >&2
    [ -f "$log_file" ] && cat "$log_file" >&2
    exit 1
}

require_tool ssh
require_tool ssh-keygen
require_tool sshd
require_tool nc
require_tool curl
require_tool python3

ROOT="$(mktemp -d /tmp/cocxy-ssh-smoke.XXXXXX)"
TARGET_PORT="$(pick_port)"
JUMP_PORT="$(pick_port)"
HTTP_PORT="$(pick_port)"
FORWARD_PORT="$(pick_port)"

cleanup() {
    set +e
    [ -f "$ROOT/forward.pid" ] && kill "$(cat "$ROOT/forward.pid")" 2>/dev/null
    [ -f "$ROOT/http.pid" ] && kill "$(cat "$ROOT/http.pid")" 2>/dev/null
    [ -f "$ROOT/sshd_target.pid" ] && kill "$(cat "$ROOT/sshd_target.pid")" 2>/dev/null
    [ -f "$ROOT/sshd_jump.pid" ] && kill "$(cat "$ROOT/sshd_jump.pid")" 2>/dev/null
    rm -rf "$ROOT"
}
trap cleanup EXIT

USER_NAME="$(id -un)"

ssh-keygen -q -t ed25519 -N '' -f "$ROOT/client_key"
ssh-keygen -q -t ed25519 -N '' -f "$ROOT/target_host_key"
ssh-keygen -q -t ed25519 -N '' -f "$ROOT/jump_host_key"
cat "$ROOT/client_key.pub" > "$ROOT/authorized_keys"
chmod 700 "$ROOT"
chmod 600 "$ROOT/client_key" "$ROOT/authorized_keys"

write_sshd_config() {
    local name="$1"
    local port="$2"
    local config="$ROOT/${name}_sshd_config"
    cat > "$config" <<EOF
Port $port
ListenAddress 127.0.0.1
HostKey $ROOT/${name}_host_key
PidFile $ROOT/sshd_${name}.pid
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
}

write_sshd_config target "$TARGET_PORT"
write_sshd_config jump "$JUMP_PORT"

/usr/sbin/sshd -f "$ROOT/target_sshd_config" -E "$ROOT/target.log"
/usr/sbin/sshd -f "$ROOT/jump_sshd_config" -E "$ROOT/jump.log"
wait_for_port "$TARGET_PORT" "target sshd" "$ROOT/target.log"
wait_for_port "$JUMP_PORT" "jump sshd" "$ROOT/jump.log"

cat > "$ROOT/ssh_config" <<EOF
Host cocxy-target
  HostName 127.0.0.1
  Port $TARGET_PORT
  User $USER_NAME
  IdentityFile $ROOT/client_key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile $ROOT/known_hosts
  BatchMode yes
  LogLevel ERROR
Host cocxy-jump
  HostName 127.0.0.1
  Port $JUMP_PORT
  User $USER_NAME
  IdentityFile $ROOT/client_key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile $ROOT/known_hosts
  BatchMode yes
  LogLevel ERROR
Host cocxy-through-jump
  HostName 127.0.0.1
  Port $TARGET_PORT
  User $USER_NAME
  IdentityFile $ROOT/client_key
  IdentitiesOnly yes
  StrictHostKeyChecking no
  UserKnownHostsFile $ROOT/known_hosts
  BatchMode yes
  LogLevel ERROR
  ProxyJump cocxy-jump
EOF

direct_result="$(ssh -F "$ROOT/ssh_config" cocxy-target 'printf direct-ok')"
if [ "$direct_result" != "direct-ok" ]; then
    echo "error: direct SSH smoke failed: $direct_result" >&2
    exit 1
fi
echo "direct-ok"

jump_result="$(ssh -F "$ROOT/ssh_config" cocxy-through-jump 'printf jump-ok')"
if [ "$jump_result" != "jump-ok" ]; then
    echo "error: ProxyJump smoke failed: $jump_result" >&2
    exit 1
fi
echo "jump-ok"

mkdir "$ROOT/www"
printf 'forward-ok' > "$ROOT/www/index.html"
(
    cd "$ROOT/www"
    python3 -m http.server "$HTTP_PORT" --bind 127.0.0.1 > "$ROOT/http.log" 2>&1 &
    echo $! > "$ROOT/http.pid"
)
wait_for_port "$HTTP_PORT" "HTTP fixture" "$ROOT/http.log"

ssh -F "$ROOT/ssh_config" -N -L "$FORWARD_PORT:127.0.0.1:$HTTP_PORT" cocxy-target \
    > "$ROOT/forward.log" 2>&1 &
echo $! > "$ROOT/forward.pid"

forward_result=""
for _ in 1 2 3 4 5; do
    forward_result="$(curl -fsS "http://127.0.0.1:$FORWARD_PORT" 2>/dev/null || true)"
    [ "$forward_result" = "forward-ok" ] && break
    sleep 1
done

if [ "$forward_result" != "forward-ok" ]; then
    echo "error: local port forwarding smoke failed: $forward_result" >&2
    cat "$ROOT/forward.log" >&2
    exit 1
fi
echo "forward-ok"

echo "Local SSH smoke passed"
