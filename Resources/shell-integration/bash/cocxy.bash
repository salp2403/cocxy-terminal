# Copyright (c) 2026 Said Arturo Lopez. MIT License.
# Minimal manual shell integration for bash.

[[ "$-" == *i* ]] || return 0

if [[ -n "${_COCXY_BASH_INTEGRATION_LOADED:-}" ]]; then
  return 0
fi
export _COCXY_BASH_INTEGRATION_LOADED=1

_COCXY_EXECUTING=0
_COCXY_LAST_REPORTED_CWD=""
_COCXY_SAVED_PS1="$PS1"
_COCXY_SAVED_PS2="$PS2"
_COCXY_MARKED_PS1=""
_COCXY_MARKED_PS2=""

__cocxy_report_pwd() {
  if [[ "$_COCXY_LAST_REPORTED_CWD" != "$PWD" ]]; then
    _COCXY_LAST_REPORTED_CWD="$PWD"
    builtin printf '\e]7;%s\a' "$PWD"
  fi
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

  __cocxy_report_pwd

  if [[ "${COCXY_SHELL_FEATURES:-}" == *title* ]]; then
    builtin printf '\e]2;%s\a' "${PWD/#$HOME/~}"
  fi

  __cocxy_wrap_prompts
}

__cocxy_preexec() {
  local command_text="$1"

  __cocxy_restore_prompts

  if [[ "${COCXY_SHELL_FEATURES:-}" == *title* && -n "$command_text" ]]; then
    builtin printf '\e]2;%s\a' "${command_text//[$'\x00'-$'\x1f']/}"
  fi

  builtin printf '\e]133;B\a'
  builtin printf '\e]133;C\a'
  _COCXY_EXECUTING=1
}

trap '__cocxy_precmd' DEBUG
PROMPT_COMMAND='__cocxy_precmd'
