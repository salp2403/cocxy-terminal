#!/bin/bash
# install-local-app.sh - Install the locally built Cocxy app into /Applications
# and refresh Quick Look registration from the real app path users launch.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="${1:-${PROJECT_ROOT}/build/CocxyTerminal.app}"
DEST_APP="${2:-/Applications/Cocxy Terminal.app}"
PLUGIN_ID="dev.cocxy.terminal.quicklook"
PLUGIN_PATH="${DEST_APP}/Contents/PlugIns/CocxyQuickLook.appex"

if [ ! -d "${SOURCE_APP}" ]; then
    echo "ERROR: Source app not found at ${SOURCE_APP}"
    exit 1
fi

echo "==> Installing local app bundle..."
rm -rf "${DEST_APP}"
cp -R "${SOURCE_APP}" "${DEST_APP}"

echo "==> Registering Quick Look extension..."
pluginkit -a "${PLUGIN_PATH}" || true
qlmanage -r cache >/dev/null 2>&1 || true
qlmanage -r >/dev/null 2>&1 || true
/usr/bin/open -n "${DEST_APP}" >/dev/null 2>&1 || true

echo "==> Waiting for PlugInKit registration..."
for _ in 1 2 3 4 5; do
    if pluginkit -m -A -vvv -i "${PLUGIN_ID}" | grep -Fq "${DEST_APP}"; then
        echo "    Registered: ${PLUGIN_ID}"
        echo "    Path: ${DEST_APP}"
        exit 0
    fi
    sleep 1
done

echo "ERROR: Quick Look extension did not register from ${DEST_APP}"
exit 1
