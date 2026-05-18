#!/usr/bin/env bash
# Manual CocxyCore moat smoke.
#
# Defaults are intentionally local-friendly. For heavier proof runs:
#   COCXYCORE_MOAT_FUZZ_CASES=1000000 \
#   COCXYCORE_MOAT_SEARCH_ROWS=1000000 \
#   COCXYCORE_MOAT_PATTERN_ROWS=1000000 \
#   COCXYCORE_MOAT_SEARCH_MAX_MICROS=100000 \
#   ./scripts/smoke-cocxycore-moat.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_ROOT="${COCXYCORE_MOAT_ARTIFACTS:-${ROOT_DIR}/build/cocxycore-moat/$(date +%Y%m%d-%H%M%S)}"
SUMMARY="${ARTIFACT_ROOT}/summary.txt"
FUZZ_CASES="${COCXYCORE_MOAT_FUZZ_CASES:-10000}"
SEARCH_ROWS="${COCXYCORE_MOAT_SEARCH_ROWS:-60000}"
PATTERN_ROWS="${COCXYCORE_MOAT_PATTERN_ROWS:-${SEARCH_ROWS}}"
SEARCH_MAX_MICROS="${COCXYCORE_MOAT_SEARCH_MAX_MICROS:-100000}"

mkdir -p "${ARTIFACT_ROOT}"

cd "${ROOT_DIR}"

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

{
  echo "cocxycore-moat-smoke"
  echo "fuzzCases=${FUZZ_CASES}"
  echo "searchRows=${SEARCH_ROWS}"
  echo "patternRows=${PATTERN_ROWS}"
  echo "searchMaxMicros=${SEARCH_MAX_MICROS}"
  echo "artifactRoot=${ARTIFACT_ROOT}"
} | tee "${SUMMARY}"

if ! COCXYCORE_MOAT_FUZZ_CASES="${FUZZ_CASES}" \
     COCXYCORE_MOAT_SEARCH_ROWS="${SEARCH_ROWS}" \
     COCXYCORE_MOAT_PATTERN_ROWS="${PATTERN_ROWS}" \
     COCXYCORE_MOAT_SEARCH_MAX_MICROS="${SEARCH_MAX_MICROS}" \
     swift test --filter CocxyCoreMoatSmokeSwiftTestingTests \
       > "${ARTIFACT_ROOT}/swift-test.out" \
       2> "${ARTIFACT_ROOT}/swift-test.err"; then
  {
    echo "status=failed"
    echo "reason=CocxyCore moat smoke test failed"
    echo "swiftTestOutput=${ARTIFACT_ROOT#${ROOT_DIR}/}/swift-test.out"
    echo "swiftTestOutputSha256=$(sha256_file "${ARTIFACT_ROOT}/swift-test.out")"
    echo "swiftTestError=${ARTIFACT_ROOT#${ROOT_DIR}/}/swift-test.err"
    echo "swiftTestErrorSha256=$(sha256_file "${ARTIFACT_ROOT}/swift-test.err")"
  } | tee -a "${SUMMARY}"
  cat "${ARTIFACT_ROOT}/swift-test.out" >&2 || true
  cat "${ARTIFACT_ROOT}/swift-test.err" >&2 || true
  exit 1
fi

{
  echo "status=ok"
  echo "result=cocxycore-moat-smoke-ok"
  echo "swiftTestOutput=${ARTIFACT_ROOT#${ROOT_DIR}/}/swift-test.out"
  echo "swiftTestOutputSha256=$(sha256_file "${ARTIFACT_ROOT}/swift-test.out")"
  echo "swiftTestError=${ARTIFACT_ROOT#${ROOT_DIR}/}/swift-test.err"
  echo "swiftTestErrorSha256=$(sha256_file "${ARTIFACT_ROOT}/swift-test.err")"
} | tee -a "${SUMMARY}"
