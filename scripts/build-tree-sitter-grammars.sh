#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_ROOT="${COCXY_TREE_SITTER_BUILD_ROOT:-${PROJECT_ROOT}/.build/tree-sitter-grammars}"
SOURCES_DIR="${BUILD_ROOT}/sources"
STAGING_DIR="${BUILD_ROOT}/staging"
RESOURCES_DIR="${PROJECT_ROOT}/Resources"

CORE_REPO="https://github.com/tree-sitter/tree-sitter.git"
CORE_REF="cd5b087cd9f45ca6d93ab1954f6b7c8534f324d2" # v0.26.8

SWIFT_REPO="https://github.com/alex-pinkus/tree-sitter-swift.git"
SWIFT_REF="c354345348cf8079e6794fa1b1324d8d44b6807b"
TREE_SITTER_CLI_VERSION="0.26.8"

RUST_REPO="https://github.com/tree-sitter/tree-sitter-rust.git"
RUST_REF="77a3747266f4d621d0757825e6b11edcbf991ca5" # v0.24.2

PYTHON_REPO="https://github.com/tree-sitter/tree-sitter-python.git"
PYTHON_REF="293fdc02038ee2bf0e2e206711b69c90ac0d413f" # v0.25.0

TYPESCRIPT_REPO="https://github.com/tree-sitter/tree-sitter-typescript.git"
TYPESCRIPT_REF="f975a621f4e7f532fe322e13c4f79495e0a7b2e7" # v0.23.2

GO_REPO="https://github.com/tree-sitter/tree-sitter-go.git"
GO_REF="1547678a9da59885853f5f5cc8a99cc203fa2e2c" # v0.25.0

require_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: required tool '$1' was not found" >&2
        exit 1
    fi
}

fetch_repo() {
    local name="$1"
    local repo="$2"
    local ref="$3"
    local destination="${SOURCES_DIR}/${name}"

    if [ -d "${destination}/.git" ] && [ "$(git -C "${destination}" rev-parse HEAD)" = "${ref}" ]; then
        echo "==> ${name}: cached ${ref}"
        return
    fi

    rm -rf "${destination}"
    mkdir -p "${destination}"
    git -C "${destination}" init -q
    git -C "${destination}" remote add origin "${repo}"
    git -C "${destination}" fetch --depth 1 origin "${ref}"
    git -C "${destination}" checkout -q FETCH_HEAD
    echo "==> ${name}: fetched ${ref}"
}

sha256_resource() {
    shasum -a 256 "$1" | awk '{print $1}'
}

build_core() {
    local core_dir="${SOURCES_DIR}/core"
    mkdir -p "${STAGING_DIR}/TreeSitter"

    cc -dynamiclib -fPIC -O2 -std=c11 \
        -I "${core_dir}/lib/include" \
        -I "${core_dir}/lib/src" \
        "${core_dir}/lib/src/lib.c" \
        -o "${STAGING_DIR}/TreeSitter/libtree-sitter.dylib" \
        -install_name "@rpath/libtree-sitter.dylib"
}

build_parser() {
    local language_id="$1"
    local install_name="$2"
    shift 2
    local grammar_include_dir
    grammar_include_dir="$(dirname "$1")"

    mkdir -p "${STAGING_DIR}/Grammars/${language_id}"
    cc -dynamiclib -fPIC -O2 -std=c11 \
        -I "${SOURCES_DIR}/core/lib/include" \
        -I "${grammar_include_dir}" \
        "$@" \
        -o "${STAGING_DIR}/Grammars/${language_id}/parser.dylib" \
        -install_name "@rpath/${install_name}.dylib"
}

copy_query() {
    local language_id="$1"
    local upstream_query="$2"
    local existing_query="${RESOURCES_DIR}/Grammars/${language_id}/highlights.scm"
    local target_query="${STAGING_DIR}/Grammars/${language_id}/highlights.scm"

    if [ -f "${upstream_query}" ]; then
        cp "${upstream_query}" "${target_query}"
    elif [ -f "${existing_query}" ]; then
        cp "${existing_query}" "${target_query}"
    else
        echo "error: no highlights.scm available for ${language_id}" >&2
        exit 1
    fi
}

copy_license() {
    local source="$1"
    local target="$2"
    if [ -f "${source}" ]; then
        cp "${source}" "${STAGING_DIR}/Grammars/LICENSES/${target}"
    fi
}

write_manifest() {
    local swift_checksum rust_checksum python_checksum typescript_checksum go_checksum
    swift_checksum="$(sha256_resource "${STAGING_DIR}/Grammars/swift/parser.dylib")"
    rust_checksum="$(sha256_resource "${STAGING_DIR}/Grammars/rust/parser.dylib")"
    python_checksum="$(sha256_resource "${STAGING_DIR}/Grammars/python/parser.dylib")"
    typescript_checksum="$(sha256_resource "${STAGING_DIR}/Grammars/typescript/parser.dylib")"
    go_checksum="$(sha256_resource "${STAGING_DIR}/Grammars/go/parser.dylib")"

    cat > "${STAGING_DIR}/Grammars/manifest.json" <<EOF
{
  "languages": [
    {
      "languageID": "swift",
      "displayName": "Swift",
      "fileExtensions": ["swift"],
      "parserResource": "Grammars/swift/parser.dylib",
      "highlightQueryResource": "Grammars/swift/highlights.scm",
      "upstreamVersion": "tree-sitter-swift@${SWIFT_REF}",
      "license": "MIT",
      "checksum": "sha256:${swift_checksum}"
    },
    {
      "languageID": "rust",
      "displayName": "Rust",
      "fileExtensions": ["rs"],
      "parserResource": "Grammars/rust/parser.dylib",
      "highlightQueryResource": "Grammars/rust/highlights.scm",
      "upstreamVersion": "tree-sitter-rust@${RUST_REF}",
      "license": "MIT",
      "checksum": "sha256:${rust_checksum}"
    },
    {
      "languageID": "python",
      "displayName": "Python",
      "fileExtensions": ["py", "pyw"],
      "parserResource": "Grammars/python/parser.dylib",
      "highlightQueryResource": "Grammars/python/highlights.scm",
      "upstreamVersion": "tree-sitter-python@${PYTHON_REF}",
      "license": "MIT",
      "checksum": "sha256:${python_checksum}"
    },
    {
      "languageID": "typescript",
      "displayName": "TypeScript",
      "fileExtensions": ["ts", "tsx"],
      "parserResource": "Grammars/typescript/parser.dylib",
      "highlightQueryResource": "Grammars/typescript/highlights.scm",
      "upstreamVersion": "tree-sitter-typescript@${TYPESCRIPT_REF}",
      "license": "MIT",
      "checksum": "sha256:${typescript_checksum}"
    },
    {
      "languageID": "go",
      "displayName": "Go",
      "fileExtensions": ["go"],
      "parserResource": "Grammars/go/parser.dylib",
      "highlightQueryResource": "Grammars/go/highlights.scm",
      "upstreamVersion": "tree-sitter-go@${GO_REF}",
      "license": "MIT",
      "checksum": "sha256:${go_checksum}"
    }
  ]
}
EOF
}

install_staging() {
    rm -rf "${RESOURCES_DIR}/TreeSitter"
    mkdir -p "${RESOURCES_DIR}/TreeSitter"
    cp -R "${STAGING_DIR}/TreeSitter/." "${RESOURCES_DIR}/TreeSitter/"

    mkdir -p "${RESOURCES_DIR}/Grammars"
    for language_id in swift rust python typescript go; do
        rm -rf "${RESOURCES_DIR}/Grammars/${language_id}"
        mkdir -p "${RESOURCES_DIR}/Grammars/${language_id}"
        cp -R "${STAGING_DIR}/Grammars/${language_id}/." "${RESOURCES_DIR}/Grammars/${language_id}/"
    done
    rm -rf "${RESOURCES_DIR}/Grammars/LICENSES"
    cp -R "${STAGING_DIR}/Grammars/LICENSES" "${RESOURCES_DIR}/Grammars/LICENSES"
    cp "${STAGING_DIR}/Grammars/manifest.json" "${RESOURCES_DIR}/Grammars/manifest.json"
}

require_tool git
require_tool cc
require_tool npm
require_tool shasum

mkdir -p "${SOURCES_DIR}"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}/Grammars/LICENSES"

fetch_repo core "${CORE_REPO}" "${CORE_REF}"
fetch_repo swift "${SWIFT_REPO}" "${SWIFT_REF}"
fetch_repo rust "${RUST_REPO}" "${RUST_REF}"
fetch_repo python "${PYTHON_REPO}" "${PYTHON_REF}"
fetch_repo typescript "${TYPESCRIPT_REPO}" "${TYPESCRIPT_REF}"
fetch_repo go "${GO_REPO}" "${GO_REF}"

echo "==> Building Tree-sitter core"
build_core

echo "==> Regenerating Swift parser with tree-sitter-cli@${TREE_SITTER_CLI_VERSION}"
(cd "${SOURCES_DIR}/swift" && npx --yes "tree-sitter-cli@${TREE_SITTER_CLI_VERSION}" generate)

echo "==> Building parser dylibs"
build_parser swift "tree-sitter-swift" \
    "${SOURCES_DIR}/swift/src/parser.c" \
    "${SOURCES_DIR}/swift/src/scanner.c"
build_parser rust "tree-sitter-rust" \
    "${SOURCES_DIR}/rust/src/parser.c" \
    "${SOURCES_DIR}/rust/src/scanner.c"
build_parser python "tree-sitter-python" \
    "${SOURCES_DIR}/python/src/parser.c" \
    "${SOURCES_DIR}/python/src/scanner.c"
build_parser typescript "tree-sitter-typescript" \
    "${SOURCES_DIR}/typescript/typescript/src/parser.c" \
    "${SOURCES_DIR}/typescript/typescript/src/scanner.c"
build_parser go "tree-sitter-go" \
    "${SOURCES_DIR}/go/src/parser.c"

echo "==> Copying highlight queries and licenses"
copy_query swift "${SOURCES_DIR}/swift/queries/highlights.scm"
copy_query rust "${SOURCES_DIR}/rust/queries/highlights.scm"
copy_query python "${SOURCES_DIR}/python/queries/highlights.scm"
copy_query typescript "${SOURCES_DIR}/typescript/queries/highlights.scm"
copy_query go "${SOURCES_DIR}/go/queries/highlights.scm"

copy_license "${SOURCES_DIR}/core/lib/LICENSE" "tree-sitter-core-LICENSE.txt"
copy_license "${SOURCES_DIR}/core/lib/src/unicode/LICENSE" "tree-sitter-core-unicode-LICENSE.txt"
copy_license "${SOURCES_DIR}/swift/LICENSE" "tree-sitter-swift-LICENSE.txt"
copy_license "${SOURCES_DIR}/rust/LICENSE" "tree-sitter-rust-LICENSE.txt"
copy_license "${SOURCES_DIR}/python/LICENSE" "tree-sitter-python-LICENSE.txt"
copy_license "${SOURCES_DIR}/typescript/LICENSE" "tree-sitter-typescript-LICENSE.txt"
copy_license "${SOURCES_DIR}/go/LICENSE" "tree-sitter-go-LICENSE.txt"

write_manifest
install_staging

echo "==> Tree-sitter grammars installed"
echo "    Core: ${RESOURCES_DIR}/TreeSitter/libtree-sitter.dylib"
echo "    Grammars: ${RESOURCES_DIR}/Grammars/{swift,rust,python,typescript,go}/parser.dylib"
