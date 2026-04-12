#!/bin/bash
# build-app.sh - Build Cocxy Terminal as a macOS .app bundle.
#
# Usage:
#   ./scripts/build-app.sh          # Debug build
#   ./scripts/build-app.sh release  # Release build (optimized)
#
# Output: build/CocxyTerminal.app
#
# Copyright (c) 2026 Said Arturo Lopez. MIT License.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_MODE="${1:-debug}"
APP_NAME="CocxyTerminal"
BUNDLE_NAME="Cocxy Terminal"

# Determine build configuration.
if [ "$BUILD_MODE" = "release" ]; then
    SWIFT_FLAGS="-c release"
    BUILD_DIR="${PROJECT_ROOT}/.build/arm64-apple-macosx/release"
else
    SWIFT_FLAGS=""
    BUILD_DIR="${PROJECT_ROOT}/.build/arm64-apple-macosx/debug"
fi

OUTPUT_DIR="${PROJECT_ROOT}/build"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "==> Building ${BUNDLE_NAME} (${BUILD_MODE})..."

# Step 1: Build the Swift package.
cd "${PROJECT_ROOT}"
swift build ${SWIFT_FLAGS} 2>&1 | tail -3

# Verify binary exists.
if [ ! -f "${BUILD_DIR}/${APP_NAME}" ]; then
    echo "ERROR: Binary not found at ${BUILD_DIR}/${APP_NAME}"
    exit 1
fi

# Step 2: Create .app bundle structure.
echo "==> Creating app bundle..."
rm -rf "${APP_BUNDLE}"
FRAMEWORKS="${CONTENTS}/Frameworks"
mkdir -p "${MACOS}"
mkdir -p "${RESOURCES}"
mkdir -p "${FRAMEWORKS}"

# Step 3: Copy binary.
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS}/${APP_NAME}"

# Step 3b: Copy Sparkle.framework into bundle.
SPARKLE_FW=$(find "${PROJECT_ROOT}/.build/artifacts" -name "Sparkle.framework" -path "*/macos-*" -type d 2>/dev/null | head -1)
if [ -z "${SPARKLE_FW}" ]; then
    SPARKLE_FW=$(find "${PROJECT_ROOT}/.build" -name "Sparkle.framework" -type d 2>/dev/null | head -1)
fi
if [ -n "${SPARKLE_FW}" ]; then
    cp -R "${SPARKLE_FW}" "${FRAMEWORKS}/"
    echo "    Sparkle.framework: ${FRAMEWORKS}/Sparkle.framework"
fi

# Step 3c: Set rpath for Sparkle.
install_name_tool -add_rpath @executable_path/../Frameworks "${MACOS}/${APP_NAME}" 2>/dev/null || true

# Step 4: Copy Info.plist.
if [ -f "${PROJECT_ROOT}/Resources/Info.plist" ]; then
    cp "${PROJECT_ROOT}/Resources/Info.plist" "${CONTENTS}/Info.plist"
else
    echo "WARNING: Info.plist not found, bundle may not work correctly"
fi

# Step 4b: Copy app icon assets.
for icon_file in AppIcon.png; do
    if [ -f "${PROJECT_ROOT}/Resources/${icon_file}" ]; then
        cp "${PROJECT_ROOT}/Resources/${icon_file}" "${RESOURCES}/${icon_file}"
    fi
done

# Step 5: Copy default config files.
if [ -d "${PROJECT_ROOT}/Resources/defaults" ]; then
    cp -R "${PROJECT_ROOT}/Resources/defaults" "${RESOURCES}/defaults"
fi

# Step 6: Copy theme files.
if [ -d "${PROJECT_ROOT}/Resources/Themes" ]; then
    cp -R "${PROJECT_ROOT}/Resources/Themes" "${RESOURCES}/Themes"
fi

# Step 6b: Copy notification sound files.
if [ -d "${PROJECT_ROOT}/Resources/Sounds" ]; then
    cp -R "${PROJECT_ROOT}/Resources/Sounds" "${RESOURCES}/Sounds"
fi

# Step 6c: Copy shell integration scripts.
if [ -d "${PROJECT_ROOT}/Resources/shell-integration" ]; then
    cp -R "${PROJECT_ROOT}/Resources/shell-integration" "${RESOURCES}/shell-integration"
fi

# Step 6d: Copy bundled terminal fonts.
if [ -d "${PROJECT_ROOT}/Resources/Fonts" ]; then
    cp -R "${PROJECT_ROOT}/Resources/Fonts" "${RESOURCES}/Fonts"
fi

# Step 6e: Copy markdown preview resources (Mermaid, KaTeX).
if [ -d "${PROJECT_ROOT}/Resources/Markdown" ]; then
    cp -R "${PROJECT_ROOT}/Resources/Markdown" "${RESOURCES}/Markdown"
fi

# Step 7: Also build the CLI companion and place it in Resources.
echo "==> Building CLI companion..."
swift build --target cocxy ${SWIFT_FLAGS} 2>&1 | tail -1
if [ -f "${BUILD_DIR}/cocxy" ]; then
    cp "${BUILD_DIR}/cocxy" "${RESOURCES}/cocxy"
    echo "    CLI companion: ${RESOURCES}/cocxy"
fi

# Step 8: Ad-hoc code sign (required for local execution on modern macOS).
echo "==> Signing app bundle (ad-hoc)..."
codesign --force --deep --sign - "${APP_BUNDLE}" 2>/dev/null || true

# Step 9: Print summary.
echo ""
echo "==> Build complete!"
echo "    App: ${APP_BUNDLE}"
echo "    Binary: ${MACOS}/${APP_NAME}"
echo "    Mode: ${BUILD_MODE}"
echo ""
echo "    To run: open ${APP_BUNDLE}"
echo "    To install: cp -R ${APP_BUNDLE} /Applications/"
