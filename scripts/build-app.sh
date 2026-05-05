#!/bin/bash
# build-app.sh - Build Cocxy Terminal as a macOS .app bundle.
#
# Usage:
#   ./scripts/build-app.sh                   # Debug build
#   ./scripts/build-app.sh release           # Release build (optimized)
#   ./scripts/build-app.sh release --version 0.1.86
#   ./scripts/build-app.sh release --install # Build, install, and register Quick Look
#
# Output: build/CocxyTerminal.app
#
# Copyright (c) 2026 Said Arturo Lopez. MIT License.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_MODE="debug"
INSTALL_AFTER_BUILD=0
VERSION_OVERRIDE=""
APP_NAME="CocxyTerminal"
BUNDLE_NAME="Cocxy Terminal"
APP_ENTITLEMENTS="${PROJECT_ROOT}/Resources/CocxyTerminal.entitlements"
QL_ENTITLEMENTS="${PROJECT_ROOT}/QuickLook/CocxyQuickLook.entitlements"

while [ $# -gt 0 ]; do
    case "$1" in
        debug|release)
            BUILD_MODE="$1"
            shift
            ;;
        --install|install)
            INSTALL_AFTER_BUILD=1
            shift
            ;;
        --version)
            if [ $# -lt 2 ]; then
                echo "ERROR: --version requires a value"
                echo "Usage: ./scripts/build-app.sh [debug|release] [--version X.Y.Z] [--install]"
                exit 1
            fi
            VERSION_OVERRIDE="${2#v}"
            shift 2
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            echo "Usage: ./scripts/build-app.sh [debug|release] [--version X.Y.Z] [--install]"
            exit 1
            ;;
    esac
done

if [ -n "${VERSION_OVERRIDE}" ] && ! [[ "${VERSION_OVERRIDE}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: Invalid --version '${VERSION_OVERRIDE}' (expected semver X.Y.Z)"
    exit 1
fi

# Determine build configuration.
if [ "$BUILD_MODE" = "release" ]; then
    SWIFT_FLAGS="-c release"
    BUILD_DIR="${PROJECT_ROOT}/.build/arm64-apple-macosx/release"
else
    SWIFT_FLAGS=""
    BUILD_DIR="${PROJECT_ROOT}/.build/arm64-apple-macosx/debug"
fi
APPINTENTS_WORK_DIR="${BUILD_DIR}/AppIntents"
APPINTENTS_CONST_VALUES="${APPINTENTS_WORK_DIR}/${APP_NAME}.swiftconstvalues"
APPINTENTS_PROTOCOL_LIST="${APPINTENTS_WORK_DIR}/protocols.json"
APPINTENTS_SOURCE_LIST="${APPINTENTS_WORK_DIR}/sources.list"
APPINTENTS_DEPLOYMENT_TARGET="14.0"

OUTPUT_DIR="${PROJECT_ROOT}/build"
APP_BUNDLE="${OUTPUT_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
PLUGINS="${CONTENTS}/PlugIns"
LAUNCH_SERVICES="${CONTENTS}/Library/LaunchServices"

echo "==> Building ${BUNDLE_NAME} (${BUILD_MODE})..."

# Step 1: Build the Swift package.
cd "${PROJECT_ROOT}"
mkdir -p "${APPINTENTS_WORK_DIR}"
TOOLCHAIN_USR="$(cd "$(dirname "$(xcrun -find swiftc)")/.." && pwd)"
TOOLCHAIN_DIR="$(cd "${TOOLCHAIN_USR}/.." && pwd)"
APPINTENTS_PROTOCOLS_JSON="${TOOLCHAIN_USR}/share/swift/SwiftConstantValues/AppIntents.json"
if [ ! -f "${APPINTENTS_PROTOCOLS_JSON}" ]; then
    echo "ERROR: App Intents protocol list not found at ${APPINTENTS_PROTOCOLS_JSON}"
    exit 1
fi
plutil -extract constValueProtocols json -o "${APPINTENTS_PROTOCOL_LIST}" "${APPINTENTS_PROTOCOLS_JSON}"
printf '%s\n' "${PROJECT_ROOT}/Sources/App/Shortcuts/CocxyShortcuts.swift" > "${APPINTENTS_SOURCE_LIST}"

swift build --product "${APP_NAME}" ${SWIFT_FLAGS} \
    -Xswiftc -emit-const-values-path \
    -Xswiftc "${APPINTENTS_CONST_VALUES}" \
    -Xswiftc -Xfrontend \
    -Xswiftc -const-gather-protocols-file \
    -Xswiftc -Xfrontend \
    -Xswiftc "${APPINTENTS_PROTOCOL_LIST}" \
    2>&1 | tail -3

# Verify binary exists.
if [ ! -f "${BUILD_DIR}/${APP_NAME}" ]; then
    echo "ERROR: Binary not found at ${BUILD_DIR}/${APP_NAME}"
    exit 1
fi
if [ ! -s "${APPINTENTS_CONST_VALUES}" ]; then
    echo "ERROR: App Intents const values not generated at ${APPINTENTS_CONST_VALUES}"
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
mkdir -p "${LAUNCH_SERVICES}"

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
PLIST_ARGS=(
    "${CONTENTS}/Info.plist"
    --bundle-name "${BUNDLE_NAME}"
    --display-name "${BUNDLE_NAME}"
    --bundle-id "dev.cocxy.terminal"
    --executable "${APP_NAME}"
)
if [ -n "${VERSION_OVERRIDE}" ]; then
    PLIST_ARGS+=(--version "${VERSION_OVERRIDE}" --short-version "${VERSION_OVERRIDE}")
fi
"${PROJECT_ROOT}/scripts/generate-app-info-plist.sh" "${PLIST_ARGS[@]}"

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

# Step 4d: Generate Shortcuts/App Intents metadata. SwiftPM compiles the
# intents, while LaunchServices needs this metadata bundle to discover actions.
echo "==> Generating Shortcuts metadata..."
SDK_ROOT="$(xcrun --sdk macosx --show-sdk-path)"
XCODE_BUILD_VERSION="$(xcodebuild -version | awk '/Build version/ { print $3; exit }')"
TARGET_TRIPLE="$(uname -m)-apple-macosx${APPINTENTS_DEPLOYMENT_TARGET}"
printf '%s\n' "${APPINTENTS_CONST_VALUES}" > "${APPINTENTS_WORK_DIR}/constvalues.list"
xcrun appintentsmetadataprocessor \
    --output "${RESOURCES}" \
    --toolchain-dir "${TOOLCHAIN_DIR}" \
    --module-name "${APP_NAME}" \
    --sdk-root "${SDK_ROOT}" \
    --xcode-version "${XCODE_BUILD_VERSION}" \
    --platform-family macOS \
    --deployment-target "${APPINTENTS_DEPLOYMENT_TARGET}" \
    --target-triple "${TARGET_TRIPLE}" \
    --source-file-list "${APPINTENTS_SOURCE_LIST}" \
    --swift-const-vals-list "${APPINTENTS_WORK_DIR}/constvalues.list" \
    --force-metadata-output \
    --no-app-shortcuts-localization \
    2>&1 | tail -3
if [ ! -s "${RESOURCES}/Metadata.appintents/extract.actionsdata" ]; then
    echo "ERROR: Shortcuts metadata was not generated in ${RESOURCES}/Metadata.appintents"
    exit 1
fi
echo "    Shortcuts metadata: ${RESOURCES}/Metadata.appintents"

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

# Step 6c: Copy localization bundles.
if [ -d "${PROJECT_ROOT}/Resources/Localization" ]; then
    find "${PROJECT_ROOT}/Resources/Localization" -maxdepth 1 -type d -name "*.lproj" -exec cp -R {} "${RESOURCES}/" \;
fi

# Step 6d: Copy shell integration scripts.
if [ -d "${PROJECT_ROOT}/Resources/shell-integration" ]; then
    cp -R "${PROJECT_ROOT}/Resources/shell-integration" "${RESOURCES}/shell-integration"
fi

# Step 6e: Copy bundled terminal fonts.
if [ -d "${PROJECT_ROOT}/Resources/Fonts" ]; then
    cp -R "${PROJECT_ROOT}/Resources/Fonts" "${RESOURCES}/Fonts"
fi

# Step 6f: Copy bundled Tree-sitter core and syntax grammar resources. Parser
# dylibs are added by the grammar build pipeline; manifest and queries are copied
# independently so the runtime can degrade safely when parsers are not present yet.
if [ -d "${PROJECT_ROOT}/Resources/TreeSitter" ]; then
    cp -R "${PROJECT_ROOT}/Resources/TreeSitter" "${RESOURCES}/TreeSitter"
fi
if [ -d "${PROJECT_ROOT}/Resources/Grammars" ]; then
    cp -R "${PROJECT_ROOT}/Resources/Grammars" "${RESOURCES}/Grammars"
fi

# Step 6g: Copy markdown preview resources (Mermaid, KaTeX).
if [ -d "${PROJECT_ROOT}/Resources/Markdown" ]; then
    cp -R "${PROJECT_ROOT}/Resources/Markdown" "${RESOURCES}/Markdown"
fi

# Step 6h: Copy in-page JS bundles used by the browser panel features
# (dom-grab.js for the click-to-capture flow). Plain vanilla JS, no
# bundler, no external dependencies — copied as-is so the WKWebView
# user-script loader can pick it up by name at runtime.
if [ -d "${PROJECT_ROOT}/Resources/JS" ]; then
    cp -R "${PROJECT_ROOT}/Resources/JS" "${RESOURCES}/JS"
fi

# Step 6i: Copy bundled local skills.
if [ -d "${PROJECT_ROOT}/Resources/Skills" ]; then
    cp -R "${PROJECT_ROOT}/Resources/Skills" "${RESOURCES}/Skills"
fi

# Step 6j: Copy bundled project templates.
if [ -d "${PROJECT_ROOT}/Resources/Templates" ]; then
    cp -R "${PROJECT_ROOT}/Resources/Templates" "${RESOURCES}/Templates"
fi

# Step 6k: Copy bundled plugin repos for the local marketplace.
if [ -d "${PROJECT_ROOT}/Resources/Plugins" ]; then
    cp -R "${PROJECT_ROOT}/Resources/Plugins" "${RESOURCES}/Plugins"
fi

# Step 6l: Build and embed the QuickLook extension.
echo "==> Building QuickLook extension..."
QL_APPEX="$("${PROJECT_ROOT}/scripts/build-quicklook-extension.sh" "${BUILD_MODE}")"
cp -R "${QL_APPEX}" "${PLUGINS}/"
codesign --force --sign - --entitlements "${QL_ENTITLEMENTS}" "${PLUGINS}/$(basename "${QL_APPEX}")" >/dev/null
echo "    QuickLook: ${PLUGINS}/$(basename "${QL_APPEX}")"

# Step 7: Also build the CLI companion and place it in Resources.
echo "==> Building CLI companion..."
swift build --product cocxy ${SWIFT_FLAGS} 2>&1 | tail -1
if [ -f "${BUILD_DIR}/cocxy" ]; then
    cp "${BUILD_DIR}/cocxy" "${RESOURCES}/cocxy"
    echo "    CLI companion: ${RESOURCES}/cocxy"
fi

# Step 7b: Build and embed the local PTY daemon helper. The raw Resources
# binary stays as a compatibility probe path, while the signed helper app under
# Contents/Library/LaunchServices is the preferred runtime path for the
# experimental [experimental].pty-daemon gate.
echo "==> Building PTY daemon helper..."
swift build --target cocxyd ${SWIFT_FLAGS} 2>&1 | tail -1
if [ -f "${BUILD_DIR}/cocxyd" ]; then
    "${PROJECT_ROOT}/scripts/embed-pty-daemon-helper.sh" "${APP_BUNDLE}" "${BUILD_DIR}/cocxyd"
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
