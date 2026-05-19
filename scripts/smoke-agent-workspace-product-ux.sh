#!/usr/bin/env bash
set -euo pipefail

# Manual release-candidate Product UX acceptance smoke.
#
# This script intentionally cannot produce a passing UX artifact by itself. It
# requires a human walkthrough acceptance file plus automated evidence from
# accessibility, visual screenshot golden, and bundle-local CLI smokes.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_ROOT="${COCXY_AGENT_WORKSPACE_PRODUCT_UX_ARTIFACTS:-${ROOT_DIR}/build/agent-workspace-product-ux/${TIMESTAMP}}"
SUMMARY="${ARTIFACT_ROOT}/summary.txt"
ACCEPTANCE_FILE="${COCXY_AGENT_WORKSPACE_PRODUCT_UX_ACCEPTANCE_FILE:-}"

usage() {
  cat <<'USAGE'
usage: COCXY_AGENT_WORKSPACE_PRODUCT_UX_ACCEPTANCE_FILE=<file> scripts/smoke-agent-workspace-product-ux.sh
       scripts/smoke-agent-workspace-product-ux.sh --write-template <file>

The acceptance file must be created by the release-candidate reviewer after a
real walkthrough of command palette, dashboard, Browser DevTools, remote ports,
Agent Teams, Code Review, manual VoiceOver, keyboard navigation, reduce motion,
and contrast.

Required acceptance file lines:
  Status: Accepted for v1.18.0 release candidate.
  Reviewer: <human reviewer>

This script also requires existing automated evidence:
  - build/agent-workspace-os-a11y/**/summary.txt with status=ok
  - build/agent-workspace-os-a11y/voiceover-ok.txt
  - build/visual-screenshot-golden/**/summary.txt with status=ok
  - build/bundle-local-cli/**/summary.txt with status=ok
USAGE
}

write_acceptance_template() {
  local template_path="$1"
  mkdir -p "$(dirname "$template_path")"
  cat > "$template_path" <<'TEMPLATE'
# Cocxy Agent Workspace OS v1.18.0 Product UX acceptance
#
# This template is not an acceptance artifact. A human release-candidate
# reviewer must complete the walkthrough and replace the Status line with:
# Status: Accepted for v1.18.0 release candidate.

Status: Pending release-candidate walkthrough.
Reviewer:

Surfaces:
- Command Palette (Cmd+Shift+P): cells, vault, browser searches have no visible lag: Pending
- Dashboard (Cmd+Option+D): agents listed and status pills update: Pending
- Browser DevTools: Inspect opens DevTools and console works: Pending
- Remote ports: Remote sidebar connects and port suggestions appear: Pending
- Agent Teams: create a team with two members without a crash: Pending
- Code Review (Cmd+Option+R): panel opens and diff state is visible: Pending

Manual accessibility checks:
- VoiceOver: Pending
- Keyboard navigation: Pending
- Reduce motion: Pending
- Contrast: Pending

Reviewer notes:
-
TEMPLATE
  printf 'template=%s\n' "$template_path"
}

latest_ok_summary() {
  local directory="$1"
  shift
  local file
  if [ ! -d "$directory" ]; then
    return 1
  fi

  while IFS= read -r file; do
    if ! grep -q '^status=ok$' "$file"; then
      continue
    fi

    local field
    local missing=0
    for field in "$@"; do
      if ! grep -q "^${field}$" "$file"; then
        missing=1
        break
      fi
    done
    if [ "$missing" -eq 0 ]; then
      printf '%s\n' "$file"
      return 0
    fi
  done < <(find "$directory" -maxdepth 2 -type f -name summary.txt -print 2>/dev/null | sort -r)

  return 1
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

write_blocked_summary() {
  local reason="$1"
  {
    echo "status=blocked"
    echo "result=agent-workspace-product-ux-blocked"
    echo "surfaces=6"
    echo "commandPalette=blocked"
    echo "dashboard=blocked"
    echo "browserDevTools=blocked"
    echo "remotePorts=blocked"
    echo "teams=blocked"
    echo "codeReview=blocked"
    echo "voiceOverManual=blocked"
    echo "keyboard=blocked"
    echo "reduceMotion=blocked"
    echo "contrast=blocked"
    echo "manualAcceptance=blocked"
    echo "automatedA11y=blocked"
    echo "visualGoldens=blocked"
    echo "bundleLocalCLI=blocked"
    echo "reason=${reason}"
    echo "acceptanceFile=${ACCEPTANCE_FILE:-missing}"
    echo "artifactRoot=${ARTIFACT_ROOT}"
  } > "$SUMMARY"
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  --write-template)
    if [ -z "${2:-}" ]; then
      usage
      exit 2
    fi
    write_acceptance_template "$2"
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

if [ -z "$ACCEPTANCE_FILE" ] || [ ! -f "$ACCEPTANCE_FILE" ]; then
  write_blocked_summary "missing-human-acceptance-file"
  cat "$SUMMARY"
  exit 1
fi

if ! grep -q '^Status: Accepted for v1.18.0 release candidate\.$' "$ACCEPTANCE_FILE"; then
  write_blocked_summary "acceptance-file-missing-status"
  cat "$SUMMARY"
  exit 1
fi

reviewer="$(sed -n 's/^Reviewer:[[:space:]]*//p' "$ACCEPTANCE_FILE" | head -1)"
if [ -z "$reviewer" ]; then
  write_blocked_summary "acceptance-file-missing-reviewer"
  cat "$SUMMARY"
  exit 1
fi

a11y_summary="$(latest_ok_summary \
  "${ROOT_DIR}/build/agent-workspace-os-a11y" \
  'result=agent-workspace-a11y-ok' \
  'surfaces=6' \
  'voiceoverAcceptance=source-and-test' \
  'wcagAA=ok' || true)"
if [ -z "$a11y_summary" ] || [ ! -f "${ROOT_DIR}/build/agent-workspace-os-a11y/voiceover-ok.txt" ]; then
  write_blocked_summary "missing-a11y-evidence"
  cat "$SUMMARY"
  exit 1
fi

visual_summary="$(latest_ok_summary \
  "${ROOT_DIR}/build/visual-screenshot-golden" \
  'result=visual-screenshot-golden-ok' \
  'checkedScreenshots=20' \
  'requiredScreenshots=20' || true)"
if [ -z "$visual_summary" ]; then
  write_blocked_summary "missing-visual-golden-evidence"
  cat "$SUMMARY"
  exit 1
fi

bundle_summary="$(latest_ok_summary \
  "${ROOT_DIR}/build/bundle-local-cli" \
  'result=bundle-local-cli-ok' \
  'statusCheck=ok' || true)"
if [ -z "$bundle_summary" ]; then
  write_blocked_summary "missing-bundle-local-cli-evidence"
  cat "$SUMMARY"
  exit 1
fi

{
  echo "status=ok"
  echo "result=agent-workspace-product-ux-ok"
  echo "surfaces=6"
  echo "commandPalette=ok"
  echo "dashboard=ok"
  echo "browserDevTools=ok"
  echo "remotePorts=ok"
  echo "teams=ok"
  echo "codeReview=ok"
  echo "voiceOverManual=ok"
  echo "keyboard=ok"
  echo "reduceMotion=ok"
  echo "contrast=ok"
  echo "manualAcceptance=ok"
  echo "automatedA11y=ok"
  echo "visualGoldens=ok"
  echo "bundleLocalCLI=ok"
  echo "reviewer=${reviewer}"
  echo "acceptanceFile=${ACCEPTANCE_FILE#${ROOT_DIR}/}"
  echo "acceptanceSha256=$(sha256_file "$ACCEPTANCE_FILE")"
  echo "a11ySummary=${a11y_summary#${ROOT_DIR}/}"
  echo "a11ySummarySha256=$(sha256_file "$a11y_summary")"
  echo "visualSummary=${visual_summary#${ROOT_DIR}/}"
  echo "visualSummarySha256=$(sha256_file "$visual_summary")"
  echo "bundleSummary=${bundle_summary#${ROOT_DIR}/}"
  echo "bundleSummarySha256=$(sha256_file "$bundle_summary")"
  echo "artifactRoot=${ARTIFACT_ROOT}"
} > "$SUMMARY"

cat "$SUMMARY"
