#!/usr/bin/env bash
set -euo pipefail

# Manual/audit runner for the private Agent Workspace OS verification moat.
#
# This script makes the 9 planned E2E matrices explicit and audits concrete
# artifacts. It intentionally reports partial or missing evidence as blocked
# instead of treating unit tests or implementation breadth as a full E2E pass.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:---audit}"
MATRIX_COUNT=0
BLOCKED_COUNT=0

print_list() {
  printf 'id\tname\ttarget\trunner\n'
  printf 'browser-automation\tBrowser Automation Matrix\t45+ commands and 80+ browser E2E cases\tscripts/smoke-browser-automation-matrix.sh\n'
  printf 'remote-ssh-browser\tRemote SSH Browser Matrix\t12+ Docker SSH scenarios with HMAC, upload, proxy fallback, discovery\tscripts/smoke-remote-browser-docker-ssh.sh\n'
  printf 'agent-team-launcher\tAgent Team Launcher Matrix\t11+ providers with real launcher and hook workflow smoke\tscripts/smoke-agent-teams-provider-process.sh\n'
  printf 'socket-security\tSocket Security Matrix\tSingle-use leases, HMAC relay failures, bearer auth, socket contracts\tswift test filters + bundle attach smoke\n'
  printf 'privacy-audit\tPrivacy Audit\tNo telemetry and no restricted private terms in public surfaces\trg static scans\n'
  printf 'bundle-local-cli-smoke\tBundle-Local CLI Smoke\tBundle-local version/status against a running app\tscripts/smoke-bundle-local-cli.sh\n'
  printf 'visual-screenshot\tVisual Screenshot Tests\tGolden image coverage for user-facing strategic surfaces\tscripts/smoke-visual-screenshot-golden.sh\n'
  printf 'performance-regressions\tPerformance Regressions\tVersioned benchmark artifacts checked against baselines\tscripts/check-performance-regression.py\n'
  printf 'config-import\tConfig Import Tests\t5 terminal importers dry-run/apply matrix\tConfigImport tests and importer fixtures\n'
}

latest_file() {
  local directory="$1"
  local pattern="$2"
  if [ ! -d "$directory" ]; then
    return 1
  fi
  find "$directory" -maxdepth 2 -type f -name "$pattern" -print 2>/dev/null | sort -r | head -1
}

latest_directory() {
  local directory="$1"
  if [ ! -d "$directory" ]; then
    return 1
  fi
  find "$directory" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | sort -r | head -1
}

artifact_with_fields() {
  local directory="$1"
  local pattern="$2"
  shift 2
  local file
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
  done < <(find "$directory" -maxdepth 2 -type f -name "$pattern" -print 2>/dev/null | sort -r)
  return 1
}

emit_matrix() {
  local id="$1"
  local status="$2"
  local evidence="$3"
  local detail="$4"
  MATRIX_COUNT=$((MATRIX_COUNT + 1))
  if [ "$status" != "ok" ]; then
    BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
  fi
  printf 'matrix=%s\tstatus=%s\tevidence=%s\tdetail=%s\n' "$id" "$status" "$evidence" "$detail"
}

audit_browser_automation() {
  local matrix
  matrix="$(latest_file "${ROOT_DIR}/build/browser-automation-matrix" "matrix.tsv" || true)"
  if [ -z "$matrix" ]; then
    emit_matrix "browser-automation" "blocked" "missing" "no browser automation matrix.tsv artifact; target=80"
    return
  fi

  local scenarios
  scenarios="$(($(wc -l < "$matrix") - 1))"
  if [ "$scenarios" -ge 80 ]; then
    emit_matrix "browser-automation" "ok" "${matrix#${ROOT_DIR}/}" "scenarios=${scenarios}; target=80"
  else
    emit_matrix "browser-automation" "blocked" "${matrix#${ROOT_DIR}/}" "scenarios=${scenarios}; target=80"
  fi
}

audit_remote_ssh_browser() {
  local docker_state="available"
  if ! command -v docker >/dev/null 2>&1; then
    docker_state="missing"
  elif ! docker info >/dev/null 2>&1; then
    docker_state="daemon-unavailable"
  fi

  local summary
  summary="$(
    artifact_with_fields \
      "${ROOT_DIR}/build/remote-browser-docker-ssh" \
      "summary.txt" \
      "hmac=ok" \
      "proxyFallback=ok" \
      "dragDropUpload=ok" \
      "discovery=ok" || true
  )"
  local latest_summary
  latest_summary="$(latest_file "${ROOT_DIR}/build/remote-browser-docker-ssh" "summary.txt" || true)"
  if [ "$docker_state" != "available" ]; then
    local evidence="missing"
    if [ -n "$latest_summary" ]; then
      evidence="${latest_summary#${ROOT_DIR}/}"
    fi
    emit_matrix "remote-ssh-browser" "blocked" "$evidence" "docker=${docker_state}; live Docker SSH smoke cannot be refreshed"
    return
  fi

  if [ -n "$summary" ]; then
    emit_matrix "remote-ssh-browser" "ok" "${summary#${ROOT_DIR}/}" "docker-ssh-summary=ok"
    return
  fi

  local evidence="missing"
  if [ -n "$latest_summary" ]; then
    evidence="${latest_summary#${ROOT_DIR}/}"
  fi
  emit_matrix "remote-ssh-browser" "blocked" "$evidence" "no Docker SSH status=ok summary; docker=${docker_state}"
}

audit_agent_team_launcher() {
  local preflight
  preflight="$(latest_file "${ROOT_DIR}/build/agent-teams-provider-coverage-preflight" "preflight.txt" || true)"
  if [ -n "$preflight" ]; then
    local status installed passed evidence
    status="$(sed -n 's/^status=//p' "$preflight" | head -1)"
    installed="$(sed -n 's/^latestProviderProcessInstalled=//p' "$preflight" | head -1)"
    passed="$(sed -n 's/^latestProviderProcessPassed=//p' "$preflight" | head -1)"
    evidence="$(sed -n 's/^latestProviderProcessEvidence=//p' "$preflight" | head -1)"
    if [ "$status" = "ok" ] &&
       [ "$installed" = "12" ] &&
       [ "$passed" = "12" ] &&
       [ "$evidence" = "ok" ]; then
      emit_matrix "agent-team-launcher" "ok" "${preflight#${ROOT_DIR}/}" "all-provider-process-preflight=ok"
    else
      emit_matrix "agent-team-launcher" "blocked" "${preflight#${ROOT_DIR}/}" "provider coverage status=${status:-missing}; installed=${installed:-0}/12; passed=${passed:-0}/12; evidence=${evidence:-missing}"
    fi
    return
  fi

  local latest
  latest="$(latest_directory "${ROOT_DIR}/build/agent-teams-provider-process" || true)"
  if [ -n "$latest" ]; then
    emit_matrix "agent-team-launcher" "blocked" "${latest#${ROOT_DIR}/}" "provider coverage preflight missing; process smoke alone is not all-provider coverage"
  else
    emit_matrix "agent-team-launcher" "blocked" "missing" "no provider coverage preflight artifact"
  fi
}

audit_socket_security() {
  local attach_summary
  attach_summary="$(latest_directory "${ROOT_DIR}/build/cells-attach-bundle" || true)"
  if [ -n "$attach_summary" ] &&
     [ -s "${attach_summary}/websocket-client.out" ] &&
     grep -q 'badAuthRejected=true' "${attach_summary}/websocket-client.out" &&
     grep -q 'validAuthAccepted=true' "${attach_summary}/websocket-client.out" &&
     grep -q 'replayRejected=true' "${attach_summary}/websocket-client.out"; then
    emit_matrix "socket-security" "ok" "${attach_summary#${ROOT_DIR}/}" "one-shot websocket bad-auth, valid-auth, and replay rejection observed"
  else
    emit_matrix "socket-security" "blocked" "missing" "no bundle attach artifact with bad-auth, valid-auth, and replay rejection"
  fi
}

audit_privacy() {
  local restricted_pattern
  restricted_pattern="${COCXY_RESTRICTED_PUBLIC_TERMS_REGEX:-$(printf '\\143\\155\\165\\170|\\155\\141\\156\\141\\146\\154\\157\\167')}"

  local output
  output="$(
    rg -n -i "$restricted_pattern" \
      "${ROOT_DIR}/README"* \
      "${ROOT_DIR}/Sources" \
      "${ROOT_DIR}/CLI" \
      "${ROOT_DIR}/Resources" \
      "${ROOT_DIR}/Shared" \
      "${ROOT_DIR}/Daemon" \
      "${ROOT_DIR}/QuickLook" 2>/dev/null || true
  )"
  if [ -n "$output" ]; then
    emit_matrix "privacy-audit" "blocked" "rg public scan" "restricted private terms found in public surfaces"
  else
    emit_matrix "privacy-audit" "ok" "rg public scan" "no restricted private terms in public surfaces"
  fi
}

audit_bundle_local_cli() {
  local summary
  summary="$(
    artifact_with_fields \
      "${ROOT_DIR}/build/bundle-local-cli" \
      "summary.txt" \
      "statusCheck=ok" \
      "result=bundle-local-cli-ok" || true
  )"
  if [ -n "$summary" ]; then
    local version
    version="$(sed -n 's/^version=//p' "$summary" | head -1)"
    emit_matrix "bundle-local-cli-smoke" "ok" "${summary#${ROOT_DIR}/}" "version=${version}; status=ok"
  else
    emit_matrix "bundle-local-cli-smoke" "blocked" "missing" "no bundle-local summary.txt with statusCheck=ok and result=bundle-local-cli-ok"
  fi
}

audit_visual_screenshot() {
  local summary
  summary="$(
    artifact_with_fields \
      "${ROOT_DIR}/build/visual-screenshot-golden" \
      "summary.txt" \
      "result=visual-screenshot-golden-ok" \
      "requiredScreenshots=20" || true
  )"
  if [ -n "$summary" ]; then
    local checked
    checked="$(sed -n 's/^checkedScreenshots=//p' "$summary" | head -1)"
    if [ "${checked:-0}" -ge 20 ]; then
      emit_matrix "visual-screenshot" "ok" "${summary#${ROOT_DIR}/}" "approved-golden-screenshots=${checked}"
      return
    fi
  fi

  local latest
  latest="$(latest_directory "${ROOT_DIR}/build/browser-automation-matrix" || true)"
  if [ -n "$latest" ] && find "${latest}/action-screenshots" -type f -name '*.png' -print -quit 2>/dev/null | grep -q .; then
    emit_matrix "visual-screenshot" "blocked" "${latest#${ROOT_DIR}/action-screenshots}" "action screenshots exist, but no approved golden image matrix"
  else
    emit_matrix "visual-screenshot" "blocked" "missing" "no screenshot artifact and no approved golden image matrix"
  fi
}

audit_performance_regressions() {
  local performance_dir="${ROOT_DIR}/build/performance"
  local cold_start="${performance_dir}/cold-start.json"
  local memory="${performance_dir}/memory-baseline.json"
  local benchmark_log="${performance_dir}/benchmark-suite.log"
  local regression_check="${performance_dir}/regression-check.json"

  if [ -s "$cold_start" ] && [ -s "$memory" ] && [ -s "$benchmark_log" ]; then
    if "${ROOT_DIR}/scripts/check-performance-regression.py" \
      --baseline "${ROOT_DIR}/scripts/performance-baselines.json" \
      --metric-file "$cold_start" \
      --metric-file "$memory" \
      --log-file "$benchmark_log" \
      --enforce > "$regression_check" 2> "${regression_check}.err"; then
      emit_matrix "performance-regressions" "ok" "${performance_dir#${ROOT_DIR}/}" "benchmark artifacts passed baseline check"
    else
      emit_matrix "performance-regressions" "blocked" "${performance_dir#${ROOT_DIR}/}" "benchmark artifacts failed baseline check"
    fi
  else
    emit_matrix "performance-regressions" "blocked" "missing" "no current build/performance benchmark artifact checked against baselines"
  fi
}

audit_config_import() {
  local test_file="${ROOT_DIR}/Tests/Unit/ConfigImportTests/TerminalConfigImportersSwiftTestingTests.swift"
  if [ -s "$test_file" ] &&
     grep -q "Ghostty" "$test_file" &&
     grep -q "iTerm2" "$test_file" &&
     grep -q "Alacritty" "$test_file" &&
     grep -q "Kitty" "$test_file" &&
     grep -q "WezTerm" "$test_file"; then
    emit_matrix "config-import" "ok" "${test_file#${ROOT_DIR}/}" "five importer fixtures covered by Swift Testing"
  else
    emit_matrix "config-import" "blocked" "${test_file#${ROOT_DIR}/}" "five importer matrix coverage missing"
  fi
}

audit_all() {
  audit_browser_automation
  audit_remote_ssh_browser
  audit_agent_team_launcher
  audit_socket_security
  audit_privacy
  audit_bundle_local_cli
  audit_visual_screenshot
  audit_performance_regressions
  audit_config_import

  if [ "$MATRIX_COUNT" -eq 9 ] && [ "$BLOCKED_COUNT" -eq 0 ]; then
    echo "status=complete"
  else
    echo "status=not-complete"
  fi
  echo "matrix-count=${MATRIX_COUNT}"
  echo "blocked-count=${BLOCKED_COUNT}"

  if [ "$MATRIX_COUNT" -eq 9 ] && [ "$BLOCKED_COUNT" -eq 0 ]; then
    return 0
  fi
  return 1
}

case "$MODE" in
  --list)
    print_list
    ;;
  --audit)
    audit_all
    ;;
  *)
    echo "usage: $0 [--list|--audit]" >&2
    exit 64
    ;;
esac
