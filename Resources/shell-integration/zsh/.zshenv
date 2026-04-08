# Copyright (c) 2026 Said Arturo Lopez. MIT License.
# Cocxy Terminal zsh bootstrap for shell integration.

# Restore the user's original ZDOTDIR as early as possible so the rest of zsh's
# startup sequence uses the expected configuration tree.
if [[ -n "${COCXY_ZSH_ORIG_ZDOTDIR+set}" ]]; then
    export ZDOTDIR="$COCXY_ZSH_ORIG_ZDOTDIR"
    unset COCXY_ZSH_ORIG_ZDOTDIR
else
    unset ZDOTDIR
fi

# Source the user's own .zshenv first. We intentionally mirror zsh's default
# behavior: unreadable files are ignored silently.
typeset _cocxy_user_zshenv="${ZDOTDIR-$HOME}/.zshenv"
[[ ! -r "$_cocxy_user_zshenv" ]] || source "$_cocxy_user_zshenv"
unset _cocxy_user_zshenv

if [[ -o interactive ]]; then
    typeset _cocxy_integration="${${(%):-%x}:A:h}/cocxy-integration"
    [[ ! -r "$_cocxy_integration" ]] || source "$_cocxy_integration"
    unset _cocxy_integration
fi
