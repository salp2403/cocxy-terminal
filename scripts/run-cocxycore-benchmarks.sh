#!/usr/bin/env bash
# Copyright (c) 2026 Said Arturo Lopez. MIT License.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

export COCXY_RUN_COCXYCORE_BENCHMARKS=1

echo "Running gated CocxyCore benchmarks..."
swift test --filter CocxyTerminalTests.CocxyCorePerformanceBenchmarks "$@"
