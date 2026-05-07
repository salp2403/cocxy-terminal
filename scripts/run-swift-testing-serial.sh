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

build_dir=""
coverage_dir=""
profile_dir=""
merged_profile=""
coverage_json=""
if [[ "$coverage_enabled" == true ]]; then
  build_dir="$(swift build --show-bin-path)"
  coverage_dir="$build_dir/codecov"
  profile_dir="$build_dir/swift-testing-serial-profraw"
  merged_profile="$coverage_dir/swift-testing-serial.profdata"
  coverage_json="$coverage_dir/CocxyTerminal-SwiftTesting.json"
  rm -rf "$profile_dir"
  mkdir -p "$profile_dir"
fi

index=0
for suite in "${suites[@]}"; do
  index=$((index + 1))
  echo "::group::Swift Testing suite ${index}/${#suites[@]}: ${suite}"
  if [[ "$coverage_enabled" == true ]]; then
    find "$coverage_dir" -maxdepth 1 -name "*.profraw" -delete 2>/dev/null || true
    swift test "${common_args[@]}" "$@" --filter "$suite"
    safe_suite="$(printf "%s" "$suite" | tr -c "A-Za-z0-9_.-" "_")"
    shopt -s nullglob
    suite_profiles=("$coverage_dir"/*.profraw)
    shopt -u nullglob
    if [[ ${#suite_profiles[@]} -eq 0 ]]; then
      echo "error: coverage profile was not generated for Swift Testing suite '$suite'" >&2
      exit 1
    fi
    for profile in "${suite_profiles[@]}"; do
      cp "$profile" "$profile_dir/${index}-${safe_suite}-$(basename "$profile")"
    done
  else
    swift test --skip-build "${common_args[@]}" "$@" --filter "$suite"
  fi
  echo "::endgroup::"
done

if [[ "$coverage_enabled" == true ]]; then
  test_binary="$build_dir/CocxyTerminalPackageTests.xctest/Contents/MacOS/CocxyTerminalPackageTests"
  if [[ ! -x "$test_binary" ]]; then
    echo "error: test binary not found at $test_binary" >&2
    exit 1
  fi
  all_profiles=()
  while IFS= read -r profile; do
    all_profiles+=("$profile")
  done < <(find "$profile_dir" -type f -name "*.profraw" | sort)
  if [[ ${#all_profiles[@]} -eq 0 ]]; then
    echo "error: no Swift Testing coverage profiles were captured" >&2
    exit 1
  fi
  xcrun llvm-profdata merge -sparse "${all_profiles[@]}" -o "$merged_profile"
  xcrun llvm-cov export -format=text -instr-profile "$merged_profile" "$test_binary" > "$coverage_json"
  echo "Swift Testing coverage JSON written to $coverage_json"
fi

echo "All ${#suites[@]} Swift Testing suite(s) passed."
