#!/bin/sh
# Copyright (c) 2026 Said Arturo Lopez. MIT License.
# cocxyd.sh — Cocxy remote daemon. POSIX shell with a bounded Python listener.
# Manages persistent terminal sessions and provides a JSON-lines control interface.
#
# Usage: cocxyd.sh {--version|start|stop|status|ping} <profile-namespace>
# Protocol: JSON lines over Unix socket, bridged to TCP for SSH reverse tunnel.
# Version: 1.2.0

COCXYD_VERSION="1.2.0"
COCXYD_PROTO=1
umask 077

# Runtime directories are private and each connection profile owns an isolated
# daemon namespace. The namespace is a lowercase UUID without hyphens.
RUNTIME_BASE="${XDG_RUNTIME_DIR:-/tmp}/cocxyd-$(id -u)"
NAMESPACE=""
RUNTIME_DIR=""
PIDFILE=""
LOGFILE=""
TCP_PORT_FILE=""
CAPABILITY_FILE=""
GENERATION_FILE=""
SESSION_DIR=""
SCREEN_DIR=""
TMUX_SOCKET=""
FORWARD_DIR=""
SYNC_DIR=""
LAST_CLIENT_FILE=""
LIFECYCLE_LOCK_DIR=""
LIFECYCLE_LOCK_OWNER=""
LIFECYCLE_LOCK_HELD=0

configure_namespace() {
    candidate_namespace="$1"
    [ "${#candidate_namespace}" -eq 32 ] || return 1
    case "$candidate_namespace" in
        *[!0-9a-f]*) return 1 ;;
    esac
    NAMESPACE="$candidate_namespace"
    RUNTIME_DIR="$RUNTIME_BASE/$NAMESPACE"
    PIDFILE="$RUNTIME_DIR/cocxyd.pid"
    LOGFILE="$RUNTIME_DIR/cocxyd.log"
    TCP_PORT_FILE="$RUNTIME_DIR/cocxyd.port"
    CAPABILITY_FILE="$RUNTIME_DIR/cocxyd.cap"
    GENERATION_FILE="$RUNTIME_DIR/cocxyd.generation"
    SESSION_DIR="$RUNTIME_DIR/sessions"
    SCREEN_DIR="$RUNTIME_DIR/screen"
    TMUX_SOCKET="$RUNTIME_DIR/tmux.sock"
    FORWARD_DIR="$RUNTIME_DIR/forwards"
    SYNC_DIR="$RUNTIME_DIR/sync"
    LAST_CLIENT_FILE="$RUNTIME_DIR/last_client"
    LIFECYCLE_LOCK_DIR="$RUNTIME_DIR/lifecycle.lock"
    LIFECYCLE_LOCK_OWNER="$LIFECYCLE_LOCK_DIR/owner"
}

# Log rotation: 5MB max.
MAX_LOG_SIZE=5242880

# Auto-cleanup: 24 hours.
MAX_IDLE_SECONDS=86400

# Session logs are private and bounded. Screen has no incremental capture API,
# so its raw output log is drained by offset and compacted on the next attach.
MAX_SESSION_LOG_BYTES=4194304
MAX_SESSION_OUTPUT_CHUNK_BYTES=524288

# --- Utility Functions ---

directory_metadata() {
    stat -c '%u %a' "$1" 2>/dev/null || stat -f '%u %Lp' "$1" 2>/dev/null
}

ensure_private_directory() {
    directory="$1"
    case "$directory" in
        /*) ;;
        *) return 1 ;;
    esac
    [ ! -L "$directory" ] || return 1
    if [ ! -e "$directory" ]; then
        mkdir -m 700 "$directory" 2>/dev/null || return 1
    fi
    [ -d "$directory" ] || return 1
    metadata=$(directory_metadata "$directory") || return 1
    owner=${metadata%% *}
    mode=${metadata#* }
    [ "$owner" = "$(id -u)" ] && [ "$mode" = "700" ]
}

ensure_runtime_layout() {
    ensure_private_directory "$RUNTIME_BASE" || return 1
    ensure_private_directory "$RUNTIME_DIR" || return 1
    ensure_private_directory "$SESSION_DIR" || return 1
    ensure_private_directory "$SCREEN_DIR" || return 1
    ensure_private_directory "$FORWARD_DIR" || return 1
    ensure_private_directory "$SYNC_DIR" || return 1
}

generate_secret() {
    secret=$(od -An -tx1 -N32 /dev/urandom 2>/dev/null | tr -d ' \n')
    [ "${#secret}" -eq 64 ] || return 1
    case "$secret" in
        *[!0-9a-f]*) return 1 ;;
    esac
    printf '%s\n' "$secret"
}

publish_private_value() {
    destination="$1"
    value="$2"
    pending_value="${destination}.tmp.$$"
    printf '%s\n' "$value" > "$pending_value" || return 1
    chmod 600 "$pending_value" || {
        rm -f "$pending_value"
        return 1
    }
    mv "$pending_value" "$destination" || {
        rm -f "$pending_value"
        return 1
    }
}

read_generation() {
    [ -f "$GENERATION_FILE" ] && [ ! -L "$GENERATION_FILE" ] || return 1
    metadata=$(directory_metadata "$GENERATION_FILE") || return 1
    owner=${metadata%% *}
    mode=${metadata#* }
    [ "$owner" = "$(id -u)" ] && [ "$mode" = "600" ] || return 1
    candidate=$(cat "$GENERATION_FILE" 2>/dev/null)
    [ "${#candidate}" -eq 64 ] || return 1
    case "$candidate" in
        *[!0-9a-f]*) return 1 ;;
    esac
    printf '%s\n' "$candidate"
}

generation_is_current() {
    expected_generation="$1"
    current_generation=$(read_generation) || return 1
    [ "$current_generation" = "$expected_generation" ]
}

read_capability() {
    [ -f "$CAPABILITY_FILE" ] && [ ! -L "$CAPABILITY_FILE" ] || return 1
    metadata=$(directory_metadata "$CAPABILITY_FILE") || return 1
    owner=${metadata%% *}
    mode=${metadata#* }
    [ "$owner" = "$(id -u)" ] && [ "$mode" = "600" ] || return 1
    candidate=$(cat "$CAPABILITY_FILE" 2>/dev/null)
    [ "${#candidate}" -eq 64 ] || return 1
    case "$candidate" in
        *[!0-9a-f]*) return 1 ;;
    esac
    printf '%s\n' "$candidate"
}

publish_capability() {
    capability=$(generate_secret) || return 1
    publish_private_value "$CAPABILITY_FILE" "$capability"
}

is_safe_identifier() {
    value="$1"
    [ -n "$value" ] && [ "${#value}" -le 128 ] || return 1
    case "$value" in
        -*) return 1 ;;
    esac
    [ -z "$(printf '%s' "$value" | sed 's/[-A-Za-z0-9._@$]//g')" ]
}

is_safe_request_id() {
    value="$1"
    case "$value" in
        req-*) digits=${value#req-} ;;
        *) return 1 ;;
    esac
    [ -n "$digits" ] || return 1
    case "$digits" in
        *[!0-9]*) return 1 ;;
    esac
    [ "${#digits}" -le 20 ]
}

decode_base64_to_private_file() {
    encoded_value="$1"
    destination="$2"
    if printf '%s' "$encoded_value" | base64 -d > "$destination" 2>/dev/null; then
        return 0
    fi
    : > "$destination" || return 1
    printf '%s' "$encoded_value" | base64 -D > "$destination" 2>/dev/null
}

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

process_holds_file() {
    process_pid="$1"
    expected_file="$2"
    [ -f "$expected_file" ] && [ ! -L "$expected_file" ] || return 1
    if [ -d "/proc/$process_pid/fd" ] && command -v readlink >/dev/null 2>&1; then
        expected_target=$(readlink -f "$expected_file" 2>/dev/null) || return 1
        for descriptor in "/proc/$process_pid/fd"/*; do
            [ -e "$descriptor" ] || continue
            descriptor_target=$(readlink -f "$descriptor" 2>/dev/null) || continue
            [ "$descriptor_target" = "$expected_target" ] && return 0
        done
        return 1
    fi
    if command -v lsof >/dev/null 2>&1; then
        lsof -a -p "$process_pid" "$expected_file" >/dev/null 2>&1
        return $?
    fi
    if [ -x /usr/sbin/lsof ]; then
        /usr/sbin/lsof -a -p "$process_pid" "$expected_file" >/dev/null 2>&1
        return $?
    fi
    return 2
}

read_daemon_pid() {
    [ -f "$PIDFILE" ] && [ ! -L "$PIDFILE" ] || return 1
    metadata=$(directory_metadata "$PIDFILE") || return 1
    owner=${metadata%% *}
    mode=${metadata#* }
    [ "$owner" = "$(id -u)" ] && [ "$mode" = "600" ] || return 1
    stored_record=$(cat "$PIDFILE" 2>/dev/null) || return 1
    pid=${stored_record%% *}
    stored_generation=${stored_record#* }
    case "$pid" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$stored_generation" != "$stored_record" ] || return 1
    [ "${#stored_generation}" -eq 64 ] || return 1
    case "$stored_generation" in
        *[!0-9a-f]*) return 1 ;;
    esac
    [ "$pid" -gt 1 ] 2>/dev/null || return 1
}

process_matches_daemon() {
    expected_pid="$1"
    expected_generation="$2"
    kill -0 "$expected_pid" 2>/dev/null || return 1
    process_holds_file "$expected_pid" "$GENERATION_FILE" || return 1
    if process_command=$(ps -p "$expected_pid" -o command= 2>/dev/null); then
        case "$process_command" in
            *cocxyd.sh*" _run $NAMESPACE $expected_generation"*) ;;
            *) return 1 ;;
        esac
    fi
    return 0
}

check_pid() {
    read_daemon_pid || return 1
    generation_is_current "$stored_generation" || return 1
    process_matches_daemon "$pid" "$stored_generation"
}

lock_owner_is_alive() {
    [ -f "$LIFECYCLE_LOCK_OWNER" ] && [ ! -L "$LIFECYCLE_LOCK_OWNER" ] || return 1
    lock_record=$(cat "$LIFECYCLE_LOCK_OWNER" 2>/dev/null) || return 1
    lock_pid="$lock_record"
    case "$lock_pid" in
        ''|*[!0-9]*) return 1 ;;
    esac
    kill -0 "$lock_pid" 2>/dev/null || return 1
    process_holds_file "$lock_pid" "$LIFECYCLE_LOCK_OWNER"
    owner_check=$?
    [ "$owner_check" -eq 0 ] || [ "$owner_check" -eq 2 ]
}

acquire_lifecycle_lock() {
    ensure_runtime_layout || return 1
    lock_attempt=0
    missing_owner_attempts=0
    while [ "$lock_attempt" -lt 20 ]; do
        if mkdir -m 700 "$LIFECYCLE_LOCK_DIR" 2>/dev/null; then
            pending_owner="$LIFECYCLE_LOCK_DIR/owner.tmp.$$"
            if ! printf '%s\n' "$$" > "$pending_owner" \
                || ! chmod 600 "$pending_owner" \
                || ! mv "$pending_owner" "$LIFECYCLE_LOCK_OWNER" \
                || ! exec 8<"$LIFECYCLE_LOCK_OWNER"; then
                exec 8<&- 2>/dev/null || true
                rm -f "$pending_owner" "$LIFECYCLE_LOCK_OWNER"
                rmdir "$LIFECYCLE_LOCK_DIR" 2>/dev/null
                return 1
            fi
            LIFECYCLE_LOCK_HELD=1
            return 0
        fi
        [ -d "$LIFECYCLE_LOCK_DIR" ] && [ ! -L "$LIFECYCLE_LOCK_DIR" ] || return 1
        if lock_owner_is_alive; then
            missing_owner_attempts=0
        elif [ -f "$LIFECYCLE_LOCK_OWNER" ]; then
            rm -f "$LIFECYCLE_LOCK_OWNER"
            rmdir "$LIFECYCLE_LOCK_DIR" 2>/dev/null || true
            missing_owner_attempts=0
        else
            missing_owner_attempts=$((missing_owner_attempts + 1))
            if [ "$missing_owner_attempts" -ge 2 ]; then
                rm -f "$LIFECYCLE_LOCK_DIR"/owner.tmp.* 2>/dev/null
                rmdir "$LIFECYCLE_LOCK_DIR" 2>/dev/null || true
                missing_owner_attempts=0
            fi
        fi
        lock_attempt=$((lock_attempt + 1))
        sleep 1
    done
    return 1
}

release_lifecycle_lock() {
    [ "$LIFECYCLE_LOCK_HELD" -eq 1 ] || return 0
    if [ -f "$LIFECYCLE_LOCK_OWNER" ]; then
        lock_record=$(cat "$LIFECYCLE_LOCK_OWNER" 2>/dev/null)
        lock_pid=${lock_record%% *}
        [ "$lock_pid" = "$$" ] || return 1
    fi
    exec 8<&- 2>/dev/null || true
    rm -f "$LIFECYCLE_LOCK_OWNER"
    rmdir "$LIFECYCLE_LOCK_DIR" 2>/dev/null || return 1
    LIFECYCLE_LOCK_HELD=0
}

run_with_lifecycle_lock() {
    acquire_lifecycle_lock || {
        echo "Daemon lifecycle lock is unavailable" >&2
        return 1
    }
    trap 'release_lifecycle_lock; exit 1' 1 2 15
    trap 'release_lifecycle_lock' 0
    "$@"
    command_status=$?
    release_lifecycle_lock
    trap - 0 1 2 15
    return "$command_status"
}

read_tcp_port() {
    [ -f "$TCP_PORT_FILE" ] && [ ! -L "$TCP_PORT_FILE" ] || return 1
    metadata=$(directory_metadata "$TCP_PORT_FILE") || return 1
    owner=${metadata%% *}
    mode=${metadata#* }
    [ "$owner" = "$(id -u)" ] && [ "$mode" = "600" ] || return 1
    candidate=$(cat "$TCP_PORT_FILE" 2>/dev/null)
    case "$candidate" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$candidate" -ge 1 ] 2>/dev/null || return 1
    [ "$candidate" -le 65535 ] 2>/dev/null || return 1
    printf '%s\n' "$candidate"
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

tmux_cursor_fields() {
    cursor_target="$1"
    cursor_position=$(tmux -S "$TMUX_SOCKET" display-message -p \
        -t "=$cursor_target" '#{cursor_x}:#{cursor_y}' 2>/dev/null) || return 1
    case "$cursor_position" in
        *:*) ;;
        *) return 1 ;;
    esac
    cursor_x=${cursor_position%%:*}
    cursor_y=${cursor_position#*:}
    case "$cursor_y" in
        *:*) return 1 ;;
    esac
    case "$cursor_x:$cursor_y" in
        *[!0-9:]*|:|:*|*:) return 1 ;;
    esac
    printf '"cursor_x":%s,"cursor_y":%s' "$cursor_x" "$cursor_y"
}

session_list() {
    req_id="$1"
    tool=$(detect_session_tool)
    sessions="[]"

    case "$tool" in
        tmux)
            sessions=$(tmux -S "$TMUX_SOCKET" list-sessions -F '#{session_name}' 2>/dev/null | \
                awk 'BEGIN{printf "["} /^[A-Za-z0-9._@$-]+$/ && length($0) <= 128 {if (count++) printf ","; printf "{\"id\":\"%s\",\"title\":\"%s\",\"pid\":0,\"age\":0,\"status\":\"running\"}",$0,$0} END{printf "]"}')
            [ -z "$sessions" ] && sessions="[]"
            ;;
        screen)
            sessions=$(SCREENDIR="$SCREEN_DIR" screen -ls 2>/dev/null | \
                awk 'BEGIN{printf "["} /^[[:space:]]*[0-9]+\.[A-Za-z0-9._@$-]+[[:space:]]/ {entry=$1; sub(/^[0-9]+\./,"",entry); if (length(entry) <= 128) {if (count++) printf ","; printf "{\"id\":\"%s\",\"title\":\"%s\",\"pid\":0,\"age\":0,\"status\":\"running\"}",entry,entry}} END{printf "]"}')
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
                        sessions="${sessions}{\"id\":\"${name}\",\"title\":\"${name}\",\"pid\":${pid},\"age\":0,\"status\":\"running\"}"
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
    if ! is_safe_identifier "$title"; then
        json_err "$req_id" "invalid session title"
        return
    fi
    tool=$(detect_session_tool)

    case "$tool" in
        tmux)
            tmux -S "$TMUX_SOCKET" new-session -d -s "$title" 2>/dev/null
            if [ $? -eq 0 ]; then
                json_ok "$req_id" "\"id\":\"$title\",\"pid\":0"
            else
                json_err "$req_id" "Failed to create tmux session"
            fi
            ;;
        screen)
            if SCREENDIR="$SCREEN_DIR" screen -dmS "$title" 2>/dev/null; then
                if configure_screen_logging "$title"; then
                    json_ok "$req_id" "\"id\":\"$title\",\"pid\":0"
                else
                    SCREENDIR="$SCREEN_DIR" screen -S "$title" -X quit 2>/dev/null
                    json_err "$req_id" "Failed to configure screen session output"
                fi
            else
                json_err "$req_id" "Failed to create screen session"
            fi
            ;;
        pty)
            pid_file="$SESSION_DIR/${title}.pid"
            script -q /dev/null sh -c 'exec sh' &
            spid=$!
            printf '%s\n' "$spid" > "$pid_file"
            json_ok "$req_id" "\"id\":\"$title\",\"pid\":$spid"
            ;;
    esac

    log_msg "Session created: $title"
}

screen_log_path() {
    printf '%s/%s.screenlog\n' "$SESSION_DIR" "$1"
}

screen_offset_path() {
    printf '%s/%s.offset\n' "$SESSION_DIR" "$1"
}

configure_screen_logging() {
    target="$1"
    output_log=$(screen_log_path "$target")
    [ ! -L "$output_log" ] || return 1
    if [ ! -e "$output_log" ]; then
        : > "$output_log" || return 1
    fi
    [ -f "$output_log" ] || return 1
    chmod 600 "$output_log" || return 1
    SCREENDIR="$SCREEN_DIR" screen -S "$target" -p 0 \
        -X logfile "$output_log" 2>/dev/null \
        && SCREENDIR="$SCREEN_DIR" screen -S "$target" -p 0 \
            -X logfile flush 1 2>/dev/null \
        && SCREENDIR="$SCREEN_DIR" screen -S "$target" -p 0 \
            -X log on 2>/dev/null
}

prepare_screen_log_for_attach() {
    target="$1"
    output_log=$(screen_log_path "$target")
    configure_screen_logging "$target" || return 1
    output_size=$(wc -c < "$output_log" 2>/dev/null | tr -d ' ')
    case "$output_size" in
        ''|*[!0-9]*) return 1 ;;
    esac
    if [ "$output_size" -gt "$MAX_SESSION_LOG_BYTES" ] 2>/dev/null; then
        compact_log=$(mktemp "$SESSION_DIR/.screenlog.XXXXXX" 2>/dev/null) || return 1
        chmod 600 "$compact_log" || { rm -f "$compact_log"; return 1; }
        SCREENDIR="$SCREEN_DIR" screen -S "$target" -p 0 -X log off 2>/dev/null
        tail -c "$MAX_SESSION_LOG_BYTES" "$output_log" > "$compact_log" 2>/dev/null \
            || { rm -f "$compact_log"; return 1; }
        cat "$compact_log" > "$output_log" || { rm -f "$compact_log"; return 1; }
        rm -f "$compact_log"
        configure_screen_logging "$target" || return 1
    fi
    publish_private_value "$(screen_offset_path "$target")" 0
}

screen_session_output() {
    req_id="$1"
    target="$2"
    output_log=$(screen_log_path "$target")
    offset_file=$(screen_offset_path "$target")
    [ -f "$output_log" ] && [ ! -L "$output_log" ] || {
        json_err "$req_id" "screen session output is unavailable"
        return
    }
    output_size=$(wc -c < "$output_log" 2>/dev/null | tr -d ' ')
    output_offset=$(cat "$offset_file" 2>/dev/null)
    case "$output_size:$output_offset" in
        *[!0-9:]*) json_err "$req_id" "invalid screen output state"; return ;;
    esac
    if [ -z "$output_offset" ] || [ "$output_offset" -gt "$output_size" ] 2>/dev/null; then
        output_offset=0
    fi
    remaining=$((output_size - output_offset))
    if [ "$remaining" -le 0 ]; then
        json_ok "$req_id" '"data":"","mode":"stream"'
        return
    fi
    output_count="$remaining"
    if [ "$output_count" -gt "$MAX_SESSION_OUTPUT_CHUNK_BYTES" ]; then
        output_count="$MAX_SESSION_OUTPUT_CHUNK_BYTES"
    fi
    output_start=$((output_offset + 1))
    encoded=$(tail -c "+$output_start" "$output_log" 2>/dev/null \
        | head -c "$output_count" \
        | base64 2>/dev/null \
        | tr -d '\n')
    [ -n "$encoded" ] || {
        json_err "$req_id" "screen session output encoding failed"
        return
    }
    next_offset=$((output_offset + output_count))
    publish_private_value "$offset_file" "$next_offset" || {
        json_err "$req_id" "screen session output cursor failed"
        return
    }
    if [ "$next_offset" -ge "$MAX_SESSION_LOG_BYTES" ] 2>/dev/null; then
        compact_consumed_screen_log "$target" "$next_offset" || \
            log_msg "Screen output compaction deferred: $target"
    fi
    json_ok "$req_id" "\"data\":\"$encoded\",\"mode\":\"stream\""
}

compact_consumed_screen_log() {
    target="$1"
    consumed_bytes="$2"
    output_log=$(screen_log_path "$target")
    offset_file=$(screen_offset_path "$target")
    compact_log=$(mktemp "$SESSION_DIR/.screenlog.XXXXXX" 2>/dev/null) || return 1
    chmod 600 "$compact_log" || { rm -f "$compact_log"; return 1; }
    SCREENDIR="$SCREEN_DIR" screen -S "$target" -p 0 -X log off 2>/dev/null \
        || { rm -f "$compact_log"; return 1; }
    current_size=$(wc -c < "$output_log" 2>/dev/null | tr -d ' ')
    case "$current_size" in
        ''|*[!0-9]*)
            rm -f "$compact_log"
            configure_screen_logging "$target" >/dev/null 2>&1
            return 1
            ;;
    esac
    if [ "$consumed_bytes" -gt "$current_size" ] 2>/dev/null; then
        consumed_bytes="$current_size"
    fi
    unread_start=$((consumed_bytes + 1))
    if [ "$current_size" -gt "$consumed_bytes" ] 2>/dev/null; then
        tail -c "+$unread_start" "$output_log" > "$compact_log" 2>/dev/null || {
            rm -f "$compact_log"
            configure_screen_logging "$target" >/dev/null 2>&1
            return 1
        }
    fi
    cat "$compact_log" > "$output_log" || {
        rm -f "$compact_log"
        configure_screen_logging "$target" >/dev/null 2>&1
        return 1
    }
    rm -f "$compact_log"
    publish_private_value "$offset_file" 0 || {
        configure_screen_logging "$target" >/dev/null 2>&1
        return 1
    }
    configure_screen_logging "$target"
}

session_exists() {
    tool="$1"
    target="$2"
    case "$tool" in
        tmux)
            tmux -S "$TMUX_SOCKET" has-session -t "=$target" 2>/dev/null
            ;;
        screen)
            SCREENDIR="$SCREEN_DIR" screen -ls 2>/dev/null | awk -v target="$target" '
                /^[[:space:]]*[0-9]+\./ {
                    entry=$1
                    sub(/^[0-9]+\./, "", entry)
                    if (entry == target) found=1
                }
                END { exit found ? 0 : 1 }
            '
            ;;
        pty)
            target_file="$SESSION_DIR/${target}.pid"
            [ -f "$target_file" ] && [ ! -L "$target_file" ] || return 1
            target_pid=$(cat "$target_file" 2>/dev/null)
            case "$target_pid" in
                ''|*[!0-9]*) return 1 ;;
            esac
            [ "$target_pid" -gt 1 ] 2>/dev/null && kill -0 "$target_pid" 2>/dev/null
            ;;
    esac
}

session_kill() {
    req_id="$1"
    target="$2"
    if ! is_safe_identifier "$target"; then
        json_err "$req_id" "invalid session identifier"
        return
    fi
    tool=$(detect_session_tool)
    killed=0

    case "$tool" in
        tmux)
            if tmux -S "$TMUX_SOCKET" kill-session -t "=$target" 2>/dev/null; then killed=1; fi
            ;;
        screen)
            if SCREENDIR="$SCREEN_DIR" screen -S "$target" -X quit 2>/dev/null; then killed=1; fi
            ;;
        pty)
            target_file="$SESSION_DIR/${target}.pid"
            if [ -f "$target_file" ] && [ ! -L "$target_file" ]; then
                pid=$(cat "$target_file" 2>/dev/null)
                case "$pid" in
                    ''|*[!0-9]*) pid="" ;;
                esac
                if [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null \
                    && kill "$pid" 2>/dev/null; then
                    rm -f "$target_file"
                    killed=1
                fi
            fi
            ;;
    esac

    if [ "$killed" -eq 1 ]; then
        rm -f "$(screen_log_path "$target")" "$(screen_offset_path "$target")"
        json_simple_ok "$req_id"
        log_msg "Session killed: $target"
    else
        json_err "$req_id" "session not found or could not be terminated"
    fi
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
    host=$(echo "$spec" | cut -d: -f3)
    extra=$(echo "$spec" | cut -s -d: -f4-)
    # Validate ports are numeric and in valid range (1-65535).
    case "$local_port" in *[!0-9]*) json_err "$req_id" "invalid local port"; return ;; esac
    case "$remote_port" in *[!0-9]*) json_err "$req_id" "invalid remote port"; return ;; esac
    if [ "$local_port" -lt 1 ] || [ "$local_port" -gt 65535 ] 2>/dev/null; then
        json_err "$req_id" "local port out of range (1-65535)"; return
    fi
    if [ "$remote_port" -lt 1 ] || [ "$remote_port" -gt 65535 ] 2>/dev/null; then
        json_err "$req_id" "remote port out of range (1-65535)"; return
    fi
    if [ -n "$extra" ] || [ "${#host}" -gt 253 ] \
        || [ -n "$(printf '%s' "$host" | sed 's/[-A-Za-z0-9._]//g')" ]; then
        json_err "$req_id" "invalid forward host"; return
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
    host=$(echo "$spec" | cut -d: -f3)
    extra=$(echo "$spec" | cut -s -d: -f4-)
    case "$local_port" in
        ''|*[!0-9]*) json_err "$req_id" "invalid local port"; return ;;
    esac
    case "$remote_port" in
        ''|*[!0-9]*) json_err "$req_id" "invalid remote port"; return ;;
    esac
    if [ "$local_port" -lt 1 ] 2>/dev/null || [ "$local_port" -gt 65535 ] 2>/dev/null \
        || [ "$remote_port" -lt 1 ] 2>/dev/null || [ "$remote_port" -gt 65535 ] 2>/dev/null \
        || [ -n "$extra" ] || [ "${#host}" -gt 253 ] \
        || [ -n "$(printf '%s' "$host" | sed 's/[-A-Za-z0-9._]//g')" ]; then
        json_err "$req_id" "invalid forward spec"
        return
    fi
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
    if [ -z "$path" ] || [ "${#path}" -gt 4096 ]; then
        json_err "$req_id" "invalid path to watch"
        return
    fi
    case "$path" in
        /*) ;;
        *) json_err "$req_id" "watch path must be absolute"
        return
        ;;
    esac
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

    proto=$(printf '%s' "$line" \
        | sed -n 's/^{"proto":\([0-9][0-9]*\),"id":"[^"]*","cmd":"[^"]*".*$/\1/p')
    req_id=$(printf '%s' "$line" \
        | sed -n 's/^{"proto":[0-9][0-9]*,"id":"\([^"]*\)","cmd":"[^"]*".*$/\1/p')
    cmd=$(printf '%s' "$line" \
        | sed -n 's/^{"proto":[0-9][0-9]*,"id":"[^"]*","cmd":"\([^"]*\)".*$/\1/p')
    if ! is_safe_request_id "$req_id"; then
        json_err "invalid" "invalid request identifier"
        return
    fi
    if [ "$proto" != "$COCXYD_PROTO" ]; then
        json_err "$req_id" "unsupported protocol version"
        return
    fi
    if [ -z "$cmd" ] || [ "${#cmd}" -gt 64 ] \
        || [ -n "$(printf '%s' "$cmd" | sed 's/[A-Za-z0-9._-]//g')" ]; then
        json_err "$req_id" "invalid command"
        return
    fi
    # Track client activity for auto-cleanup.
    update_last_client
    title_arg=$(printf '%s' "$line" | sed -n 's/.*"title"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    data_arg=$(printf '%s' "$line" | sed -n 's/.*"data"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
    cols_arg=$(printf '%s' "$line" | sed -n 's/.*"cols"[[:space:]]*:[[:space:]]*"\([0-9][0-9]*\)".*/\1/p')
    rows_arg=$(printf '%s' "$line" | sed -n 's/.*"rows"[[:space:]]*:[[:space:]]*"\([0-9][0-9]*\)".*/\1/p')
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
            session_kill "$req_id" "$session_id_arg"
            ;;
        session.attach)
            if ! is_safe_identifier "$session_id_arg"; then
                json_err "$req_id" "invalid session identifier"
                return
            fi
            tool=$(detect_session_tool)
            if ! session_exists "$tool" "$session_id_arg"; then
                json_err "$req_id" "session not found"
                return
            fi
            attach_mode="snapshot"
            attach_cursor_fields=""
            if [ "$tool" = "screen" ]; then
                if ! prepare_screen_log_for_attach "$session_id_arg"; then
                    json_err "$req_id" "screen session output setup failed"
                    return
                fi
                attach_mode="stream"
            elif [ "$tool" = "tmux" ]; then
                attach_cursor_fields=$(tmux_cursor_fields "$session_id_arg") \
                    || attach_cursor_fields=""
            fi
            attach_data="\"attached\":true,\"session\":\"$session_id_arg\",\"mode\":\"$attach_mode\",\"tool\":\"$tool\""
            if [ -n "$attach_cursor_fields" ]; then
                attach_data="$attach_data,$attach_cursor_fields"
            fi
            json_ok "$req_id" "$attach_data"
            log_msg "Session attached: $session_id_arg"
            ;;
        session.input)
            if ! is_safe_identifier "$session_id_arg"; then
                json_err "$req_id" "invalid session identifier"
                return
            fi
            tool=$(detect_session_tool)
            if ! session_exists "$tool" "$session_id_arg"; then
                json_err "$req_id" "session not found"
                return
            fi
            input_file=$(mktemp "$SESSION_DIR/.input.XXXXXX" 2>/dev/null)
            if [ -z "$input_file" ] || [ ! -f "$input_file" ] || [ -L "$input_file" ]; then
                json_err "$req_id" "could not allocate private input buffer"
                return
            fi
            chmod 600 "$input_file" || {
                rm -f "$input_file"
                json_err "$req_id" "could not secure private input buffer"
                return
            }
            if ! decode_base64_to_private_file "$data_arg" "$input_file"; then
                rm -f "$input_file"
                json_err "$req_id" "invalid base64 input"
                return
            fi

            input_status=1
            case "$tool" in
                tmux)
                    buffer_name="cocxy-${req_id#req-}-$$"
                    if tmux -S "$TMUX_SOCKET" load-buffer -b "$buffer_name" "$input_file" 2>/dev/null \
                        && tmux -S "$TMUX_SOCKET" paste-buffer -b "$buffer_name" -t "=$session_id_arg" -d 2>/dev/null; then
                        input_status=0
                    fi
                    ;;
                screen)
                    if SCREENDIR="$SCREEN_DIR" screen -S "$session_id_arg" -p 0 \
                        -X readbuf "$input_file" 2>/dev/null \
                        && SCREENDIR="$SCREEN_DIR" screen -S "$session_id_arg" -p 0 \
                            -X paste . 2>/dev/null; then
                        input_status=0
                    fi
                    ;;
                pty) input_status=2 ;;
            esac
            rm -f "$input_file"
            if [ "$input_status" -eq 0 ]; then
                json_simple_ok "$req_id"
            elif [ "$input_status" -eq 2 ]; then
                json_err "$req_id" "direct PTY input is unavailable; install tmux or screen"
            else
                json_err "$req_id" "session input delivery failed"
            fi
            ;;
        session.output)
            if ! is_safe_identifier "$session_id_arg"; then
                json_err "$req_id" "invalid session identifier"
                return
            fi
            # Read pending output from the session and return as base64.
            # tmux uses snapshots; screen drains its private raw stream log.
            tool=$(detect_session_tool)
            if ! session_exists "$tool" "$session_id_arg"; then
                json_err "$req_id" "session not found"
                return
            fi
            output_data=""
            output_cursor_fields=""
            case "$tool" in
                tmux)
                    if [ -n "$session_id_arg" ]; then
                        output_data=$(tmux -S "$TMUX_SOCKET" capture-pane -t "=$session_id_arg" -p -e 2>/dev/null)
                        output_cursor_fields=$(tmux_cursor_fields "$session_id_arg") \
                            || output_cursor_fields=""
                    fi
                    ;;
                screen)
                    screen_session_output "$req_id" "$session_id_arg"
                    return
                    ;;
                pty)
                    output_data=""
                    ;;
            esac
            if [ -n "$output_data" ]; then
                encoded=$(printf '%s\n' "$output_data" | base64 2>/dev/null | tr -d '\n')
                output_fields="\"data\":\"$encoded\",\"mode\":\"snapshot\""
            else
                output_fields='"data":"","mode":"snapshot"'
            fi
            if [ -n "$output_cursor_fields" ]; then
                output_fields="$output_fields,$output_cursor_fields"
            fi
            json_ok "$req_id" "$output_fields"
            ;;
        session.resize)
            if ! is_safe_identifier "$session_id_arg"; then
                json_err "$req_id" "invalid session identifier"
                return
            fi
            tool=$(detect_session_tool)
            if ! session_exists "$tool" "$session_id_arg"; then
                json_err "$req_id" "session not found"
                return
            fi
            case "$cols_arg:$rows_arg" in
                *[!0-9:]*|:|:*|*:) json_err "$req_id" "invalid terminal size"; return ;;
            esac
            if [ "$cols_arg" -lt 1 ] 2>/dev/null || [ "$cols_arg" -gt 1000 ] 2>/dev/null \
                || [ "$rows_arg" -lt 1 ] 2>/dev/null || [ "$rows_arg" -gt 1000 ] 2>/dev/null; then
                json_err "$req_id" "terminal size out of range"
                return
            fi
            case "$tool" in
                tmux)
                    if tmux -S "$TMUX_SOCKET" resize-window -t "=$session_id_arg" \
                        -x "$cols_arg" -y "$rows_arg" 2>/dev/null; then
                        json_simple_ok "$req_id"
                    else
                        json_err "$req_id" "session resize failed"
                    fi
                    ;;
                screen)
                    if SCREENDIR="$SCREEN_DIR" screen -S "$session_id_arg" -p 0 \
                        -X width "$cols_arg" "$rows_arg" 2>/dev/null; then
                        json_simple_ok "$req_id"
                    else
                        json_err "$req_id" "session resize failed"
                    fi
                    ;;
                pty)
                    json_err "$req_id" "direct PTY resize is unavailable; install tmux or screen"
                    ;;
            esac
            ;;
        session.detach)
            if is_safe_identifier "$session_id_arg"; then
                json_simple_ok "$req_id"
            else
                json_err "$req_id" "invalid session identifier"
            fi
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
            return 75
            ;;
        *)
            json_err "$req_id" "unknown command: $cmd"
            ;;
    esac
}

# --- TCP Listener ---

# Defense in depth for the bounded Python listener. It invokes this handler
# with one authenticated frame and EOF; generation and capability are checked
# again immediately before command dispatch.
handle_tcp_connection() {
    handler_generation="$1"
    ensure_runtime_layout || return 1
    generation_is_current "$handler_generation" || return 1
    tab=$(printf '\t')
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        generation_is_current "$handler_generation" || return 1
        expected_capability=$(read_capability) || return 1
        case "$line" in
            "$expected_capability$tab"*) request=${line#"$expected_capability$tab"} ;;
            *)
                supplied_id=$(printf '%s' "$line" | sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
                if ! is_safe_request_id "$supplied_id"; then supplied_id="invalid"; fi
                json_err "$supplied_id" "authentication failed"
                return 1
                ;;
        esac
        response=$(handle_command "$request")
        command_status=$?
        generation_is_current "$handler_generation" || return 1
        printf '%s\n' "$response"
        log_msg "Handled authenticated daemon request"
        if [ "$command_status" -eq 75 ]; then
            if check_pid && [ "$stored_generation" = "$handler_generation" ]; then
                kill "$pid" 2>/dev/null
            fi
            return 0
        fi
    done
}

# --- Main Loop ---

run_daemon() {
    DAEMON_GENERATION="$1"
    ensure_runtime_layout || {
        echo "Daemon runtime directory is not private" >&2
        exit 1
    }
    generation_is_current "$DAEMON_GENERATION" || exit 1
    read_capability >/dev/null || {
        log_msg "Daemon capability is unavailable"
        cleanup_generation "$DAEMON_GENERATION"
        exit 1
    }
    command -v python3 >/dev/null 2>&1 || {
        log_msg "No supported loopback listener is available (requires Python 3)"
        cleanup_generation "$DAEMON_GENERATION"
        exit 1
    }

    log_msg "Daemon starting (version $COCXYD_VERSION)"
    trap 'cleanup_generation "$DAEMON_GENERATION"; exit 0' HUP INT TERM
    update_last_client
    LISTENER_PID=""

    python3 - "$0" "$NAMESPACE" "$DAEMON_GENERATION" \
        "$GENERATION_FILE" "$CAPABILITY_FILE" "$TCP_PORT_FILE" <<'PY' &
import hmac
import json
import os
import signal
import socket
import subprocess
import sys
import threading
import time

MAX_CONNECTIONS = 16
MAX_FRAME_BYTES = 1024 * 1024
PREAUTH_SECONDS = 5.0
AUTHENTICATED_IDLE_SECONDS = 65.0
HANDLER_SECONDS = 60.0

script_path, namespace, generation = sys.argv[1:4]
generation_path, capability_path, port_path = sys.argv[4:7]
generation_bytes = generation.encode("ascii")
stopping = threading.Event()
slots = threading.BoundedSemaphore(MAX_CONNECTIONS)
state_lock = threading.Lock()
connections = set()
handlers = set()
threads = set()
server = None

def read_private_value(path):
    try:
        with open(path, "rb") as handle:
            return handle.read(256).strip()
    except OSError:
        return b""

def generation_is_current():
    return hmac.compare_digest(read_private_value(generation_path), generation_bytes)

def current_capability():
    value = read_private_value(capability_path)
    if len(value) != 64:
        return b""
    return value

def request_id(payload):
    try:
        value = json.loads(payload.decode("utf-8")).get("id", "invalid")
    except (UnicodeDecodeError, ValueError, AttributeError):
        return "invalid"
    if not isinstance(value, str) or not value.startswith("req-"):
        return "invalid"
    suffix = value[4:]
    return value if suffix.isdigit() and len(suffix) <= 20 else "invalid"

def send_authentication_failure(connection, payload):
    response = json.dumps({
        "ok": False,
        "id": request_id(payload),
        "error": "authentication failed",
    }, separators=(",", ":")).encode("utf-8") + b"\n"
    try:
        connection.sendall(response)
    except OSError:
        pass

def read_frame(connection, buffered, deadline):
    while b"\n" not in buffered:
        if len(buffered) > MAX_FRAME_BYTES:
            raise ValueError("frame too large")
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise socket.timeout()
        connection.settimeout(remaining)
        chunk = connection.recv(min(65536, MAX_FRAME_BYTES + 1 - len(buffered)))
        if not chunk:
            return None, b""
        buffered += chunk
    frame, buffered = buffered.split(b"\n", 1)
    if len(frame) > MAX_FRAME_BYTES:
        raise ValueError("frame too large")
    return frame.rstrip(b"\r"), buffered

def run_handler(frame):
    process = subprocess.Popen(
        ["/bin/sh", script_path, "_handle", namespace, generation],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        close_fds=True,
    )
    with state_lock:
        handlers.add(process)
    try:
        output, _ = process.communicate(frame + b"\n", timeout=HANDLER_SECONDS)
    except subprocess.TimeoutExpired:
        process.terminate()
        try:
            process.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            process.kill()
        return b""
    finally:
        with state_lock:
            handlers.discard(process)
    return output if len(output) <= MAX_FRAME_BYTES else b""

def serve_connection(connection):
    authenticated = False
    buffered = b""
    try:
        while not stopping.is_set():
            timeout = AUTHENTICATED_IDLE_SECONDS if authenticated else PREAUTH_SECONDS
            frame, buffered = read_frame(connection, buffered, time.monotonic() + timeout)
            if frame is None:
                return
            capability, separator, payload = frame.partition(b"\t")
            expected_capability = current_capability()
            if (not generation_is_current() or separator != b"\t"
                    or not expected_capability
                    or not hmac.compare_digest(capability, expected_capability)):
                send_authentication_failure(connection, payload if separator else frame)
                return
            authenticated = True
            output = run_handler(frame)
            if not output or not generation_is_current() or stopping.is_set():
                return
            connection.sendall(output)
    except (OSError, ValueError, socket.timeout):
        return
    finally:
        with state_lock:
            connections.discard(connection)
            threads.discard(threading.current_thread())
        try:
            connection.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        connection.close()
        slots.release()

def request_stop(_signum, _frame):
    stopping.set()
    try:
        server.close()
    except (AttributeError, OSError):
        pass

def shutdown_all():
    stopping.set()
    with state_lock:
        open_connections = list(connections)
        active_handlers = list(handlers)
        active_threads = list(threads)
    for connection in open_connections:
        try:
            connection.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        connection.close()
    for process in active_handlers:
        process.terminate()
    for process in active_handlers:
        try:
            process.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            process.kill()
    for thread in active_threads:
        thread.join(timeout=1.0)

signal.signal(signal.SIGTERM, request_stop)
signal.signal(signal.SIGINT, request_stop)
server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("127.0.0.1", 0))
server.listen(32)
server.settimeout(1.0)

if not generation_is_current() or not current_capability():
    raise SystemExit(1)
published_port = str(server.getsockname()[1]).encode("ascii") + b"\n"
temporary_port_path = port_path + ".tmp." + str(os.getpid())
descriptor = os.open(temporary_port_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
with os.fdopen(descriptor, "wb") as port_file:
    port_file.write(published_port)
if not generation_is_current():
    os.unlink(temporary_port_path)
    raise SystemExit(1)
os.replace(temporary_port_path, port_path)

try:
    while not stopping.is_set():
        try:
            connection, _ = server.accept()
        except socket.timeout:
            continue
        except OSError:
            break
        if not slots.acquire(blocking=False):
            connection.close()
            continue
        with state_lock:
            connections.add(connection)
        thread = threading.Thread(target=serve_connection, args=(connection,), daemon=True)
        with state_lock:
            threads.add(thread)
        thread.start()
finally:
    try:
        server.close()
    except OSError:
        pass
    shutdown_all()
PY
    LISTENER_PID=$!

    listener_start_attempt=0
    while [ "$listener_start_attempt" -lt 12 ]; do
        if port=$(read_tcp_port) && generation_is_current "$DAEMON_GENERATION"; then
            log_msg "TCP listener ready on 127.0.0.1:$port"
            break
        fi
        if ! kill -0 "$LISTENER_PID" 2>/dev/null; then
            log_msg "Loopback listener failed to start"
            LISTENER_PID=""
            cleanup_generation "$DAEMON_GENERATION"
            exit 1
        fi
        listener_start_attempt=$((listener_start_attempt + 1))
        sleep 1
    done
    if ! read_tcp_port >/dev/null || ! generation_is_current "$DAEMON_GENERATION"; then
        log_msg "Loopback listener start timed out"
        cleanup_generation "$DAEMON_GENERATION"
        exit 1
    fi

    idle_check_tick=0
    while kill -0 "$LISTENER_PID" 2>/dev/null; do
        generation_is_current "$DAEMON_GENERATION" || {
            cleanup_generation "$DAEMON_GENERATION"
            exit 0
        }
        sleep 1
        idle_check_tick=$((idle_check_tick + 1))
        if [ "$idle_check_tick" -ge 60 ]; then
            idle_check_tick=0
            if check_idle_timeout; then
                log_msg "Idle timeout ($MAX_IDLE_SECONDS s) reached, shutting down"
                cleanup_generation "$DAEMON_GENERATION"
                exit 0
            fi
        fi
    done

    LISTENER_PID=""
    log_msg "Loopback listener stopped unexpectedly"
    cleanup_generation "$DAEMON_GENERATION"
    exit 1
}

# --- Lifecycle ---

cleanup_generation() {
    cleanup_target_generation="$1"
    if [ -n "${LISTENER_PID:-}" ]; then
        listener_to_stop="$LISTENER_PID"
        LISTENER_PID=""
        kill "$listener_to_stop" 2>/dev/null || true
        listener_stop_attempt=0
        while [ "$listener_stop_attempt" -lt 3 ] && kill -0 "$listener_to_stop" 2>/dev/null; do
            listener_stop_attempt=$((listener_stop_attempt + 1))
            sleep 1
        done
        if kill -0 "$listener_to_stop" 2>/dev/null; then
            kill -KILL "$listener_to_stop" 2>/dev/null || true
        fi
    fi
    if read_daemon_pid && [ "$stored_generation" = "$cleanup_target_generation" ]; then
        rm -f "$PIDFILE"
    fi
    generation_is_current "$cleanup_target_generation" || return 0
    rm -f "$TCP_PORT_FILE" "$CAPABILITY_FILE" "$LAST_CLIENT_FILE"
    rm -f "$SYNC_DIR"/*.marker 2>/dev/null
    rm -f "$GENERATION_FILE"
    log_msg "Daemon generation stopped"
}

do_start() {
    ensure_runtime_layout || {
        echo "Daemon runtime directory is not private" >&2
        return 1
    }
    if check_pid; then
        if existing_port=$(read_tcp_port) && read_capability >/dev/null; then
            echo "COCXYD_PORT=$existing_port"
            echo "Daemon already running (PID $pid)"
            return 0
        fi
        echo "Daemon is running but its authenticated loopback endpoint is unavailable" >&2
        return 1
    fi
    if read_daemon_pid \
        && process_matches_daemon "$pid" "$stored_generation"; then
        echo "Daemon generation ownership is inconsistent" >&2
        return 1
    fi

    rm -f "$PIDFILE" "$TCP_PORT_FILE" "$CAPABILITY_FILE" "$GENERATION_FILE"
    daemon_generation=$(generate_secret) || {
        echo "Daemon generation failed" >&2
        return 1
    }
    publish_private_value "$GENERATION_FILE" "$daemon_generation" || return 1
    if ! publish_capability; then
        cleanup_generation "$daemon_generation"
        echo "Daemon capability generation failed" >&2
        return 1
    fi

    if [ -f "$LOGFILE" ]; then
        log_size=$(wc -c < "$LOGFILE" 2>/dev/null | tr -d ' ')
        if [ "$log_size" -gt "$MAX_LOG_SIZE" ] 2>/dev/null; then
            mv "$LOGFILE" "${LOGFILE}.1"
        fi
    fi

    if [ -t 0 ] && command -v setsid >/dev/null 2>&1; then
        nohup setsid sh "$0" _run "$NAMESPACE" "$daemon_generation" \
            9<"$GENERATION_FILE" >> "$LOGFILE" 2>&1 &
    else
        nohup sh "$0" _run "$NAMESPACE" "$daemon_generation" \
            9<"$GENERATION_FILE" >> "$LOGFILE" 2>&1 &
    fi
    startup_pid=$!
    if ! process_matches_daemon "$startup_pid" "$daemon_generation"; then
        kill "$startup_pid" 2>/dev/null || true
        cleanup_generation "$daemon_generation"
        echo "Daemon generation ownership could not be established" >&2
        return 1
    fi
    publish_private_value \
        "$PIDFILE" "$startup_pid $daemon_generation" || {
        kill "$startup_pid" 2>/dev/null || true
        cleanup_generation "$daemon_generation"
        return 1
    }

    startup_attempt=0
    while [ "$startup_attempt" -lt 12 ]; do
        if started_port=$(read_tcp_port) \
            && process_matches_daemon "$startup_pid" "$daemon_generation" \
            && generation_is_current "$daemon_generation"; then
            echo "COCXYD_PORT=$started_port"
            echo "Daemon started (PID $startup_pid)"
            return 0
        fi
        if ! process_matches_daemon "$startup_pid" "$daemon_generation"; then
            cleanup_generation "$daemon_generation"
            echo "Daemon failed to start; inspect $LOGFILE" >&2
            return 1
        fi
        startup_attempt=$((startup_attempt + 1))
        sleep 1
    done

    kill "$startup_pid" 2>/dev/null || true
    cleanup_generation "$daemon_generation"
    echo "Daemon start timed out; inspect $LOGFILE" >&2
    return 1
}

do_stop() {
    ensure_runtime_layout || {
        echo "Daemon runtime directory is not private" >&2
        return 1
    }
    if ! check_pid; then
        if stale_generation=$(read_generation); then
            cleanup_generation "$stale_generation"
        fi
        echo "Daemon not running"
        return 0
    fi

    target_pid="$pid"
    target_generation="$stored_generation"
    generation_is_current "$target_generation" || {
        echo "Daemon generation changed before stop" >&2
        return 1
    }
    rm -f "$CAPABILITY_FILE" "$TCP_PORT_FILE"
    if ! kill "$target_pid" 2>/dev/null; then
        echo "Daemon could not be stopped" >&2
        return 1
    fi
    stop_attempt=0
    while [ "$stop_attempt" -lt 5 ] \
        && process_matches_daemon "$target_pid" "$target_generation"; do
        stop_attempt=$((stop_attempt + 1))
        sleep 1
    done
    if process_matches_daemon "$target_pid" "$target_generation"; then
        kill -KILL "$target_pid" 2>/dev/null || true
        sleep 1
    fi
    if process_matches_daemon "$target_pid" "$target_generation"; then
        echo "Daemon termination could not be confirmed" >&2
        return 1
    fi
    cleanup_generation "$target_generation"
    echo "Daemon stopped"
}

do_status() {
    ensure_runtime_layout || {
        printf '{"ok":false,"error":"daemon runtime directory is not private"}\n'
        return
    }
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
    ensure_runtime_layout || {
        printf '{"ok":false,"error":"daemon runtime directory is not private"}\n'
        return
    }
    if check_pid; then
        printf '{"ok":true,"data":{"pong":true}}\n'
    else
        printf '{"ok":false,"error":"daemon not running"}\n'
    fi
}

# --- Entry Point ---

case "${1:-help}" in
    --version)
        printf '%s\n' "$COCXYD_VERSION"
        ;;
    start|stop|status|ping)
        configure_namespace "${2:-}" || {
            echo "A 32-character lowercase hexadecimal profile namespace is required" >&2
            exit 2
        }
        case "$1" in
            start) run_with_lifecycle_lock do_start ;;
            stop) run_with_lifecycle_lock do_stop ;;
            status) do_status ;;
            ping) do_ping ;;
        esac
        ;;
    _run|_handle)
        configure_namespace "${2:-}" || exit 2
        case "$1" in
            _run) run_daemon "${3:-}" ;;
            _handle) handle_tcp_connection "${3:-}" ;;
        esac
        ;;
    help|*)
        echo "cocxyd.sh v$COCXYD_VERSION — Cocxy remote daemon"
        echo "Usage: $0 {--version|start|stop|status|ping} <profile-namespace>"
        ;;
esac
