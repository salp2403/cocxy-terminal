#!/usr/bin/env bash
set -euo pipefail

# Read-only preflight for Agent Workspace OS v1.18 product UX acceptance.
#
# This does not open the app, drive UI, edit screenshots, or create acceptance
# decisions. It only records whether a release-candidate UX walkthrough artifact
# already exists for the six Agent Workspace surfaces from the plan.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_ROOT="${COCXY_AGENT_WORKSPACE_PRODUCT_UX_PREFLIGHT_ARTIFACTS:-${PROJECT_ROOT}/build/agent-workspace-product-ux-preflight/${TIMESTAMP}}"
SUMMARY="${ARTIFACT_ROOT}/summary.tsv"
UX_ARTIFACT_ROOT="${COCXY_AGENT_WORKSPACE_PRODUCT_UX_ARTIFACT_ROOT:-${PROJECT_ROOT}/build/agent-workspace-product-ux}"

usage() {
  cat <<'USAGE'
usage: scripts/preflight-agent-workspace-product-ux.sh

This is read-only. It reports whether an Agent Workspace OS product UX
release-candidate walkthrough has been archived for the six planned surfaces:
command palette, dashboard, browser DevTools, remote ports, teams, and code
review.

Expected passing artifact:
  build/agent-workspace-product-ux/<timestamp>/summary.txt

Required fields:
  status=ok
  result=agent-workspace-product-ux-ok
  surfaces=6
  commandPalette=ok
  dashboard=ok
  browserDevTools=ok
  remotePorts=ok
  teams=ok
  codeReview=ok
  voiceOverManual=ok
  keyboard=ok
  reduceMotion=ok
  contrast=ok
  manualAcceptance=ok
  automatedA11y=ok
  visualGoldens=ok
  bundleLocalCLI=ok
  reviewer=<human reviewer>
  acceptanceFile=<path>
  acceptanceSha256=<sha256>
  a11ySummary=<path>
  a11ySummarySha256=<sha256>
  visualSummary=<path>
  visualSummarySha256=<sha256>
  bundleSummary=<path>
  bundleSummarySha256=<sha256>
USAGE
}

field_value() {
  local field="$1"
  local file="$2"
  sed -n "s/^${field}=//p" "$file" | tail -1
}

resolve_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "${PROJECT_ROOT}/${path}"
  fi
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

verify_referenced_file() {
  local summary="$1"
  local path_field="$2"
  local hash_field="$3"
  local raw_path
  local expected_hash
  local path

  raw_path="$(field_value "$path_field" "$summary")"
  expected_hash="$(field_value "$hash_field" "$summary")"
  if [ -z "$raw_path" ] || [ -z "$expected_hash" ]; then
    return 1
  fi

  path="$(resolve_path "$raw_path")"
  if [ ! -f "$path" ]; then
    return 1
  fi

  [ "$(sha256_file "$path")" = "$expected_hash" ]
}

latest_ok_summary() {
  local file
  if [ ! -d "$UX_ARTIFACT_ROOT" ]; then
    return 1
  fi

  file="$(
    find "$UX_ARTIFACT_ROOT" -maxdepth 2 -type f -name summary.txt -print 2>/dev/null |
      LC_ALL=C sort -r |
      head -1
  )"
  if [ -z "$file" ]; then
    return 1
  fi

  if grep -q '^status=ok$' "$file" &&
     grep -q '^result=agent-workspace-product-ux-ok$' "$file" &&
     grep -q '^surfaces=6$' "$file" &&
     grep -q '^commandPalette=ok$' "$file" &&
     grep -q '^dashboard=ok$' "$file" &&
     grep -q '^browserDevTools=ok$' "$file" &&
     grep -q '^remotePorts=ok$' "$file" &&
     grep -q '^teams=ok$' "$file" &&
     grep -q '^codeReview=ok$' "$file" &&
     grep -q '^voiceOverManual=ok$' "$file" &&
     grep -q '^keyboard=ok$' "$file" &&
     grep -q '^reduceMotion=ok$' "$file" &&
     grep -q '^contrast=ok$' "$file" &&
     grep -q '^manualAcceptance=ok$' "$file" &&
     grep -q '^automatedA11y=ok$' "$file" &&
     grep -q '^visualGoldens=ok$' "$file" &&
     grep -q '^bundleLocalCLI=ok$' "$file" &&
     grep -Eq '^reviewer=.+$' "$file" &&
     verify_referenced_file "$file" "acceptanceFile" "acceptanceSha256" &&
     verify_referenced_file "$file" "a11ySummary" "a11ySummarySha256" &&
     verify_referenced_file "$file" "visualSummary" "visualSummarySha256" &&
     verify_referenced_file "$file" "bundleSummary" "bundleSummarySha256"; then
    printf '%s\n' "$file"
    return 0
  fi

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
if ux_summary="$(latest_ok_summary)"; then
  overall_status="ok"
  printf 'product-ux-walkthrough\tok\t%s\tall required release-candidate UX fields present\n' \
    "${ux_summary#${PROJECT_ROOT}/}" >> "$SUMMARY"
else
  printf 'product-ux-walkthrough\tblocked\t-\tmissing build/agent-workspace-product-ux/**/summary.txt with status=ok, six surfaces, manual VoiceOver, keyboard, reduce motion, contrast, human acceptance, and automated evidence\n' >> "$SUMMARY"
fi

{
  echo "status=${overall_status}"
  echo "artifactRoot=${ARTIFACT_ROOT}"
  echo "summary=${SUMMARY}"
  echo "uxArtifactRoot=${UX_ARTIFACT_ROOT}"
  echo "next=archive a release-candidate UX walkthrough summary for the six Agent Workspace surfaces"
} | tee "${ARTIFACT_ROOT}/preflight.txt"

cat "$SUMMARY"

if [ "$overall_status" = "ok" ]; then
  exit 0
fi
exit 1
