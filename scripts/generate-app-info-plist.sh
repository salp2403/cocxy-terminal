#!/bin/bash
# generate-app-info-plist.sh - Render the app Info.plist from the shared base template.
#
# Usage:
#   ./scripts/generate-app-info-plist.sh OUTPUT_PATH [options]
#
# Options:
#   --bundle-name NAME
#   --display-name NAME
#   --bundle-id IDENTIFIER
#   --executable NAME
#   --version VERSION
#   --short-version VERSION
#   --feed-url URL
#   --public-key KEY

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_PLIST="${PROJECT_ROOT}/Resources/Info.plist"

if [ $# -lt 1 ]; then
    echo "Usage: ./scripts/generate-app-info-plist.sh OUTPUT_PATH [options]" >&2
    exit 1
fi

OUTPUT_PATH="$1"
shift

BUNDLE_NAME=""
DISPLAY_NAME=""
BUNDLE_ID=""
EXECUTABLE=""
VERSION=""
SHORT_VERSION=""
FEED_URL=""
PUBLIC_KEY=""

while [ $# -gt 0 ]; do
    case "$1" in
        --bundle-name)
            BUNDLE_NAME="$2"
            shift 2
            ;;
        --display-name)
            DISPLAY_NAME="$2"
            shift 2
            ;;
        --bundle-id)
            BUNDLE_ID="$2"
            shift 2
            ;;
        --executable)
            EXECUTABLE="$2"
            shift 2
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        --short-version)
            SHORT_VERSION="$2"
            shift 2
            ;;
        --feed-url)
            FEED_URL="$2"
            shift 2
            ;;
        --public-key)
            PUBLIC_KEY="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [ ! -f "$BASE_PLIST" ]; then
    echo "Base Info.plist not found at $BASE_PLIST" >&2
    exit 1
fi

mkdir -p "$(dirname "$OUTPUT_PATH")"
cp "$BASE_PLIST" "$OUTPUT_PATH"

if [ -z "$VERSION" ]; then
    VERSION="$(/usr/bin/plutil -extract CFBundleVersion raw "$BASE_PLIST")"
fi

if [ -z "$SHORT_VERSION" ]; then
    SHORT_VERSION="$VERSION"
fi

if [ -n "$BUNDLE_NAME" ]; then
    /usr/bin/plutil -replace CFBundleName -string "$BUNDLE_NAME" "$OUTPUT_PATH"
fi

if [ -n "$DISPLAY_NAME" ]; then
    /usr/bin/plutil -replace CFBundleDisplayName -string "$DISPLAY_NAME" "$OUTPUT_PATH"
fi

if [ -n "$BUNDLE_ID" ]; then
    /usr/bin/plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$OUTPUT_PATH"
fi

if [ -n "$EXECUTABLE" ]; then
    /usr/bin/plutil -replace CFBundleExecutable -string "$EXECUTABLE" "$OUTPUT_PATH"
fi

/usr/bin/plutil -replace CFBundleVersion -string "$VERSION" "$OUTPUT_PATH"
/usr/bin/plutil -replace CFBundleShortVersionString -string "$SHORT_VERSION" "$OUTPUT_PATH"

if [ -n "$FEED_URL" ]; then
    /usr/bin/plutil -replace SUFeedURL -string "$FEED_URL" "$OUTPUT_PATH"
fi

if [ -n "$PUBLIC_KEY" ]; then
    /usr/bin/plutil -replace SUPublicEDKey -string "$PUBLIC_KEY" "$OUTPUT_PATH"
fi
