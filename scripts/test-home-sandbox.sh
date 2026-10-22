#!/usr/bin/env bash
# Sourced by the test runners: tests get a private home directory and the real
# one is checked afterwards, so a run that leaves Cocxy state in the user's
# account fails.
#
# Foundation ignores HOME on macOS; CFFIXED_USER_HOME is what moves
# NSHomeDirectory(), homeDirectoryForCurrentUser and "~" expansion. HOME is set
# as well for the shells, git and interpreters that tests launch. cfprefsd
# ignores both, so preference domains are checked by listing files.

cocxy_test_home_begin() {
  if [[ -n "${COCXY_TEST_HOME:-}" ]]; then
    return 0
  fi
  cocxy_test_home_real="${HOME:?HOME must name the real home to guard it}"
  # Short on purpose: SSH control sockets live under the home and a Unix
  # socket path must fit in 104 bytes, which a TMPDIR-based home exceeds.
  cocxy_test_home_state="$(mktemp -d /tmp/cxh.XXXXXX)"
  mkdir "$cocxy_test_home_state/home"
  # Keychain Services looks for the user's file keychains under the home and
  # blocks on a dialog when they are missing, so the private home links them.
  if [[ -d "$cocxy_test_home_real/Library/Keychains" ]]; then
    mkdir "$cocxy_test_home_state/home/Library"
    ln -s "$cocxy_test_home_real/Library/Keychains" "$cocxy_test_home_state/home/Library/Keychains"
  fi
  cocxy_test_home_preferences > "$cocxy_test_home_state/preferences.before"
  cocxy_test_home_owned_preferences > "$cocxy_test_home_state/owned-preferences.before"
  cocxy_test_home_config > "$cocxy_test_home_state/config.before"
  export COCXY_TEST_HOME="$cocxy_test_home_state/home"
  export CFFIXED_USER_HOME="$COCXY_TEST_HOME"
  export HOME="$COCXY_TEST_HOME"
}

cocxy_test_home_preferences() {
  local directory="$cocxy_test_home_real/Library/Preferences"
  [[ -d "$directory" ]] || return 0
  # cfprefsd writes through temporary siblings; only settled domains count.
  # macOS services create com.apple.* domains at any time, and AppKit saves
  # window frames into the test host's own domain, which a fresh machine does
  # not have yet; neither is state a test left in the user's account.
  ls -1A "$directory" \
    | { grep '\.plist$' || true; } \
    | { grep -Ev '^(com\.apple\..*|swiftpm-testing-helper\.plist)$' || true; } \
    | LC_ALL=C sort
}

# Other apps rewrite their own domains during a long run, so contents are only
# compared for the domains that belong to Cocxy.
cocxy_test_home_owned_preferences() {
  local directory="$cocxy_test_home_real/Library/Preferences"
  [[ -d "$directory" ]] || return 0
  { find "$directory" -maxdepth 1 -iname '*cocxy*.plist' -print0 \
      | xargs -0 stat -f '%m %z %N' 2>/dev/null || true; } | LC_ALL=C sort
}

cocxy_test_home_config() {
  local directory="$cocxy_test_home_real/.config/cocxy"
  [[ -d "$directory" ]] || return 0
  # A running app may delete entries between find and stat.
  { find "$directory" -print0 | xargs -0 stat -f '%m %z %N' 2>/dev/null || true; } | LC_ALL=C sort
}

# Every Cocxy bundle runs an executable named CocxyTerminal. Matching the
# process name, not the command line, keeps test processes and shells that
# merely mention the app from counting as a running app.
cocxy_test_home_app_name='CocxyTerminal'

cocxy_test_home_app_running() {
  pgrep -x "$cocxy_test_home_app_name" >/dev/null 2>&1
}

# Verifies the real home and removes the private one. Only the runner that
# created the sandbox checks it; nested runners share it.
cocxy_test_home_end() {
  [[ -n "${cocxy_test_home_state:-}" ]] || return 0
  local status=0
  local created
  created="$(LC_ALL=C comm -13 "$cocxy_test_home_state/preferences.before" \
    <(cocxy_test_home_preferences))"
  if [[ -n "$created" ]]; then
    echo "error: the test run created preference files in $cocxy_test_home_real/Library/Preferences:" >&2
    printf '%s\n' "$created" | head -20 >&2 || true
    status=1
  fi
  if ! cocxy_test_home_owned_preferences | cmp -s "$cocxy_test_home_state/owned-preferences.before" -; then
    if cocxy_test_home_app_running; then
      echo "warning: Cocxy preference files changed while a Cocxy app was running; the change is not attributed to the tests." >&2
    else
      echo "error: the test run changed Cocxy preference files in $cocxy_test_home_real/Library/Preferences:" >&2
      cocxy_test_home_owned_preferences | diff "$cocxy_test_home_state/owned-preferences.before" - | head -20 >&2 || true
      status=1
    fi
  fi
  if ! cocxy_test_home_config | cmp -s "$cocxy_test_home_state/config.before" -; then
    if cocxy_test_home_app_running; then
      echo "warning: $cocxy_test_home_real/.config/cocxy changed while a Cocxy app was running; the change is not attributed to the tests." >&2
    else
      echo "error: the test run changed $cocxy_test_home_real/.config/cocxy:" >&2
      cocxy_test_home_config | diff "$cocxy_test_home_state/config.before" - | head -20 >&2 || true
      status=1
    fi
  fi
  cocxy_test_home_cleanup
  return "$status"
}

cocxy_test_home_cleanup() {
  [[ -n "${cocxy_test_home_state:-}" ]] || return 0
  # Xcode mounts the Metal toolchain it downloads under the home in use, and a
  # mounted volume cannot be removed, so detach anything mounted in the sandbox.
  local real_state mount_point
  real_state="$(cd "$cocxy_test_home_state" 2>/dev/null && pwd -P)" || real_state="$cocxy_test_home_state"
  while IFS= read -r mount_point; do
    hdiutil detach -force "$mount_point" >/dev/null 2>&1 || true
  done < <(mount | awk -v root="$real_state/" -v alias="$cocxy_test_home_state/" \
    '{ for (i = 3; i <= NF; i++) if ($(i - 1) == "on") { if (index($i, root) == 1 || index($i, alias) == 1) print $i; break } }')
  rm -rf "$cocxy_test_home_state" || echo "warning: could not remove the test home $cocxy_test_home_state" >&2
  cocxy_test_home_state=""
}
