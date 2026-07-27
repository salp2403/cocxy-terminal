#!/bin/bash
# install-pinned-xcodegen.sh - Install a checksum-pinned XcodeGen release.

set -euo pipefail

readonly XCODEGEN_VERSION="2.45.3"
readonly XCODEGEN_ASSET="xcodegen.zip"
readonly XCODEGEN_SHA256="0c90f4d28ca57335f9fa78cf5bf6dabfe20a232036dabe36de2eef79cb7c0878"
readonly XCODEGEN_URL="https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/${XCODEGEN_ASSET}"

if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [absolute-install-directory]" >&2
    exit 64
fi

DEFAULT_ROOT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
INSTALL_DIR="${1:-${DEFAULT_ROOT}/xcodegen-${XCODEGEN_VERSION}}"
case "${INSTALL_DIR}" in
    /*) ;;
    *)
        echo "ERROR: XcodeGen install directory must be absolute: ${INSTALL_DIR}" >&2
        exit 64
        ;;
esac

if [ -e "${INSTALL_DIR}" ] || [ -L "${INSTALL_DIR}" ]; then
    if [ -x "${INSTALL_DIR}/bin/xcodegen" ] \
        && [ "$("${INSTALL_DIR}/bin/xcodegen" --version)" = "Version: ${XCODEGEN_VERSION}" ]; then
        printf '%s\n' "${INSTALL_DIR}/bin"
        exit 0
    fi
    echo "ERROR: Refusing to replace an existing XcodeGen path: ${INSTALL_DIR}" >&2
    exit 73
fi

INSTALL_PARENT="$(dirname "${INSTALL_DIR}")"
mkdir -p "${INSTALL_PARENT}"
WORK_DIR="$(mktemp -d "${INSTALL_PARENT}/.xcodegen-${XCODEGEN_VERSION}.XXXXXX")"
cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

ARCHIVE="${WORK_DIR}/${XCODEGEN_ASSET}"
curl \
    --proto '=https' \
    --tlsv1.2 \
    --fail \
    --show-error \
    --location \
    --retry 3 \
    --retry-delay 2 \
    --output "${ARCHIVE}" \
    "${XCODEGEN_URL}"

printf '%s  %s\n' "${XCODEGEN_SHA256}" "${ARCHIVE}" | shasum -a 256 -c -
mkdir "${WORK_DIR}/extract"
unzip -q "${ARCHIVE}" -d "${WORK_DIR}/extract"

EXTRACTED="${WORK_DIR}/extract/xcodegen"
if [ ! -x "${EXTRACTED}/bin/xcodegen" ] \
    || [ ! -d "${EXTRACTED}/share/xcodegen/SettingPresets" ]; then
    echo "ERROR: Pinned XcodeGen archive has an unexpected layout." >&2
    exit 65
fi
if [ "$("${EXTRACTED}/bin/xcodegen" --version)" != "Version: ${XCODEGEN_VERSION}" ]; then
    echo "ERROR: Pinned XcodeGen archive reports an unexpected version." >&2
    exit 65
fi

mv "${EXTRACTED}" "${INSTALL_DIR}"
printf '%s\n' "${INSTALL_DIR}/bin"
