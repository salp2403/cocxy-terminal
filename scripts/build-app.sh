#!/bin/bash
# build-app.sh - Build Cocxy Terminal as a macOS .app bundle.
#
# Usage:
#   ./scripts/build-app.sh                   # Debug build
#   ./scripts/build-app.sh release           # Release build (optimized)
#   ./scripts/build-app.sh release --install # Build, install, and register Quick Look
#
# Output: build/CocxyTerminal.app
#
# Copyright (c) 2026 Said Arturo Lopez. MIT License.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_MODE="debug"
INSTALL_AFTER_BUILD=0
APP_NAME="CocxyTerminal"
BUNDLE_NAME="Cocxy Terminal"
APP_ENTITLEMENTS="${PROJECT_ROOT}/Resources/CocxyTerminal.entitlements"
QL_ENTITLEMENTS="${PROJECT_ROOT}/QuickLook/CocxyQuickLook.entitlements"

for arg in "$@"; do
    case "$arg" in
        debug|release)
            BUILD_MODE="$arg"
            ;;
        --install|install)
            INSTALL_AFTER_BUILD=1
            ;;
        *)
            echo "ERROR: Unknown argument: $arg"
            echo "Usage: ./scripts/build-app.sh [debug|release] [--install]"
            exit 1
            ;;
    esac
done

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
PLUGINS="${CONTENTS}/PlugIns"

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
mkdir -p "${PLUGINS}"

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

# Step 4: Generate Info.plist from the shared base template.
"${PROJECT_ROOT}/scripts/generate-app-info-plist.sh" "${CONTENTS}/Info.plist" \
    --bundle-name "${BUNDLE_NAME}" \
    --display-name "${BUNDLE_NAME}" \
    --bundle-id "dev.cocxy.terminal" \
    --executable "${APP_NAME}"

# Step 4b: Copy app icon assets.
for icon_file in AppIcon.png; do
    if [ -f "${PROJECT_ROOT}/Resources/${icon_file}" ]; then
        cp "${PROJECT_ROOT}/Resources/${icon_file}" "${RESOURCES}/${icon_file}"
    fi
done

# Step 4c: Copy AppleScript definition if present.
if [ -f "${PROJECT_ROOT}/Resources/CocxyTerminal.sdef" ]; then
    cp "${PROJECT_ROOT}/Resources/CocxyTerminal.sdef" "${RESOURCES}/CocxyTerminal.sdef"
fi

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

# Step 6f: Build and embed the QuickLook extension.
echo "==> Building QuickLook extension..."
QL_APPEX="$("${PROJECT_ROOT}/scripts/build-quicklook-extension.sh" "${BUILD_MODE}")"
cp -R "${QL_APPEX}" "${PLUGINS}/"
codesign --force --sign - --entitlements "${QL_ENTITLEMENTS}" "${PLUGINS}/$(basename "${QL_APPEX}")" >/dev/null
echo "    QuickLook: ${PLUGINS}/$(basename "${QL_APPEX}")"

# Step 7: Also build the CLI companion and place it in Resources.
echo "==> Building CLI companion..."
swift build --target cocxy ${SWIFT_FLAGS} 2>&1 | tail -1
if [ -f "${BUILD_DIR}/cocxy" ]; then
    cp "${BUILD_DIR}/cocxy" "${RESOURCES}/cocxy"
    echo "    CLI companion: ${RESOURCES}/cocxy"
fi

# Step 8: Ad-hoc code sign (required for local execution on modern macOS).
echo "==> Signing app bundle (ad-hoc)..."
codesign --force --sign - --entitlements "${APP_ENTITLEMENTS}" "${APP_BUNDLE}" 2>/dev/null || true

# Step 9: Print summary.
echo ""
echo "==> Build complete!"
echo "    App: ${APP_BUNDLE}"
echo "    Binary: ${MACOS}/${APP_NAME}"
echo "    Mode: ${BUILD_MODE}"
echo ""
echo "    To run: open ${APP_BUNDLE}"
echo "    To install/register Quick Look: ${PROJECT_ROOT}/scripts/install-local-app.sh ${APP_BUNDLE}"

if [ "${INSTALL_AFTER_BUILD}" -eq 1 ]; then
    echo ""
    echo "==> Installing built app into /Applications..."
    "${PROJECT_ROOT}/scripts/install-local-app.sh" "${APP_BUNDLE}"
fi
