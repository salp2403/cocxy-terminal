# Copyright (c) 2026 Said Arturo Lopez. MIT License.
# Minimal manual shell integration for bash.
#
# Design notes
# ============
#
# This script provides OSC 7 (cwd reporting) and OSC 133 (semantic prompt
# marks) so Cocxy Terminal can track shell state without polling. It is
# designed to coexist with full-featured prompt frameworks like
# bash-it, oh-my-bash and Liquidprompt by following two strict rules:
#
#   1. NEVER mutate $PS1, $PS2, $PROMPT or any other prompt variable.
#      Frameworks own those — touching them breaks their renderers,
#      width calculators and segment caches in ways that surface as
#      "bad math expression" or "unbound variable" errors because those
#      frameworks evaluate prompt fragments via (( )) or [[ ]].
#
#   2. NEVER use a local variable named `status`. While bash does not
#      enforce a read-only `status` like zsh, the symmetry with the zsh
#      integration script keeps the two implementations consistent.
#
# OSC 133 marks are emitted directly to the TTY via `printf` from the
# precmd / preexec hooks instead of being embedded in PS1. This is the
# same approach Ghostty uses and avoids every prompt-machinery
# interaction.
#
# Known limitation: PS2 continuation prompts
# ------------------------------------------
# Multi-line commands (backslash continuation, open strings, heredocs)
# show the `$PS2` prompt, not `$PS1`. Because rule 1 above forbids
# mutating `$PS2`, no OSC 133;A mark is emitted for continuation lines.
# In practice this means the IDE click-to-position feature does not
# activate while typing a continuation line — the host does not know a
# prompt is visible there. A future iteration may add an opt-in wrap
# of `$PS2` guarded by a `COCXY_SHELL_FEATURES=*ps2*` flag for users
# who know their framework leaves PS2 alone. Do not enable this by
# default: some bash frameworks do mirror PS2 through the same layout
# machinery they use for PS1, and the wrap would regress them the way
# the PS1 wrap regressed Prezto/YADR before v0.1.53.

[[ "$-" == *i* ]] || return 0

if [[ -n "${_COCXY_BASH_INTEGRATION_LOADED:-}" ]]; then
  return 0
fi
_COCXY_BASH_INTEGRATION_LOADED=1

_COCXY_EXECUTING=0
_COCXY_PREEXEC_FIRED=0
_COCXY_LAST_REPORTED_CWD=""

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

__cocxy_precmd() {
  # Capture $? FIRST so it reports the user's last command exit status,
  # not the success status of any helper we run inside this function.
  #
  # NOTE: do NOT name this `status` (see Design notes at the top).
  local _cocxy_last_status=$?

  if [[ "$_COCXY_EXECUTING" == "1" ]]; then
    builtin printf '\e]133;D;%s\a' "$_cocxy_last_status"
    _COCXY_EXECUTING=0
  fi
  _COCXY_PREEXEC_FIRED=0

  __cocxy_report_pwd

  if [[ "${COCXY_SHELL_FEATURES:-}" == *title* ]]; then
    builtin printf '\e]2;%s\a' "${PWD/#$HOME/~}"
  fi

  # Emit OSC 133;A directly to the TTY so Cocxy can mark the start of
  # the prompt without modifying $PS1. Modifying $PS1 would interact
  # with the user's prompt framework (bash-it, oh-my-bash, Liquidprompt)
  # and break their renderers — see Design notes at the top.
  builtin printf '\e]133;A\a'
}

__cocxy_preexec() {
  # Guard: fire only once per command (DEBUG trap fires for each
  # simple command in a pipeline/compound statement).
  if [[ "$_COCXY_PREEXEC_FIRED" == "1" ]]; then
    return
  fi
  _COCXY_PREEXEC_FIRED=1

  local command_text="$1"

  if [[ "${COCXY_SHELL_FEATURES:-}" == *title* && -n "$command_text" ]]; then
    builtin printf '\e]2;%s\a' "${command_text//[$'\x00'-$'\x1f']/}"
  fi

  # OSC 133;B marks the end of the prompt / start of the command.
  # The host's CommandDurationTracker and cocxycore's semantic lexer
  # both listen for ;B (not ;C) to emit `commandStarted`, which drives
  # the running-command state, duration tracking and exit-code pill
  # in the status bar. Without ;B here, bash sessions show no
  # "running" state and no duration for any command — only fish worked
  # before this line because its integration already emitted both.
  builtin printf '\e]133;B\a'
  # OSC 133;C marks that the command is actually being executed.
  # Emitted right after ;B so hosts that treat them as a pair (or that
  # prefer ;C over ;B) both see a consistent signal.
  builtin printf '\e]133;C\a'
  _COCXY_EXECUTING=1
}

__cocxy_debug_trap() {
  local command_text="${BASH_COMMAND:-}"

  case "$command_text" in
    __cocxy_precmd*|__cocxy_preexec*|__cocxy_debug_trap*|__cocxy_report_pwd*|trap*DEBUG*|"")
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
