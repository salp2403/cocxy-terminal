# Copyright (c) 2026 Said Arturo Lopez. MIT License.
# Minimal manual shell integration for fish.

status is-interactive; or return

if set -q __cocxy_fish_integration_loaded
    return
end
set -g __cocxy_fish_integration_loaded 1

set -g __cocxy_fish_executing 0
set -g __cocxy_fish_last_reported_cwd ""

function __cocxy_fish_print
    if test -w /dev/tty
        printf '%b' "$argv[1]" > /dev/tty
    else
        printf '%b' "$argv[1]"
    end
end

function __cocxy_fish_report_pwd --on-variable PWD
    if test "$__cocxy_fish_last_reported_cwd" != "$PWD"
        set -g __cocxy_fish_last_reported_cwd "$PWD"
        set -l encoded_pwd (string escape --style=url -- "$PWD")
        __cocxy_fish_print "\e]7;file://$encoded_pwd\a"
    end
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

    if string match -q '*title*' -- "$COCXY_SHELL_FEATURES"
        if test -n "$command_text"
            __cocxy_fish_print "\e]2;$command_text\a"
        end
    end

    __cocxy_fish_print "\e]133;B\a"
    __cocxy_fish_print "\e]133;C\a"
    set -g __cocxy_fish_executing 1
end

__cocxy_fish_report_pwd
