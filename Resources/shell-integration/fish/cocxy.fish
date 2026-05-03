# Copyright (c) 2026 Said Arturo Lopez. MIT License.
# Minimal manual shell integration for fish.

status is-interactive; or return

if set -q __cocxy_fish_integration_loaded
    return
end
set -g __cocxy_fish_integration_loaded 1

set -g __cocxy_fish_executing 0
set -g __cocxy_fish_last_reported_cwd ""

function __cocxy_fish_wrap_control_sequence
    set -l seq (printf '%b' "$argv[1]")
    if set -q TMUX; and test -n "$TMUX"
        set -l marker (printf '%b' "\e]7770;{\"type\":\"cocxy_shell_multiplexer\",\"name\":\"tmux\"}\a")
        set -l payload "$marker$seq"
        set -l esc (printf '\e')
        set -l escaped (string replace -a "$esc" "$esc$esc" -- "$payload")
        printf '%b%s%b' "\ePtmux;" "$escaped" "\e\\"
    else if set -q STY; and test -n "$STY"
        printf '%b%s%b' "\eP\e]7770;{\"type\":\"cocxy_shell_multiplexer\",\"name\":\"screen\"}\a" "$seq" "\e\\"
    else
        printf '%s' "$seq"
    end
end

function __cocxy_fish_print
    set -l wrapped (__cocxy_fish_wrap_control_sequence "$argv[1]")
    if test -w /dev/tty
        printf '%s' "$wrapped" > /dev/tty
    else
        printf '%s' "$wrapped"
    end
end

function __cocxy_fish_report_pwd --on-variable PWD
    if test "$__cocxy_fish_last_reported_cwd" != "$PWD"
        set -g __cocxy_fish_last_reported_cwd "$PWD"
        set -l encoded_pwd (string escape --style=url -- "$PWD")
        __cocxy_fish_print "\e]7;file://$encoded_pwd\a"
    end
end

function __cocxy_fish_encode_command_payload
    # URL escaping keeps OSC 133;C payload printable; newlines become %0A
    # and literal percent signs become %25.
    set -l encoded_command (string escape --style=url -- "$argv[1]")
    printf 'cocxy-percent-v1:%s' "$encoded_command"
end

function __cocxy_fish_prompt --on-event fish_prompt
    set -l __cocxy_last_status $status
    if test "$__cocxy_fish_executing" = "1"
        __cocxy_fish_print "\e]133;D;$__cocxy_last_status\a"
        set -g __cocxy_fish_executing 0
    end

    __cocxy_fish_report_pwd

    if string match -q '*title*' -- "$COCXY_SHELL_FEATURES"
        set -l title (string replace -- "$HOME" "~" "$PWD")
        __cocxy_fish_print "\e]2;$title\a"
    end

    __cocxy_fish_print "\e]133;A\a"
end

function __cocxy_fish_preexec --on-event fish_preexec
    set -l command_text "$argv[1]"
    set -l sanitized_command (string replace -ra '[[:cntrl:]]' '' -- "$command_text")
    set -l encoded_command ""
    if test -n "$command_text"
        set encoded_command (__cocxy_fish_encode_command_payload "$command_text")
    end

    if string match -q '*title*' -- "$COCXY_SHELL_FEATURES"
        if test -n "$sanitized_command"
            __cocxy_fish_print "\e]2;$sanitized_command\a"
        end
    end

    __cocxy_fish_print "\e]133;B\a"
    if test -n "$encoded_command"
        __cocxy_fish_print "\e]133;C;$encoded_command\a"
    else
        __cocxy_fish_print "\e]133;C\a"
    end
    set -g __cocxy_fish_executing 1
end

__cocxy_fish_report_pwd
