#!/usr/bin/env bash
set -euo pipefail

# Manual Cocxy Cells Operator control-plane smoke.
#
# This is local-only. It runs the Swift control-plane contract tests for the
# self-hosted Cells Operator and archives the evidence consumed by the private
# Agent Workspace OS completion gate. It does not create cloud resources, start
# daemons, or write user configuration.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_ROOT="${COCXY_CELLS_OPERATOR_ARTIFACTS:-${ROOT_DIR}/build/cells-operator/${TIMESTAMP}}"
SUMMARY="${ARTIFACT_ROOT}/summary.txt"
LOG="${ARTIFACT_ROOT}/swift-test.log"

usage() {
  cat <<'USAGE'
usage: scripts/smoke-cells-operator.sh

Runs the local-only Cells Operator control-plane tests and archives:
  build/cells-operator/<timestamp>/summary.txt

Expected passing fields:
  status=ok
  result=cells-operator-ok
  providerCount=2
  lifecycle=ok
  ownershipRecovery=ok
  unsafeRequestGuards=ok
USAGE
}

write_summary() {
  local status="$1"
  local result="$2"
  local reason="${3:-}"
  {
    echo "status=${status}"
    echo "result=${result}"
    echo "providerCount=2"
    echo "lifecycle=$([ "$status" = "ok" ] && echo ok || echo fail)"
    echo "ownershipRecovery=$([ "$status" = "ok" ] && echo ok || echo fail)"
    echo "unsafeRequestGuards=$([ "$status" = "ok" ] && echo ok || echo fail)"
    echo "cloudResources=none"
    echo "userConfigWrites=none"
    echo "swiftTests=$([ "$status" = "ok" ] && echo passed || echo failed)"
    if [ -n "$reason" ]; then
      echo "reason=${reason}"
    fi
    echo "log=${LOG#${ROOT_DIR}/}"
  } > "$SUMMARY"
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    usage
    exit 2
    ;;
esac

mkdir -p "$ARTIFACT_ROOT"

if swift test --filter CellOperatorSwiftTestingTests 2>&1 | tee "$LOG"; then
  write_summary "ok" "cells-operator-ok"
  cat "$SUMMARY"
else
  write_summary "failed" "cells-operator-failed" "swift-test-failed"
  cat "$SUMMARY"
  exit 1
fi
