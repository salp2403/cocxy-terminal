#!/bin/bash
# verify-swiftpm-resolution.sh - Enforce reviewed SwiftPM release inputs.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_FILE="${ROOT_DIR}/Package.resolved"
MANIFEST_FILE="${ROOT_DIR}/Package.swift"
SPARKLE_CHECKOUT="${ROOT_DIR}/.build/checkouts/Sparkle"
SPARKLE_ARTIFACT_ROOT="${ROOT_DIR}/.build/artifacts/sparkle/Sparkle"
SPARKLE_TOOL="${SPARKLE_ARTIFACT_ROOT}/bin/sign_update"
SPARKLE_FRAMEWORK="${SPARKLE_ARTIFACT_ROOT}/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

readonly SPARKLE_VERSION="2.9.4"
readonly SPARKLE_REVISION="b6496a74a087257ef5e6da1c5b29a447a60f5bd7"
readonly SPARKLE_LOCATION="https://github.com/sparkle-project/Sparkle"
readonly SPARKLE_ARTIFACT_SHA256="cb6fdbdc8884f15d62a616e79face92b08322410fd2d425edc6596ccbf4ba3b0"
readonly SPARKLE_SIGN_UPDATE_SHA256="bfb52400c3da18bb4c251ac4818c2c2e1e31c2e649a45b31c11109b6e57b34ad"

MODE="lock"
if [ "$#" -gt 1 ]; then
    echo "Usage: $0 [--lock-only|--verify-artifacts|--print-sign-update]" >&2
    exit 64
fi
if [ "$#" -eq 1 ]; then
    case "$1" in
        --lock-only) MODE="lock" ;;
        --verify-artifacts) MODE="artifacts" ;;
        --print-sign-update) MODE="print-tool" ;;
        *)
            echo "Usage: $0 [--lock-only|--verify-artifacts|--print-sign-update]" >&2
            exit 64
            ;;
    esac
fi

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ -f "${LOCK_FILE}" ] || fail "Package.resolved is missing."
if git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${ROOT_DIR}" ls-files --error-unmatch Package.resolved >/dev/null 2>&1 \
        || fail "Package.resolved is not tracked by Git."
    if git -C "${ROOT_DIR}" check-ignore -q Package.resolved; then
        fail "Package.resolved is ignored by Git."
    fi
fi

EXPECTED_REQUIREMENT=".package(url: \"${SPARKLE_LOCATION}\", exact: \"${SPARKLE_VERSION}\")"
grep -Fq "${EXPECTED_REQUIREMENT}" "${MANIFEST_FILE}" \
    || fail "Package.swift does not use the reviewed exact Sparkle requirement."

/usr/bin/python3 - "${LOCK_FILE}" "${SPARKLE_VERSION}" "${SPARKLE_REVISION}" "${SPARKLE_LOCATION}" <<'PY'
import json
import pathlib
import sys

lock_path = pathlib.Path(sys.argv[1])
expected_version, expected_revision, expected_location = sys.argv[2:]
try:
    payload = json.loads(lock_path.read_text(encoding="utf-8"))
except (OSError, UnicodeError, json.JSONDecodeError) as error:
    raise SystemExit(f"ERROR: invalid Package.resolved: {error}")

pins = [pin for pin in payload.get("pins", []) if pin.get("identity") == "sparkle"]
if len(pins) != 1:
    raise SystemExit("ERROR: Package.resolved must contain exactly one Sparkle pin.")
pin = pins[0]
state = pin.get("state", {})
if pin.get("kind") != "remoteSourceControl":
    raise SystemExit("ERROR: Sparkle pin is not remote source control.")
if pin.get("location") != expected_location:
    raise SystemExit("ERROR: Sparkle pin location does not match the reviewed repository.")
if state.get("version") != expected_version or state.get("revision") != expected_revision:
    raise SystemExit("ERROR: Sparkle pin does not match the reviewed version and revision.")
PY

if [ "${MODE}" = "lock" ]; then
    exit 0
fi

[ -d "${SPARKLE_CHECKOUT}/.git" ] || fail "Sparkle source checkout is missing."
ACTUAL_REVISION="$(git -C "${SPARKLE_CHECKOUT}" rev-parse HEAD)"
[ "${ACTUAL_REVISION}" = "${SPARKLE_REVISION}" ] \
    || fail "Sparkle checkout revision does not match Package.resolved."
grep -Fq "let version = \"${SPARKLE_VERSION}\"" "${SPARKLE_CHECKOUT}/Package.swift" \
    || fail "Sparkle checkout declares an unexpected version."
grep -Fq "let tag = \"${SPARKLE_VERSION}\"" "${SPARKLE_CHECKOUT}/Package.swift" \
    || fail "Sparkle checkout declares an unexpected artifact tag."
grep -Fq "let checksum = \"${SPARKLE_ARTIFACT_SHA256}\"" "${SPARKLE_CHECKOUT}/Package.swift" \
    || fail "Sparkle checkout declares an unreviewed artifact checksum."

[ -d "${SPARKLE_FRAMEWORK}" ] || fail "Pinned Sparkle.framework artifact is missing."
[ -f "${SPARKLE_TOOL}" ] && [ -x "${SPARKLE_TOOL}" ] \
    || fail "Pinned Sparkle sign_update tool is missing or not executable."
[ ! -L "${SPARKLE_TOOL}" ] || fail "Pinned Sparkle sign_update tool must not be a symlink."
ACTUAL_TOOL_SHA="$(shasum -a 256 "${SPARKLE_TOOL}" | awk '{print $1}')"
[ "${ACTUAL_TOOL_SHA}" = "${SPARKLE_SIGN_UPDATE_SHA256}" ] \
    || fail "Sparkle sign_update digest does not match the reviewed artifact."
lipo "${SPARKLE_TOOL}" -verify_arch x86_64 arm64 >/dev/null \
    || fail "Sparkle sign_update is not the reviewed universal macOS tool."
codesign --verify --strict "${SPARKLE_TOOL}" \
    || fail "Sparkle sign_update code signature is invalid."

if [ "${MODE}" = "print-tool" ]; then
    printf '%s\n' "${SPARKLE_TOOL}"
fi
