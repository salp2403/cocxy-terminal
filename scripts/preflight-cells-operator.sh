#!/usr/bin/env bash
set -euo pipefail

# Read-only preflight for the Cocxy Cells Operator control-plane requirement.
#
# This never creates cells, starts services, or writes scope decisions. It only
# records whether there is already a passing Operator smoke artifact or an
# explicit owner decision that the Operator is out of scope for v1.18.0.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_ROOT="${COCXY_CELLS_OPERATOR_PREFLIGHT_ARTIFACTS:-${PROJECT_ROOT}/build/cells-operator-preflight/${TIMESTAMP}}"
SUMMARY="${ARTIFACT_ROOT}/summary.tsv"
SCOPE_DECISION="${PROJECT_ROOT}/docs/project/plans/2026-05-16-cells-operator-scope-decision.md"

usage() {
  cat <<'USAGE'
usage: scripts/preflight-cells-operator.sh

This is read-only. It reports whether the Cocxy Cells Operator control-plane
requirement has:
  - an existing status=ok Operator E2E summary artifact, or
  - an explicit owner decision removing it from v1.18.0 scope.

It never creates cloud resources, starts daemons, or writes the scope decision.
USAGE
}

latest_operator_summary() {
  local directory="${PROJECT_ROOT}/build/cells-operator"
  local file
  if [ ! -d "$directory" ]; then
    return 1
  fi

  while IFS= read -r file; do
    if grep -q '^status=ok$' "$file" &&
       grep -q '^result=cells-operator-ok$' "$file"; then
      printf '%s\n' "$file"
      return 0
    fi
  done < <(find "$directory" -maxdepth 2 -type f -name summary.txt -print 2>/dev/null | sort -r)

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
if operator_artifact="$(latest_operator_summary)"; then
  overall_status="complete"
  printf 'operator-e2e-artifact\tcomplete\t%s\tstatus=ok result=cells-operator-ok\n' \
    "${operator_artifact#${PROJECT_ROOT}/}" >> "$SUMMARY"
elif [ -f "$SCOPE_DECISION" ] &&
     grep -q '^Status: Out of scope for v1.18.0\.$' "$SCOPE_DECISION"; then
  overall_status="out-of-scope"
  printf 'operator-scope-decision\tout-of-scope\t%s\tStatus: Out of scope for v1.18.0.\n' \
    "${SCOPE_DECISION#${PROJECT_ROOT}/}" >> "$SUMMARY"
else
  printf 'operator-e2e-artifact\tblocked\t-\tmissing build/cells-operator/**/summary.txt with status=ok and result=cells-operator-ok\n' >> "$SUMMARY"
  printf 'operator-scope-decision\tblocked\t-\tmissing docs/project/plans/2026-05-16-cells-operator-scope-decision.md with Status: Out of scope for v1.18.0.\n' >> "$SUMMARY"
fi

{
  echo "status=${overall_status}"
  echo "artifactRoot=${ARTIFACT_ROOT}"
  echo "summary=${SUMMARY}"
  echo "operatorArtifactRoot=${PROJECT_ROOT}/build/cells-operator"
  echo "scopeDecision=${SCOPE_DECISION}"
  echo "next=implement and smoke Cocxy Cells Operator, or record an explicit owner scope decision"
} | tee "${ARTIFACT_ROOT}/preflight.txt"

cat "$SUMMARY"

case "$overall_status" in
  complete|out-of-scope) exit 0 ;;
  *) exit 1 ;;
esac
