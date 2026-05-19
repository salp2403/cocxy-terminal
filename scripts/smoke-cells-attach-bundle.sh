#!/usr/bin/env bash
set -euo pipefail

# Manual bundle-local Cells attach smoke.
#
# Launches the shipped app bundle, creates a temporary SSH-backed Cell, runs the
# bundle-local `cocxy cell attach`, then proves the returned one-shot WebSocket:
# - rejects a bad bearer token before first-use,
# - accepts the real attach lease token,
# - relays keyboard input into the attached terminal PTY,
# - rejects replay after the authenticated connection closes.
#
# This smoke uses only localhost services, a temporary sshd, generated keys, and
# the bundle-local CLI. It is intentionally manual and kept out of CI because it
# launches the macOS app bundle and uses WebKit/AppKit runtime state.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${COCXY_CELLS_ATTACH_APP:-${PROJECT_ROOT}/build/CocxyTerminal.app}"
CLI="${COCXY_CELLS_ATTACH_CLI:-${APP}/Contents/Resources/cocxy}"
SOCKET_PATH="${HOME}/.config/cocxy/cocxy.sock"
ARTIFACT_ROOT="${COCXY_CELLS_ATTACH_ARTIFACTS:-${PROJECT_ROOT}/build/cells-attach-bundle/$(date +%Y%m%d-%H%M%S)}"
ROOT=""
SSHD_PORT=""
CELL_ID=""
PROFILE="cells-attach-smoke-$$"
MARKER="COCXY_ATTACH_INPUT_OK_$$"
CLIENT=""

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
    port=$((26000 + (RANDOM % 23000)))
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
  local log_file="$3"
  local attempt
  for attempt in $(seq 1 30); do
    if nc -z 127.0.0.1 "$port" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  fail_with_output "${label} did not open on 127.0.0.1:${port}" "$log_file"
}

wait_for_app_socket() {
  local attempt
  for attempt in $(seq 1 40); do
    if [ -S "$SOCKET_PATH" ] && "$CLI" status > "${ARTIFACT_ROOT}/cocxy-status.out" 2> "${ARTIFACT_ROOT}/cocxy-status.err"; then
      return 0
    fi
    sleep 1
  done
  fail_with_output "bundle-local CLI did not reach the Cocxy app socket" "${ARTIFACT_ROOT}/cocxy-status.err"
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
  pkill -x CocxyTerminal >/dev/null 2>&1
}
trap cleanup EXIT

require_tool ssh
require_tool ssh-keygen
require_tool nc
require_tool jq
require_tool swift

if [ ! -d "$APP" ]; then
  skip "app bundle not found: ${APP}"
fi
if [ ! -x "$CLI" ]; then
  skip "bundle-local Cocxy CLI is not executable: ${CLI}"
fi
if [ ! -x /usr/sbin/sshd ]; then
  skip "/usr/sbin/sshd is not executable"
fi

mkdir -p "$ARTIFACT_ROOT"
pkill -x CocxyTerminal >/dev/null 2>&1 || true
open -n -g "$APP"
wait_for_app_socket

ROOT="$(mktemp -d /tmp/cocxy-cells-attach.XXXXXX)"
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

if ! "$CLI" cell create --provider ssh --profile "$PROFILE" --host 127.0.0.1 \
  --user "$USER_NAME" --port "$SSHD_PORT" --identity "$ROOT/client_key" \
  --known-hosts "$ROOT/known_hosts" --strict-host-key-checking no \
  > "${ARTIFACT_ROOT}/cell-create.out" 2> "${ARTIFACT_ROOT}/cell-create.err"; then
  fail_with_output "cell create failed" "${ARTIFACT_ROOT}/cell-create.err"
fi
CELL_ID="$(sed -n 's/^Cell created: //p' "${ARTIFACT_ROOT}/cell-create.out" | head -1)"
if [ -z "$CELL_ID" ]; then
  fail_with_output "cell create did not return a cell id" "${ARTIFACT_ROOT}/cell-create.out"
fi

if ! "$CLI" cell status "$CELL_ID" > "${ARTIFACT_ROOT}/cell-status.json" 2> "${ARTIFACT_ROOT}/cell-status.err"; then
  fail_with_output "cell status failed" "${ARTIFACT_ROOT}/cell-status.err"
fi
if [ "$(jq -r '.status // empty' "${ARTIFACT_ROOT}/cell-status.json")" != "running" ]; then
  fail_with_output "cell did not report running status" "${ARTIFACT_ROOT}/cell-status.json"
fi

if ! "$CLI" cell attach "$CELL_ID" > "${ARTIFACT_ROOT}/cell-attach.json" 2> "${ARTIFACT_ROOT}/cell-attach.err"; then
  fail_with_output "cell attach failed" "${ARTIFACT_ROOT}/cell-attach.err"
fi

ATTACH_STATUS="$(jq -r '.status // empty' "${ARTIFACT_ROOT}/cell-attach.json")"
APP_ATTACH="$(jq -r '."app-attach" // empty' "${ARTIFACT_ROOT}/cell-attach.json")"
WEB_ORIGIN="$(jq -r '."web-origin" // empty' "${ARTIFACT_ROOT}/cell-attach.json")"
WEB_TOKEN="$(jq -r '."web-token" // empty' "${ARTIFACT_ROOT}/cell-attach.json")"
WEB_ONE_SHOT="$(jq -r '."web-one-shot" // empty' "${ARTIFACT_ROOT}/cell-attach.json")"

if [ "$ATTACH_STATUS" != "attach-ready" ]; then
  fail_with_output "cell attach did not return attach-ready" "${ARTIFACT_ROOT}/cell-attach.json"
fi
if [ "$APP_ATTACH" != "tab-opened" ]; then
  fail_with_output "cell attach did not open an app tab" "${ARTIFACT_ROOT}/cell-attach.json"
fi
if [ -z "$WEB_ORIGIN" ] || [ -z "$WEB_TOKEN" ] || [ "$WEB_ONE_SHOT" != "true" ]; then
  fail_with_output "cell attach did not return one-shot WebTerminal details" "${ARTIFACT_ROOT}/cell-attach.json"
fi

# `cell attach` opens the tab synchronously but sends the provider PTY command on
# the main actor after the tab has a surface. Wait before injecting WebSocket
# input so the smoke proves input relay into the attached session instead of
# racing the app-side command dispatch.
sleep "${COCXY_CELLS_ATTACH_READY_DELAY:-4}"

CLIENT="${ARTIFACT_ROOT}/CellAttachWebSocketSmoke.swift"
cat > "$CLIENT" <<'SWIFT'
import Darwin
import Foundation

enum SmokeError: Error, CustomStringConvertible {
    case missingArgument(String)
    case timeout(String)
    case unexpected(String)

    var description: String {
        switch self {
        case .missingArgument(let name):
            return "missing argument: \(name)"
        case .timeout(let message), .unexpected(let message):
            return message
        }
    }
}

final class WebSocketProbe {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    init(url: URL, token: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 4
        session = URLSession(configuration: configuration)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        task = session.webSocketTask(with: request)
        task.resume()
    }

    func receive(timeout: TimeInterval) throws -> String {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<String, Error>?
        task.receive { message in
            switch message {
            case .success(.string(let text)):
                result = .success(text)
            case .success(.data(let data)):
                result = .success(String(decoding: data, as: UTF8.self))
            case .failure(let error):
                result = .failure(error)
            @unknown default:
                result = .failure(SmokeError.unexpected("unexpected WebSocket message kind"))
            }
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            throw SmokeError.timeout("timed out waiting for WebSocket message")
        }
        return try result?.get() ?? {
            throw SmokeError.unexpected("WebSocket receive produced no result")
        }()
    }

    func receive(until needle: String, timeout: TimeInterval, label: String) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var transcript: [String] = []
        repeat {
            let remaining = max(0.25, deadline.timeIntervalSinceNow)
            let message = try receive(timeout: remaining)
            transcript.append(message)
            if message.contains(needle) {
                return message
            }
        } while Date() < deadline
        throw SmokeError.timeout("timed out waiting for \(label); transcript=\(transcript.joined(separator: " | "))")
    }

    func send(_ text: String) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var sendError: Error?
        task.send(.string(text)) { error in
            sendError = error
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 4) == .timedOut {
            throw SmokeError.timeout("timed out sending WebSocket message")
        }
        if let sendError {
            throw sendError
        }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }
}

func argument(_ name: String) throws -> String {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: name), index + 1 < args.count else {
        throw SmokeError.missingArgument(name)
    }
    return args[index + 1]
}

func jsonString(_ value: String) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: [value], options: [])
    let array = String(decoding: data, as: UTF8.self)
    return String(array.dropFirst().dropLast())
}

func keyPayload(char: Character) throws -> String {
    """
    {"type":"key","char":\(try jsonString(String(char))),"mods":{"shift":false,"alt":false,"ctrl":false,"meta":false}}
    """
}

func enterPayload() -> String {
    """
    {"type":"key","key":"enter","mods":{"shift":false,"alt":false,"ctrl":false,"meta":false}}
    """
}

func sendCommand(_ command: String, through probe: WebSocketProbe) throws {
    for char in command {
        try probe.send(try keyPayload(char: char))
        Thread.sleep(forTimeInterval: 0.01)
    }
    try probe.send(enterPayload())
}

do {
    let origin = try argument("--origin")
    let token = try argument("--token")
    let marker = try argument("--marker")
    guard let httpURL = URL(string: origin),
          var components = URLComponents(url: httpURL, resolvingAgainstBaseURL: false) else {
        throw SmokeError.unexpected("invalid origin: \(origin)")
    }
    components.scheme = "ws"
    components.path = "/"
    guard let wsURL = components.url else {
        throw SmokeError.unexpected("invalid websocket URL for origin: \(origin)")
    }

    let badProbe = WebSocketProbe(url: wsURL, token: "bad-\(token)")
    defer { badProbe.close() }
    _ = try badProbe.receive(until: "\"type\":\"auth_fail\"", timeout: 5, label: "bad bearer auth_fail")
    print("badAuthRejected=true")
    badProbe.close()

    let goodProbe = WebSocketProbe(url: wsURL, token: token)
    _ = try goodProbe.receive(until: "\"type\":\"auth_ok\"", timeout: 5, label: "valid bearer auth_ok")
    print("validAuthAccepted=true")
    try sendCommand("printf \(marker)", through: goodProbe)
    print("inputSent=true")
    Thread.sleep(forTimeInterval: 1.0)
    goodProbe.close()

    Thread.sleep(forTimeInterval: 1.5)
    let replayProbe = WebSocketProbe(url: wsURL, token: token)
    defer { replayProbe.close() }
    do {
        let message = try replayProbe.receive(until: "\"type\":\"auth_ok\"", timeout: 2, label: "replay auth_ok")
        throw SmokeError.unexpected("replay unexpectedly authenticated: \(message)")
    } catch let error as SmokeError {
        switch error {
        case .timeout:
            print("replayRejected=true")
        default:
            throw error
        }
    } catch {
        print("replayRejected=true")
    }
} catch {
    fputs("websocket-smoke-error: \(error)\n", stderr)
    exit(1)
}
SWIFT

if ! swift "$CLIENT" --origin "$WEB_ORIGIN" --token "$WEB_TOKEN" --marker "$MARKER" \
  > "${ARTIFACT_ROOT}/websocket-client.out" 2> "${ARTIFACT_ROOT}/websocket-client.err"; then
  fail_with_output "WebSocket attach probe failed" "${ARTIFACT_ROOT}/websocket-client.err"
fi
for expected in "badAuthRejected=true" "validAuthAccepted=true" "inputSent=true" "replayRejected=true"; do
  if ! grep -q "$expected" "${ARTIFACT_ROOT}/websocket-client.out"; then
    fail_with_output "WebSocket attach probe missed ${expected}" "${ARTIFACT_ROOT}/websocket-client.out"
  fi
done

for attempt in $(seq 1 30); do
  if "$CLI" capture-pane > "${ARTIFACT_ROOT}/capture-pane.out" 2> "${ARTIFACT_ROOT}/capture-pane.err" \
    && grep -q "$MARKER" "${ARTIFACT_ROOT}/capture-pane.out"; then
    break
  fi
  sleep 1
  if [ "$attempt" = "30" ]; then
    fail_with_output "capture-pane did not include relayed attach input marker" "${ARTIFACT_ROOT}/capture-pane.out"
  fi
done

if ! "$CLI" web status > "${ARTIFACT_ROOT}/web-status-after-close.out" 2> "${ARTIFACT_ROOT}/web-status-after-close.err"; then
  fail_with_output "web status failed after attach WebSocket close" "${ARTIFACT_ROOT}/web-status-after-close.err"
fi
if ! grep -q "Status: stopped" "${ARTIFACT_ROOT}/web-status-after-close.out"; then
  fail_with_output "one-shot WebTerminal did not stop after authenticated disconnect" "${ARTIFACT_ROOT}/web-status-after-close.out"
fi

if ! "$CLI" cell destroy "$CELL_ID" --force > "${ARTIFACT_ROOT}/cell-destroy.out" 2> "${ARTIFACT_ROOT}/cell-destroy.err"; then
  fail_with_output "cell destroy failed" "${ARTIFACT_ROOT}/cell-destroy.err"
fi
CELL_ID=""

echo "status=ok"
echo "artifactRoot=${ARTIFACT_ROOT}"
echo "sshPort=${SSHD_PORT}"
echo "cellProfile=${PROFILE}"
echo "webOrigin=${WEB_ORIGIN}"
echo "marker=${MARKER}"
echo "result=cells-attach-websocket-ok"
