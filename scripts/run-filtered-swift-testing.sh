#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || -z "$1" ]]; then
  echo "Usage: $0 <test-filter> [swift-test-arguments...]" >&2
  exit 64
fi

filter="$1"
shift
swift_bin="${SWIFT:-swift}"
common_args=(
  --disable-automatic-resolution
  --disable-xctest
  --skip PerformanceTests
  --skip CocxyCorePerformanceBenchmarks
)
test_list="$(mktemp "${TMPDIR:-/tmp}/cocxy-swift-test-list.XXXXXX")"
trap 'rm -f "$test_list"' EXIT

"$swift_bin" test list "${common_args[@]}" "$@" > "$test_list"

matching_test_count=0
while IFS= read -r test_identifier; do
  if [[ "$test_identifier" =~ ^[A-Za-z0-9_]+\.[A-Za-z0-9_]+/ ]] \
      && [[ "$test_identifier" =~ $filter ]]; then
    matching_test_count=$((matching_test_count + 1))
  fi
done < "$test_list"

if (( matching_test_count == 0 )); then
  echo "error: Swift Testing filter discovered zero tests: $filter" >&2
  exit 1
fi

echo "Discovered $matching_test_count Swift Testing test(s) for filter: $filter"
"$swift_bin" test "${common_args[@]}" "$@" --filter "$filter"
