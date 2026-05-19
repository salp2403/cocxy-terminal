#!/usr/bin/env bash
set -euo pipefail

# Manual Team Graph visual performance smoke.
#
# This runs the opt-in SwiftUI/AppKit benchmark that mounts TeamGraphView in an
# NSHostingView, applies real AgentTeamGraph updates, forces layout/display, and
# archives the 12-node 16ms frame-budget summary consumed by the completion gate.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_ROOT="${COCXY_AGENT_TEAMS_GRAPH_PERFORMANCE_ARTIFACTS:-${ROOT_DIR}/build/agent-teams-graph-performance/${TIMESTAMP}}"
SUMMARY="${ARTIFACT_ROOT}/summary.txt"
LOG="${ARTIFACT_ROOT}/swift-test.log"

usage() {
  cat <<'USAGE'
usage: scripts/smoke-agent-teams-graph-performance.sh

Runs the opt-in AgentTeamGraphPerformanceBenchmarks suite and archives:
  build/agent-teams-graph-performance/<timestamp>/summary.txt

Expected passing fields:
  status=ok
  result=agent-teams-graph-performance-ok
  nodeCount=12
  frameBudgetMs=16
  maxFrameMs=ok
  updates=ok
USAGE
}

write_failure_summary() {
  local reason="$1"
  {
    echo "status=failed"
    echo "result=agent-teams-graph-performance-failed"
    echo "nodeCount=12"
    echo "frameBudgetMs=16"
    echo "maxFrameMs=fail"
    echo "updates=fail"
    echo "reason=${reason}"
    echo "log=${LOG#${ROOT_DIR}/}"
  } > "$SUMMARY"
}

require_summary_field() {
  local field="$1"
  if ! grep -q "^${field}$" "$SUMMARY"; then
    return 1
  fi
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

if COCXY_RUN_AGENT_TEAMS_GRAPH_BENCHMARKS=1 \
   COCXY_AGENT_TEAMS_GRAPH_PERF_ARTIFACT_ROOT="$ARTIFACT_ROOT" \
   swift test --filter AgentTeamGraphPerformanceBenchmarks 2>&1 | tee "$LOG"; then
  :
else
  if [ ! -f "$SUMMARY" ]; then
    write_failure_summary "swift-test-failed"
  fi
  cat "$SUMMARY"
  exit 1
fi

if [ ! -f "$SUMMARY" ]; then
  write_failure_summary "summary-missing"
  cat "$SUMMARY"
  exit 1
fi

for field in \
  'status=ok' \
  'result=agent-teams-graph-performance-ok' \
  'nodeCount=12' \
  'frameBudgetMs=16' \
  'maxFrameMs=ok' \
  'updates=ok'
do
  if ! require_summary_field "$field"; then
    cat "$SUMMARY"
    exit 1
  fi
done

cat "$SUMMARY"
