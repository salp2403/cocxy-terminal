#!/bin/bash
# download-ripgrep.sh - Build the bundled macOS ripgrep helper.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${RIPGREP_VERSION:-15.1.0}"
BASE_URL="https://github.com/BurntSushi/ripgrep/releases/download/${VERSION}"
WORK_DIR="${PROJECT_ROOT}/.build/ripgrep-${VERSION}"
OUTPUT_RG="${PROJECT_ROOT}/Resources/rg"
LICENSE_DIR="${PROJECT_ROOT}/Resources/Ripgrep"

ARM64_ASSET="ripgrep-${VERSION}-aarch64-apple-darwin.tar.gz"
ARM64_SHA="378e973289176ca0c6054054ee7f631a065874a352bf43f0fa60ef079b6ba715"
X86_64_ASSET="ripgrep-${VERSION}-x86_64-apple-darwin.tar.gz"
X86_64_SHA="64811cb24e77cac3057d6c40b63ac9becf9082eedd54ca411b475b755d334882"

download_asset() {
    local asset="$1"
    local sha="$2"
    local destination="${WORK_DIR}/${asset}"

    if [ ! -f "${destination}" ]; then
        echo "==> Downloading ${asset}"
        curl -fL --retry 3 --retry-delay 2 "${BASE_URL}/${asset}" -o "${destination}"
    else
        echo "==> Reusing ${destination}"
    fi

    echo "${sha}  ${destination}" | shasum -a 256 -c -
}

extract_binary() {
    local asset="$1"
    local arch="$2"
    local extract_dir="${WORK_DIR}/${arch}"
    local binary

    rm -rf "${extract_dir}"
    mkdir -p "${extract_dir}"
    tar -xzf "${WORK_DIR}/${asset}" -C "${extract_dir}"
    binary="$(find "${extract_dir}" -type f -name rg | head -1)"
    if [ -z "${binary}" ]; then
        echo "ERROR: rg binary not found in ${asset}"
        exit 1
    fi
    printf '%s\n' "${binary}"
}

copy_licenses() {
    local extract_root="$1"
    mkdir -p "${LICENSE_DIR}"

    for name in LICENSE-MIT UNLICENSE README.md; do
        local source
        source="$(find "${extract_root}" -type f -name "${name}" | head -1)"
        if [ -n "${source}" ]; then
            cp "${source}" "${LICENSE_DIR}/${name}"
        fi
    done
}

mkdir -p "${WORK_DIR}"

download_asset "${ARM64_ASSET}" "${ARM64_SHA}"
download_asset "${X86_64_ASSET}" "${X86_64_SHA}"

ARM64_RG="$(extract_binary "${ARM64_ASSET}" "arm64")"
X86_64_RG="$(extract_binary "${X86_64_ASSET}" "x86_64")"

echo "==> Creating universal Resources/rg"
lipo -create "${ARM64_RG}" "${X86_64_RG}" -output "${OUTPUT_RG}"
chmod 755 "${OUTPUT_RG}"
lipo "${OUTPUT_RG}" -verify_arch arm64 x86_64

rm -rf "${LICENSE_DIR}"
copy_licenses "${WORK_DIR}/arm64"

"${OUTPUT_RG}" --version | head -1
echo "==> Wrote ${OUTPUT_RG}"
