#!/usr/bin/env bash
# Copyright (c) 2026 Said Arturo Lopez. MIT License.
# build-libghostty.sh - Build GhosttyKit.xcframework from source.
#
# This script clones the Ghostty repository, compiles libghostty as an
# xcframework for Apple Silicon, and copies the result into the project.
#
# Usage:
#   ./scripts/build-libghostty.sh [--clean] [--universal]
#
# Options:
#   --clean       Remove cached build artifacts and re-clone Ghostty
#   --universal   Build universal binary (arm64 + x86_64). Default: native only.
#
# Prerequisites:
#   - Xcode 15+ with Metal Toolchain (xcodebuild -downloadComponent MetalToolchain)
#   - Zig 0.15.2+ (brew install zig)
#   - gettext (brew install gettext)
#
# Output:
#   libs/GhosttyKit.xcframework/  - The compiled xcframework
#   libs/ghostty-resources/        - Shell integration scripts

set -euo pipefail

# --- Configuration -----------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="/tmp/ghostty-build"
GHOSTTY_REPO="https://github.com/ghostty-org/ghostty.git"
XCFRAMEWORK_OUTPUT="${PROJECT_ROOT}/libs/GhosttyKit.xcframework"
RESOURCES_OUTPUT="${PROJECT_ROOT}/libs/ghostty-resources"
XCFRAMEWORK_TARGET="native"

# --- Parse arguments ---------------------------------------------------------

CLEAN=false
for arg in "$@"; do
    case "${arg}" in
        --clean)
            CLEAN=true
            ;;
        --universal)
            XCFRAMEWORK_TARGET="universal"
            ;;
        *)
            echo "Error: unknown argument '${arg}'"
            echo "Usage: $0 [--clean] [--universal]"
            exit 1
            ;;
    esac
done

# --- Functions ---------------------------------------------------------------

log_step() {
    echo ""
    echo "==> $1"
    echo ""
}

check_command() {
    if ! command -v "$1" &>/dev/null; then
        echo "Error: '$1' is not installed."
        echo "Install with: $2"
        exit 1
    fi
}

# --- Step 1: Verify prerequisites -------------------------------------------

log_step "Verificando prerequisitos..."

check_command "zig" "brew install zig"
check_command "xcodebuild" "Install Xcode from the App Store"

ZIG_VERSION=$(zig version)
echo "  Zig version: ${ZIG_VERSION}"

XCODE_FULL=$(xcodebuild -version 2>/dev/null || true)
XCODE_VERSION=$(echo "${XCODE_FULL}" | head -1)
echo "  ${XCODE_VERSION}"

# Check Xcode path is correct (not CommandLineTools)
XCODE_PATH=$(xcode-select --print-path)
if [[ "${XCODE_PATH}" == *"CommandLineTools"* ]]; then
    echo "Error: xcode-select points to CommandLineTools: '${XCODE_PATH}'"
    echo "Run: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
    exit 1
fi
echo "  Xcode path: ${XCODE_PATH}"

# Check Metal toolchain
if ! xcrun -sdk macosx metal --version &>/dev/null; then
    echo "Error: Metal Toolchain not found."
    echo "Run: xcodebuild -downloadComponent MetalToolchain"
    exit 1
fi
echo "  Metal Toolchain: OK"

# Check gettext
if ! brew list gettext &>/dev/null; then
    echo "Warning: gettext not found. Installing..."
    brew install gettext
fi
echo "  gettext: OK"

# --- Step 2: Clone or update Ghostty ----------------------------------------

log_step "Preparando codigo fuente de Ghostty..."

if [ "${CLEAN}" = true ] && [ -d "${BUILD_DIR}" ]; then
    echo "  Limpiando build anterior..."
    rm -rf "${BUILD_DIR}"
fi

if [ -d "${BUILD_DIR}/.git" ]; then
    echo "  Repositorio existente encontrado. Actualizando..."
    cd "${BUILD_DIR}"
    git fetch --depth 1 origin main
    git checkout FETCH_HEAD
    echo "  Commit: $(git rev-parse --short HEAD)"
else
    echo "  Clonando repositorio (shallow)..."
    git clone --depth 1 "${GHOSTTY_REPO}" "${BUILD_DIR}"
    cd "${BUILD_DIR}"
    echo "  Commit: $(git rev-parse --short HEAD)"
fi

# --- Step 3: Build xcframework ----------------------------------------------

log_step "Compilando GhosttyKit.xcframework (target: ${XCFRAMEWORK_TARGET})..."

cd "${BUILD_DIR}"
zig build \
    -Doptimize=ReleaseFast \
    "-Dxcframework-target=${XCFRAMEWORK_TARGET}" \
    -Demit-macos-app=false

# Verify the xcframework was produced
BUILT_XCFRAMEWORK="${BUILD_DIR}/macos/GhosttyKit.xcframework"
if [ ! -d "${BUILT_XCFRAMEWORK}" ]; then
    echo "Error: xcframework not found at ${BUILT_XCFRAMEWORK}"
    echo "Build may have failed silently. Check the output above."
    exit 1
fi

echo "  Build exitoso."
echo "  xcframework: ${BUILT_XCFRAMEWORK}"

# Verify architecture
STATIC_LIB=$(find "${BUILT_XCFRAMEWORK}" -name "libghostty-fat.a" -type f | head -1)
if [ -n "${STATIC_LIB}" ]; then
    LIB_SIZE=$(du -h "${STATIC_LIB}" | cut -f1)
    echo "  Libreria estatica: ${LIB_SIZE}"

    # Check symbols
    SYMBOL_COUNT=$(nm -gU "${STATIC_LIB}" 2>/dev/null | grep -c "_ghostty_" || true)
    echo "  Simbolos ghostty_*: ${SYMBOL_COUNT}"
fi

# --- Step 4: Copy to project ------------------------------------------------

log_step "Copiando artefactos al proyecto..."

# xcframework
mkdir -p "$(dirname "${XCFRAMEWORK_OUTPUT}")"
rm -rf "${XCFRAMEWORK_OUTPUT}"
cp -R "${BUILT_XCFRAMEWORK}" "${XCFRAMEWORK_OUTPUT}"
echo "  xcframework -> ${XCFRAMEWORK_OUTPUT}"

# Shell integration resources
mkdir -p "${RESOURCES_OUTPUT}"
if [ -d "${BUILD_DIR}/zig-out/share/ghostty/shell-integration" ]; then
    rm -rf "${RESOURCES_OUTPUT}/shell-integration"
    cp -R "${BUILD_DIR}/zig-out/share/ghostty/shell-integration" "${RESOURCES_OUTPUT}/"
    echo "  shell-integration -> ${RESOURCES_OUTPUT}/shell-integration"
fi

# --- Step 5: Verify integration ----------------------------------------------

log_step "Verificando integracion con el proyecto SPM..."

cd "${PROJECT_ROOT}"
if swift build 2>&1 | tail -1 | grep -q "Build complete"; then
    echo "  swift build: OK"
else
    echo "  swift build: FALLO"
    echo "  Ejecuta 'swift build' manualmente para ver los errores."
    exit 1
fi

# --- Done --------------------------------------------------------------------

log_step "GhosttyKit.xcframework compilado e integrado correctamente."

echo "Resumen:"
echo "  Ghostty commit: $(cd "${BUILD_DIR}" && git rev-parse --short HEAD)"
echo "  Zig version: ${ZIG_VERSION}"
echo "  Target: ${XCFRAMEWORK_TARGET}"
echo "  Output: ${XCFRAMEWORK_OUTPUT}"
echo ""
echo "Para ejecutar los tests:"
echo "  swift test"
echo ""
