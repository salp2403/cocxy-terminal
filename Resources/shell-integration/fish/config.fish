# Copyright (c) 2026 Said Arturo Lopez. MIT License.
# Cocxy Terminal fish bootstrap for shell integration.

set -l __cocxy_orig_xdg_config_home ""

if set -q COCXY_FISH_ORIG_XDG_CONFIG_HOME
    set __cocxy_orig_xdg_config_home "$COCXY_FISH_ORIG_XDG_CONFIG_HOME"
else if set -q COCXY_FISH_ORIG_HOME
    set __cocxy_orig_xdg_config_home "$COCXY_FISH_ORIG_HOME/.config"
else
    set __cocxy_orig_xdg_config_home "$HOME/.config"
end

set -l __cocxy_user_config "$__cocxy_orig_xdg_config_home/fish/config.fish"
if test -r "$__cocxy_user_config"
    source "$__cocxy_user_config"
end

set -l __cocxy_integration (string join / (status dirname) cocxy.fish)
if test -r "$__cocxy_integration"
    source "$__cocxy_integration"
end

set -e __cocxy_orig_xdg_config_home
set -e __cocxy_user_config
set -e __cocxy_integration
