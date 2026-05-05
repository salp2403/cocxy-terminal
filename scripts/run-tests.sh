#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "Running XCTest suite..."
swift test --disable-swift-testing --skip PerformanceTests --skip CocxyCorePerformanceBenchmarks

echo "Running Swift Testing suite..."
./scripts/run-swift-testing-serial.sh

echo "All XCTest and Swift Testing tests passed."
