# Copyright (c) 2026 Said Arturo Lopez. MIT License.
# Cocxy Terminal bash bootstrap for shell integration.

if [[ -n "${COCXY_BASH_ORIG_HOME+set}" ]]; then
  export HOME="$COCXY_BASH_ORIG_HOME"
  unset COCXY_BASH_ORIG_HOME
fi

# Only source user config and shell integration in interactive mode.
# Non-interactive bash -c commands should not load prompt/hook machinery.
[[ "$-" == *i* ]] || return 0

_cocxy_user_bashrc="${HOME}/.bashrc"
if [[ -r "${_cocxy_user_bashrc}" ]]; then
  # shellcheck source=/dev/null
  source "${_cocxy_user_bashrc}"
fi
unset _cocxy_user_bashrc

_cocxy_integration_file="${BASH_SOURCE[0]%/*}/cocxy.bash"
if [[ -r "${_cocxy_integration_file}" ]]; then
  # shellcheck source=/dev/null
  source "${_cocxy_integration_file}"
fi
unset _cocxy_integration_file
