#!/bin/bash
# build-app.sh - Build Cocxy Terminal as a macOS .app bundle.
#
# Usage:
#   ./scripts/build-app.sh                   # Debug build
#   ./scripts/build-app.sh release           # Release build (optimized)
#   ./scripts/build-app.sh release --version 0.1.86
#   ./scripts/build-app.sh release --channel preview
#   ./scripts/build-app.sh release --install # Build, install, and register Quick Look
#
# Output: build/CocxyTerminal.app by default; channel builds use
# build/CocxyTerminalPreview.app or build/CocxyTerminalNightly.app.
#
# Copyright (c) 2026 Said Arturo Lopez. MIT License.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_MODE="debug"
INSTALL_AFTER_BUILD=0
VERSION_OVERRIDE=""
CHANNEL="stable"
APP_NAME="CocxyTerminal"
APP_BUNDLE_BASENAME="CocxyTerminal"
BUNDLE_NAME="Cocxy Terminal"
BUNDLE_ID="dev.cocxy.terminal"
FEED_URL="https://cocxy.dev/appcast.xml"
PUBLIC_KEY="gMWhWC+AqrUZqRg1RbTr32MDdkk7H3DhLfnEqtQnWQU="
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
                echo "Usage: ./scripts/build-app.sh [debug|release] [--version X.Y.Z] [--channel stable|preview|nightly] [--install]"
                exit 1
            fi
            VERSION_OVERRIDE="${2#v}"
            shift 2
            ;;
        --channel)
            if [ $# -lt 2 ]; then
                echo "ERROR: --channel requires stable, preview, or nightly"
                echo "Usage: ./scripts/build-app.sh [debug|release] [--version X.Y.Z] [--channel stable|preview|nightly] [--install]"
                exit 1
            fi
            CHANNEL="$2"
            shift 2
            ;;
        *)
            echo "ERROR: Unknown argument: $1"
            echo "Usage: ./scripts/build-app.sh [debug|release] [--version X.Y.Z] [--channel stable|preview|nightly] [--install]"
            exit 1
            ;;
    esac
done

case "${CHANNEL}" in
    stable)
        APP_BUNDLE_BASENAME="CocxyTerminal"
        BUNDLE_NAME="Cocxy Terminal"
        BUNDLE_ID="dev.cocxy.terminal"
        FEED_URL="https://cocxy.dev/appcast.xml"
        ;;
    preview)
        APP_BUNDLE_BASENAME="CocxyTerminalPreview"
        BUNDLE_NAME="Cocxy Terminal Preview"
        BUNDLE_ID="dev.cocxy.terminal.preview"
        FEED_URL="https://cocxy.dev/appcast-preview.xml"
        ;;
    nightly)
        APP_BUNDLE_BASENAME="CocxyTerminalNightly"
        BUNDLE_NAME="Cocxy Terminal Nightly"
        BUNDLE_ID="dev.cocxy.terminal.nightly"
        FEED_URL="https://cocxy.dev/appcast-nightly.xml"
        ;;
    *)
        echo "ERROR: Invalid --channel '${CHANNEL}' (expected stable, preview, or nightly)"
        exit 1
        ;;
esac

if [ -n "${VERSION_OVERRIDE}" ]; then
    case "${CHANNEL}" in
        stable)
            VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'
            EXPECTED_VERSION="X.Y.Z"
            ;;
        preview)
            VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+-preview\.[0-9]+$'
            EXPECTED_VERSION="X.Y.Z-preview.N"
            ;;
        nightly)
            VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+-nightly\.[0-9]{8}$'
            EXPECTED_VERSION="X.Y.Z-nightly.YYYYMMDD"
            ;;
    esac

    if ! [[ "${VERSION_OVERRIDE}" =~ ${VERSION_PATTERN} ]]; then
        echo "ERROR: Invalid --version '${VERSION_OVERRIDE}' for ${CHANNEL} channel (expected ${EXPECTED_VERSION})"
        exit 1
    fi
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
APP_BUNDLE="${OUTPUT_DIR}/${APP_BUNDLE_BASENAME}.app"
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

# App Intents support requires a recent Xcode toolchain that ships
# AppIntents.json under SwiftConstantValues. When the toolchain does not
# provide it (older Xcode on CI runners), fall back to a standard build so
# the app binary still compiles. Shortcuts.app metadata is regenerated by
# any later build that runs on a toolchain with App Intents support.
if [ -f "${APPINTENTS_PROTOCOLS_JSON}" ]; then
    APPINTENTS_AVAILABLE=1
    plutil -extract constValueProtocols json -o "${APPINTENTS_PROTOCOL_LIST}" "${APPINTENTS_PROTOCOLS_JSON}"
    printf '%s\n' "${PROJECT_ROOT}/Sources/App/Shortcuts/CocxyShortcuts.swift" > "${APPINTENTS_SOURCE_LIST}"
else
    APPINTENTS_AVAILABLE=0
    echo "    WARNING: App Intents toolchain not found at ${APPINTENTS_PROTOCOLS_JSON}"
    echo "    Building without Shortcuts.app metadata. Binary still works; rebuild on a"
    echo "    toolchain that ships AppIntents.json to regenerate Shortcuts metadata."
fi

run_appintents_swift_build() {
    if [ "${APPINTENTS_AVAILABLE}" = "1" ]; then
        swift build --product "${APP_NAME}" ${SWIFT_FLAGS} \
            -Xswiftc -emit-const-values-path \
            -Xswiftc "${APPINTENTS_CONST_VALUES}" \
            -Xswiftc -Xfrontend \
            -Xswiftc -const-gather-protocols-file \
            -Xswiftc -Xfrontend \
            -Xswiftc "${APPINTENTS_PROTOCOL_LIST}" \
            2>&1 | tail -3
    else
        swift build --product "${APP_NAME}" ${SWIFT_FLAGS} 2>&1 | tail -3
    fi
}

appintents_const_values_contain_metadata() {
    [ -s "${APPINTENTS_CONST_VALUES}" ] \
        && grep -q '"AppIntents.AppIntent"' "${APPINTENTS_CONST_VALUES}"
}

run_appintents_swift_build

if [ "${APPINTENTS_AVAILABLE}" = "1" ] && ! appintents_const_values_contain_metadata; then
    echo "    App Intents const values did not contain AppIntent metadata; rebuilding Shortcuts source..."
    rm -f "${APPINTENTS_CONST_VALUES}"
    rm -f "${BUILD_DIR}/${APP_NAME}.build"/CocxyShortcuts.*
    run_appintents_swift_build
fi

# Verify binary exists.
if [ ! -f "${BUILD_DIR}/${APP_NAME}" ]; then
    echo "ERROR: Binary not found at ${BUILD_DIR}/${APP_NAME}"
    exit 1
fi
if [ "${APPINTENTS_AVAILABLE}" = "1" ] && ! appintents_const_values_contain_metadata; then
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
    --bundle-id "${BUNDLE_ID}"
    --executable "${APP_NAME}"
    --feed-url "${FEED_URL}"
    --public-key "${PUBLIC_KEY}"
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
# When the toolchain does not provide AppIntents.json (older Xcode), skip
# metadata generation so the build still succeeds; the binary keeps working.
if [ "${APPINTENTS_AVAILABLE}" = "1" ]; then
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
else
    echo "==> Skipping Shortcuts metadata generation (App Intents toolchain unavailable)"
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

# Step 6i: Copy hook integration script templates.
if [ -d "${PROJECT_ROOT}/Resources/HookScripts" ]; then
    cp -R "${PROJECT_ROOT}/Resources/HookScripts" "${RESOURCES}/HookScripts"
fi

# Step 6j: Copy bundled local skills.
if [ -d "${PROJECT_ROOT}/Resources/Skills" ]; then
    cp -R "${PROJECT_ROOT}/Resources/Skills" "${RESOURCES}/Skills"
fi

# Step 6k: Copy bundled project templates.
if [ -d "${PROJECT_ROOT}/Resources/Templates" ]; then
    cp -R "${PROJECT_ROOT}/Resources/Templates" "${RESOURCES}/Templates"
fi

# Step 6l: Copy bundled plugin repos for the local marketplace.
if [ -d "${PROJECT_ROOT}/Resources/Plugins" ]; then
    cp -R "${PROJECT_ROOT}/Resources/Plugins" "${RESOURCES}/Plugins"
fi

# Step 6m: Copy bundled search helper. `Resources/rg` is produced by
# scripts/download-ripgrep.sh and signed with the rest of the app bundle.
if [ -f "${PROJECT_ROOT}/Resources/rg" ]; then
    cp "${PROJECT_ROOT}/Resources/rg" "${RESOURCES}/rg"
    chmod 755 "${RESOURCES}/rg"
    codesign --force --sign - "${RESOURCES}/rg" >/dev/null
    echo "    ripgrep: ${RESOURCES}/rg"
fi
if [ -d "${PROJECT_ROOT}/Resources/Ripgrep" ]; then
    cp -R "${PROJECT_ROOT}/Resources/Ripgrep" "${RESOURCES}/Ripgrep"
fi

# Step 6n: Build and copy cocxyd-remote binaries for verified SSH daemon
# auto-deploy. The CocxyCore checkout is expected next to this repo locally;
# CI can override with COCXYCORE_DIR.
COCXYCORE_DIR="${COCXYCORE_DIR:-$(cd "${PROJECT_ROOT}/.." && pwd)/cocxycore}"
REMOTE_DAEMON_SRC="${COCXYCORE_DIR}/zig-out/bin"
if [ ! -x "${COCXYCORE_DIR}/scripts/build.sh" ]; then
    echo "ERROR: CocxyCore checkout not found at ${COCXYCORE_DIR}; set COCXYCORE_DIR"
    exit 1
fi
echo "==> Building remote daemon binaries..."
"${COCXYCORE_DIR}/scripts/build.sh" build >/dev/null
mkdir -p "${RESOURCES}/RemoteDaemon"
for remote_binary in \
    cocxyd-remote-macos-arm64 \
    cocxyd-remote-linux-x86_64 \
    cocxyd-remote-linux-arm64
do
    if [ ! -f "${REMOTE_DAEMON_SRC}/${remote_binary}" ]; then
        echo "ERROR: Missing remote daemon binary: ${REMOTE_DAEMON_SRC}/${remote_binary}"
        exit 1
    fi
    cp "${REMOTE_DAEMON_SRC}/${remote_binary}" "${RESOURCES}/RemoteDaemon/${remote_binary}"
    chmod 755 "${RESOURCES}/RemoteDaemon/${remote_binary}"
done
codesign --force --sign - "${RESOURCES}/RemoteDaemon/cocxyd-remote-macos-arm64" >/dev/null
echo "    remote daemon: ${RESOURCES}/RemoteDaemon"

# Step 6m: Build and embed the QuickLook extension.
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
swift build --product cocxyd ${SWIFT_FLAGS} 2>&1 | tail -1
COCXYD_BINARY="${BUILD_DIR}/cocxyd"
if [ ! -f "${COCXYD_BINARY}" ]; then
    DETECTED_BIN_DIR="$(swift build --product cocxyd --show-bin-path ${SWIFT_FLAGS} 2>/dev/null || true)"
    if [ -n "${DETECTED_BIN_DIR}" ] && [ -f "${DETECTED_BIN_DIR}/cocxyd" ]; then
        COCXYD_BINARY="${DETECTED_BIN_DIR}/cocxyd"
    fi
fi
if [ -f "${COCXYD_BINARY}" ]; then
    "${PROJECT_ROOT}/scripts/embed-pty-daemon-helper.sh" "${APP_BUNDLE}" "${COCXYD_BINARY}"
else
    echo "ERROR: cocxyd binary not found (looked in ${BUILD_DIR}/cocxyd and SwiftPM bin path)"
    exit 1
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
