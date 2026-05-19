#!/usr/bin/env bash
set -euo pipefail

# Read-only preflight for the Agent Teams graph visual performance KPI.
#
# This does not open the app, render SwiftUI, synthesize performance numbers, or
# create acceptance decisions. It only records whether a real archived graph
# performance artifact already proves the plan target:
#   Team graph visual < 16ms render per update.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_ROOT="${COCXY_AGENT_TEAMS_GRAPH_PREFLIGHT_ARTIFACTS:-${ROOT_DIR}/build/agent-teams-graph-performance-preflight/${TIMESTAMP}}"
SUMMARY="${ARTIFACT_ROOT}/summary.tsv"
GRAPH_ARTIFACT_ROOT="${COCXY_AGENT_TEAMS_GRAPH_PERFORMANCE_ARTIFACT_ROOT:-${ROOT_DIR}/build/agent-teams-graph-performance}"

usage() {
  cat <<'USAGE'
usage: scripts/preflight-agent-teams-graph-performance.sh

This is read-only. It reports whether an Agent Teams graph performance artifact
has been archived for the visual KPI from the private plan.

Expected passing artifact:
  build/agent-teams-graph-performance/<timestamp>/summary.txt

Required fields:
  status=ok
  result=agent-teams-graph-performance-ok
  nodeCount=12
  frameBudgetMs=16
  maxFrameMs=ok
  updates=ok

The preflight never generates the performance numbers itself. A passing artifact
must come from an app/benchmark run that measured graph update rendering.
USAGE
}

latest_ok_summary() {
  local file
  if [ ! -d "$GRAPH_ARTIFACT_ROOT" ]; then
    return 1
  fi

  while IFS= read -r file; do
    if grep -q '^status=ok$' "$file" &&
       grep -q '^result=agent-teams-graph-performance-ok$' "$file" &&
       grep -q '^nodeCount=12$' "$file" &&
       grep -q '^frameBudgetMs=16$' "$file" &&
       grep -q '^maxFrameMs=ok$' "$file" &&
       grep -q '^updates=ok$' "$file"; then
      printf '%s\n' "$file"
      return 0
    fi
  done < <(find "$GRAPH_ARTIFACT_ROOT" -maxdepth 2 -type f -name summary.txt -print 2>/dev/null | sort -r)

  return 1
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
printf 'requirement\tstatus\tevidence\tdetail\n' > "$SUMMARY"

overall_status="blocked"
graph_summary="-"
if graph_summary_path="$(latest_ok_summary)"; then
  overall_status="ok"
  graph_summary="${graph_summary_path#${ROOT_DIR}/}"
  printf 'team-graph-frame-budget\tok\t%s\t12-node graph update render artifact stays within 16ms budget\n' \
    "$graph_summary" >> "$SUMMARY"
else
  printf 'team-graph-frame-budget\tblocked\t-\tmissing build/agent-teams-graph-performance/**/summary.txt with status=ok, nodeCount=12, frameBudgetMs=16, maxFrameMs=ok, and updates=ok\n' >> "$SUMMARY"
fi

{
  echo "status=${overall_status}"
  echo "artifactRoot=${ARTIFACT_ROOT}"
  echo "summary=${SUMMARY}"
  echo "graphArtifactRoot=${GRAPH_ARTIFACT_ROOT}"
  echo "latestGraphPerformanceSummary=${graph_summary}"
  echo "next=run and archive a real TeamGraphView performance smoke proving 12-node updates stay under 16ms"
} | tee "${ARTIFACT_ROOT}/preflight.txt"

cat "$SUMMARY"

if [ "$overall_status" = "ok" ]; then
  exit 0
fi
exit 1
