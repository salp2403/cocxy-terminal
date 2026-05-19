#!/usr/bin/env bash
set -euo pipefail

# Read-only preflight for Agent Teams provider process coverage.
#
# This does not launch providers, install hooks, or write user config. It only
# records whether the already-archived provider-process smoke covers all
# planned Agent Teams providers from the v1.17/v1.18 plan.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_ROOT="${COCXY_AGENT_TEAMS_PROVIDER_PREFLIGHT_ARTIFACTS:-${ROOT_DIR}/build/agent-teams-provider-coverage-preflight/${TIMESTAMP}}"
SUMMARY="${ARTIFACT_ROOT}/summary.tsv"
PROVIDER_PROCESS_ARTIFACT_ROOT="${COCXY_AGENT_TEAMS_PROVIDER_PROCESS_ARTIFACT_ROOT:-${ROOT_DIR}/build/agent-teams-provider-process}"
REQUIRED_PROVIDER_COUNT=12
EXPECTED_PROVIDER_IDS=(
  "claude-code"
  "codex"
  "opencode"
  "pi"
  "cursor"
  "gemini"
  "rovo-dev"
  "copilot"
  "codebuddy"
  "factory"
  "qoder"
  "kiro"
)

usage() {
  cat <<'USAGE'
usage: scripts/preflight-agent-teams-provider-coverage.sh

This is read-only. It reports:
  - expected Agent Teams providers from the plan
  - provider binaries currently present on PATH
  - latest archived provider-process smoke summary
  - provider-process output evidence files and SHA-256 hashes
  - whether all 12 providers have real process smoke coverage

It never launches providers and never writes hook or user config.
USAGE
}

AGENTS=(
  "claude-code|Claude Code|claude,claude-code"
  "codex|Codex CLI|codex"
  "opencode|OpenCode|opencode,open-code"
  "pi|Pi|pi"
  "cursor|Cursor|cursor-agent,cursor"
  "gemini|Gemini CLI|gemini"
  "rovo-dev|Rovo Dev|acli,rovodev,rovo"
  "copilot|Copilot|copilot"
  "codebuddy|CodeBuddy|codebuddy"
  "factory|Factory|droid,factory"
  "qoder|Qoder|qodercli,qoder"
  "kiro|Kiro|kiro,kiro-cli"
)

find_provider_binary() {
  local candidates_csv="$1"
  local candidate
  IFS=',' read -r -a candidates <<< "$candidates_csv"
  for candidate in "${candidates[@]}"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

latest_provider_process_summary() {
  local directory="${PROVIDER_PROCESS_ARTIFACT_ROOT}"
  local file
  if [ ! -d "$directory" ]; then
    return 1
  fi

  file="$(
    find "$directory" -maxdepth 2 -type f -name summary.txt -print 2>/dev/null |
      LC_ALL=C sort -r |
      head -1
  )"
  if [ -z "$file" ]; then
    return 1
  fi

  if grep -q '^result=agent-teams-provider-process-ok$' "$file"; then
    printf '%s\n' "$file"
    return 0
  fi

  return 1
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
    printf '%s\n' "${ROOT_DIR}/${path}"
  fi
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

verify_file_hash() {
  local raw_path="$1"
  local expected_hash="$2"
  local path
  if [ -z "$raw_path" ] || [ -z "$expected_hash" ]; then
    return 1
  fi
  path="$(resolve_path "$raw_path")"
  if [ ! -f "$path" ]; then
    return 1
  fi
  [ "$(sha256_file "$path")" = "$expected_hash" ]
}

is_expected_provider_id() {
  local provider="$1"
  local expected
  for expected in "${EXPECTED_PROVIDER_IDS[@]}"; do
    if [ "$provider" = "$expected" ]; then
      return 0
    fi
  done
  return 1
}

verify_provider_evidence_manifest() {
  local summary="$1"
  local expected_count="$2"
  local raw_manifest
  local expected_hash
  local manifest
  local header
  local row_count
  local seen_provider_ids="|"
  local seen_count=0

  raw_manifest="$(field_value providerEvidence "$summary")"
  expected_hash="$(field_value providerEvidenceSha256 "$summary")"
  if ! verify_file_hash "$raw_manifest" "$expected_hash"; then
    return 1
  fi

  manifest="$(resolve_path "$raw_manifest")"
  header="$(sed -n '1p' "$manifest")"
  if [ "$header" != $'providerID\thookAgent\tbinary\tprocessOutput\tprocessOutputSha256\tdryRunOutput\tdryRunOutputSha256\tinstallOutput\tinstallOutputSha256\tcheckOutput\tcheckOutputSha256\thookHandlerOutput\thookHandlerOutputSha256\tremoveOutput\tremoveOutputSha256' ]; then
    return 1
  fi
  row_count="$(awk -F '\t' 'NR > 1 { count++ } END { print count + 0 }' "$manifest")"
  if [ "$row_count" != "$expected_count" ]; then
    return 1
  fi

  while IFS=$'\t' read -r provider hook_agent binary process_path process_hash dry_path dry_hash install_path install_hash check_path check_hash hook_path hook_hash remove_path remove_hash; do
    if [ "$provider" = "providerID" ]; then
      continue
    fi
    is_expected_provider_id "$provider" || return 1
    case "$seen_provider_ids" in
      *"|${provider}|"*) return 1 ;;
    esac
    seen_provider_ids="${seen_provider_ids}${provider}|"
    seen_count=$((seen_count + 1))
    [ -n "$hook_agent" ] || return 1
    [ -n "$binary" ] || return 1
    verify_file_hash "$process_path" "$process_hash" || return 1
    verify_file_hash "$dry_path" "$dry_hash" || return 1
    verify_file_hash "$install_path" "$install_hash" || return 1
    verify_file_hash "$check_path" "$check_hash" || return 1
    verify_file_hash "$hook_path" "$hook_hash" || return 1
    verify_file_hash "$remove_path" "$remove_hash" || return 1
  done < "$manifest"

  [ "$seen_count" = "$expected_count" ]
  return 0
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
printf 'provider\tstatus\tbinary\n' > "$SUMMARY"

available_count=0
for row in "${AGENTS[@]}"; do
  IFS='|' read -r provider _display candidates <<< "$row"
  binary="$(find_provider_binary "$candidates" || true)"
  if [ -n "$binary" ]; then
    available_count=$((available_count + 1))
    printf '%s\tavailable\t%s\n' "$provider" "$binary" >> "$SUMMARY"
  else
    printf '%s\tmissing\t-\n' "$provider" >> "$SUMMARY"
  fi
done

process_summary="-"
process_status="missing"
process_installed="0"
process_passed="0"
process_evidence="missing"
if process_summary_path="$(latest_provider_process_summary)"; then
  process_summary="${process_summary_path#${ROOT_DIR}/}"
  process_status="$(field_value status "$process_summary_path")"
  process_installed="$(field_value installedProviders "$process_summary_path")"
  process_passed="$(field_value passedProviders "$process_summary_path")"
  if [ "$process_status" = "ok" ] &&
     [ "$process_passed" -gt 0 ] 2>/dev/null &&
     verify_provider_evidence_manifest "$process_summary_path" "$process_passed"; then
    process_evidence="ok"
  else
    process_evidence="blocked"
  fi
fi

if [ "$process_status" = "ok" ] &&
   [ "$process_installed" = "$REQUIRED_PROVIDER_COUNT" ] &&
   [ "$process_passed" = "$REQUIRED_PROVIDER_COUNT" ] &&
   [ "$process_evidence" = "ok" ]; then
  status="ok"
else
  status="blocked"
fi

{
  echo "status=${status}"
  echo "artifactRoot=${ARTIFACT_ROOT}"
  echo "summary=${SUMMARY}"
  echo "providerCount=${REQUIRED_PROVIDER_COUNT}"
  echo "availableProviderBinaries=${available_count}"
  echo "latestProviderProcessSummary=${process_summary}"
  echo "latestProviderProcessStatus=${process_status}"
  echo "latestProviderProcessInstalled=${process_installed}"
  echo "latestProviderProcessPassed=${process_passed}"
  echo "latestProviderProcessEvidence=${process_evidence}"
  echo "next=install missing provider CLIs and run scripts/smoke-agent-teams-provider-process.sh with all 12 providers"
} | tee "${ARTIFACT_ROOT}/preflight.txt"

cat "$SUMMARY"

if [ "$status" = "ok" ]; then
  exit 0
fi
exit 1
