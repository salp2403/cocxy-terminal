#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -f web/scripts/build-site.mjs ]]; then
  NODE_BIN="${NODE:-node}"
  if [[ -x /opt/homebrew/bin/node ]]; then
    NODE_BIN="/opt/homebrew/bin/node"
  fi

  if ! command -v "$NODE_BIN" >/dev/null 2>&1; then
    echo "Node.js 18+ is required to generate public website test fixtures." >&2
    exit 1
  fi

  NODE_MAJOR="$("$NODE_BIN" -p "Number(process.versions.node.split('.')[0])")"
  if (( NODE_MAJOR < 18 )); then
    echo "Node.js 18+ is required to generate public website test fixtures; found $("$NODE_BIN" -v)." >&2
    exit 1
  fi

  echo "Generating public website test fixtures..."
  "$NODE_BIN" web/scripts/build-site.mjs
fi

echo "Running XCTest suite..."
swift test --disable-swift-testing --skip PerformanceTests --skip CocxyCorePerformanceBenchmarks \
  --disable-automatic-resolution

echo "Running Swift Testing suite..."
./scripts/run-swift-testing-serial.sh

echo "All XCTest and Swift Testing tests passed."
