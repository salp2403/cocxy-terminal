#!/bin/bash
# embed-pty-daemon-helper.sh - Stage cocxyd as a signed app-bundled helper.
#
# Usage:
#   ./scripts/embed-pty-daemon-helper.sh <Cocxy.app> <path/to/cocxyd>
#
# Environment:
#   SIGNING_IDENTITY      Codesign identity. Defaults to ad-hoc "-".
#   COCXY_CODESIGN_FLAGS  Extra flags, e.g. "--options runtime --timestamp".
#
# The script keeps a legacy Resources/cocxyd copy for existing smoke tests and
# installs the LaunchServices helper app used by PTYDaemonHelperLocator.

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <Cocxy.app> <path/to/cocxyd>" >&2
    exit 64
fi

APP_BUNDLE="$1"
HELPER_BINARY="$2"

if [ ! -d "$APP_BUNDLE/Contents" ]; then
    echo "error: app bundle not found: $APP_BUNDLE" >&2
    exit 65
fi

if [ ! -x "$HELPER_BINARY" ]; then
    echo "error: helper binary not executable: $HELPER_BINARY" >&2
    exit 66
fi

CONTENTS="$APP_BUNDLE/Contents"
RESOURCES="$CONTENTS/Resources"
LAUNCH_SERVICES="$CONTENTS/Library/LaunchServices"
HELPER_APP="$LAUNCH_SERVICES/cocxyd.app"
HELPER_CONTENTS="$HELPER_APP/Contents"
HELPER_MACOS="$HELPER_CONTENTS/MacOS"
HELPER_PLIST="$HELPER_CONTENTS/Info.plist"
HELPER_EXECUTABLE="$HELPER_MACOS/cocxyd"

APP_PLIST="$CONTENTS/Info.plist"
APP_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP_PLIST")"
APP_SHORT_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP_PLIST")"
APP_BUILD_VERSION="$(plutil -extract CFBundleVersion raw -o - "$APP_PLIST")"

mkdir -p "$RESOURCES" "$HELPER_MACOS"

# Compatibility path for smoke tests, direct manual probing, and older builds.
cp "$HELPER_BINARY" "$RESOURCES/cocxyd"
chmod 755 "$RESOURCES/cocxyd"

cp "$HELPER_BINARY" "$HELPER_EXECUTABLE"
chmod 755 "$HELPER_EXECUTABLE"

cat > "$HELPER_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>cocxyd</string>
    <key>CFBundleIdentifier</key>
    <string>${APP_BUNDLE_ID}.cocxyd</string>
    <key>CFBundleName</key>
    <string>Cocxy PTY Daemon</string>
    <key>CFBundleDisplayName</key>
    <string>Cocxy PTY Daemon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_SHORT_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${APP_BUILD_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

plutil -lint "$HELPER_PLIST" >/dev/null

SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"

if [ -n "${COCXY_CODESIGN_FLAGS:-}" ]; then
    # Intentional word splitting: callers pass codesign flags such as
    # "--options runtime --timestamp" through one environment variable.
    # shellcheck disable=SC2086
    codesign --force --sign "$SIGNING_IDENTITY" ${COCXY_CODESIGN_FLAGS} "$RESOURCES/cocxyd" >/dev/null
    # shellcheck disable=SC2086
    codesign --force --sign "$SIGNING_IDENTITY" ${COCXY_CODESIGN_FLAGS} "$HELPER_APP" >/dev/null
else
    codesign --force --sign "$SIGNING_IDENTITY" "$RESOURCES/cocxyd" >/dev/null
    codesign --force --sign "$SIGNING_IDENTITY" "$HELPER_APP" >/dev/null
fi

echo "    PTY daemon helper: $RESOURCES/cocxyd"
echo "    PTY daemon helper app: $HELPER_APP"
