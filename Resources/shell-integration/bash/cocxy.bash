# Copyright (c) 2026 Said Arturo Lopez. MIT License.
# Minimal manual shell integration for bash.

[[ "$-" == *i* ]] || return 0

if [[ -n "${_COCXY_BASH_INTEGRATION_LOADED:-}" ]]; then
  return 0
fi
_COCXY_BASH_INTEGRATION_LOADED=1

_COCXY_EXECUTING=0
_COCXY_PREEXEC_FIRED=0
_COCXY_LAST_REPORTED_CWD=""
_COCXY_SAVED_PS1="$PS1"
_COCXY_SAVED_PS2="$PS2"
_COCXY_MARKED_PS1=""
_COCXY_MARKED_PS2=""
# Preserve PROMPT_COMMAND as array (Bash 5.1+) or string (older).
if [[ ${#PROMPT_COMMAND[@]} -gt 1 ]] 2>/dev/null; then
  _COCXY_OLD_PROMPT_COMMAND=("${PROMPT_COMMAND[@]}")
  _COCXY_PC_IS_ARRAY=1
else
  _COCXY_OLD_PROMPT_COMMAND="${PROMPT_COMMAND:-}"
  _COCXY_PC_IS_ARRAY=0
fi
_COCXY_DEBUG_TRAP_RAW="$(trap -p DEBUG)"

if [[ "$_COCXY_DEBUG_TRAP_RAW" =~ ^trap\ --\ \'(.*)\'\ DEBUG$ ]]; then
  _COCXY_OLD_DEBUG_TRAP="${BASH_REMATCH[1]}"
else
  _COCXY_OLD_DEBUG_TRAP=""
fi
unset _COCXY_DEBUG_TRAP_RAW

__cocxy_report_pwd() {
  if [[ "$_COCXY_LAST_REPORTED_CWD" != "$PWD" ]]; then
    _COCXY_LAST_REPORTED_CWD="$PWD"
    builtin printf '\e]7;file://%s\a' "$(__cocxy_uri_encode_path "$PWD")"
  fi
}

__cocxy_uri_encode_path() {
  local input="$1"
  local output=""
  local i ch
  local LC_ALL=C

  for (( i = 0; i < ${#input}; i++ )); do
    ch="${input:i:1}"
    case "$ch" in
      [a-zA-Z0-9.~_/-])
        output+="$ch"
        ;;
      *)
        printf -v output '%s%%%02X' "$output" "'$ch"
        ;;
    esac
  done

  builtin printf '%s' "$output"
}

__cocxy_wrap_prompts() {
  if [[ -n "$_COCXY_MARKED_PS1" && "$PS1" == "$_COCXY_MARKED_PS1" ]]; then
    PS1="$_COCXY_SAVED_PS1"
    PS2="$_COCXY_SAVED_PS2"
  else
    _COCXY_SAVED_PS1="$PS1"
    _COCXY_SAVED_PS2="$PS2"
  fi

  local prompt_start='\[\e]133;A\a\]'
  PS1="${prompt_start}${_COCXY_SAVED_PS1}"
  PS2="${prompt_start}${_COCXY_SAVED_PS2}"
  _COCXY_MARKED_PS1="$PS1"
  _COCXY_MARKED_PS2="$PS2"
}

__cocxy_restore_prompts() {
  if [[ -n "$_COCXY_MARKED_PS1" && "$PS1" == "$_COCXY_MARKED_PS1" ]]; then
    PS1="$_COCXY_SAVED_PS1"
    PS2="$_COCXY_SAVED_PS2"
  fi
}

__cocxy_precmd() {
  local status="$?"

  if [[ "$_COCXY_EXECUTING" == "1" ]]; then
    builtin printf '\e]133;D;%s\a' "$status"
    _COCXY_EXECUTING=0
  fi
  _COCXY_PREEXEC_FIRED=0

  __cocxy_report_pwd

  if [[ "${COCXY_SHELL_FEATURES:-}" == *title* ]]; then
    builtin printf '\e]2;%s\a' "${PWD/#$HOME/~}"
  fi

  __cocxy_wrap_prompts
}

__cocxy_preexec() {
  # Guard: fire only once per command (DEBUG trap fires for each
  # simple command in a pipeline/compound statement).
  if [[ "$_COCXY_PREEXEC_FIRED" == "1" ]]; then
    return
  fi
  _COCXY_PREEXEC_FIRED=1

  local command_text="$1"

  __cocxy_restore_prompts

  if [[ "${COCXY_SHELL_FEATURES:-}" == *title* && -n "$command_text" ]]; then
    builtin printf '\e]2;%s\a' "${command_text//[$'\x00'-$'\x1f']/}"
  fi

  builtin printf '\e]133;B\a'
  builtin printf '\e]133;C\a'
  _COCXY_EXECUTING=1
}

__cocxy_debug_trap() {
  local command_text="${BASH_COMMAND:-}"

  case "$command_text" in
    __cocxy_precmd*|__cocxy_preexec*|__cocxy_debug_trap*|__cocxy_wrap_prompts*|__cocxy_restore_prompts*|__cocxy_report_pwd*|trap*DEBUG*|"")
      ;;
    *)
      __cocxy_preexec "$command_text"
      ;;
  esac

  if [[ -n "${_COCXY_OLD_DEBUG_TRAP:-}" ]]; then
    builtin eval -- "${_COCXY_OLD_DEBUG_TRAP}"
  fi
}

trap '__cocxy_debug_trap' DEBUG
if [[ "$_COCXY_PC_IS_ARRAY" == "1" ]]; then
  PROMPT_COMMAND=('__cocxy_precmd' "${_COCXY_OLD_PROMPT_COMMAND[@]}")
elif [[ -n "$_COCXY_OLD_PROMPT_COMMAND" ]]; then
  PROMPT_COMMAND="__cocxy_precmd; ${_COCXY_OLD_PROMPT_COMMAND}"
else
  PROMPT_COMMAND='__cocxy_precmd'
fi
