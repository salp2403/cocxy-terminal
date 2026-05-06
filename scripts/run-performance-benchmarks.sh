#!/usr/bin/env bash
# Copyright (c) 2026 Said Arturo Lopez. MIT License.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "::group::Editor performance benchmarks"
COCXY_RUN_EDITOR_BENCHMARKS=1 swift test --filter EditorPerformanceBenchmarks
echo "::endgroup::"

echo "::group::Syntax tree performance benchmarks"
COCXY_RUN_SYNTAX_BENCHMARKS=1 swift test -Xswiftc -O --filter SyntaxTreePerformanceBenchmarks
echo "::endgroup::"

echo "::group::CocxyCore performance benchmarks"
./scripts/run-cocxycore-benchmarks.sh
echo "::endgroup::"

echo "Performance benchmark suite passed."
