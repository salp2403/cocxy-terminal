#!/usr/bin/env bash
set -euo pipefail

# Internal completion gate for the private Agent Workspace OS plan.
#
# This script is intentionally conservative: it fails while any explicit
# plan-level requirement still lacks real evidence. It is a guard against
# treating green builds or partial smokes as "100% complete".

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAN="${ROOT_DIR}/docs/project/plans/2026-05-16-agent-workspace-os-supremacy.md"
AUDIT="${ROOT_DIR}/docs/project/plans/2026-05-16-agent-workspace-os-completion-audit.md"
FINAL_AUDIT_REPORT="${ROOT_DIR}/docs/project/plans/2026-05-17-agent-workspace-os-completion-audit-final.md"
COMMAND_INSTRUCTION_DOC="${ROOT_DIR}/docs/commands/instruccion.md"
if [ ! -f "$COMMAND_INSTRUCTION_DOC" ] && [ -n "${HOME:-}" ] && [ -f "${HOME}/claude-terminal/docs/commands/instruccion.md" ]; then
  COMMAND_INSTRUCTION_DOC="${HOME}/claude-terminal/docs/commands/instruccion.md"
fi
REMOTE_DOCKER_SMOKE="${ROOT_DIR}/scripts/smoke-remote-browser-docker-ssh.sh"
CELLS_DOCKER_SMOKE="${ROOT_DIR}/scripts/smoke-cells-docker.sh"
CELLS_SSH_SMOKE="${ROOT_DIR}/scripts/smoke-cells-local-ssh.sh"
CELLS_CLOUD_SMOKE="${ROOT_DIR}/scripts/smoke-cells-cloud-account.sh"
CELLS_AWS_SETUP_VERIFY="${ROOT_DIR}/scripts/verify-cells-aws-setup.sh"
CELLS_AWS_READINESS_SEQUENCE="${ROOT_DIR}/scripts/run-cells-aws-readiness-sequence.sh"
# Stable readiness sequence check emitted by require_executable:
# cells-aws-readiness-sequence=present
CELLS_OPERATOR_SMOKE="${ROOT_DIR}/scripts/smoke-cells-operator.sh"
CELLS_OPERATOR_PREFLIGHT="${ROOT_DIR}/scripts/preflight-cells-operator.sh"
CELLS_OPERATOR_SCOPE_DECISION="${ROOT_DIR}/docs/project/plans/2026-05-16-cells-operator-scope-decision.md"
AGENT_WORKSPACE_RELEASE_PREFLIGHT="${ROOT_DIR}/scripts/preflight-agent-workspace-release.sh"
AGENT_WORKSPACE_PRODUCT_UX_SMOKE="${ROOT_DIR}/scripts/smoke-agent-workspace-product-ux.sh"
AGENT_WORKSPACE_PRODUCT_UX_PREFLIGHT="${ROOT_DIR}/scripts/preflight-agent-workspace-product-ux.sh"
AGENT_TEAMS_PROVIDER_COVERAGE_PREFLIGHT="${ROOT_DIR}/scripts/preflight-agent-teams-provider-coverage.sh"
AGENT_TEAMS_GRAPH_PERFORMANCE_SMOKE="${ROOT_DIR}/scripts/smoke-agent-teams-graph-performance.sh"
AGENT_TEAMS_GRAPH_PERFORMANCE_PREFLIGHT="${ROOT_DIR}/scripts/preflight-agent-teams-graph-performance.sh"
E2E_MATRIX_SMOKE="${ROOT_DIR}/scripts/smoke-agent-workspace-e2e-matrices.sh"
A11Y_SMOKE="${ROOT_DIR}/scripts/smoke-agent-workspace-a11y.sh"
COCXYCORE_MOAT_SMOKE="${ROOT_DIR}/scripts/smoke-cocxycore-moat.sh"

BLOCKERS=()
CHECKS=()
BLOCKER_COUNT=0
FINAL_REPORT_DECLARED_STATUS=""

record_check() {
  CHECKS+=("$1")
}

blocker() {
  BLOCKERS+=("$1")
  BLOCKER_COUNT=$((BLOCKER_COUNT + 1))
}

count_browser_commands() {
  grep -E '^[[:space:]]+case browser[A-Z]' "${ROOT_DIR}/CLI/Lib/Shared/CLICommandDefinition.swift" | wc -l | tr -d ' '
}

count_browser_mcp_tools() {
  grep -E '^[[:space:]]+spec\("browser_' "${ROOT_DIR}/Sources/Domain/MCP/BrowserMCPTool.swift" | wc -l | tr -d ' '
}

count_swift_files_under() {
  local directory="$1"
  if [ ! -d "$directory" ]; then
    echo 0
    return 0
  fi

  find "$directory" -maxdepth 1 -type f -name '*.swift' -print 2>/dev/null |
    wc -l |
    tr -d ' '
}

count_notebook_cli_commands() {
  grep -E '^[[:space:]]+case notebook[A-Z]' "${ROOT_DIR}/CLI/Lib/Shared/CLICommandDefinition.swift" |
    wc -l |
    tr -d ' '
}

count_vault_builtin_agents() {
  grep -E '^[[:space:]]+VaultAgent\(' "${ROOT_DIR}/Sources/Domain/Vault/VaultBuiltInAgents.swift" |
    wc -l |
    tr -d ' '
}

count_remote_docker_manifest_rows() {
  "${REMOTE_DOCKER_SMOKE}" --matrix-manifest |
    awk -F '\t' 'NR > 1 && $2 == "implemented" { count++ } END { print count + 0 }'
}

latest_artifact_with_fields() {
  local directory="$1"
  local pattern="$2"
  shift 2
  if [ ! -d "$directory" ]; then
    return 1
  fi

  local file
  file="$(
    find "$directory" -maxdepth 2 -type f -name "$pattern" -print 2>/dev/null |
      LC_ALL=C sort -r |
      head -1
  )"
  if [ -z "$file" ]; then
    return 1
  fi

  if ! grep -q '^status=ok$' "$file"; then
    return 1
  fi

  local field
  for field in "$@"; do
    if ! grep -q "^${field}$" "$file"; then
      return 1
    fi
  done

  printf '%s\n' "$file"
  return 0
}

latest_artifact() {
  local directory="$1"
  local pattern="$2"
  if [ ! -d "$directory" ]; then
    return 1
  fi

  local file
  file="$(
    find "$directory" -maxdepth 2 -type f -name "$pattern" -print 2>/dev/null |
      LC_ALL=C sort -r |
      head -1
  )"
  if [ -z "$file" ]; then
    return 1
  fi

  printf '%s\n' "$file"
  return 0
}

artifact_field() {
  local file="$1"
  local field="$2"
  sed -n "s/^${field}=//p" "$file" | tail -1
}

resolve_artifact_path() {
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

verify_referenced_file() {
  local summary="$1"
  local path_field="$2"
  local hash_field="${path_field}Sha256"
  verify_referenced_file_with_hash "$summary" "$path_field" "$hash_field"
}

verify_referenced_file_with_hash() {
  local summary="$1"
  local path_field="$2"
  local hash_field="$3"
  local raw_path
  local expected_hash
  local path

  raw_path="$(artifact_field "$summary" "$path_field")"
  expected_hash="$(artifact_field "$summary" "$hash_field")"
  if [ -z "$raw_path" ] || [ -z "$expected_hash" ]; then
    return 1
  fi

  path="$(resolve_artifact_path "$raw_path")"
  if [ ! -f "$path" ]; then
    return 1
  fi

  [ "$(sha256_file "$path")" = "$expected_hash" ]
}

verify_file_hash() {
  local raw_path="$1"
  local expected_hash="$2"
  local path
  if [ -z "$raw_path" ] || [ -z "$expected_hash" ]; then
    return 1
  fi

  path="$(resolve_artifact_path "$raw_path")"
  if [ ! -f "$path" ]; then
    return 1
  fi

  [ "$(sha256_file "$path")" = "$expected_hash" ]
}

verify_release_preflight_summary() {
  local preflight="$1"
  local raw_summary
  local summary
  local requirement

  raw_summary="$(artifact_field "$preflight" summary)"
  if [ -z "$raw_summary" ]; then
    return 1
  fi

  summary="$(resolve_artifact_path "$raw_summary")"
  if [ ! -f "$summary" ]; then
    return 1
  fi

  if awk -F '\t' 'NR > 1 && $2 == "blocked" { found = 1 } END { exit found ? 0 : 1 }' "$summary"; then
    return 1
  fi

  for requirement in \
    resources-info-version \
    cli-fallback-version \
    bundle-info-version \
    bundle-contents-verification \
    bundle-codesign-verification \
    bundle-cli-version \
    cells-cloud-account-readiness \
    dmg-artifact \
    dmg-image-verification \
    dmg-codesign-verification \
    appcast-version \
    appcast-dmg-reference \
    appcast-sparkle-signature \
    appcast-enclosure-length \
    changelog-version \
    local-release-tag
  do
    awk -F '\t' -v requirement="$requirement" \
      'NR > 1 && $1 == requirement && $2 == "ok" { found = 1 } END { exit found ? 0 : 1 }' \
      "$summary" || return 1
  done

  return 0
}

record_release_preflight_blockers() {
  local preflight="$1"
  local raw_summary
  local summary
  local requirement
  local status
  local evidence
  local detail

  raw_summary="$(artifact_field "$preflight" summary)"
  if [ -z "$raw_summary" ]; then
    blocker "Agent Workspace OS release preflight missing summary path in ${preflight#${ROOT_DIR}/}"
    return 0
  fi

  summary="$(resolve_artifact_path "$raw_summary")"
  if [ ! -f "$summary" ]; then
    blocker "Agent Workspace OS release preflight summary missing: ${raw_summary}"
    return 0
  fi

  while IFS=$'\t' read -r requirement status evidence detail; do
    if [ "$requirement" = "requirement" ]; then
      continue
    fi
    if [ "$status" = "blocked" ]; then
      blocker "Agent Workspace OS release preflight blocked: ${requirement} evidence=${evidence} detail=${detail}"
    fi
  done < "$summary"
}

verify_agent_teams_provider_preflight_summary() {
  local preflight="$1"
  local raw_summary
  local summary
  local raw_process_summary
  local process_summary

  raw_summary="$(artifact_field "$preflight" summary)"
  if [ -z "$raw_summary" ]; then
    return 1
  fi

  summary="$(resolve_artifact_path "$raw_summary")"
  if [ ! -f "$summary" ]; then
    return 1
  fi

  awk -F '\t' '
    BEGIN {
      expected["claude-code"] = 1
      expected["codex"] = 1
      expected["opencode"] = 1
      expected["pi"] = 1
      expected["cursor"] = 1
      expected["gemini"] = 1
      expected["rovo-dev"] = 1
      expected["copilot"] = 1
      expected["codebuddy"] = 1
      expected["factory"] = 1
      expected["qoder"] = 1
      expected["kiro"] = 1
      expected_count = 12
    }
    NR == 1 {
      if ($1 != "provider" || $2 != "status" || $3 != "binary") {
        invalid = 1
      }
      next
    }
    NR > 1 {
      total++
      if (!($1 in expected) || seen[$1] || $2 != "available" || $3 == "" || $3 == "-") {
        invalid = 1
      }
      seen[$1] = 1
    }
    END {
      for (provider in expected) {
        if (!seen[provider]) {
          invalid = 1
        }
      }
      exit (!invalid && total == expected_count) ? 0 : 1
    }
  ' "$summary" || return 1

  raw_process_summary="$(artifact_field "$preflight" latestProviderProcessSummary)"
  if [ -z "$raw_process_summary" ]; then
    return 1
  fi
  process_summary="$(resolve_artifact_path "$raw_process_summary")"
  if [ ! -f "$process_summary" ]; then
    return 1
  fi
  verify_agent_teams_provider_process_summary "$process_summary"
}

verify_agent_teams_provider_process_summary() {
  local summary="$1"
  local raw_manifest
  local manifest
  local provider
  local hook_agent
  local binary
  local process_path
  local process_hash
  local dry_path
  local dry_hash
  local install_path
  local install_hash
  local check_path
  local check_hash
  local hook_path
  local hook_hash
  local remove_path
  local remove_hash

  grep -q '^status=ok$' "$summary" || return 1
  grep -q '^installedProviders=12$' "$summary" || return 1
  grep -q '^passedProviders=12$' "$summary" || return 1
  grep -q '^result=agent-teams-provider-process-ok$' "$summary" || return 1
  verify_referenced_file_with_hash "$summary" "providerEvidence" "providerEvidenceSha256" || return 1

  raw_manifest="$(artifact_field "$summary" providerEvidence)"
  manifest="$(resolve_artifact_path "$raw_manifest")"
  awk -F '\t' '
    BEGIN {
      expected["claude-code"] = "claude"
      expected["codex"] = "codex"
      expected["opencode"] = "opencode"
      expected["pi"] = "pi"
      expected["cursor"] = "cursor"
      expected["gemini"] = "gemini"
      expected["rovo-dev"] = "rovo-dev"
      expected["copilot"] = "copilot"
      expected["codebuddy"] = "codebuddy"
      expected["factory"] = "factory"
      expected["qoder"] = "qoder"
      expected["kiro"] = "kiro"
      expected_count = 12
    }
    NR == 1 {
      if ($1 != "providerID" || $2 != "hookAgent" || $3 != "binary") {
        invalid = 1
      }
      next
    }
    NR > 1 {
      total++
      if (!($1 in expected) || seen[$1] || $2 != expected[$1] || $3 == "" || $3 == "-") {
        invalid = 1
      }
      seen[$1] = 1
    }
    END {
      for (provider in expected) {
        if (!seen[provider]) {
          invalid = 1
        }
      }
      exit (!invalid && total == expected_count) ? 0 : 1
    }
  ' "$manifest" || return 1

  while IFS=$'\t' read -r provider hook_agent binary process_path process_hash dry_path dry_hash install_path install_hash check_path check_hash hook_path hook_hash remove_path remove_hash; do
    if [ "$provider" = "providerID" ]; then
      continue
    fi
    [ -n "$hook_agent" ] || return 1
    [ -n "$binary" ] || return 1
    verify_file_hash "$process_path" "$process_hash" || return 1
    verify_file_hash "$dry_path" "$dry_hash" || return 1
    verify_file_hash "$install_path" "$install_hash" || return 1
    verify_file_hash "$check_path" "$check_hash" || return 1
    verify_file_hash "$hook_path" "$hook_hash" || return 1
    verify_file_hash "$remove_path" "$remove_hash" || return 1
  done < "$manifest"

  return 0
}

verify_product_ux_evidence() {
  local summary="$1"
  verify_referenced_file_with_hash "$summary" "acceptanceFile" "acceptanceSha256" || return 1
  verify_referenced_file_with_hash "$summary" "a11ySummary" "a11ySummarySha256" || return 1
  verify_referenced_file_with_hash "$summary" "visualSummary" "visualSummarySha256" || return 1
  verify_referenced_file_with_hash "$summary" "bundleSummary" "bundleSummarySha256" || return 1
  return 0
}

latest_product_ux_summary() {
  local directory="${ROOT_DIR}/build/agent-workspace-product-ux"
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
     verify_product_ux_evidence "$file"; then
    printf '%s\n' "$file"
    return 0
  fi

  return 1
}

latest_product_ux_any_summary() {
  local directory="${ROOT_DIR}/build/agent-workspace-product-ux"
  if [ ! -d "$directory" ]; then
    return 1
  fi

  find "$directory" -maxdepth 2 -type f -name summary.txt -print 2>/dev/null |
    LC_ALL=C sort -r |
    head -1
}

record_product_ux_smoke_blocker() {
  local summary
  local reason
  local acceptance_file

  summary="$(latest_product_ux_any_summary || true)"
  if [ -z "$summary" ]; then
    blocker "Agent Workspace OS product UX has no archived release-candidate summary.txt with six surfaces, manual VoiceOver, keyboard, reduce motion, contrast acceptance, reviewer, and hashed evidence"
    return 0
  fi

  reason="$(artifact_field "$summary" reason)"
  acceptance_file="$(artifact_field "$summary" acceptanceFile)"
  blocker "Agent Workspace OS product UX latest smoke blocked: ${summary#${ROOT_DIR}/} reason=${reason:-unknown} acceptanceFile=${acceptance_file:-missing}"
}

record_product_ux_acceptance_state() {
  local acceptance_file="${ROOT_DIR}/build/agent-workspace-product-ux/manual-acceptance/acceptance.txt"
  local template_file="${ROOT_DIR}/build/agent-workspace-product-ux/manual-acceptance/acceptance-template.txt"
  local reviewer

  if [ -f "$acceptance_file" ]; then
    reviewer="$(sed -n 's/^Reviewer:[[:space:]]*//p' "$acceptance_file" | head -1)"
    if grep -q '^Status: Accepted for v1.18.0 release candidate\.$' "$acceptance_file" &&
       [ -n "$reviewer" ]; then
      record_check "agent-workspace-product-ux-manual-acceptance=accepted"
    elif grep -q '^Status: Accepted for v1.18.0 release candidate\.$' "$acceptance_file"; then
      record_check "agent-workspace-product-ux-manual-acceptance=missing-reviewer"
    else
      record_check "agent-workspace-product-ux-manual-acceptance=not-accepted"
    fi
  elif [ -f "$template_file" ]; then
    record_check "agent-workspace-product-ux-manual-acceptance=template-only"
  else
    record_check "agent-workspace-product-ux-manual-acceptance=missing"
  fi
}

verify_summary_hash_for_basename() {
  local summary="$1"
  local expected_basename="$2"
  local expected_hash
  local raw_path

  while read -r expected_hash raw_path; do
    if [ -z "$expected_hash" ] || [ -z "$raw_path" ]; then
      continue
    fi
    if [ "$(basename "$raw_path")" = "$expected_basename" ]; then
      verify_file_hash "$raw_path" "$expected_hash"
      return $?
    fi
  done < <(
    awk 'length($1) == 64 && $2 != "" { print $1 " " $2 }' "$summary"
  )

  return 1
}

verify_agent_workspace_ui_smoke_summary() {
  local summary="$1"
  grep -q '^status=ok$' "$summary" || return 1
  grep -q '^commandPalette=cells,vault,browser ok$' "$summary" || return 1
  grep -Eq '^dashboard=session_count=[0-9]+ active_count=[0-9]+ subagent_count=2 active_subagent_count=2$' "$summary" || return 1
  grep -Eq '^browserDevTools=opened consoleCount=[1-9][0-9]* message=.+$' "$summary" || return 1
  grep -Eq '^remotePorts=connected forwardedLocalPort=[0-9]+ suggestion=localhost:3000$' "$summary" || return 1
  grep -q '^agentTeams=created team with Planner,Reviewer$' "$summary" || return 1
  grep -q '^codeReview=visible empty diff state$' "$summary" || return 1
  grep -q '^cleanup=ok$' "$summary" || return 1

  for evidence_basename in \
    28-final4-command-palette-cells.png \
    29-final4-command-palette-vault.png \
    30-final4-command-palette-browser.png \
    26-final3-dashboard-agent-team.png \
    16c-final-browser-devtools-console-visible.png \
    17-final-remote-sidebar-suggestions.png \
    18-final-code-review-panel.png \
    31-cleanup-final-summary.txt
  do
    verify_summary_hash_for_basename "$summary" "$evidence_basename" || return 1
  done

  return 0
}

latest_agent_workspace_ui_smoke_summary() {
  local directory="${ROOT_DIR}/build/agent-workspace-ui-smoke"
  local file
  if [ ! -d "$directory" ]; then
    return 1
  fi

  file="$(
    find "$directory" -maxdepth 2 -type f -name summary-final.txt -print 2>/dev/null |
      LC_ALL=C sort -r |
      head -1
  )"
  if [ -z "$file" ]; then
    return 1
  fi

  if verify_agent_workspace_ui_smoke_summary "$file"; then
    printf '%s\n' "$file"
    return 0
  fi

  return 1
}

verify_cells_cloud_evidence() {
  local summary="$1"
  local field
  for field in \
    createOutput \
    statusOutput \
    execOutput \
    logsOutput \
    attachOutput \
    listOutput \
    destroyOutput
  do
    verify_referenced_file "$summary" "$field" || return 1
  done
  return 0
}

latest_cells_cloud_summary() {
  local provider="$1"
  local directory="${ROOT_DIR}/build/cells-cloud-${provider}"
  local file
  if [ ! -d "$directory" ]; then
    return 1
  fi

  while IFS= read -r file; do
    if grep -q '^status=ok$' "$file" &&
       grep -q "^provider=${provider}$" "$file" &&
       grep -q '^create=ok$' "$file" &&
       grep -q '^status-check=ok$' "$file" &&
       grep -q '^exec=ok$' "$file" &&
       grep -q '^logs=ok$' "$file" &&
       grep -q '^attach=ok$' "$file" &&
       grep -q '^list=ok$' "$file" &&
       grep -q '^destroy=ok$' "$file" &&
       grep -q "^result=cells-cloud-${provider}-ok$" "$file" &&
       verify_cells_cloud_evidence "$file"; then
      printf '%s\n' "$file"
      return 0
    fi
  done < <(
    find "$directory" -maxdepth 2 -type f -name summary.txt -print 2>/dev/null |
      LC_ALL=C sort -r
  )

  return 1
}

latest_cells_cloud_any_summary() {
  local provider="$1"
  local directory="${ROOT_DIR}/build/cells-cloud-${provider}"
  if [ ! -d "$directory" ]; then
    return 1
  fi

  find "$directory" -maxdepth 2 -type f -name summary.txt -print 2>/dev/null |
    LC_ALL=C sort -r |
    head -1
}

record_cells_cloud_latest_smoke_failure() {
  local provider="$1"
  local summary
  local status
  local reason
  local output

  summary="$(latest_cells_cloud_any_summary "$provider" || true)"
  if [ -z "$summary" ]; then
    record_check "cells-cloud-${provider}-latest-smoke=missing"
    record_check "cells-cloud-${provider}-latest-smoke-status=missing"
    record_check "cells-cloud-${provider}-latest-smoke-reason=missing"
    record_check "cells-cloud-${provider}-latest-smoke-output=missing"
    return 0
  fi

  status="$(artifact_field "$summary" status)"
  reason="$(artifact_field "$summary" reason)"
  output="$(artifact_field "$summary" output)"

  record_check "cells-cloud-${provider}-latest-smoke=${summary#${ROOT_DIR}/}"
  record_check "cells-cloud-${provider}-latest-smoke-status=${status:-unknown}"
  record_check "cells-cloud-${provider}-latest-smoke-reason=${reason:-unknown}"
  record_existing_path_check "cells-cloud-${provider}-latest-smoke-output" "$output"

  if [ "${status:-unknown}" != "ok" ]; then
    blocker "Cells cloud account latest ${provider} smoke failed: status=${status:-unknown} reason=${reason:-unknown} output=${output:-missing}"
  fi
}

latest_aws_setup_verify_summary() {
  local directory="${ROOT_DIR}/build/cells-aws-setup-verify"
  if [ ! -d "$directory" ]; then
    return 1
  fi

  find "$directory" -maxdepth 2 -type f -name summary.txt -exec sh -c '
    for path do
      mtime="$(stat -f "%m" "$path" 2>/dev/null || stat -c "%Y" "$path" 2>/dev/null || echo 0)"
      printf "%s\t%s\n" "$mtime" "$path"
    done
  ' sh {} + 2>/dev/null |
    LC_ALL=C sort -rn |
    cut -f2- |
    head -1
}

setup_verify_check_status() {
  local checks="$1"
  local check_name="$2"

  if [ -z "$checks" ]; then
    return 1
  fi

  checks="$(resolve_artifact_path "$checks")"
  if [ ! -f "$checks" ]; then
    return 1
  fi

  awk -F '\t' -v check_name="$check_name" \
    'NR > 1 && $1 == check_name { print $2; exit }' \
    "$checks"
}

record_aws_setup_verify_summary() {
  local summary
  local checks
  local remediation
  local status
  local blockers
  local profile_dry_run
  local profile_arn_dry_run
  local without_profile_dry_run

  summary="$(latest_aws_setup_verify_summary || true)"
  if [ -z "$summary" ]; then
    record_check "cells-aws-setup-verify-latest=missing"
    record_check "cells-aws-setup-verify-status=missing"
    record_check "cells-aws-setup-verify-blockers=unknown"
    record_check "cells-aws-setup-verify-profile-dry-run=unknown"
    record_check "cells-aws-setup-verify-profile-arn-dry-run=unknown"
    record_check "cells-aws-setup-verify-without-profile-dry-run=unknown"
    return 0
  fi

  status="$(artifact_field "$summary" status)"
  blockers="$(artifact_field "$summary" blockers)"
  checks="$(artifact_field "$summary" checks)"
  remediation="$(artifact_field "$summary" remediation)"
  profile_dry_run="$(setup_verify_check_status "$checks" run-instances-with-profile-dry-run || true)"
  profile_arn_dry_run="$(setup_verify_check_status "$checks" run-instances-with-profile-arn-dry-run || true)"
  without_profile_dry_run="$(setup_verify_check_status "$checks" run-instances-without-profile-dry-run || true)"

  record_check "cells-aws-setup-verify-latest=${summary#${ROOT_DIR}/}"
  record_check "cells-aws-setup-verify-status=${status:-unknown}"
  record_check "cells-aws-setup-verify-blockers=${blockers:-unknown}"
  record_check "cells-aws-setup-verify-profile-dry-run=${profile_dry_run:-unknown}"
  record_check "cells-aws-setup-verify-profile-arn-dry-run=${profile_arn_dry_run:-unknown}"
  record_check "cells-aws-setup-verify-without-profile-dry-run=${without_profile_dry_run:-unknown}"
  record_existing_path_check "cells-aws-setup-verify-checks" "$checks"
  record_existing_path_check "cells-aws-setup-verify-remediation" "$remediation"

  if [ "$status" = "blocked" ]; then
    blocker "AWS setup verifier blocked: blockers=${blockers:-unknown}"
  elif [ "$status" != "ok" ] && [ "$status" != "ready" ]; then
    blocker "AWS setup verifier has unknown status: ${status:-missing}"
  fi
}

latest_cells_aws_readonly_diagnostics_summary() {
  local directory="${ROOT_DIR}/build/cells-aws-readonly-diagnostics"
  if [ ! -d "$directory" ]; then
    return 1
  fi

  find "$directory" -maxdepth 2 -type f -name summary.txt -exec sh -c '
    for path do
      mtime="$(stat -f "%m" "$path" 2>/dev/null || stat -c "%Y" "$path" 2>/dev/null || echo 0)"
      printf "%s\t%s\n" "$mtime" "$path"
    done
  ' sh {} + 2>/dev/null |
    LC_ALL=C sort -rn |
    cut -f2- |
    head -1
}

record_cells_aws_readonly_diagnostics_summary() {
  local summary
  local caller_identity
  local associations
  local simulate_policy
  local describe_image

  summary="$(latest_cells_aws_readonly_diagnostics_summary || true)"
  if [ -z "$summary" ]; then
    record_check "cells-aws-readonly-diagnostics-latest=missing"
    record_check "cells-aws-readonly-diagnostics-describe-image-exit=unknown"
    record_check "cells-aws-readonly-diagnostics-image-state=unknown"
    record_check "cells-aws-readonly-diagnostics-associations-exit=unknown"
    record_check "cells-aws-readonly-diagnostics-associations=unknown"
    record_check "cells-aws-readonly-diagnostics-simulate-principal-policy-exit=unknown"
    record_check "cells-aws-readonly-diagnostics-simulate-principal-policy=unknown"
    return 0
  fi

  caller_identity="$(artifact_field "$summary" callerIdentity)"
  associations="$(artifact_field "$summary" ec2InstanceProfileAssociations)"
  simulate_policy="$(artifact_field "$summary" simulatePrincipalPolicy)"
  describe_image="$(artifact_field "$summary" describeImage)"

  record_check "cells-aws-readonly-diagnostics-latest=${summary#${ROOT_DIR}/}"
  record_check "cells-aws-readonly-diagnostics-caller-identity-exit=$(artifact_field "$summary" callerIdentityExit)"
  record_check "cells-aws-readonly-diagnostics-associations-exit=$(artifact_field "$summary" associationsExit)"
  record_check "cells-aws-readonly-diagnostics-simulate-principal-policy-exit=$(artifact_field "$summary" simulatePrincipalPolicyExit)"
  record_check "cells-aws-readonly-diagnostics-describe-image-exit=$(artifact_field "$summary" describeImageExit)"
  record_existing_path_check "cells-aws-readonly-diagnostics-caller-identity" "$caller_identity"
  record_existing_path_check "cells-aws-readonly-diagnostics-associations-output" "$associations"
  record_existing_path_check "cells-aws-readonly-diagnostics-simulate-principal-policy-error" "$simulate_policy"
  record_existing_path_check "cells-aws-readonly-diagnostics-describe-image-output" "$describe_image"

  describe_image="$(resolve_artifact_path "$describe_image")"
  if [ -f "$describe_image" ] && grep -q '"State": "available"' "$describe_image"; then
    record_check "cells-aws-readonly-diagnostics-image-state=available"
  else
    record_check "cells-aws-readonly-diagnostics-image-state=unknown"
  fi

  associations="$(resolve_artifact_path "$associations")"
  if [ -f "$associations" ] && grep -q '"IamInstanceProfileAssociations": \[\]' "$associations"; then
    record_check "cells-aws-readonly-diagnostics-associations=empty"
  else
    record_check "cells-aws-readonly-diagnostics-associations=unknown"
  fi

  simulate_policy="$(resolve_artifact_path "$simulate_policy")"
  if [ -f "$simulate_policy" ] && grep -q 'AccessDenied' "$simulate_policy"; then
    record_check "cells-aws-readonly-diagnostics-simulate-principal-policy=access-denied"
  else
    record_check "cells-aws-readonly-diagnostics-simulate-principal-policy=unknown"
  fi
}

latest_cells_aws_direct_dryrun_summary() {
  local directory="${ROOT_DIR}/build/cells-aws-direct-dryrun"
  if [ ! -d "$directory" ]; then
    return 1
  fi

  find "$directory" -maxdepth 2 -type f -name summary.txt -exec sh -c '
    for path do
      mtime="$(stat -f "%m" "$path" 2>/dev/null || stat -c "%Y" "$path" 2>/dev/null || echo 0)"
      printf "%s\t%s\n" "$mtime" "$path"
    done
  ' sh {} + 2>/dev/null |
    LC_ALL=C sort -rn |
    cut -f2- |
    head -1
}

record_cells_aws_direct_dryrun_summary() {
  local summary
  local env_file
  local with_profile_error
  local without_profile_error
  local env_contents=""
  local subnet
  local security_group
  local key_name

  summary="$(latest_cells_aws_direct_dryrun_summary || true)"
  if [ -z "$summary" ]; then
    record_check "cells-aws-direct-dryrun-latest=missing"
    record_check "cells-aws-direct-dryrun-with-profile=unknown"
    record_check "cells-aws-direct-dryrun-without-profile=unknown"
    record_check "cells-aws-direct-dryrun-subnet=unknown"
    record_check "cells-aws-direct-dryrun-security-group=unknown"
    record_check "cells-aws-direct-dryrun-key=unknown"
    return 0
  fi

  env_file="$(artifact_field "$summary" env)"
  with_profile_error="$(artifact_field "$summary" withProfileError)"
  without_profile_error="$(artifact_field "$summary" withoutProfileError)"

  record_check "cells-aws-direct-dryrun-latest=${summary#${ROOT_DIR}/}"
  record_check "cells-aws-direct-dryrun-with-profile-exit=$(artifact_field "$summary" withProfileExit)"
  record_check "cells-aws-direct-dryrun-without-profile-exit=$(artifact_field "$summary" withoutProfileExit)"
  record_existing_path_check "cells-aws-direct-dryrun-env" "$env_file"
  record_existing_path_check "cells-aws-direct-dryrun-with-profile-error" "$with_profile_error"
  record_existing_path_check "cells-aws-direct-dryrun-without-profile-error" "$without_profile_error"

  env_file="$(resolve_artifact_path "$env_file")"
  if [ -f "$env_file" ]; then
    env_contents="$(cat "$env_file")"
  fi
  subnet="$(text_field "$env_contents" subnet)"
  security_group="$(text_field "$env_contents" sg)"
  key_name="$(text_field "$env_contents" key)"
  record_check "cells-aws-direct-dryrun-subnet=${subnet:-missing}"
  record_check "cells-aws-direct-dryrun-security-group=${security_group:-missing}"
  record_check "cells-aws-direct-dryrun-key=${key_name:-missing}"

  with_profile_error="$(resolve_artifact_path "$with_profile_error")"
  if [ -f "$with_profile_error" ] && grep -q 'Invalid IAM Instance Profile name' "$with_profile_error"; then
    record_check "cells-aws-direct-dryrun-with-profile=invalid-instance-profile"
  else
    record_check "cells-aws-direct-dryrun-with-profile=unknown"
  fi

  without_profile_error="$(resolve_artifact_path "$without_profile_error")"
  if [ -f "$without_profile_error" ] && grep -q 'DryRunOperation' "$without_profile_error"; then
    record_check "cells-aws-direct-dryrun-without-profile=authorized"
  else
    record_check "cells-aws-direct-dryrun-without-profile=unknown"
  fi
}

latest_cells_aws_profile_diagnostics_summary() {
  local directory="${ROOT_DIR}/build/cells-aws-profile-diagnostics"
  if [ ! -d "$directory" ]; then
    return 1
  fi

  find "$directory" -maxdepth 2 -type f -name summary.txt -exec sh -c '
    for path do
      mtime="$(stat -f "%m" "$path" 2>/dev/null || stat -c "%Y" "$path" 2>/dev/null || echo 0)"
      printf "%s\t%s\n" "$mtime" "$path"
    done
  ' sh {} + 2>/dev/null |
    LC_ALL=C sort -rn |
    cut -f2- |
    head -1
}

record_cells_aws_profile_diagnostics_summary() {
  local summary
  local profile_list
  local identity
  local list_instance_profiles_error
  local configured_profile
  local aws_profile
  local profile_count="unknown"
  local active_identity="unknown"
  local list_instance_profiles_status="unknown"

  summary="$(latest_cells_aws_profile_diagnostics_summary || true)"
  if [ -z "$summary" ]; then
    record_check "cells-aws-profile-diagnostics-latest=missing"
    record_check "cells-aws-profile-diagnostics-configured-profile=unknown"
    record_check "cells-aws-profile-diagnostics-aws-profile=unknown"
    record_check "cells-aws-profile-diagnostics-configured-profile-count=unknown"
    record_check "cells-aws-profile-diagnostics-active-identity=unknown"
    record_check "cells-aws-profile-diagnostics-list-instance-profiles=unknown"
    return 0
  fi

  profile_list="$(artifact_field "$summary" profileList)"
  identity="$(artifact_field "$summary" identity)"
  list_instance_profiles_error="$(artifact_field "$summary" listInstanceProfiles)"
  configured_profile="$(artifact_field "$summary" configuredProfile)"
  aws_profile="$(artifact_field "$summary" awsProfile)"

  record_check "cells-aws-profile-diagnostics-latest=${summary#${ROOT_DIR}/}"
  record_check "cells-aws-profile-diagnostics-configured-profile=${configured_profile:-unknown}"
  record_check "cells-aws-profile-diagnostics-aws-profile=${aws_profile:-missing}"
  record_existing_path_check "cells-aws-profile-diagnostics-profile-list" "$profile_list"
  record_existing_path_check "cells-aws-profile-diagnostics-identity" "$identity"
  record_existing_path_check "cells-aws-profile-diagnostics-list-instance-profiles-error" "$list_instance_profiles_error"

  profile_list="$(resolve_artifact_path "$profile_list")"
  if [ -f "$profile_list" ]; then
    profile_count="$(
      awk 'NF { count++ } END { print count + 0 }' "$profile_list"
    )"
  fi
  record_check "cells-aws-profile-diagnostics-configured-profile-count=${profile_count}"

  identity="$(resolve_artifact_path "$identity")"
  if [ -f "$identity" ]; then
    if grep -q '"Arn"[[:space:]]*:[[:space:]]*"arn:aws:iam::[^"]*:user/' "$identity"; then
      active_identity="user"
    elif grep -q '"Arn"[[:space:]]*:[[:space:]]*"arn:aws:sts::[^"]*:assumed-role/' "$identity"; then
      active_identity="assumed-role"
    elif grep -q '"Arn"[[:space:]]*:' "$identity"; then
      active_identity="present"
    fi
  fi
  record_check "cells-aws-profile-diagnostics-active-identity=${active_identity}"

  list_instance_profiles_error="$(resolve_artifact_path "$list_instance_profiles_error")"
  if [ -f "$list_instance_profiles_error" ] && grep -q 'AccessDenied' "$list_instance_profiles_error"; then
    list_instance_profiles_status="access-denied"
  fi
  record_check "cells-aws-profile-diagnostics-list-instance-profiles=${list_instance_profiles_status}"
}

latest_cells_aws_readiness_sequence_summary() {
  local directory="${ROOT_DIR}/build/cells-aws-readiness-sequence"
  if [ ! -d "$directory" ]; then
    return 1
  fi

  find "$directory" -maxdepth 2 -type f -name summary.txt -exec sh -c '
    for path do
      mtime="$(stat -f "%m" "$path" 2>/dev/null || stat -c "%Y" "$path" 2>/dev/null || echo 0)"
      printf "%s\t%s\n" "$mtime" "$path"
    done
  ' sh {} + 2>/dev/null |
    LC_ALL=C sort -rn |
    cut -f2- |
    head -1
}

readiness_sequence_pre_audit_steps_ok() {
  local steps="$1"
  local step

  steps="$(resolve_artifact_path "$steps")"
  if [ ! -f "$steps" ]; then
    return 1
  fi

  for step in verify-aws-setup preflight-aws smoke-aws preflight-all; do
    awk -F '\t' -v step="$step" '
      NR > 1 && $1 == step && $2 == "ok" && $3 == "0" { found = 1 }
      END { exit found ? 0 : 1 }
    ' "$steps" || return 1
  done

  return 0
}

record_cells_aws_readiness_sequence() {
  local summary
  local status
  local result
  local reason
  local aws_smoke
  local steps

  summary="$(latest_cells_aws_readiness_sequence_summary || true)"
  if [ -z "$summary" ]; then
    record_check "cells-aws-readiness-sequence-latest=missing"
    record_check "cells-aws-readiness-sequence-status=missing"
    record_check "cells-aws-readiness-sequence-result=missing"
    record_check "cells-aws-readiness-sequence-aws-smoke=missing"
    record_check "cells-aws-readiness-sequence-steps=missing"
    blocker "Cells AWS readiness sequence has no archived summary.txt"
    return 0
  fi

  status="$(artifact_field "$summary" status)"
  result="$(artifact_field "$summary" result)"
  reason="$(artifact_field "$summary" reason)"
  aws_smoke="$(artifact_field "$summary" awsSmoke)"
  steps="$(artifact_field "$summary" steps)"

  record_check "cells-aws-readiness-sequence-latest=${summary#${ROOT_DIR}/}"
  record_check "cells-aws-readiness-sequence-status=${status:-unknown}"
  record_check "cells-aws-readiness-sequence-result=${result:-unknown}"
  record_check "cells-aws-readiness-sequence-aws-smoke=${aws_smoke:-unknown}"
  record_existing_path_check "cells-aws-readiness-sequence-steps" "$steps"

  if [ "$status" != "ok" ] || [ "$result" != "cells-aws-readiness-sequence-ok" ]; then
    if [ "$status" = "blocked" ] &&
       [ "$result" = "cells-aws-readiness-sequence-blocked" ] &&
       [ "$reason" = "scripts/audit-agent-workspace-os-completion.sh failed" ] &&
       [ "$aws_smoke" = "ok" ] &&
       readiness_sequence_pre_audit_steps_ok "$steps"; then
      record_check "cells-aws-readiness-sequence-self-audit=pre-audit-steps-ok"
      return 0
    fi
    record_check "cells-aws-readiness-sequence-self-audit=not-ok"
    blocker "Cells AWS readiness sequence blocked: status=${status:-unknown} result=${result:-unknown} awsSmoke=${aws_smoke:-unknown} reason=${reason:-unknown}"
  else
    record_check "cells-aws-readiness-sequence-self-audit=not-needed"
  fi
}

latest_aws_setup_dry_run_summary() {
  local directory="${ROOT_DIR}/build/cells-aws-account-setup"
  if [ ! -d "$directory" ]; then
    return 1
  fi

  find "$directory" -maxdepth 2 -type f -name summary.txt -exec sh -c '
    for path do
      if grep -q "^status=dry-run$" "$path"; then
        mtime="$(stat -f "%m" "$path" 2>/dev/null || stat -c "%Y" "$path" 2>/dev/null || echo 0)"
        printf "%s\t%s\n" "$mtime" "$path"
      fi
    done
  ' sh {} + 2>/dev/null |
    LC_ALL=C sort -rn |
    cut -f2- |
    head -1
}

record_aws_owner_handoff() {
  local summary
  local bundle_dir
  local handoff
  local setup_policy
  local verify_script

  summary="$(latest_aws_setup_dry_run_summary || true)"
  if [ -z "$summary" ]; then
    record_check "cells-aws-setup-dryrun-latest=missing"
    record_check "cells-aws-owner-handoff=missing"
    return 0
  fi

  bundle_dir="$(dirname "$summary")"
  handoff="${bundle_dir}/AWS_OWNER_APPLY_README.md"
  setup_policy="${bundle_dir}/setup-principal-policy.json"
  verify_script="$(artifact_field "$summary" verifyScript)"
  record_check "cells-aws-setup-dryrun-latest=${summary#${ROOT_DIR}/}"
  record_existing_path_check "cells-aws-setup-principal-policy" "$setup_policy"
  record_policy_action_check \
    "cells-aws-setup-principal-policy-passrole" \
    "$setup_policy" \
    "iam:PassRole" \
    "AWS setup principal policy missing iam:PassRole for AddRoleToInstanceProfile"
  record_existing_path_check "cells-aws-setup-generated-verify-script" "$verify_script"
  record_file_contains_check \
    "cells-aws-setup-generated-verify-script-dryrun-operation" \
    "$verify_script" \
    "DryRunOperation" \
    "AWS setup generated verifier does not treat EC2 DryRunOperation as authorized"
  record_file_contains_check \
    "cells-aws-setup-generated-verify-script-profile-arn-dry-run" \
    "$verify_script" \
    "run-instances-with-profile-arn-dry-run" \
    "AWS setup generated verifier does not check instance profile ARN dry-run"
  record_file_contains_check \
    "cells-aws-setup-generated-verify-script-runner" \
    "$verify_script" \
    "run_ec2_dry_run()" \
    "AWS setup generated verifier is missing the reusable EC2 dry-run runner"

  if [ ! -f "$handoff" ]; then
    record_check "cells-aws-owner-handoff=missing"
    blocker "AWS owner handoff missing for latest dry-run setup bundle: ${handoff#${ROOT_DIR}/}"
    return 0
  fi

  record_check "cells-aws-owner-handoff=${handoff#${ROOT_DIR}/}"
  record_file_contains_check \
    "cells-aws-owner-handoff-image-export" \
    "$handoff" \
    "export COCXY_AWS_IMAGE=<valid-ami-for-region>" \
    "AWS owner handoff missing COCXY_AWS_IMAGE export before setup apply"
  record_file_contains_check \
    "cells-aws-owner-handoff-propagation-guardrail" \
    "$handoff" \
    "dry-run accepts" \
    "AWS owner handoff missing EC2 dry-run propagation guardrail"
  record_file_contains_check \
    "cells-aws-owner-handoff-dryrun-not-runtime" \
    "$handoff" \
    "DryRunOperation\` RunInstances result as exec/logs/attach" \
    "AWS owner handoff does not warn that EC2 DryRunOperation is not SSM runtime proof"
  record_file_contains_check \
    "cells-aws-owner-handoff-ssm-runtime-required" \
    "$handoff" \
    "AWS is not complete until SSM runtime is proven" \
    "AWS owner handoff missing SSM runtime completion criterion"
  if grep -Eq '[0-9]{12}|AKIA|aws_secret|AWS_SECRET|BEGIN PRIVATE|PRIVATE KEY|token|password' "$handoff"; then
    record_check "cells-aws-owner-handoff-secret-scan=blocked"
    blocker "AWS owner handoff contains a secret-like value: ${handoff#${ROOT_DIR}/}"
  else
    record_check "cells-aws-owner-handoff-secret-scan=clean"
  fi

  if grep -q 'Do not run this from CI\.' "$handoff" &&
     grep -q 'Do not treat the dry-run bundle as AWS lifecycle success\.' "$handoff" &&
     grep -Fq 'DryRunOperation` RunInstances result as exec/logs/attach' "$handoff" &&
     grep -Fq 'AWS is not complete until SSM runtime is proven' "$handoff" &&
     grep -q 'COCXY_AWS_SETUP_APPLY=1 scripts/setup-cells-aws-account.sh' "$handoff" &&
     grep -q 'scripts/verify-cells-aws-setup.sh' "$handoff" &&
     grep -q 'scripts/preflight-cells-cloud-account.sh aws' "$handoff" &&
     grep -q 'scripts/smoke-cells-cloud-account.sh aws' "$handoff" &&
     grep -q 'scripts/run-cells-aws-readiness-sequence.sh' "$handoff" &&
     grep -q 'scripts/preflight-cells-cloud-account.sh all' "$handoff" &&
     grep -q 'complete=5' "$handoff" &&
     grep -q '^## Definition Of Done$' "$handoff" &&
     grep -q 'result=cells-cloud-aws-ok' "$handoff" &&
     grep -q 'no longer reports AWS' "$handoff"; then
    record_check "cells-aws-owner-handoff-guardrails=present"
  else
    record_check "cells-aws-owner-handoff-guardrails=missing"
    blocker "AWS owner handoff missing setup, verifier, preflight, smoke, readiness sequence, aggregate, definition-of-done, no-publish, or SSM-runtime guardrails"
  fi
}

latest_cells_cloud_all_preflight() {
  local directory="${ROOT_DIR}/build/cells-cloud-preflight"
  if [ ! -d "$directory" ]; then
    return 1
  fi

  local file
  while IFS= read -r file; do
    local summary
    local provider_count
    summary="$(dirname "$file")/summary.tsv"
    if [ ! -f "$summary" ]; then
      continue
    fi

    provider_count="$(
      awk -F '\t' 'NR > 1 { count++ } END { print count + 0 }' "$summary"
    )"
    if [ "$provider_count" = "5" ]; then
      printf '%s\n' "$file"
      return 0
    fi
  done < <(
    find "$directory" -maxdepth 2 -type f -name preflight.txt -exec sh -c '
      for path do
        mtime="$(stat -f "%m" "$path" 2>/dev/null || stat -c "%Y" "$path" 2>/dev/null || echo 0)"
        printf "%s\t%s\n" "$mtime" "$path"
      done
    ' sh {} + 2>/dev/null |
      LC_ALL=C sort -rn |
      cut -f2-
  )

  return 1
}

latest_cells_cloud_provider_preflight() {
  local provider="$1"
  local directory="${ROOT_DIR}/build/cells-cloud-preflight"
  if [ ! -d "$directory" ]; then
    return 1
  fi

  local file
  while IFS= read -r file; do
    local summary
    summary="$(dirname "$file")/summary.tsv"
    if [ ! -f "$summary" ]; then
      continue
    fi

    if awk -F '\t' -v provider="$provider" \
      'NR > 1 && $1 == provider { found = 1 } END { exit found ? 0 : 1 }' \
      "$summary"; then
      printf '%s\n' "$file"
      return 0
    fi
  done < <(
    find "$directory" -maxdepth 2 -type f -name preflight.txt -exec sh -c '
      for path do
        mtime="$(stat -f "%m" "$path" 2>/dev/null || stat -c "%Y" "$path" 2>/dev/null || echo 0)"
        printf "%s\t%s\n" "$mtime" "$path"
      done
    ' sh {} + 2>/dev/null |
      LC_ALL=C sort -rn |
      cut -f2-
  )

  return 1
}

provider_preflight_field() {
  local preflight="$1"
  local provider="$2"
  local field="$3"
  local summary
  local column

  summary="$(dirname "$preflight")/summary.tsv"
  if [ ! -f "$summary" ]; then
    return 1
  fi

  case "$field" in
    status) column=2 ;;
    tool) column=3 ;;
    toolStatus) column=4 ;;
    missingPrerequisites) column=5 ;;
    okArtifact) column=6 ;;
    latestSmokeArtifact) column=7 ;;
    latestSmokeStatus) column=8 ;;
    latestSmokeReason) column=9 ;;
    latestSmokeOutput) column=10 ;;
    *) return 1 ;;
  esac

  awk -F '\t' -v provider="$provider" -v column="$column" '
    NR > 1 && $1 == provider {
      found = 1
      if (column <= NF && $column != "") {
        print $column
        exit 0
      }
      exit 1
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "$summary"
}

record_cells_cloud_preflight_blockers() {
  local preflight="$1"
  local summary
  local provider
  local status
  local tool
  local tool_status
  local missing_prerequisites
  local artifact

  summary="$(dirname "$preflight")/summary.tsv"
  if [ ! -f "$summary" ]; then
    blocker "Cells cloud preflight has no summary.tsv next to ${preflight#${ROOT_DIR}/}"
    return 0
  fi

  while IFS=$'\t' read -r provider status tool tool_status missing_prerequisites artifact; do
    if [ "$provider" = "provider" ]; then
      continue
    fi
    if [ "$status" = "blocked" ]; then
      blocker "Cells cloud preflight blocked: ${provider} toolStatus=${tool_status} missingPrerequisites=${missing_prerequisites}"
    fi
  done < "$summary"
}

record_cells_cloud_diagnostics() {
  local preflight="$1"
  local raw_diagnostics
  local diagnostics
  local compute_enabled

  raw_diagnostics="$(artifact_field "$preflight" gcpDiagnostics)"
  if [ -z "$raw_diagnostics" ]; then
    record_check "cells-cloud-gcp-diagnostics=missing"
    record_check "cells-cloud-gcp-compute-api=unknown"
    return 0
  fi

  diagnostics="$(resolve_artifact_path "$raw_diagnostics")"
  if [ ! -f "$diagnostics" ]; then
    record_check "cells-cloud-gcp-diagnostics=missing-file"
    record_check "cells-cloud-gcp-compute-api=unknown"
    return 0
  fi

  compute_enabled="$(artifact_field "$diagnostics" computeApiEnabled)"
  record_check "cells-cloud-gcp-diagnostics=${diagnostics#${ROOT_DIR}/}"
  case "$compute_enabled" in
    yes) record_check "cells-cloud-gcp-compute-api=enabled" ;;
    no) record_check "cells-cloud-gcp-compute-api=disabled" ;;
    *) record_check "cells-cloud-gcp-compute-api=unknown" ;;
  esac
}

record_existing_path_check() {
  local label="$1"
  local raw_path="$2"
  local path

  if [ -z "$raw_path" ]; then
    record_check "${label}=missing"
    return 0
  fi

  path="$(resolve_artifact_path "$raw_path")"
  if [ ! -f "$path" ]; then
    record_check "${label}=missing-file"
    return 0
  fi

  if [[ "$path" = "${ROOT_DIR}/"* ]]; then
    record_check "${label}=${path#${ROOT_DIR}/}"
  else
    record_check "${label}=${path}"
  fi
}

record_policy_action_check() {
  local label="$1"
  local raw_path="$2"
  local action="$3"
  local blocker_message="$4"
  local path

  if [ -z "$raw_path" ]; then
    record_check "${label}=missing"
    blocker "$blocker_message"
    return 0
  fi

  path="$(resolve_artifact_path "$raw_path")"
  if [ ! -f "$path" ]; then
    record_check "${label}=missing-file"
    blocker "$blocker_message"
    return 0
  fi

  if grep -q "\"${action}\"" "$path"; then
    record_check "${label}=present"
  else
    record_check "${label}=missing"
    blocker "$blocker_message"
  fi
}

record_file_contains_check() {
  local label="$1"
  local raw_path="$2"
  local expected="$3"
  local blocker_message="$4"
  local path

  if [ -z "$raw_path" ]; then
    record_check "${label}=missing"
    blocker "$blocker_message"
    return 0
  fi

  path="$(resolve_artifact_path "$raw_path")"
  if [ ! -f "$path" ]; then
    record_check "${label}=missing-file"
    blocker "$blocker_message"
    return 0
  fi

  if grep -Fq "$expected" "$path"; then
    record_check "${label}=present"
  else
    record_check "${label}=missing"
    blocker "$blocker_message"
  fi
}

text_field() {
  local contents="$1"
  local field="$2"
  printf '%s\n' "$contents" | sed -n "s/^${field}=//p" | tail -1
}

record_cells_cloud_aws_diagnostics() {
  local preflight="$1"
  local raw_diagnostics
  local diagnostics
  local identity
  local permission_probe_image
  local ssm_runtime_policy_simulation

  if [ -z "$preflight" ] || [ ! -f "$preflight" ]; then
    record_check "cells-cloud-aws-diagnostics=missing"
    record_check "cells-cloud-aws-identity=unknown"
    record_check "cells-cloud-aws-profile=unknown"
    record_check "cells-cloud-aws-profile-source=unknown"
    record_check "cells-cloud-aws-configured-profile-count=unknown"
    record_check "cells-cloud-aws-caller-identity-type=unknown"
    record_check "cells-cloud-aws-iam-get-user=unknown"
    record_check "cells-cloud-aws-iam-list-attached-user-policies=unknown"
    record_check "cells-cloud-aws-iam-list-user-policies=unknown"
    record_check "cells-cloud-aws-iam-list-groups-for-user=unknown"
    record_check "cells-cloud-aws-setup-role=unknown"
    record_check "cells-cloud-aws-iam-get-setup-role=unknown"
    record_check "cells-cloud-aws-iam-list-roles=unknown"
    record_check "cells-cloud-aws-iam-list-instance-profiles=unknown"
    record_check "cells-cloud-aws-ssm-runtime-policy-simulation=unknown"
    record_check "cells-cloud-aws-instance-profile=unknown"
    record_check "cells-cloud-aws-instance-profile-check=unknown"
    record_check "cells-cloud-aws-run-instances-dry-run=unknown"
    record_check "cells-cloud-aws-run-instances-profile-arn-dry-run=unknown"
    record_check "cells-cloud-aws-run-instances-without-profile-dry-run=unknown"
    record_check "cells-cloud-aws-permission-probe-image=not-configured"
    record_check "cells-cloud-aws-permission-probe-status=unknown"
    record_check "cells-cloud-aws-required-policy=missing"
    record_check "cells-cloud-aws-diagnostic-policy=missing"
    record_check "cells-cloud-aws-setup-principal-policy=missing"
    record_check "cells-cloud-aws-required-setup=missing"
    return 0
  fi

  raw_diagnostics="$(artifact_field "$preflight" awsDiagnostics)"
  if [ -z "$raw_diagnostics" ]; then
    record_check "cells-cloud-aws-diagnostics=missing"
    record_check "cells-cloud-aws-identity=unknown"
    record_check "cells-cloud-aws-profile=unknown"
    record_check "cells-cloud-aws-profile-source=unknown"
    record_check "cells-cloud-aws-configured-profile-count=unknown"
    record_check "cells-cloud-aws-caller-identity-type=unknown"
    record_check "cells-cloud-aws-iam-get-user=unknown"
    record_check "cells-cloud-aws-iam-list-attached-user-policies=unknown"
    record_check "cells-cloud-aws-iam-list-user-policies=unknown"
    record_check "cells-cloud-aws-iam-list-groups-for-user=unknown"
    record_check "cells-cloud-aws-setup-role=unknown"
    record_check "cells-cloud-aws-iam-get-setup-role=unknown"
    record_check "cells-cloud-aws-iam-list-roles=unknown"
    record_check "cells-cloud-aws-iam-list-instance-profiles=unknown"
    record_check "cells-cloud-aws-ssm-runtime-policy-simulation=unknown"
    record_check "cells-cloud-aws-instance-profile=unknown"
    record_check "cells-cloud-aws-instance-profile-check=unknown"
    record_check "cells-cloud-aws-run-instances-dry-run=unknown"
    record_check "cells-cloud-aws-run-instances-without-profile-dry-run=unknown"
    record_check "cells-cloud-aws-permission-probe-image=not-configured"
    record_check "cells-cloud-aws-permission-probe-status=unknown"
    record_check "cells-cloud-aws-required-policy=missing"
    record_check "cells-cloud-aws-diagnostic-policy=missing"
    record_check "cells-cloud-aws-setup-principal-policy=missing"
    record_check "cells-cloud-aws-required-setup=missing"
    return 0
  fi

  diagnostics="$(resolve_artifact_path "$raw_diagnostics")"
  if [ ! -f "$diagnostics" ]; then
    record_check "cells-cloud-aws-diagnostics=missing-file"
    record_check "cells-cloud-aws-identity=unknown"
    record_check "cells-cloud-aws-profile=unknown"
    record_check "cells-cloud-aws-profile-source=unknown"
    record_check "cells-cloud-aws-configured-profile-count=unknown"
    record_check "cells-cloud-aws-caller-identity-type=unknown"
    record_check "cells-cloud-aws-iam-get-user=unknown"
    record_check "cells-cloud-aws-iam-list-attached-user-policies=unknown"
    record_check "cells-cloud-aws-iam-list-user-policies=unknown"
    record_check "cells-cloud-aws-iam-list-groups-for-user=unknown"
    record_check "cells-cloud-aws-instance-profile=unknown"
    record_check "cells-cloud-aws-ssm-runtime-policy-simulation=unknown"
    record_check "cells-cloud-aws-instance-profile-check=unknown"
    record_check "cells-cloud-aws-run-instances-dry-run=unknown"
    record_check "cells-cloud-aws-run-instances-without-profile-dry-run=unknown"
    record_check "cells-cloud-aws-permission-probe-image=not-configured"
    record_check "cells-cloud-aws-permission-probe-status=unknown"
    record_check "cells-cloud-aws-required-policy=missing"
    record_check "cells-cloud-aws-diagnostic-policy=missing"
    record_check "cells-cloud-aws-setup-principal-policy=missing"
    record_check "cells-cloud-aws-required-setup=missing"
    return 0
  fi

  if [[ "$diagnostics" = "${ROOT_DIR}/"* ]]; then
    record_check "cells-cloud-aws-diagnostics=${diagnostics#${ROOT_DIR}/}"
  else
    record_check "cells-cloud-aws-diagnostics=${diagnostics}"
  fi

  identity="$(artifact_field "$diagnostics" identity)"
  if [ -n "$identity" ] && [ "$identity" != "unknown" ]; then
    record_check "cells-cloud-aws-identity=present"
  else
    record_check "cells-cloud-aws-identity=unknown"
  fi

  record_check "cells-cloud-aws-profile=$(artifact_field "$diagnostics" profile)"
  record_check "cells-cloud-aws-profile-source=$(artifact_field "$diagnostics" profileSource)"
  record_check "cells-cloud-aws-configured-profile-count=$(artifact_field "$diagnostics" configuredProfileCount)"
  record_check "cells-cloud-aws-caller-identity-type=$(artifact_field "$diagnostics" callerIdentityType)"
  record_check "cells-cloud-aws-iam-get-user=$(artifact_field "$diagnostics" iamGetUser)"
  record_check "cells-cloud-aws-iam-list-attached-user-policies=$(artifact_field "$diagnostics" iamListAttachedUserPolicies)"
  record_check "cells-cloud-aws-iam-list-user-policies=$(artifact_field "$diagnostics" iamListUserPolicies)"
  record_check "cells-cloud-aws-iam-list-groups-for-user=$(artifact_field "$diagnostics" iamListGroupsForUser)"
  record_check "cells-cloud-aws-setup-role=$(artifact_field "$diagnostics" setupRole)"
  record_check "cells-cloud-aws-iam-get-setup-role=$(artifact_field "$diagnostics" iamGetSetupRole)"
  record_check "cells-cloud-aws-iam-list-roles=$(artifact_field "$diagnostics" iamListRoles)"
  record_check "cells-cloud-aws-iam-list-instance-profiles=$(artifact_field "$diagnostics" iamListInstanceProfiles)"
  ssm_runtime_policy_simulation="$(artifact_field "$diagnostics" ssmRuntimePolicySimulation)"
  record_check "cells-cloud-aws-ssm-runtime-policy-simulation=${ssm_runtime_policy_simulation:-unknown}"
  record_check "cells-cloud-aws-instance-profile=$(artifact_field "$diagnostics" instanceProfile)"
  record_check "cells-cloud-aws-instance-profile-check=$(artifact_field "$diagnostics" instanceProfileCheck)"
  record_check "cells-cloud-aws-run-instances-dry-run=$(artifact_field "$diagnostics" runInstancesDryRun)"
  record_check "cells-cloud-aws-run-instances-profile-arn-dry-run=$(artifact_field "$diagnostics" runInstancesProfileArnDryRun)"
  record_check "cells-cloud-aws-run-instances-without-profile-dry-run=$(artifact_field "$diagnostics" runInstancesWithoutProfileDryRun)"

  permission_probe_image="$(artifact_field "$diagnostics" permissionProbeImage)"
  if [ -n "$permission_probe_image" ]; then
    record_check "cells-cloud-aws-permission-probe-image=configured"
  else
    record_check "cells-cloud-aws-permission-probe-image=not-configured"
  fi
  record_check "cells-cloud-aws-permission-probe-status=$(artifact_field "$diagnostics" permissionProbeStatus)"

  record_existing_path_check \
    "cells-cloud-aws-required-policy" \
    "$(artifact_field "$diagnostics" requiredPolicy)"
  record_existing_path_check \
    "cells-cloud-aws-diagnostic-policy" \
    "$(artifact_field "$diagnostics" diagnosticPolicy)"
  record_policy_action_check \
    "cells-cloud-aws-diagnostic-policy-simulate-principal-policy" \
    "$(artifact_field "$diagnostics" diagnosticPolicy)" \
    "iam:SimulatePrincipalPolicy" \
    "AWS cloud preflight diagnostic policy missing iam:SimulatePrincipalPolicy"
  record_existing_path_check \
    "cells-cloud-aws-setup-principal-policy" \
    "$(artifact_field "$diagnostics" setupPrincipalPolicy)"
  record_policy_action_check \
    "cells-cloud-aws-setup-principal-policy-passrole" \
    "$(artifact_field "$diagnostics" setupPrincipalPolicy)" \
    "iam:PassRole" \
    "AWS cloud preflight setup principal policy missing iam:PassRole for AddRoleToInstanceProfile"
  record_existing_path_check \
    "cells-cloud-aws-required-setup" \
    "$(artifact_field "$diagnostics" requiredSetup)"
}

record_cells_cloud_aws_latest_recheck() {
  local preflight
  local raw_diagnostics
  local diagnostics
  local status
  local missing_prerequisites
  local ssm_runtime_policy_simulation

  preflight="$(latest_cells_cloud_provider_preflight aws || true)"
  if [ -z "$preflight" ]; then
    record_check "cells-cloud-aws-latest-recheck=missing"
    record_check "cells-cloud-aws-latest-recheck-status=missing"
    record_check "cells-cloud-aws-latest-recheck-missing-prerequisites=unknown"
    record_check "cells-cloud-aws-latest-recheck-diagnostics=missing"
    record_check "cells-cloud-aws-latest-recheck-instance-profile-check=unknown"
    record_check "cells-cloud-aws-latest-recheck-run-instances-dry-run=unknown"
    record_check "cells-cloud-aws-latest-recheck-run-instances-profile-arn-dry-run=unknown"
    record_check "cells-cloud-aws-latest-recheck-run-instances-without-profile-dry-run=unknown"
    record_check "cells-cloud-aws-latest-recheck-ssm-runtime-policy-simulation=unknown"
    record_check "cells-cloud-aws-latest-recheck-latest-smoke-artifact=unknown"
    record_check "cells-cloud-aws-latest-recheck-latest-smoke-status=unknown"
    record_check "cells-cloud-aws-latest-recheck-latest-smoke-reason=unknown"
    record_check "cells-cloud-aws-latest-recheck-latest-smoke-output=unknown"
    return 0
  fi

  status="$(provider_preflight_field "$preflight" aws status)"
  missing_prerequisites="$(provider_preflight_field "$preflight" aws missingPrerequisites)"

  record_check "cells-cloud-aws-latest-recheck=${preflight#${ROOT_DIR}/}"
  record_check "cells-cloud-aws-latest-recheck-status=${status:-unknown}"
  record_check "cells-cloud-aws-latest-recheck-missing-prerequisites=${missing_prerequisites:-unknown}"
  record_check "cells-cloud-aws-latest-recheck-latest-smoke-artifact=$(provider_preflight_field "$preflight" aws latestSmokeArtifact || echo unknown)"
  record_check "cells-cloud-aws-latest-recheck-latest-smoke-status=$(provider_preflight_field "$preflight" aws latestSmokeStatus || echo unknown)"
  record_check "cells-cloud-aws-latest-recheck-latest-smoke-reason=$(provider_preflight_field "$preflight" aws latestSmokeReason || echo unknown)"
  record_check "cells-cloud-aws-latest-recheck-latest-smoke-output=$(provider_preflight_field "$preflight" aws latestSmokeOutput || echo unknown)"

  raw_diagnostics="$(artifact_field "$preflight" awsDiagnostics)"
  if [ -z "$raw_diagnostics" ]; then
    record_check "cells-cloud-aws-latest-recheck-diagnostics=missing"
    record_check "cells-cloud-aws-latest-recheck-instance-profile-check=unknown"
    record_check "cells-cloud-aws-latest-recheck-run-instances-dry-run=unknown"
    record_check "cells-cloud-aws-latest-recheck-run-instances-profile-arn-dry-run=unknown"
    record_check "cells-cloud-aws-latest-recheck-run-instances-without-profile-dry-run=unknown"
    record_check "cells-cloud-aws-latest-recheck-ssm-runtime-policy-simulation=unknown"
  else
    diagnostics="$(resolve_artifact_path "$raw_diagnostics")"
    if [ -f "$diagnostics" ]; then
      record_check "cells-cloud-aws-latest-recheck-diagnostics=${diagnostics#${ROOT_DIR}/}"
      record_check "cells-cloud-aws-latest-recheck-profile=$(artifact_field "$diagnostics" profile)"
      record_check "cells-cloud-aws-latest-recheck-instance-profile=$(artifact_field "$diagnostics" instanceProfile)"
      record_check "cells-cloud-aws-latest-recheck-instance-profile-check=$(artifact_field "$diagnostics" instanceProfileCheck)"
      record_check "cells-cloud-aws-latest-recheck-run-instances-dry-run=$(artifact_field "$diagnostics" runInstancesDryRun)"
      record_check "cells-cloud-aws-latest-recheck-run-instances-profile-arn-dry-run=$(artifact_field "$diagnostics" runInstancesProfileArnDryRun)"
      record_check "cells-cloud-aws-latest-recheck-run-instances-without-profile-dry-run=$(artifact_field "$diagnostics" runInstancesWithoutProfileDryRun)"
      ssm_runtime_policy_simulation="$(artifact_field "$diagnostics" ssmRuntimePolicySimulation)"
      record_check "cells-cloud-aws-latest-recheck-ssm-runtime-policy-simulation=${ssm_runtime_policy_simulation:-unknown}"
      record_existing_path_check \
        "cells-cloud-aws-latest-recheck-required-policy" \
        "$(artifact_field "$diagnostics" requiredPolicy)"
      record_existing_path_check \
        "cells-cloud-aws-latest-recheck-diagnostic-policy" \
        "$(artifact_field "$diagnostics" diagnosticPolicy)"
      record_policy_action_check \
        "cells-cloud-aws-latest-recheck-diagnostic-policy-simulate-principal-policy" \
        "$(artifact_field "$diagnostics" diagnosticPolicy)" \
        "iam:SimulatePrincipalPolicy" \
        "Latest AWS cloud preflight diagnostic policy missing iam:SimulatePrincipalPolicy"
      record_existing_path_check \
        "cells-cloud-aws-latest-recheck-setup-principal-policy" \
        "$(artifact_field "$diagnostics" setupPrincipalPolicy)"
      record_policy_action_check \
        "cells-cloud-aws-latest-recheck-setup-principal-policy-passrole" \
        "$(artifact_field "$diagnostics" setupPrincipalPolicy)" \
        "iam:PassRole" \
        "Latest AWS cloud preflight setup principal policy missing iam:PassRole for AddRoleToInstanceProfile"
      record_existing_path_check \
        "cells-cloud-aws-latest-recheck-required-setup" \
        "$(artifact_field "$diagnostics" requiredSetup)"
    else
      record_check "cells-cloud-aws-latest-recheck-diagnostics=missing-file"
      record_check "cells-cloud-aws-latest-recheck-instance-profile-check=unknown"
      record_check "cells-cloud-aws-latest-recheck-run-instances-dry-run=unknown"
      record_check "cells-cloud-aws-latest-recheck-run-instances-profile-arn-dry-run=unknown"
      record_check "cells-cloud-aws-latest-recheck-run-instances-without-profile-dry-run=unknown"
      record_check "cells-cloud-aws-latest-recheck-ssm-runtime-policy-simulation=unknown"
    fi
  fi

  if [ "$status" = "blocked" ]; then
    blocker "Latest AWS cloud preflight blocked: missingPrerequisites=${missing_prerequisites:-unknown}"
  fi
}

record_cells_cloud_aws_persistent_env_state() {
  local preflight="$1"
  local raw_diagnostics
  local diagnostics
  local preflight_image=""
  local env_output
  local region
  local image
  local instance_profile
  local permission_probe_image

  if ! command -v zsh >/dev/null 2>&1; then
    record_check "cells-cloud-aws-persistent-env=missing-zsh"
    record_check "cells-cloud-aws-persistent-region=unknown"
    record_check "cells-cloud-aws-persistent-image=unknown"
    record_check "cells-cloud-aws-persistent-instance-profile=unknown"
    record_check "cells-cloud-aws-persistent-permission-probe-image=unknown"
    record_check "cells-cloud-aws-persistent-image-matches-preflight=unknown"
    return 0
  fi

  env_output="$(
    zsh -ic '
      printf "region=%s\n" "${COCXY_AWS_REGION-}"
      printf "image=%s\n" "${COCXY_AWS_IMAGE-}"
      printf "instanceProfile=%s\n" "${COCXY_AWS_INSTANCE_PROFILE-}"
      printf "permissionProbeImage=%s\n" "${COCXY_AWS_PERMISSION_PROBE_IMAGE-}"
    ' 2>/dev/null || true
  )"

  region="$(text_field "$env_output" region)"
  image="$(text_field "$env_output" image)"
  instance_profile="$(text_field "$env_output" instanceProfile)"
  permission_probe_image="$(text_field "$env_output" permissionProbeImage)"

  record_check "cells-cloud-aws-persistent-env=zsh"
  record_check "cells-cloud-aws-persistent-region=${region:-missing}"
  record_check "cells-cloud-aws-persistent-image=${image:-missing}"
  record_check "cells-cloud-aws-persistent-instance-profile=${instance_profile:-missing}"
  if [ -z "$instance_profile" ]; then
    blocker "AWS persistent shell environment missing COCXY_AWS_INSTANCE_PROFILE"
  fi
  if [ -n "$permission_probe_image" ]; then
    record_check "cells-cloud-aws-persistent-permission-probe-image=configured"
  else
    record_check "cells-cloud-aws-persistent-permission-probe-image=missing"
  fi

  if [ -n "$preflight" ] && [ -f "$preflight" ]; then
    raw_diagnostics="$(artifact_field "$preflight" awsDiagnostics)"
    if [ -n "$raw_diagnostics" ]; then
      diagnostics="$(resolve_artifact_path "$raw_diagnostics")"
      if [ -f "$diagnostics" ]; then
        preflight_image="$(artifact_field "$diagnostics" image)"
      fi
    fi
  fi

  if [ -z "$image" ] || [ -z "$preflight_image" ]; then
    record_check "cells-cloud-aws-persistent-image-matches-preflight=unknown"
  elif [ "$image" = "$preflight_image" ]; then
    record_check "cells-cloud-aws-persistent-image-matches-preflight=yes"
  else
    record_check "cells-cloud-aws-persistent-image-matches-preflight=no"
    blocker "AWS persistent shell COCXY_AWS_IMAGE does not match latest AWS preflight image"
  fi
}

record_agent_workspace_plan_phase_statuses() {
  if grep -q '^## 4 · Fase 0' "$PLAN" &&
     grep -q '^## Completion Unlock Checklist$' "$AUDIT"; then
    record_check "agent-workspace-plan-phase-0=capability-matrix-audit-gated"
  else
    record_check "agent-workspace-plan-phase-0=blocked"
    blocker "Agent Workspace OS phase 0 missing private capability matrix/audit checklist evidence"
  fi

  if [ "${BROWSER_COMMANDS:-0}" -ge 45 ] &&
     [ "${BROWSER_MCP_TOOLS:-0}" -ge 45 ]; then
    record_check "agent-workspace-plan-phase-1=browser-v2-gated"
  else
    record_check "agent-workspace-plan-phase-1=blocked"
  fi

  if [ "${REMOTE_DOCKER_ROWS:-0}" -ge 12 ] &&
     [ -n "${REMOTE_DOCKER_SUMMARY:-}" ]; then
    record_check "agent-workspace-plan-phase-2=remote-browser-e2e-gated"
  else
    record_check "agent-workspace-plan-phase-2=blocked"
  fi

  local cells_cloud_complete="0"
  if [ -n "${CELLS_CLOUD_PREFLIGHT_LATEST:-}" ]; then
    cells_cloud_complete="$(artifact_field "$CELLS_CLOUD_PREFLIGHT_LATEST" complete)"
  fi
  if [ -n "${CELLS_DOCKER_SUMMARY:-}" ] &&
     [ -n "${CELLS_SSH_SUMMARY:-}" ] &&
     [ -n "${CELLS_SELF_HOSTED_SUMMARY:-}" ] &&
     [ "$cells_cloud_complete" = "5" ]; then
    record_check "agent-workspace-plan-phase-3=cells-e2e-complete"
  else
    record_check "agent-workspace-plan-phase-3=blocked"
  fi

  if [ -n "${COCXYCORE_MOAT_SUMMARY:-}" ]; then
    record_check "agent-workspace-plan-phase-4=cocxycore-moat-gated"
  else
    record_check "agent-workspace-plan-phase-4=blocked"
  fi

  if [ -n "${AGENT_TEAMS_PROVIDER_COVERAGE_SUMMARY:-}" ] &&
     [ -n "${AGENT_TEAMS_GRAPH_PERFORMANCE_SUMMARY:-}" ] &&
     [ "${VAULT_BUILTIN_AGENTS:-0}" -ge 11 ] &&
     [ "${CODE_REVIEW_DOMAIN_FILES:-0}" -ge 10 ]; then
    record_check "agent-workspace-plan-phase-5=agent-teams-platform-gated"
  else
    record_check "agent-workspace-plan-phase-5=blocked"
  fi

  if [ "${E2E_MATRIX_COUNT:-0}" = "9" ] &&
     printf '%s\n' "${E2E_MATRIX_AUDIT:-}" | grep -q '^status=complete$'; then
    record_check "agent-workspace-plan-phase-6=verification-moat-complete"
  else
    record_check "agent-workspace-plan-phase-6=blocked"
  fi

  if [ -n "${AGENT_WORKSPACE_UI_SMOKE_SUMMARY:-}" ] &&
     [ -n "${AGENT_WORKSPACE_PRODUCT_UX_SUMMARY:-}" ] &&
     [ -n "${A11Y_SUMMARY:-}" ]; then
    record_check "agent-workspace-plan-phase-7=product-ux-complete"
  else
    record_check "agent-workspace-plan-phase-7=blocked"
  fi
}

require_executable() {
  local path="$1"
  local label="$2"
  if [ -x "$path" ]; then
    record_check "${label}=present"
  else
    blocker "${label}: missing or not executable"
  fi
}

record_docker_runtime_diagnostics() {
  local colima_status
  local lima_status

  if command -v colima >/dev/null 2>&1; then
    colima_status="$(colima status 2>&1 || true)"
    if printf '%s\n' "$colima_status" | grep -qi 'not running'; then
      record_check "docker-colima=installed-not-running"
    elif printf '%s\n' "$colima_status" | grep -qi 'running'; then
      record_check "docker-colima=installed-running"
    else
      record_check "docker-colima=installed-error"
    fi
  else
    record_check "docker-colima=missing"
  fi

  if command -v limactl >/dev/null 2>&1; then
    lima_status="$(limactl list 2>&1 || true)"
    if printf '%s\n' "$lima_status" | grep -qi 'rosetta'; then
      record_check "docker-lima=rosetta-incompatible"
    elif printf '%s\n' "$lima_status" | grep -qi '^NAME[[:space:]]'; then
      record_check "docker-lima=installed-native"
    else
      record_check "docker-lima=installed-error"
    fi
  else
    record_check "docker-lima=missing"
  fi
}

final_report_puerta_has_required_fields() {
  local title="$1"
  awk -v title="$title" '
    $0 == title {
      in_section = 1
      next
    }
    in_section && /^## Puerta / {
      exit
    }
    in_section {
      if ($0 == "Initial state:") {
        has_initial = 1
      }
      if ($0 == "Action taken:") {
        has_action = 1
      }
      if ($0 ~ /^Final( audit)? artifacts?:$/) {
        has_artifact = 1
      }
      if ($0 == "Verdict:") {
        has_verdict = 1
      }
      if ($0 ~ /SHA-256:/) {
        has_sha = 1
      }
    }
    END {
      exit (has_initial && has_action && has_artifact && has_verdict && has_sha) ? 0 : 1
    }
  ' "$FINAL_AUDIT_REPORT"
}

if [ -f "$PLAN" ]; then
  record_check "plan=present"
  if grep -q '^## Estado verificado 2026-05-18$' "$PLAN" &&
     grep -q 'verificación 2026-05-18 `complete`' "$PLAN" &&
     grep -q 'status=complete' "$PLAN" &&
     grep -q 'build/cells-cloud-preflight/20260518-095714/preflight.txt' "$PLAN" &&
     grep -q 'build/agent-workspace-release-preflight/20260518-100330/preflight.txt' "$PLAN" &&
     grep -Eq 'build/agent-workspace-ui-smoke/[^`[:space:]]+/summary-final\.txt' "$PLAN"; then
    record_check "plan-current-status-note=complete"
  else
    blocker "source plan missing current complete status note, cloud 5/5 evidence, release preflight evidence, or app-open smoke evidence"
  fi
else
  blocker "source plan missing: ${PLAN}"
fi

if [ -f "$AUDIT" ]; then
  record_check "completion-audit=present"
  if grep -q '^Status: Not 100% complete\.$' "$AUDIT"; then
    record_check "completion-audit-status=not-complete"
  else
    blocker "completion audit does not explicitly say Status: Not 100% complete."
  fi
  if grep -q '^## Prompt-To-Artifact Checklist$' "$AUDIT" &&
     grep -q '^## Not 100% Complete$' "$AUDIT" &&
     grep -q '^## Latest Blocking Preflights$' "$AUDIT" &&
     grep -q '^## Completion Unlock Checklist$' "$AUDIT" &&
     grep -q '^| North strategic MCP support: Browser MCP tools + configured MCP integration |' "$AUDIT" &&
     grep -q '^| North strategic Notebooks: Cocxy Notebooks `\.cocxynb` + QuickLook |' "$AUDIT" &&
     grep -q '^| North strategic Vault reuse and Code Review handoff |' "$AUDIT" &&
     grep -q '^| Docker limitation stated honestly |' "$AUDIT" &&
     grep -q '^| E2E matrix gate rejects partial verification |' "$AUDIT" &&
     grep -q '^| Docker live smoke refresh |' "$AUDIT" &&
     grep -q '^| Cloud Cells accounts |' "$AUDIT" &&
     grep -q '^| Agent Teams provider processes |' "$AUDIT" &&
     grep -q '^| v1.18.0 release target |' "$AUDIT" &&
     grep -q '^| Product UX release-candidate |' "$AUDIT"; then
    record_check "completion-audit-required-sections=present"
  else
    blocker "completion audit missing prompt-to-artifact checklist, current blockers, or unlock checklist"
  fi
else
  blocker "completion audit missing: ${AUDIT}"
fi

if [ -f "$FINAL_AUDIT_REPORT" ]; then
  record_check "completion-final-report=present"
  if grep -q '^status: complete$' "$FINAL_AUDIT_REPORT"; then
    FINAL_REPORT_DECLARED_STATUS="complete"
    record_check "completion-final-report-status=complete"
  elif grep -q '^status: not-complete$' "$FINAL_AUDIT_REPORT"; then
    FINAL_REPORT_DECLARED_STATUS="not-complete"
    record_check "completion-final-report-status=not-complete"
  else
    blocker "completion final report does not declare status: complete or status: not-complete"
  fi
  if grep -q '^## Prompt-To-Artifact Checklist$' "$FINAL_AUDIT_REPORT" &&
     grep -q '^## Phase Status Matrix$' "$FINAL_AUDIT_REPORT" &&
     grep -q '^| Fase 0 |' "$FINAL_AUDIT_REPORT" &&
     grep -q '^| Fase 1 |' "$FINAL_AUDIT_REPORT" &&
     grep -q '^| Fase 2 |' "$FINAL_AUDIT_REPORT" &&
     grep -q '^| Fase 3 |' "$FINAL_AUDIT_REPORT" &&
     grep -q '^| Fase 4 |' "$FINAL_AUDIT_REPORT" &&
     grep -q '^| Fase 5 |' "$FINAL_AUDIT_REPORT" &&
     grep -q '^| Fase 6 |' "$FINAL_AUDIT_REPORT" &&
     grep -q '^| Fase 7 |' "$FINAL_AUDIT_REPORT" &&
     grep -q '^## Puerta 1 - Docker Live Smokes$' "$FINAL_AUDIT_REPORT" &&
     grep -q '^## Puerta 2 - Agent Teams Provider And Runtime$' "$FINAL_AUDIT_REPORT" &&
     grep -q '^## Puerta 3 - Cloud Cells$' "$FINAL_AUDIT_REPORT" &&
     grep -q '^## Puerta 4 - Product UX, Manual UI Smoke, And E2E Matrix$' "$FINAL_AUDIT_REPORT" &&
     grep -q '^## Puerta 5 - Release Target And Final Audit$' "$FINAL_AUDIT_REPORT" &&
     grep -q '^Literal fresh audit output:$' "$FINAL_AUDIT_REPORT" &&
     grep -q '^| AWS owner handoff is present, secret-clean, and guarded |' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=agent-workspace-ui-smoke-command-palette=cells-vault-browser$' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=agent-workspace-ui-smoke-evidence=hashes-ok$' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-gcp-compute-api=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-diagnostics=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-profile=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-configured-profile-count=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-caller-identity-type=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-iam-get-user=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-iam-list-attached-user-policies=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-setup-role=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-iam-get-setup-role=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-iam-list-roles=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-iam-list-instance-profiles=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-instance-profile-check=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-run-instances-dry-run=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-run-instances-without-profile-dry-run=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-permission-probe-status=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-required-setup=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-latest-recheck=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-latest-recheck-status=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-latest-recheck-missing-prerequisites=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-latest-recheck-diagnostics=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-latest-recheck-instance-profile-check=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-latest-recheck-run-instances-dry-run=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-latest-recheck-run-instances-without-profile-dry-run=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-setup-verify-latest=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-setup-verify-status=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-setup-verify-blockers=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-setup-verify-checks=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-setup-verify-remediation=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-setup-dryrun-latest=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-setup-principal-policy=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-setup-principal-policy-passrole=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-setup-generated-verify-script=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-setup-generated-verify-script-dryrun-operation=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-setup-generated-verify-script-profile-arn-dry-run=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-setup-generated-verify-script-runner=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-owner-handoff=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-owner-handoff-image-export=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-owner-handoff-propagation-guardrail=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-owner-handoff-dryrun-not-runtime=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-owner-handoff-ssm-runtime-required=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-owner-handoff-secret-scan=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-aws-owner-handoff-guardrails=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-persistent-image=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-persistent-instance-profile=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=cells-cloud-aws-persistent-image-matches-preflight=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=agent-workspace-product-ux-manual-acceptance=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=agent-workspace-plan-phase-0=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=agent-workspace-plan-phase-1=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=agent-workspace-plan-phase-2=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=agent-workspace-plan-phase-3=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=agent-workspace-plan-phase-4=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=agent-workspace-plan-phase-5=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=agent-workspace-plan-phase-6=' "$FINAL_AUDIT_REPORT" &&
     grep -q '^check=agent-workspace-plan-phase-7=' "$FINAL_AUDIT_REPORT"; then
    record_check "completion-final-report-required-sections=present"
  else
    blocker "completion final report missing prompt-to-artifact checklist, phase status matrix, puerta sections, literal audit output, app-open UI smoke evidence checks, GCP/AWS cloud diagnostics/latest recheck/setup verifier/handoff checks, Product UX manual acceptance check, or phase 0-7 status checks"
  fi
  puerta_index=0
  for puerta in \
    "Puerta 1 - Docker Live Smokes" \
    "Puerta 2 - Agent Teams Provider And Runtime" \
    "Puerta 3 - Cloud Cells" \
    "Puerta 4 - Product UX, Manual UI Smoke, And E2E Matrix" \
    "Puerta 5 - Release Target And Final Audit"
  do
    puerta_index=$((puerta_index + 1))
    if final_report_puerta_has_required_fields "## ${puerta}"; then
      record_check "completion-final-report-puerta-${puerta_index}=initial-action-artifact-sha-verdict"
    else
      blocker "completion final report ${puerta} missing Initial state, Action taken, Final artifact path with SHA-256, or Verdict"
    fi
  done
else
  blocker "completion final report missing: ${FINAL_AUDIT_REPORT}"
fi

if [ -f "$COMMAND_INSTRUCTION_DOC" ]; then
  record_check "command-instruction-doc=present"
  record_check "command-instruction-doc-path=${COMMAND_INSTRUCTION_DOC}"
  if grep -q 'no auto-acceptance of fabricated evidence' "$COMMAND_INSTRUCTION_DOC" &&
     grep -q 'Do NOT push any git tags to remote\.' "$COMMAND_INSTRUCTION_DOC" &&
     grep -q 'Do NOT submit notarization to Apple\.' "$COMMAND_INSTRUCTION_DOC" &&
     grep -q 'Do NOT publish to Homebrew cask or GitHub Releases\.' "$COMMAND_INSTRUCTION_DOC" &&
     grep -q 'Do NOT auto-accept any human acceptance fields\.' "$COMMAND_INSTRUCTION_DOC" &&
     grep -q 'If any cloud smoke fails' "$COMMAND_INSTRUCTION_DOC" &&
     grep -q 'status=not-complete' "$COMMAND_INSTRUCTION_DOC" &&
     grep -q 'scripts/audit-agent-workspace-os-completion.sh' "$COMMAND_INSTRUCTION_DOC"; then
    record_check "command-instruction-doc-guards=present"
  else
    blocker "command instruction doc missing required no-fabrication, no-publish, cloud-failure, or final-audit guardrails"
  fi
else
  blocker "command instruction doc missing: ${COMMAND_INSTRUCTION_DOC}"
fi

BROWSER_COMMANDS="$(count_browser_commands)"
record_check "browser-cli-commands=${BROWSER_COMMANDS}"
if [ "$BROWSER_COMMANDS" -lt 45 ]; then
  blocker "Browser V2 command breadth below target: ${BROWSER_COMMANDS}/45"
fi

BROWSER_MCP_TOOLS="$(count_browser_mcp_tools)"
record_check "browser-mcp-tools=${BROWSER_MCP_TOOLS}"
if [ "$BROWSER_MCP_TOOLS" -lt 45 ]; then
  blocker "Browser MCP breadth below target: ${BROWSER_MCP_TOOLS}/45"
fi

MCP_DOMAIN_FILES="$(count_swift_files_under "${ROOT_DIR}/Sources/Domain/MCP")"
MCP_UNIT_TEST_FILES="$(count_swift_files_under "${ROOT_DIR}/Tests/Unit/MCPTests")"
record_check "mcp-domain-files=${MCP_DOMAIN_FILES}"
record_check "mcp-unit-test-files=${MCP_UNIT_TEST_FILES}"
if [ "$MCP_DOMAIN_FILES" -lt 8 ]; then
  blocker "MCP support incomplete: expected domain client/manager/protocol/server/transport/bridge files, found ${MCP_DOMAIN_FILES}"
fi
if [ "$MCP_UNIT_TEST_FILES" -lt 2 ]; then
  blocker "MCP support incomplete: expected MCP foundation and Browser MCP tests, found ${MCP_UNIT_TEST_FILES}"
fi
if grep -Fq 'MCPCompositeManager(managers:' "${ROOT_DIR}/Sources/UI/Window/MainWindowController+AgentMode.swift" &&
   grep -Fq 'BrowserMCPToolManager(provider:' "${ROOT_DIR}/Sources/UI/Window/MainWindowController+AgentMode.swift" &&
   grep -Fq 'MCPConfiguredManager(' "${ROOT_DIR}/Sources/UI/Window/MainWindowController+AgentMode.swift" &&
   grep -Fq 'func saveMCPConfig() throws' "${ROOT_DIR}/Sources/UI/Preferences/PreferencesViewModel.swift" &&
   grep -Fq 'case .mcpServers:' "${ROOT_DIR}/Sources/UI/Preferences/PreferencesView.swift"; then
  record_check "mcp-agent-integration=browser-and-configured"
else
  blocker "MCP support incomplete: Browser MCP tools, configured MCP manager, and Preferences MCP config are not all wired"
fi

NOTEBOOK_COMMANDS="$(count_notebook_cli_commands)"
NOTEBOOK_DOMAIN_FILES="$(count_swift_files_under "${ROOT_DIR}/Sources/Domain/Notebook")"
NOTEBOOK_UNIT_TEST_FILES="$(count_swift_files_under "${ROOT_DIR}/Tests/Unit/NotebookTests")"
record_check "notebook-cli-commands=${NOTEBOOK_COMMANDS}"
record_check "notebook-domain-files=${NOTEBOOK_DOMAIN_FILES}"
record_check "notebook-unit-test-files=${NOTEBOOK_UNIT_TEST_FILES}"
if [ "$NOTEBOOK_COMMANDS" -lt 6 ]; then
  blocker "Notebook support incomplete: CLI command breadth below target ${NOTEBOOK_COMMANDS}/6"
fi
if [ "$NOTEBOOK_DOMAIN_FILES" -lt 7 ]; then
  blocker "Notebook support incomplete: domain import/export/execution/persistence/template files below target ${NOTEBOOK_DOMAIN_FILES}/7"
fi
if [ "$NOTEBOOK_UNIT_TEST_FILES" -lt 6 ]; then
  blocker "Notebook support incomplete: unit coverage below target ${NOTEBOOK_UNIT_TEST_FILES}/6"
fi
if grep -Fq 'dev.cocxy.notebook' "${ROOT_DIR}/Resources/Info.plist" &&
   grep -Fq '<string>cocxynb</string>' "${ROOT_DIR}/Resources/Info.plist" &&
   grep -Fq 'QuickLook Cocxy notebook content type' "${ROOT_DIR}/scripts/verify-app-bundle.sh" &&
   grep -Fq 'NotebookPanelView(' "${ROOT_DIR}/Sources/UI/Window/MainWindowController+SplitActions.swift"; then
  record_check "notebook-quicklook-contract=present"
else
  blocker "Notebook support incomplete: .cocxynb document type, QuickLook bundle verification, or notebook panel wiring missing"
fi

VAULT_BUILTIN_AGENTS="$(count_vault_builtin_agents)"
VAULT_DOMAIN_FILES="$(count_swift_files_under "${ROOT_DIR}/Sources/Domain/Vault")"
VAULT_UI_FILES="$(count_swift_files_under "${ROOT_DIR}/Sources/UI/Vault")"
VAULT_UNIT_TEST_FILES="$(count_swift_files_under "${ROOT_DIR}/Tests/Unit/VaultTests")"
record_check "vault-builtin-agents=${VAULT_BUILTIN_AGENTS}"
record_check "vault-domain-files=${VAULT_DOMAIN_FILES}"
record_check "vault-ui-files=${VAULT_UI_FILES}"
record_check "vault-unit-test-files=${VAULT_UNIT_TEST_FILES}"
if [ "$VAULT_BUILTIN_AGENTS" -lt 11 ]; then
  blocker "Vault base below plan target: built-in agent registry has ${VAULT_BUILTIN_AGENTS}/11 agents"
fi
if [ "$VAULT_DOMAIN_FILES" -lt 10 ] || [ "$VAULT_UI_FILES" -lt 4 ] || [ "$VAULT_UNIT_TEST_FILES" -lt 6 ]; then
  blocker "Vault base incomplete: expected domain, UI, and unit-test coverage for visual Vault reuse"
fi
if grep -Fq 'public final class VaultSearchIndex' "${ROOT_DIR}/Sources/Domain/Vault/VaultSearchIndex.swift" &&
   grep -Fq 'public struct VaultSessionDetector' "${ROOT_DIR}/Sources/Domain/Vault/VaultSessionDetector.swift" &&
   grep -Fq 'struct VaultSidebarView' "${ROOT_DIR}/Sources/UI/Vault/VaultSidebarView.swift"; then
  record_check "vault-visual-foundation=search-detector-sidebar"
else
  blocker "Vault base incomplete: search index, session detector, or visual sidebar is missing"
fi

CODE_REVIEW_DOMAIN_FILES="$(count_swift_files_under "${ROOT_DIR}/Sources/Domain/CodeReview")"
CODE_REVIEW_UI_FILES="$(count_swift_files_under "${ROOT_DIR}/Sources/UI/CodeReview")"
CODE_REVIEW_UNIT_TEST_FILES="$(count_swift_files_under "${ROOT_DIR}/Tests/Unit/CodeReviewTests")"
record_check "code-review-domain-files=${CODE_REVIEW_DOMAIN_FILES}"
record_check "code-review-ui-files=${CODE_REVIEW_UI_FILES}"
record_check "code-review-unit-test-files=${CODE_REVIEW_UNIT_TEST_FILES}"
if [ "$CODE_REVIEW_DOMAIN_FILES" -lt 10 ] || [ "$CODE_REVIEW_UI_FILES" -lt 8 ] || [ "$CODE_REVIEW_UNIT_TEST_FILES" -lt 10 ]; then
  blocker "Code Review integration incomplete: expected domain, UI, and unit-test coverage for the integrated review panel"
fi
if grep -Fq 'struct AgentTeamReviewBeforeShipRequest' "${ROOT_DIR}/Sources/Domain/AgentTeams/AgentTeamRunState.swift" &&
   grep -Fq 'requestAgentTeamReviewBeforeShip' "${ROOT_DIR}/Sources/App/AppDelegate+AgentTeamsCLI.swift" &&
   grep -Fq 'func sessionEndAutoShowsReview()' "${ROOT_DIR}/Tests/Unit/CodeReviewTests/CodeReviewIntegrationSwiftTestingTests.swift"; then
  record_check "code-review-agent-team-handoff=present"
else
  blocker "Code Review integration incomplete: Agent Teams review-before-ship handoff is not fully wired"
fi

require_executable "$REMOTE_DOCKER_SMOKE" "remote-browser-docker-smoke"
if [ -x "$REMOTE_DOCKER_SMOKE" ]; then
  REMOTE_DOCKER_ROWS="$(count_remote_docker_manifest_rows)"
  record_check "remote-browser-docker-manifest-implemented=${REMOTE_DOCKER_ROWS}"
  if [ "$REMOTE_DOCKER_ROWS" -lt 12 ]; then
    blocker "Remote Browser Docker manifest below target: ${REMOTE_DOCKER_ROWS}/12"
  fi
fi

if command -v docker >/dev/null 2>&1; then
  record_check "docker-cli=present"
  if docker info >/dev/null 2>&1; then
    record_check "docker-daemon=available"
  else
    record_check "docker-daemon=unavailable"
    record_docker_runtime_diagnostics
    blocker "Current Docker daemon unavailable: Remote Browser Docker SSH and Cells Docker live smokes cannot be refreshed"
  fi
else
  record_check "docker-cli=missing"
  record_docker_runtime_diagnostics
  blocker "Current Docker CLI missing: Remote Browser Docker SSH and Cells Docker live smokes cannot be refreshed"
fi

REMOTE_DOCKER_SUMMARY="$(
  latest_artifact_with_fields \
    "${ROOT_DIR}/build/remote-browser-docker-ssh" \
    'summary.txt' \
    'hmac=ok' \
    'proxyFallback=ok' \
    'dragDropUpload=ok' \
    'discovery=ok' || true
)"
if [ -n "$REMOTE_DOCKER_SUMMARY" ]; then
  record_check "remote-browser-docker-artifact=${REMOTE_DOCKER_SUMMARY#${ROOT_DIR}/}"
else
  blocker "Remote Browser Docker SSH E2E latest artifact is not current-green with status=ok, hmac=ok, proxyFallback=ok, dragDropUpload=ok, and discovery=ok"
fi

require_executable "$CELLS_DOCKER_SMOKE" "cells-docker-smoke"
CELLS_DOCKER_SUMMARY="$(
  latest_artifact_with_fields \
    "${ROOT_DIR}/build/cells-docker" \
    'summary.txt' \
    'result=cells-docker-ok' || true
)"
if [ -n "$CELLS_DOCKER_SUMMARY" ]; then
  record_check "cells-docker-artifact=${CELLS_DOCKER_SUMMARY#${ROOT_DIR}/}"
else
  blocker "Cells Docker E2E latest artifact is not current-green with status=ok and result=cells-docker-ok"
fi

require_executable "$CELLS_SSH_SMOKE" "cells-ssh-smoke"
CELLS_SSH_SUMMARY="$(
  latest_artifact_with_fields \
    "${ROOT_DIR}/build/cells-local-ssh" \
    'summary.txt' \
    'provider=ssh' \
    'result=cells-ssh-ok' || true
)"
if [ -n "$CELLS_SSH_SUMMARY" ]; then
  record_check "cells-ssh-artifact=${CELLS_SSH_SUMMARY#${ROOT_DIR}/}"
else
  blocker "Cells SSH E2E has no archived summary.txt with status=ok, provider=ssh, and result=cells-ssh-ok"
fi

CELLS_SELF_HOSTED_SUMMARY="$(
  latest_artifact_with_fields \
    "${ROOT_DIR}/build/cells-self-hosted-ssh" \
    'summary.txt' \
    'provider=self-hosted' \
    'result=cells-self-hosted-ok' || true
)"
if [ -n "$CELLS_SELF_HOSTED_SUMMARY" ]; then
  record_check "cells-self-hosted-ssh-artifact=${CELLS_SELF_HOSTED_SUMMARY#${ROOT_DIR}/}"
else
  blocker "Cells self-hosted SSH E2E has no archived summary.txt with status=ok, provider=self-hosted, and result=cells-self-hosted-ok"
fi

CELLS_OPERATOR_SUMMARY="$(
  latest_artifact_with_fields \
    "${ROOT_DIR}/build/cells-operator" \
    'summary.txt' \
    'result=cells-operator-ok' || true
)"
if [ -n "$CELLS_OPERATOR_SUMMARY" ]; then
  record_check "cells-operator-artifact=${CELLS_OPERATOR_SUMMARY#${ROOT_DIR}/}"
elif [ -f "$CELLS_OPERATOR_SCOPE_DECISION" ] &&
     grep -q '^Status: Out of scope for v1.18.0\.$' "$CELLS_OPERATOR_SCOPE_DECISION"; then
  record_check "cells-operator-scope=out-of-scope-for-v1.18.0"
else
  blocker "Cells Operator control plane has no archived summary.txt with status=ok and result=cells-operator-ok, and no explicit out-of-scope decision"
fi

require_executable "$CELLS_CLOUD_SMOKE" "cells-cloud-account-smoke"
require_executable "$CELLS_AWS_SETUP_VERIFY" "cells-aws-setup-verify"
require_executable "$CELLS_AWS_READINESS_SEQUENCE" "cells-aws-readiness-sequence"
require_executable "$CELLS_OPERATOR_SMOKE" "cells-operator-smoke"
require_executable "$CELLS_OPERATOR_PREFLIGHT" "cells-operator-preflight"
record_aws_setup_verify_summary
record_cells_aws_readonly_diagnostics_summary
record_cells_aws_direct_dryrun_summary
record_cells_aws_profile_diagnostics_summary
record_cells_aws_readiness_sequence
record_aws_owner_handoff
CELLS_CLOUD_PREFLIGHT_LATEST="$(
  latest_cells_cloud_all_preflight || true
)"
if [ -n "$CELLS_CLOUD_PREFLIGHT_LATEST" ]; then
  record_check "cells-cloud-preflight-latest=${CELLS_CLOUD_PREFLIGHT_LATEST#${ROOT_DIR}/}"
  record_check "cells-cloud-preflight-scope=all"
  record_check "cells-cloud-preflight-provider-count=5"
  record_check "cells-cloud-preflight-status=$(artifact_field "$CELLS_CLOUD_PREFLIGHT_LATEST" status)"
  record_check "cells-cloud-preflight-blocked=$(artifact_field "$CELLS_CLOUD_PREFLIGHT_LATEST" blocked)"
  record_check "cells-cloud-preflight-ready=$(artifact_field "$CELLS_CLOUD_PREFLIGHT_LATEST" ready)"
  record_check "cells-cloud-preflight-complete=$(artifact_field "$CELLS_CLOUD_PREFLIGHT_LATEST" complete)"
  record_check "cells-cloud-preflight-next=$(artifact_field "$CELLS_CLOUD_PREFLIGHT_LATEST" next)"
  record_cells_cloud_diagnostics "$CELLS_CLOUD_PREFLIGHT_LATEST"
  record_cells_cloud_aws_diagnostics "$CELLS_CLOUD_PREFLIGHT_LATEST"
  record_cells_cloud_aws_persistent_env_state "$CELLS_CLOUD_PREFLIGHT_LATEST"
  record_cells_cloud_preflight_blockers "$CELLS_CLOUD_PREFLIGHT_LATEST"
else
  record_check "cells-cloud-preflight-latest=missing"
  record_check "cells-cloud-preflight-scope=all"
  record_check "cells-cloud-preflight-provider-count=0"
  record_check "cells-cloud-preflight-status=missing"
  record_check "cells-cloud-preflight-blocked=0"
  record_check "cells-cloud-preflight-ready=0"
  record_check "cells-cloud-preflight-complete=0"
  record_check "cells-cloud-gcp-diagnostics=missing"
  record_check "cells-cloud-gcp-compute-api=unknown"
  record_cells_cloud_aws_diagnostics ""
  record_cells_cloud_aws_persistent_env_state ""
  record_check "cells-cloud-preflight-next=run scripts/preflight-cells-cloud-account.sh all"
fi
record_cells_cloud_aws_latest_recheck

for provider in e2b fly aws gcp azure; do
  case "$provider" in
    e2b) provider_tool="e2b" ;;
    fly) provider_tool="fly" ;;
    aws) provider_tool="aws" ;;
    gcp) provider_tool="gcloud" ;;
    azure) provider_tool="az" ;;
  esac

  CLOUD_SUMMARY="$(latest_cells_cloud_summary "$provider" || true)"
  if [ -n "$CLOUD_SUMMARY" ]; then
    record_check "cells-cloud-${provider}-artifact=${CLOUD_SUMMARY#${ROOT_DIR}/}"
  else
    record_cells_cloud_latest_smoke_failure "$provider"
    if command -v "$provider_tool" >/dev/null 2>&1; then
      record_check "cloud-tool-${provider_tool}=present"
    else
      blocker "Cells cloud account E2E blocked: ${provider_tool} CLI missing"
    fi
    blocker "Cells cloud account E2E has no archived ${provider} summary.txt with create/status/exec/logs/attach/list/destroy ok"
  fi
done

CELLS_PROVIDER_SOURCE="${ROOT_DIR}/Sources/Domain/Cells/CommandBackedCloudCellProvider.swift"
if grep -Fq "attachUnsupported(provider: kind)" "$CELLS_PROVIDER_SOURCE"; then
  blocker "Cells cloud attach incomplete: at least one provider still throws attachUnsupported"
elif grep -Fq 'arguments: ["sandbox", "connect", record.externalID]' "$CELLS_PROVIDER_SOURCE" &&
     grep -Fq 'arguments: ["ssh", "console"] + scopedArguments(app: record.app) + ["--machine", record.externalID]' "$CELLS_PROVIDER_SOURCE"; then
  record_check "cells-cloud-attach=e2b-fly-command-backed"
else
  blocker "Cells cloud attach incomplete: E2B/Fly command-backed attach commands are not both present"
fi

require_executable "$E2E_MATRIX_SMOKE" "agent-workspace-e2e-matrix-smoke"
if [ -x "$E2E_MATRIX_SMOKE" ]; then
  E2E_MATRIX_AUDIT="$("$E2E_MATRIX_SMOKE" --audit || true)"
  E2E_MATRIX_COUNT="$(printf '%s\n' "$E2E_MATRIX_AUDIT" | sed -n 's/^matrix-count=//p' | tail -1)"
  E2E_BLOCKED_COUNT="$(printf '%s\n' "$E2E_MATRIX_AUDIT" | sed -n 's/^blocked-count=//p' | tail -1)"
  if [ "$E2E_MATRIX_COUNT" = "9" ]; then
    record_check "agent-workspace-e2e-matrices=9"
  else
    blocker "Verification moat incomplete: E2E matrix registry reports ${E2E_MATRIX_COUNT:-0}/9 matrices"
  fi
  if printf '%s\n' "$E2E_MATRIX_AUDIT" | grep -q '^status=complete$'; then
    record_check "agent-workspace-e2e-status=complete"
  else
    blocker "Verification moat incomplete: E2E matrix audit reports ${E2E_BLOCKED_COUNT:-unknown} blocked matrices"
  fi
fi

AGENT_WORKSPACE_UI_SMOKE_SUMMARY="$(
  latest_agent_workspace_ui_smoke_summary || true
)"
if [ -n "$AGENT_WORKSPACE_UI_SMOKE_SUMMARY" ]; then
  record_check "agent-workspace-ui-smoke-latest=${AGENT_WORKSPACE_UI_SMOKE_SUMMARY#${ROOT_DIR}/}"
  record_check "agent-workspace-ui-smoke-command-palette=cells-vault-browser"
  record_check "agent-workspace-ui-smoke-dashboard=agent-status-pills"
  record_check "agent-workspace-ui-smoke-browser-devtools=console-visible"
  record_check "agent-workspace-ui-smoke-remote-ports=localhost-suggestion"
  record_check "agent-workspace-ui-smoke-agent-teams=two-members"
  record_check "agent-workspace-ui-smoke-code-review=empty-diff-visible"
  record_check "agent-workspace-ui-smoke-evidence=hashes-ok"
else
  record_check "agent-workspace-ui-smoke-latest=missing"
  record_check "agent-workspace-ui-smoke-command-palette=missing"
  record_check "agent-workspace-ui-smoke-dashboard=missing"
  record_check "agent-workspace-ui-smoke-browser-devtools=missing"
  record_check "agent-workspace-ui-smoke-remote-ports=missing"
  record_check "agent-workspace-ui-smoke-agent-teams=missing"
  record_check "agent-workspace-ui-smoke-code-review=missing"
  record_check "agent-workspace-ui-smoke-evidence=missing"
  blocker "Requested app-open UI smoke has no archived summary-final.txt with status=ok for Command Palette, Dashboard, Browser DevTools, Remote ports, Agent Teams, Code Review, and hashed screenshots"
fi

require_executable "$AGENT_TEAMS_PROVIDER_COVERAGE_PREFLIGHT" "agent-teams-provider-coverage-preflight"
AGENT_TEAMS_PROVIDER_COVERAGE_LATEST="$(
  latest_artifact \
    "${ROOT_DIR}/build/agent-teams-provider-coverage-preflight" \
    'preflight.txt' || true
)"
if [ -n "$AGENT_TEAMS_PROVIDER_COVERAGE_LATEST" ]; then
  record_check "agent-teams-provider-coverage-latest=${AGENT_TEAMS_PROVIDER_COVERAGE_LATEST#${ROOT_DIR}/}"
  record_check "agent-teams-provider-coverage-status=$(artifact_field "$AGENT_TEAMS_PROVIDER_COVERAGE_LATEST" status)"
  record_check "agent-teams-provider-coverage-available=$(artifact_field "$AGENT_TEAMS_PROVIDER_COVERAGE_LATEST" availableProviderBinaries)"
  record_check "agent-teams-provider-coverage-installed=$(artifact_field "$AGENT_TEAMS_PROVIDER_COVERAGE_LATEST" latestProviderProcessInstalled)"
  record_check "agent-teams-provider-coverage-passed=$(artifact_field "$AGENT_TEAMS_PROVIDER_COVERAGE_LATEST" latestProviderProcessPassed)"
  AGENT_TEAMS_PROVIDER_COVERAGE_EVIDENCE="$(artifact_field "$AGENT_TEAMS_PROVIDER_COVERAGE_LATEST" latestProviderProcessEvidence)"
  if [ -z "$AGENT_TEAMS_PROVIDER_COVERAGE_EVIDENCE" ]; then
    AGENT_TEAMS_PROVIDER_COVERAGE_EVIDENCE="missing"
  fi
  record_check "agent-teams-provider-coverage-evidence=${AGENT_TEAMS_PROVIDER_COVERAGE_EVIDENCE}"
  record_check "agent-teams-provider-coverage-next=$(artifact_field "$AGENT_TEAMS_PROVIDER_COVERAGE_LATEST" next)"
fi
AGENT_TEAMS_PROVIDER_COVERAGE_CANDIDATE="$(
  latest_artifact_with_fields \
    "${ROOT_DIR}/build/agent-teams-provider-coverage-preflight" \
    'preflight.txt' \
    'providerCount=12' \
    'latestProviderProcessStatus=ok' \
    'latestProviderProcessInstalled=12' \
    'latestProviderProcessPassed=12' \
    'latestProviderProcessEvidence=ok' || true
)"
AGENT_TEAMS_PROVIDER_COVERAGE_SUMMARY=""
if [ -n "$AGENT_TEAMS_PROVIDER_COVERAGE_CANDIDATE" ] &&
   verify_agent_teams_provider_preflight_summary "$AGENT_TEAMS_PROVIDER_COVERAGE_CANDIDATE"; then
  AGENT_TEAMS_PROVIDER_COVERAGE_SUMMARY="$AGENT_TEAMS_PROVIDER_COVERAGE_CANDIDATE"
fi
if [ -n "$AGENT_TEAMS_PROVIDER_COVERAGE_SUMMARY" ]; then
  record_check "agent-teams-provider-coverage=${AGENT_TEAMS_PROVIDER_COVERAGE_SUMMARY#${ROOT_DIR}/}"
else
  blocker "Agent Teams provider process coverage has no archived preflight.txt with all 12 providers installed, passed, evidence verified, and detailed provider availability summary"
fi

require_executable "$AGENT_TEAMS_GRAPH_PERFORMANCE_SMOKE" "agent-teams-graph-performance-smoke"
require_executable "$AGENT_TEAMS_GRAPH_PERFORMANCE_PREFLIGHT" "agent-teams-graph-performance-preflight"
AGENT_TEAMS_GRAPH_PERFORMANCE_SUMMARY="$(
  latest_artifact_with_fields \
    "${ROOT_DIR}/build/agent-teams-graph-performance" \
    'summary.txt' \
    'result=agent-teams-graph-performance-ok' \
    'nodeCount=12' \
    'frameBudgetMs=16' \
    'maxFrameMs=ok' \
    'updates=ok' || true
)"
if [ -n "$AGENT_TEAMS_GRAPH_PERFORMANCE_SUMMARY" ]; then
  record_check "agent-teams-graph-performance=${AGENT_TEAMS_GRAPH_PERFORMANCE_SUMMARY#${ROOT_DIR}/}"
else
  blocker "Agent Teams graph performance has no archived summary.txt proving 12-node visual updates stay within the 16ms frame budget"
fi

require_executable "$AGENT_WORKSPACE_RELEASE_PREFLIGHT" "agent-workspace-release-preflight"
AGENT_WORKSPACE_RELEASE_LATEST="$(
  latest_artifact \
    "${ROOT_DIR}/build/agent-workspace-release-preflight" \
    'preflight.txt' || true
)"
if [ -n "$AGENT_WORKSPACE_RELEASE_LATEST" ]; then
  record_check "agent-workspace-release-preflight-latest=${AGENT_WORKSPACE_RELEASE_LATEST#${ROOT_DIR}/}"
  record_check "agent-workspace-release-preflight-status=$(artifact_field "$AGENT_WORKSPACE_RELEASE_LATEST" status)"
  record_check "agent-workspace-release-preflight-target=$(artifact_field "$AGENT_WORKSPACE_RELEASE_LATEST" targetVersion)"
  record_check "agent-workspace-release-preflight-blocked=$(artifact_field "$AGENT_WORKSPACE_RELEASE_LATEST" blocked)"
  record_check "agent-workspace-release-preflight-next=$(artifact_field "$AGENT_WORKSPACE_RELEASE_LATEST" next)"
  record_release_preflight_blockers "$AGENT_WORKSPACE_RELEASE_LATEST"
fi
AGENT_WORKSPACE_RELEASE_CANDIDATE="$(
  latest_artifact_with_fields \
    "${ROOT_DIR}/build/agent-workspace-release-preflight" \
    'preflight.txt' \
    'targetVersion=1.18.0' \
    'blocked=0' || true
)"
AGENT_WORKSPACE_RELEASE_SUMMARY=""
if [ -n "$AGENT_WORKSPACE_RELEASE_CANDIDATE" ] &&
   verify_release_preflight_summary "$AGENT_WORKSPACE_RELEASE_CANDIDATE"; then
  AGENT_WORKSPACE_RELEASE_SUMMARY="$AGENT_WORKSPACE_RELEASE_CANDIDATE"
fi
if [ -n "$AGENT_WORKSPACE_RELEASE_SUMMARY" ]; then
  record_check "agent-workspace-release-preflight=${AGENT_WORKSPACE_RELEASE_SUMMARY#${ROOT_DIR}/}"
else
  blocker "Agent Workspace OS v1.18.0 release target has no archived preflight.txt with status=ok, targetVersion=1.18.0, blocked=0, and detailed release evidence summary"
fi

require_executable "$AGENT_WORKSPACE_PRODUCT_UX_SMOKE" "agent-workspace-product-ux-smoke"
require_executable "$AGENT_WORKSPACE_PRODUCT_UX_PREFLIGHT" "agent-workspace-product-ux-preflight"
record_product_ux_acceptance_state
AGENT_WORKSPACE_PRODUCT_UX_PREFLIGHT_LATEST="$(
  latest_artifact \
    "${ROOT_DIR}/build/agent-workspace-product-ux-preflight" \
    'preflight.txt' || true
)"
if [ -n "$AGENT_WORKSPACE_PRODUCT_UX_PREFLIGHT_LATEST" ]; then
  record_check "agent-workspace-product-ux-preflight-latest=${AGENT_WORKSPACE_PRODUCT_UX_PREFLIGHT_LATEST#${ROOT_DIR}/}"
  record_check "agent-workspace-product-ux-preflight-status=$(artifact_field "$AGENT_WORKSPACE_PRODUCT_UX_PREFLIGHT_LATEST" status)"
  record_check "agent-workspace-product-ux-preflight-next=$(artifact_field "$AGENT_WORKSPACE_PRODUCT_UX_PREFLIGHT_LATEST" next)"
fi
AGENT_WORKSPACE_PRODUCT_UX_SUMMARY="$(
  latest_product_ux_summary || true
)"
if [ -n "$AGENT_WORKSPACE_PRODUCT_UX_SUMMARY" ]; then
  record_check "agent-workspace-product-ux-artifact=${AGENT_WORKSPACE_PRODUCT_UX_SUMMARY#${ROOT_DIR}/}"
else
  record_product_ux_smoke_blocker
fi

require_executable "$A11Y_SMOKE" "agent-workspace-a11y-smoke"
A11Y_SUMMARY="$(
  latest_artifact_with_fields \
    "${ROOT_DIR}/build/agent-workspace-os-a11y" \
    'summary.txt' \
    'result=agent-workspace-a11y-ok' \
    'surfaces=6' \
    'voiceoverAcceptance=source-and-test' \
    'wcagAA=ok' \
    'swiftTests=passed' || true
)"
if [ -n "$A11Y_SUMMARY" ] && [ -f "${ROOT_DIR}/build/agent-workspace-os-a11y/voiceover-ok.txt" ]; then
  record_check "voiceover-artifact=${A11Y_SUMMARY#${ROOT_DIR}/}"
else
  blocker "Product v1.18 UX incomplete: no VoiceOver/WCAG acceptance artifact with status=ok"
fi

require_executable "$COCXYCORE_MOAT_SMOKE" "cocxycore-moat-smoke"
COCXYCORE_MOAT_SUMMARY="$(
  latest_artifact_with_fields \
    "${ROOT_DIR}/build/cocxycore-moat" \
    'summary.txt' \
    'result=cocxycore-moat-smoke-ok' || true
)"
if [ -n "$COCXYCORE_MOAT_SUMMARY" ] &&
   verify_referenced_file_with_hash "$COCXYCORE_MOAT_SUMMARY" "swiftTestOutput" "swiftTestOutputSha256" &&
   verify_referenced_file_with_hash "$COCXYCORE_MOAT_SUMMARY" "swiftTestError" "swiftTestErrorSha256"; then
  record_check "cocxycore-moat-artifact=${COCXYCORE_MOAT_SUMMARY#${ROOT_DIR}/}"
else
  blocker "CocxyCore moat has no archived summary.txt with status=ok, result=cocxycore-moat-smoke-ok, and hashed Swift test output"
fi

record_agent_workspace_plan_phase_statuses

if [ -n "$FINAL_REPORT_DECLARED_STATUS" ]; then
  if [ "$BLOCKER_COUNT" -eq 0 ] && [ "$FINAL_REPORT_DECLARED_STATUS" != "complete" ]; then
    blocker "completion final report status is ${FINAL_REPORT_DECLARED_STATUS}, but all gates are green"
  elif [ "$BLOCKER_COUNT" -gt 0 ] && [ "$FINAL_REPORT_DECLARED_STATUS" = "complete" ]; then
    blocker "completion final report claims complete while blockers remain"
  else
    record_check "completion-final-report-status-consistency=matches-blockers"
  fi
fi

if [ "$BLOCKER_COUNT" -eq 0 ]; then
  echo "status=complete"
else
  echo "status=not-complete"
fi

for check in "${CHECKS[@]}"; do
  echo "check=${check}"
done

if [ "$BLOCKER_COUNT" -gt 0 ]; then
  for item in "${BLOCKERS[@]}"; do
    echo "blocker=${item}"
  done
fi

if [ "$BLOCKER_COUNT" -eq 0 ]; then
  exit 0
fi
exit 1
