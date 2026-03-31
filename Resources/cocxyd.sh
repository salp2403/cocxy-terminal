#!/bin/sh
# Copyright (c) 2026 Said Arturo Lopez. MIT License.
# cocxyd.sh — Cocxy remote daemon. POSIX shell, zero dependencies.
# Manages persistent terminal sessions and provides a JSON-lines control interface.
#
# Usage: cocxyd.sh {start|stop|status|ping|help}
# Protocol: JSON lines over Unix socket, bridged to TCP for SSH reverse tunnel.
# Version: 1.0.0

COCXYD_VERSION="1.0.0"
COCXYD_PROTO=1

# Runtime directory (private, mode 700).
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/cocxyd-$(id -u)"
SOCKET="$RUNTIME_DIR/cocxyd.sock"
PIDFILE="$RUNTIME_DIR/cocxyd.pid"
LOGFILE="$RUNTIME_DIR/cocxyd.log"
TCP_PORT_FILE="$RUNTIME_DIR/cocxyd.port"
SESSION_DIR="$RUNTIME_DIR/sessions"
FORWARD_DIR="$RUNTIME_DIR/forwards"
SYNC_DIR="$RUNTIME_DIR/sync"
LAST_CLIENT_FILE="$RUNTIME_DIR/last_client"

# Log rotation: 5MB max.
MAX_LOG_SIZE=5242880

# Auto-cleanup: 24 hours.
MAX_IDLE_SECONDS=86400

# --- Utility Functions ---

log_msg() {
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $1" >> "$LOGFILE" 2>/dev/null
}

json_ok() {
    printf '{"ok":true,"id":"%s","data":{%s}}\n' "$1" "$2"
}

json_err() {
    printf '{"ok":false,"id":"%s","error":"%s"}\n' "$1" "$2"
}

json_simple_ok() {
    printf '{"ok":true,"id":"%s"}\n' "$1"
}

check_pid() {
    if [ -f "$PIDFILE" ]; then
        pid=$(cat "$PIDFILE" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

get_uptime() {
    if [ -f "$PIDFILE" ]; then
        start_time=$(stat -c %Y "$PIDFILE" 2>/dev/null || stat -f %m "$PIDFILE" 2>/dev/null)
        now=$(date +%s)
        echo $((now - start_time))
    else
        echo 0
    fi
}

get_memory() {
    if command -v free >/dev/null 2>&1; then
        free -b 2>/dev/null | awk '/^Mem:/ {printf "\"total\":%s,\"used\":%s,\"free\":%s", $2, $3, $4}'
    elif command -v vm_stat >/dev/null 2>&1; then
        # macOS: approximate from vm_stat.
        pages_free=$(vm_stat 2>/dev/null | awk '/Pages free/ {gsub(/\./,"",$3); print $3}')
        pages_active=$(vm_stat 2>/dev/null | awk '/Pages active/ {gsub(/\./,"",$3); print $3}')
        page_size=16384
        free_bytes=$((pages_free * page_size))
        used_bytes=$((pages_active * page_size))
        printf '"free":%s,"used":%s' "$free_bytes" "$used_bytes"
    else
        echo '"free":0,"used":0'
    fi
}

# --- Session Management (3-level fallback) ---

detect_session_tool() {
    if command -v tmux >/dev/null 2>&1; then
        echo "tmux"
    elif command -v screen >/dev/null 2>&1; then
        echo "screen"
    else
        echo "pty"
    fi
}

session_list() {
    req_id="$1"
    tool=$(detect_session_tool)
    sessions="[]"

    case "$tool" in
        tmux)
            sessions=$(tmux list-sessions -F '{"id":"#{session_id}","title":"#{session_name}","pid":0,"age":0,"status":"running"}' 2>/dev/null | \
                grep "cocxy-" | \
                awk 'BEGIN{printf "["} NR>1{printf ","} {printf "%s",$0} END{printf "]"}')
            [ -z "$sessions" ] && sessions="[]"
            ;;
        screen)
            sessions=$(screen -ls 2>/dev/null | grep "cocxy-" | \
                awk 'BEGIN{printf "["} NR>1{printf ","} {split($1,a,"."); printf "{\"id\":\"%s\",\"title\":\"%s\",\"pid\":0,\"age\":0,\"status\":\"running\"}", a[1], a[2]} END{printf "]"}')
            [ -z "$sessions" ] && sessions="[]"
            ;;
        pty)
            sessions="[]"
            if [ -d "$SESSION_DIR" ]; then
                first=1
                sessions="["
                for f in "$SESSION_DIR"/*.pid; do
                    [ -f "$f" ] || continue
                    name=$(basename "$f" .pid)
                    pid=$(cat "$f" 2>/dev/null)
                    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                        [ "$first" = "1" ] || sessions="${sessions},"
                        sessions="${sessions}{\"id\":\"${pid}\",\"title\":\"${name}\",\"pid\":${pid},\"age\":0,\"status\":\"running\"}"
                        first=0
                    fi
                done
                sessions="${sessions}]"
            fi
            ;;
    esac

    json_ok "$req_id" "\"sessions\":$sessions"
}

session_create() {
    req_id="$1"
    title="$2"
    [ -z "$title" ] && title="cocxy-session"
    tool=$(detect_session_tool)

    case "$tool" in
        tmux)
            tmux new-session -d -s "$title" 2>/dev/null
            if [ $? -eq 0 ]; then
                sid=$(tmux list-sessions -F '#{session_id}:#{session_name}' 2>/dev/null | grep ":${title}$" | cut -d: -f1)
                json_ok "$req_id" "\"id\":\"$sid\",\"pid\":0"
            else
                json_err "$req_id" "Failed to create tmux session"
            fi
            ;;
        screen)
            screen -dmS "$title" 2>/dev/null
            json_ok "$req_id" "\"id\":\"$title\",\"pid\":0"
            ;;
        pty)
            mkdir -p "$SESSION_DIR"
            script -q /dev/null sh -c "echo \$\$ > '$SESSION_DIR/${title}.pid'; exec sh" &
            spid=$!
            json_ok "$req_id" "\"id\":\"$spid\",\"pid\":$spid"
            ;;
    esac

    log_msg "Session created: $title"
}

session_kill() {
    req_id="$1"
    target="$2"
    tool=$(detect_session_tool)

    case "$tool" in
        tmux)
            tmux kill-session -t "$target" 2>/dev/null
            ;;
        screen)
            screen -S "$target" -X quit 2>/dev/null
            ;;
        pty)
            if [ -f "$SESSION_DIR/${target}.pid" ]; then
                pid=$(cat "$SESSION_DIR/${target}.pid")
                kill "$pid" 2>/dev/null
                rm -f "$SESSION_DIR/${target}.pid"
            fi
            ;;
    esac

    json_simple_ok "$req_id"
    log_msg "Session killed: $target"
}

# --- Port Forward Persistence ---

forward_list() {
    req_id="$1"
    mkdir -p "$FORWARD_DIR"
    result="["
    first=1
    for f in "$FORWARD_DIR"/*.fwd; do
        [ -f "$f" ] || continue
        spec=$(cat "$f" 2>/dev/null)
        local_port=$(echo "$spec" | cut -d: -f1)
        remote_port=$(echo "$spec" | cut -d: -f2)
        host=$(echo "$spec" | cut -d: -f3)
        [ -z "$host" ] && host="localhost"
        [ "$first" = "1" ] || result="${result},"
        result="${result}{\"local\":$local_port,\"remote\":$remote_port,\"host\":\"$host\",\"status\":\"saved\"}"
        first=0
    done
    result="${result}]"
    json_ok "$req_id" "\"forwards\":$result"
}

forward_add() {
    req_id="$1"
    spec="$2"
    if [ -z "$spec" ]; then
        json_err "$req_id" "missing forward spec (local:remote or local:remote:host)"
        return
    fi
    mkdir -p "$FORWARD_DIR"
    local_port=$(echo "$spec" | cut -d: -f1)
    remote_port=$(echo "$spec" | cut -d: -f2)
    # Validate ports are numeric and in valid range (1-65535).
    case "$local_port" in *[!0-9]*) json_err "$req_id" "invalid local port"; return ;; esac
    case "$remote_port" in *[!0-9]*) json_err "$req_id" "invalid remote port"; return ;; esac
    if [ "$local_port" -lt 1 ] || [ "$local_port" -gt 65535 ] 2>/dev/null; then
        json_err "$req_id" "local port out of range (1-65535)"; return
    fi
    if [ "$remote_port" -lt 1 ] || [ "$remote_port" -gt 65535 ] 2>/dev/null; then
        json_err "$req_id" "remote port out of range (1-65535)"; return
    fi
    echo "$spec" > "$FORWARD_DIR/${local_port}-${remote_port}.fwd"
    log_msg "Forward added: $spec"
    json_simple_ok "$req_id"
}

forward_remove() {
    req_id="$1"
    spec="$2"
    if [ -z "$spec" ]; then
        json_err "$req_id" "missing forward spec"
        return
    fi
    local_port=$(echo "$spec" | cut -d: -f1)
    remote_port=$(echo "$spec" | cut -d: -f2)
    target="$FORWARD_DIR/${local_port}-${remote_port}.fwd"
    if [ -f "$target" ]; then
        rm -f "$target"
        log_msg "Forward removed: $spec"
        json_simple_ok "$req_id"
    else
        json_err "$req_id" "forward not found: $spec"
    fi
}

# --- File Sync Watching ---

sync_watch() {
    req_id="$1"
    path="$2"
    if [ -z "$path" ]; then
        json_err "$req_id" "missing path to watch"
        return
    fi
    mkdir -p "$SYNC_DIR"
    # Store the watched path and create a timestamp marker.
    safe_name=$(echo "$path" | sed 's/[^a-zA-Z0-9_.-]/_/g')
    echo "$path" > "$SYNC_DIR/${safe_name}.path"
    touch "$SYNC_DIR/${safe_name}.marker"
    log_msg "Sync watch started: $path"
    json_simple_ok "$req_id"
}

sync_changes() {
    req_id="$1"
    mkdir -p "$SYNC_DIR"
    result="["
    first=1
    for pathfile in "$SYNC_DIR"/*.path; do
        [ -f "$pathfile" ] || continue
        watched_path=$(cat "$pathfile" 2>/dev/null)
        safe_name=$(basename "$pathfile" .path)
        marker="$SYNC_DIR/${safe_name}.marker"
        [ -f "$marker" ] || continue
        [ -d "$watched_path" ] || continue
        # Find files modified since the last check.
        # Use temp file + read loop to handle paths with spaces
        # (pipe creates subshell in POSIX sh, losing variable changes).
        _sync_tmp="$RUNTIME_DIR/sync_tmp.$$"
        find "$watched_path" -maxdepth 2 -newer "$marker" -type f 2>/dev/null | head -50 > "$_sync_tmp"
        while IFS= read -r file; do
            # Escape double quotes and backslashes for valid JSON.
            safe_file=$(printf '%s' "$file" | sed 's/\\/\\\\/g; s/"/\\"/g')
            [ "$first" = "1" ] || result="${result},"
            result="${result}{\"path\":\"$safe_file\",\"type\":\"modified\"}"
            first=0
        done < "$_sync_tmp"
        rm -f "$_sync_tmp"
        # Update the marker to the current time for next poll.
        touch "$marker"
    done
    result="${result}]"
    json_ok "$req_id" "\"changes\":$result"
}

# --- Auto-Cleanup ---

update_last_client() {
    date +%s > "$LAST_CLIENT_FILE" 2>/dev/null
}

check_idle_timeout() {
    [ -f "$LAST_CLIENT_FILE" ] || return 1
    last=$(cat "$LAST_CLIENT_FILE" 2>/dev/null)
    now=$(date +%s)
    elapsed=$((now - last))
    [ "$elapsed" -gt "$MAX_IDLE_SECONDS" ]
}

# --- Command Handler ---

handle_command() {
    line="$1"

    req_id=$(printf '%s' "$line" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    cmd=$(printf '%s' "$line" | sed -n 's/.*"cmd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    # Track client activity for auto-cleanup.
    update_last_client
    # Validate protocol version (warn but don't reject for backward compat).
    proto=$(printf '%s' "$line" | sed -n 's/.*"proto"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p')
    if [ -n "$proto" ] && [ "$proto" -gt "$COCXYD_PROTO" ] 2>/dev/null; then
        log_msg "WARNING: Client proto=$proto > daemon proto=$COCXYD_PROTO"
    fi
    title_arg=$(printf '%s' "$line" | sed -n 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    data_arg=$(printf '%s' "$line" | sed -n 's/.*"data"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    # Extract session ID from args. The Swift client sends {"args":{"id":"...","data":"..."}}.
    # We try multiple extraction patterns to handle any JSON key ordering.
    session_id_arg=""
    if command -v python3 >/dev/null 2>&1; then
        session_id_arg=$(printf '%s' "$line" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get('args',{}).get('id',''))
except: pass
" 2>/dev/null)
    fi
    # Fallback: sed-based extraction for "id" inside "args" block.
    if [ -z "$session_id_arg" ]; then
        session_id_arg=$(printf '%s' "$line" | sed -n 's/.*"args"[^}]*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    fi
    # Final fallback: use title_arg (for commands like session.create that use "title").
    if [ -z "$session_id_arg" ]; then
        session_id_arg="$title_arg"
    fi
    # Extract spec (for forward commands) and path (for sync commands).
    spec_arg=$(printf '%s' "$line" | sed -n 's/.*"spec"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    path_arg=$(printf '%s' "$line" | sed -n 's/.*"path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    case "$cmd" in
        ping)
            json_ok "$req_id" '"pong":true'
            ;;
        status)
            uptime=$(get_uptime)
            mem=$(get_memory)
            tool=$(detect_session_tool)
            json_ok "$req_id" "\"version\":\"$COCXYD_VERSION\",\"uptime\":$uptime,\"sessionTool\":\"$tool\",$mem"
            ;;
        session.list)
            session_list "$req_id"
            ;;
        session.create)
            session_create "$req_id" "$title_arg"
            ;;
        session.kill)
            session_kill "$req_id" "$title_arg"
            ;;
        session.attach)
            # Acknowledge attach request. Full I/O streaming requires the
            # client to switch to raw byte mode after this response.
            json_ok "$req_id" "\"attached\":true,\"session\":\"$title_arg\""
            log_msg "Session attached: $title_arg"
            ;;
        session.input)
            # Write base64-decoded input bytes to the session's PTY stdin.
            tool=$(detect_session_tool)
            case "$tool" in
                tmux)
                    decoded=$(echo "$data_arg" | base64 -d 2>/dev/null)
                    if [ -n "$decoded" ] && [ -n "$session_id_arg" ]; then
                        tmux send-keys -t "$session_id_arg" "$decoded" 2>/dev/null
                    fi
                    ;;
                screen)
                    decoded=$(echo "$data_arg" | base64 -d 2>/dev/null)
                    if [ -n "$decoded" ] && [ -n "$session_id_arg" ]; then
                        screen -S "$session_id_arg" -X stuff "$decoded" 2>/dev/null
                    fi
                    ;;
                pty)
                    decoded=$(echo "$data_arg" | base64 -d 2>/dev/null)
                    if [ -n "$decoded" ] && [ -f "$SESSION_DIR/${session_id_arg}.pid" ]; then
                        pid=$(cat "$SESSION_DIR/${session_id_arg}.pid" 2>/dev/null)
                        if [ -n "$pid" ]; then
                            # Write to the PTY fd via /proc or send to process.
                            echo "$decoded" > "/proc/$pid/fd/0" 2>/dev/null
                        fi
                    fi
                    ;;
            esac
            json_simple_ok "$req_id"
            ;;
        session.output)
            # Read pending output from the session and return as base64.
            # tmux: capture-pane. screen: hardcopy. pty: read from output file.
            tool=$(detect_session_tool)
            output_data=""
            case "$tool" in
                tmux)
                    if [ -n "$session_id_arg" ]; then
                        output_data=$(tmux capture-pane -t "$session_id_arg" -p 2>/dev/null | tail -5)
                    fi
                    ;;
                screen)
                    tmpfile=$(mktemp)
                    screen -S "$session_id_arg" -X hardcopy "$tmpfile" 2>/dev/null
                    output_data=$(tail -5 "$tmpfile" 2>/dev/null)
                    rm -f "$tmpfile"
                    ;;
                pty)
                    output_data=""
                    ;;
            esac
            if [ -n "$output_data" ]; then
                encoded=$(echo "$output_data" | base64 2>/dev/null | tr -d '\n')
                json_ok "$req_id" "\"data\":\"$encoded\""
            else
                json_ok "$req_id" '"data":""'
            fi
            ;;
        session.detach)
            json_simple_ok "$req_id"
            ;;
        forward.list)
            forward_list "$req_id"
            ;;
        forward.add)
            forward_add "$req_id" "$spec_arg"
            ;;
        forward.remove)
            forward_remove "$req_id" "$spec_arg"
            ;;
        sync.watch)
            sync_watch "$req_id" "$path_arg"
            ;;
        sync.changes)
            sync_changes "$req_id"
            ;;
        shutdown)
            json_simple_ok "$req_id"
            log_msg "Shutdown requested"
            cleanup
            exit 0
            ;;
        *)
            json_err "$req_id" "unknown command: $cmd"
            ;;
    esac
}

# --- TCP Listener ---

find_free_port() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()" 2>/dev/null
        return
    fi
    if command -v python >/dev/null 2>&1; then
        python -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()" 2>/dev/null
        return
    fi
    # Fallback: random port in ephemeral range.
    echo $((49152 + ($(od -An -tu2 -N2 /dev/urandom | tr -d ' ') % 16384)))
}

# Handle a single TCP connection: read JSON lines, respond on same connection.
handle_tcp_connection() {
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        response=$(handle_command "$line")
        echo "$response"
        log_msg "CMD: $line -> $response"
    done
}

# --- Main Loop ---

run_daemon() {
    log_msg "Daemon starting (version $COCXYD_VERSION)"

    # Set up SIGTERM handler for clean shutdown.
    trap 'cleanup; exit 0' TERM INT

    port=$(find_free_port)
    echo "$port" > "$TCP_PORT_FILE"
    echo "COCXYD_PORT=$port"

    log_msg "TCP listener starting on 127.0.0.1:$port"

    # Main loop: accept TCP connections and handle JSON-RPC commands.
    # socat (preferred): forks a handler per connection for concurrency.
    # nc fallback: handles one connection at a time (sequential).
    # Initialize last-client timestamp on startup.
    update_last_client

    if command -v socat >/dev/null 2>&1; then
        socat "TCP-LISTEN:$port,bind=127.0.0.1,reuseaddr,fork" \
              "EXEC:sh $0 _handle" &
        LISTENER_PID=$!
        # Wait loop: check for idle timeout every 60s.
        while kill -0 "$LISTENER_PID" 2>/dev/null; do
            sleep 60
            if check_idle_timeout; then
                log_msg "Idle timeout ($MAX_IDLE_SECONDS s) reached, shutting down"
                kill "$LISTENER_PID" 2>/dev/null
                cleanup
                exit 0
            fi
        done
    else
        # nc fallback: one connection at a time in a loop.
        while true; do
            if check_idle_timeout; then
                log_msg "Idle timeout ($MAX_IDLE_SECONDS s) reached, shutting down"
                cleanup
                exit 0
            fi
            if command -v nc >/dev/null 2>&1; then
                nc -l 127.0.0.1 "$port" -e "sh $0 _handle" 2>/dev/null || \
                    echo '{"ok":false,"error":"nc failed"}' | nc -l "$port" 2>/dev/null
            else
                # Absolute fallback: busy wait for socat/nc to appear.
                sleep 10
            fi
        done
    fi
}

# --- Lifecycle ---

cleanup() {
    rm -f "$SOCKET" "$PIDFILE" "$TCP_PORT_FILE" "$LAST_CLIENT_FILE"
    # Remove sync markers to prevent stale timestamps on restart
    # (would cause find -newer to return false-positive changes).
    rm -f "$SYNC_DIR"/*.marker 2>/dev/null
    log_msg "Daemon stopped"
}

do_start() {
    if check_pid; then
        echo "Daemon already running (PID $(cat "$PIDFILE"))"
        exit 1
    fi

    mkdir -p -m 700 "$RUNTIME_DIR"
    mkdir -p "$SESSION_DIR"
    mkdir -p "$FORWARD_DIR"
    mkdir -p "$SYNC_DIR"

    # Rotate log if too large.
    if [ -f "$LOGFILE" ]; then
        log_size=$(wc -c < "$LOGFILE" 2>/dev/null | tr -d ' ')
        if [ "$log_size" -gt "$MAX_LOG_SIZE" ] 2>/dev/null; then
            mv "$LOGFILE" "${LOGFILE}.1"
        fi
    fi

    # Daemonize.
    if [ -t 0 ] && command -v setsid >/dev/null 2>&1; then
        nohup setsid sh "$0" _run >> "$LOGFILE" 2>&1 &
    else
        nohup sh "$0" _run >> "$LOGFILE" 2>&1 &
    fi
    echo $! > "$PIDFILE"
    echo "Daemon started (PID $!)"
}

do_stop() {
    if ! check_pid; then
        echo "Daemon not running"
        exit 0
    fi

    pid=$(cat "$PIDFILE")
    kill "$pid" 2>/dev/null
    cleanup
    echo "Daemon stopped"
}

do_status() {
    if check_pid; then
        uptime=$(get_uptime)
        mem=$(get_memory)
        tool=$(detect_session_tool)
        printf '{"ok":true,"data":{"version":"%s","uptime":%s,"sessionTool":"%s",%s}}\n' \
            "$COCXYD_VERSION" "$uptime" "$tool" "$mem"
    else
        printf '{"ok":false,"error":"daemon not running"}\n'
    fi
}

do_ping() {
    if check_pid; then
        printf '{"ok":true,"data":{"pong":true}}\n'
    else
        printf '{"ok":false,"error":"daemon not running"}\n'
    fi
}

# --- Entry Point ---

case "${1:-help}" in
    start)   do_start ;;
    stop)    do_stop ;;
    status)  do_status ;;
    ping)    do_ping ;;
    _run)    run_daemon ;;
    _handle) handle_tcp_connection ;;
    help|*)
        echo "cocxyd.sh v$COCXYD_VERSION — Cocxy remote daemon"
        echo "Usage: $0 {start|stop|status|ping|help}"
        ;;
esac
