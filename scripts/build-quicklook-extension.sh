#!/bin/bash
# build-quicklook-extension.sh - Build the Cocxy QuickLook extension (.appex).
#
# Usage:
#   ./scripts/build-quicklook-extension.sh          # Debug build
#   ./scripts/build-quicklook-extension.sh release  # Release build
#
# Output:
#   build/QuickLookDerived/Build/Products/<Config>/CocxyQuickLook.appex

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_MODE="${1:-debug}"

if [ "$BUILD_MODE" = "release" ]; then
    CONFIGURATION="Release"
else
    CONFIGURATION="Debug"
fi

DERIVED_DATA="${PROJECT_ROOT}/build/QuickLookDerived"
PROJECT_FILE="${PROJECT_ROOT}/CocxyExtensions.xcodeproj"
ENTITLEMENTS_FILE="${PROJECT_ROOT}/QuickLook/CocxyQuickLook.entitlements"

ensure_quicklook_extension_plist() {
    local plist_path="$1"
    /usr/libexec/PlistBuddy -c "Delete :NSExtension" "$plist_path" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :NSExtension dict" "$plist_path"
    /usr/libexec/PlistBuddy -c "Add :NSExtension:NSExtensionPointIdentifier string com.apple.quicklook.preview" "$plist_path"
    /usr/libexec/PlistBuddy -c "Add :NSExtension:NSExtensionPrincipalClass string CocxyQuickLook.PreviewProvider" "$plist_path"
    /usr/libexec/PlistBuddy -c "Add :NSExtension:NSExtensionAttributes dict" "$plist_path"
    /usr/libexec/PlistBuddy -c "Add :NSExtension:NSExtensionAttributes:QLSupportedContentTypes array" "$plist_path"
    /usr/libexec/PlistBuddy -c "Add :NSExtension:NSExtensionAttributes:QLSupportedContentTypes:0 string net.daringfireball.markdown" "$plist_path"
    /usr/libexec/PlistBuddy -c "Add :NSExtension:NSExtensionAttributes:QLSupportsSearchableItems bool false" "$plist_path"
    /usr/libexec/PlistBuddy -c "Add :NSExtension:NSExtensionAttributes:QLIsDataBasedPreview bool false" "$plist_path"
}

sign_quicklook_extension() {
    local appex_path="$1"
    codesign --force --sign - --entitlements "${ENTITLEMENTS_FILE}" "${appex_path}" >/dev/null
}

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "ERROR: xcodegen is required to build the QuickLook extension."
    exit 1
fi

cd "${PROJECT_ROOT}"
xcodegen generate --quiet

xcodebuild \
    -project "${PROJECT_FILE}" \
    -scheme CocxyQuickLook \
    -configuration "${CONFIGURATION}" \
    -derivedDataPath "${DERIVED_DATA}" \
    CODE_SIGNING_ALLOWED=NO \
    build >/dev/null

APPEX_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/CocxyQuickLook.appex"
if [ ! -d "${APPEX_PATH}" ]; then
    echo "ERROR: QuickLook extension not found at ${APPEX_PATH}"
    exit 1
fi

INFO_PLIST="${APPEX_PATH}/Contents/Info.plist"
ensure_quicklook_extension_plist "${INFO_PLIST}"
sign_quicklook_extension "${APPEX_PATH}"

if ! plutil -extract "NSExtension.NSExtensionPointIdentifier" raw -o - "${INFO_PLIST}" >/dev/null 2>&1; then
    echo "ERROR: QuickLook NSExtension metadata was not written to ${INFO_PLIST}"
    exit 1
fi

if ! codesign -d --entitlements :- "${APPEX_PATH}" 2>/dev/null | grep -q "<key>com.apple.security.app-sandbox</key><true/>"; then
    echo "ERROR: QuickLook sandbox entitlement was not written to ${APPEX_PATH}"
    exit 1
fi

echo "${APPEX_PATH}"
