#!/usr/bin/env bash
set -euo pipefail

# GitHub's hosted macOS runners can start the entire Swift Testing graph at
# once even when experimental serialization environment variables are set.
# Running each Swift Testing suite in its own process keeps coverage intact
# while preventing AppKit/Dispatch-heavy suites from over-parallelizing.

common_args=(
  --disable-xctest
  --skip PerformanceTests
  --skip CocxyCorePerformanceBenchmarks
)

coverage_enabled=false
list_extra_args=()
for arg in "$@"; do
  if [[ "$arg" == "--enable-code-coverage" ]]; then
    coverage_enabled=true
    continue
  fi
  list_extra_args+=("$arg")
done

list_args=("${common_args[@]}")
if [[ ${#list_extra_args[@]} -gt 0 ]]; then
  list_args+=("${list_extra_args[@]}")
fi

suites=()
while IFS= read -r suite; do
  suites+=("$suite")
done < <(
  swift test list "${list_args[@]}" \
    | awk -F'[./]' '/^[A-Za-z0-9_]+\.[A-Za-z0-9_]+\// { print $2 }' \
    | sort -u
)

if [[ ${#suites[@]} -eq 0 ]]; then
  echo "error: no Swift Testing suites discovered" >&2
  exit 1
fi

limit="${SWIFT_TESTING_SERIAL_LIMIT:-}"
if [[ -n "$limit" ]]; then
  if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
    echo "error: SWIFT_TESTING_SERIAL_LIMIT must be a positive integer" >&2
    exit 1
  fi
  suites=("${suites[@]:0:limit}")
fi

echo "Discovered ${#suites[@]} Swift Testing suite(s)."

index=0
for suite in "${suites[@]}"; do
  index=$((index + 1))
  echo "::group::Swift Testing suite ${index}/${#suites[@]}: ${suite}"
  if [[ "$coverage_enabled" == true ]]; then
    swift test "${common_args[@]}" "$@" --filter "$suite"
  else
    swift test --skip-build "${common_args[@]}" "$@" --filter "$suite"
  fi
  echo "::endgroup::"
done

echo "All ${#suites[@]} Swift Testing suite(s) passed."
