#!/usr/bin/env bash
# Sourced by the test runners: tests get a private home directory and the real
# one is checked afterwards, so a run cannot leave state in the user's account.
#
# Foundation ignores HOME on macOS; CFFIXED_USER_HOME is what moves
# NSHomeDirectory(), homeDirectoryForCurrentUser and "~" expansion. HOME is set
# as well for the shells, git and interpreters that tests launch. cfprefsd
# ignores both, so new preference domains are detected by listing files.

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
  cocxy_test_home_config > "$cocxy_test_home_state/config.before"
  export COCXY_TEST_HOME="$cocxy_test_home_state/home"
  export CFFIXED_USER_HOME="$COCXY_TEST_HOME"
  export HOME="$COCXY_TEST_HOME"
}

cocxy_test_home_preferences() {
  local directory="$cocxy_test_home_real/Library/Preferences"
  [[ -d "$directory" ]] || return 0
  # cfprefsd writes through temporary siblings; only settled domains count.
  ls -1 "$directory" | { grep '\.plist$' || true; } | LC_ALL=C sort
}

cocxy_test_home_config() {
  local directory="$cocxy_test_home_real/.config/cocxy"
  [[ -d "$directory" ]] || return 0
  # A running app may delete entries between find and stat.
  { find "$directory" -print0 | xargs -0 stat -f '%m %z %N' 2>/dev/null || true; } | LC_ALL=C sort
}

# Anchored on the app bundle so test processes, whose paths end in
# CocxyTerminalPackageTests.xctest/Contents/MacOS/..., never count as the app.
cocxy_test_home_app_pattern='\.app/Contents/MacOS/CocxyTerminal'

cocxy_test_home_app_running() {
  pgrep -f "$cocxy_test_home_app_pattern" >/dev/null 2>&1
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
  rm -rf "$cocxy_test_home_state"
  cocxy_test_home_state=""
}
