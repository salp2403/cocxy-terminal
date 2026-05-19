#!/usr/bin/env bash
set -euo pipefail

# Manual AWS Cells readiness sequence.
#
# This runner refuses to run from CI and never applies AWS setup. It orders the
# read-only verifier, read-only AWS preflight, cost-guarded AWS cloud smoke,
# aggregate cloud preflight, and final Agent Workspace OS completion audit.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_ROOT="${COCXY_CELLS_AWS_READINESS_ARTIFACTS:-${PROJECT_ROOT}/build/cells-aws-readiness-sequence/${TIMESTAMP}}"
SUMMARY_FILE="${ARTIFACT_ROOT}/summary.txt"
STEPS_FILE="${ARTIFACT_ROOT}/step-results.tsv"
AWS_VERIFY_ARTIFACTS="${ARTIFACT_ROOT}/aws-setup-verify"
AWS_PREFLIGHT_ARTIFACTS="${ARTIFACT_ROOT}/preflight-aws"
AWS_SMOKE_ARTIFACTS="${PROJECT_ROOT}/build/cells-cloud-aws/${TIMESTAMP}-readiness"
ALL_PREFLIGHT_ARTIFACTS="${ARTIFACT_ROOT}/preflight-all"
AUDIT_OUTPUT="${ARTIFACT_ROOT}/audit-agent-workspace-os-completion.out"
AWS_SMOKE_STATUS="not-run"

# Stable summary markers used by the tooling drift gate:
# awsSmoke=skipped-cost-guard
# result=cells-aws-readiness-sequence-ok

usage() {
  cat <<'USAGE'
usage: scripts/run-cells-aws-readiness-sequence.sh

Manual-only AWS readiness closure for Cocxy Cells.

Order:
  1. scripts/verify-cells-aws-setup.sh
  2. scripts/preflight-cells-cloud-account.sh aws
  3. scripts/smoke-cells-cloud-account.sh aws
  4. scripts/preflight-cells-cloud-account.sh all
  5. scripts/audit-agent-workspace-os-completion.sh

The AWS smoke can create billable user-owned AWS resources and runs only when:
  COCXY_CELLS_CLOUD_E2E=1

This script refuses to run from CI and never runs AWS setup apply.
USAGE
}

write_summary() {
  local status="$1"
  local result="$2"
  local reason="${3:-}"

  {
    echo "status=${status}"
    echo "result=${result}"
    if [ -n "$reason" ]; then
      echo "reason=${reason}"
    fi
    echo "artifactRoot=${ARTIFACT_ROOT}"
    echo "steps=${STEPS_FILE}"
    echo "awsSetupVerifyArtifacts=${AWS_VERIFY_ARTIFACTS}"
    echo "awsPreflightArtifacts=${AWS_PREFLIGHT_ARTIFACTS}"
    echo "awsSmoke=${AWS_SMOKE_STATUS}"
    echo "awsSmokeArtifacts=${AWS_SMOKE_ARTIFACTS}"
    echo "allPreflightArtifacts=${ALL_PREFLIGHT_ARTIFACTS}"
    echo "auditOutput=${AUDIT_OUTPUT}"
  } | tee "$SUMMARY_FILE"
}

record_step() {
  local name="$1"
  local status="$2"
  local exit_code="$3"
  local stdout_file="$4"
  local stderr_file="$5"

  printf '%s\t%s\t%s\t%s\t%s\n' \
    "$name" \
    "$status" \
    "$exit_code" \
    "${stdout_file#${PROJECT_ROOT}/}" \
    "${stderr_file#${PROJECT_ROOT}/}" >> "$STEPS_FILE"
}

run_step() {
  local name="$1"
  shift
  local stdout_file="${ARTIFACT_ROOT}/${name}.out"
  local stderr_file="${ARTIFACT_ROOT}/${name}.err"
  local exit_code

  set +e
  "$@" > "$stdout_file" 2> "$stderr_file"
  exit_code="$?"
  set -e

  if [ "$exit_code" -eq 0 ]; then
    record_step "$name" "ok" "0" "$stdout_file" "$stderr_file"
    return 0
  fi

  record_step "$name" "failed" "$exit_code" "$stdout_file" "$stderr_file"
  return "$exit_code"
}

fail_sequence() {
  local reason="$1"
  write_summary "blocked" "cells-aws-readiness-sequence-blocked" "$reason"
  exit 1
}

skip_sequence() {
  local reason="$1"
  write_summary "skipped" "cells-aws-readiness-sequence-skipped" "$reason"
  exit 2
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

mkdir -p "$ARTIFACT_ROOT"
printf 'step\tstatus\texitCode\tstdout\tstderr\n' > "$STEPS_FILE"
cd "$PROJECT_ROOT"

if [ -n "${CI:-}" ]; then
  skip_sequence "refuses to run from CI"
fi

if [ -n "${COCXY_AWS_SETUP_APPLY:-}" ]; then
  skip_sequence "COCXY_AWS_SETUP_APPLY is set; setup apply is intentionally not run by this readiness sequence"
fi

if ! run_step "verify-aws-setup" \
  env COCXY_AWS_VERIFY_ARTIFACTS="$AWS_VERIFY_ARTIFACTS" \
  scripts/verify-cells-aws-setup.sh; then
  fail_sequence "scripts/verify-cells-aws-setup.sh failed"
fi

if ! run_step "preflight-aws" \
  env COCXY_CELLS_CLOUD_PREFLIGHT_ARTIFACTS="$AWS_PREFLIGHT_ARTIFACTS" \
  scripts/preflight-cells-cloud-account.sh aws; then
  fail_sequence "scripts/preflight-cells-cloud-account.sh aws failed"
fi

if [ "${COCXY_CELLS_CLOUD_E2E:-0}" != "1" ]; then
  AWS_SMOKE_STATUS="skipped-cost-guard"
  write_summary "blocked" "cells-aws-readiness-sequence-blocked" \
    "set COCXY_CELLS_CLOUD_E2E=1 to allow billable user-owned AWS resources"
  exit 2
fi

AWS_SMOKE_STATUS="running"
if ! run_step "smoke-aws" \
  env COCXY_CELLS_CLOUD_ARTIFACTS="$AWS_SMOKE_ARTIFACTS" \
  scripts/smoke-cells-cloud-account.sh aws; then
  AWS_SMOKE_STATUS="failed"
  fail_sequence "scripts/smoke-cells-cloud-account.sh aws failed"
fi
AWS_SMOKE_STATUS="ok"

if ! run_step "preflight-all" \
  env COCXY_CELLS_CLOUD_PREFLIGHT_ARTIFACTS="$ALL_PREFLIGHT_ARTIFACTS" \
  scripts/preflight-cells-cloud-account.sh all; then
  fail_sequence "scripts/preflight-cells-cloud-account.sh all failed"
fi

if ! run_step "completion-audit" \
  scripts/audit-agent-workspace-os-completion.sh; then
  cp "${ARTIFACT_ROOT}/completion-audit.out" "$AUDIT_OUTPUT"
  fail_sequence "scripts/audit-agent-workspace-os-completion.sh failed"
fi
cp "${ARTIFACT_ROOT}/completion-audit.out" "$AUDIT_OUTPUT"

write_summary "ok" "cells-aws-readiness-sequence-ok"
