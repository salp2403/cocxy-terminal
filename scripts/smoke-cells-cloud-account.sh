#!/usr/bin/env bash
set -euo pipefail

# Manual account-backed cloud Cells smoke.
#
# This intentionally requires COCXY_CELLS_CLOUD_E2E=1 because it can create
# billable user-owned cloud resources. It verifies the real Cocxy app socket
# and CLI lifecycle for one cloud provider: create, status, exec, logs, attach,
# list, and destroy. It never runs from CI/release automation.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_CLI="${PROJECT_ROOT}/build/CocxyTerminal.app/Contents/Resources/cocxy"
DEBUG_CLI="${PROJECT_ROOT}/.build/debug/cocxy"
CLI="${COCXY_CELLS_CLI:-}"
SOCKET_PATH="${HOME}/.config/cocxy/cocxy.sock"
PROVIDER="${1:-${COCXY_CELLS_CLOUD_PROVIDER:-}}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
ARTIFACT_ROOT=""
CELL_ID=""

usage() {
  cat <<'USAGE'
usage: scripts/smoke-cells-cloud-account.sh <e2b|fly|aws|gcp|azure>

Required safety switch:
  COCXY_CELLS_CLOUD_E2E=1

Common:
  COCXY_CELLS_CLI=/path/to/cocxy

Provider env:
  e2b:   COCXY_E2B_TEMPLATE, optional COCXY_E2B_PATH, COCXY_E2B_CONFIG
  fly:   COCXY_FLY_APP, optional COCXY_FLY_IMAGE, COCXY_FLY_REGION, COCXY_FLY_VM_SIZE, COCXY_FLY_VM_MEMORY, COCXY_FLY_VM_CPUS
  aws:   COCXY_AWS_IMAGE, COCXY_AWS_REGION, COCXY_AWS_INSTANCE_PROFILE, optional COCXY_AWS_PROFILE, COCXY_AWS_SUBNET, COCXY_AWS_SECURITY_GROUP, COCXY_AWS_KEY_NAME, COCXY_AWS_VM_SIZE, COCXY_AWS_CLOUD_INIT
  gcp:   COCXY_GCP_IMAGE, COCXY_GCP_PROJECT, COCXY_GCP_ZONE, optional COCXY_GCP_USER, COCXY_GCP_IDENTITY, COCXY_GCP_NETWORK, COCXY_GCP_SUBNET, COCXY_GCP_VM_SIZE, COCXY_GCP_CLOUD_INIT
  azure: COCXY_AZURE_IMAGE, COCXY_AZURE_RESOURCE_GROUP, optional COCXY_AZURE_SUBSCRIPTION, COCXY_AZURE_LOCATION, COCXY_AZURE_USER, COCXY_AZURE_IDENTITY, COCXY_AZURE_NETWORK, COCXY_AZURE_SUBNET, COCXY_AZURE_VM_SIZE, COCXY_AZURE_CLOUD_INIT
USAGE
}

skip() {
  if [ -n "$ARTIFACT_ROOT" ]; then
    mkdir -p "$ARTIFACT_ROOT"
    {
      echo "status=skipped"
      echo "provider=${PROVIDER}"
      echo "reason=$1"
      echo "artifactRoot=${ARTIFACT_ROOT}"
    } | tee "$ARTIFACT_ROOT/summary.txt"
  else
    echo "status=skipped"
    echo "provider=${PROVIDER}"
    echo "reason=$1"
  fi
  exit 2
}

fail_with_output() {
  local reason="$1"
  local file="${2:-}"
  mkdir -p "$ARTIFACT_ROOT"
  {
    echo "status=failed"
    echo "provider=${PROVIDER}"
    echo "reason=${reason}"
    echo "artifactRoot=${ARTIFACT_ROOT}"
    if [ -n "$file" ] && [ -f "$file" ]; then
      echo "output=${file}"
    fi
  } | tee "$ARTIFACT_ROOT/summary.txt"
  if [ -n "$file" ] && [ -f "$file" ]; then
    sed -n '1,220p' "$file"
  fi
  exit 1
}

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    skip "missing required environment variable: ${name}"
  fi
}

append_arg_if_set() {
  local flag="$1"
  local value="${2:-}"
  if [ -n "$value" ]; then
    CREATE_ARGS+=("$flag" "$value")
  fi
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

record_output_evidence() {
  local field="$1"
  local file="$2"
  echo "${field}=${file#${PROJECT_ROOT}/}"
  echo "${field}Sha256=$(sha256_file "$file")"
}

default_exec_attempts() {
  case "$PROVIDER" in
    aws) echo 12 ;;
    *) echo 6 ;;
  esac
}

default_status_attempts() {
  case "$PROVIDER" in
    aws|azure) echo 30 ;;
    *) echo 12 ;;
  esac
}

cell_status_value() {
  local file="$1"
  sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$file" | head -1
}

wait_for_cell_running() {
  local max_attempts="${COCXY_CELLS_CLOUD_STATUS_ATTEMPTS:-$(default_status_attempts)}"
  local delay_seconds="${COCXY_CELLS_CLOUD_STATUS_RETRY_DELAY_SECONDS:-10}"
  local attempt
  local status

  : > "${ARTIFACT_ROOT}/cell-status-wait.log"
  for attempt in $(seq 1 "$max_attempts"); do
    if ! "$CLI" cell status "$CELL_ID" --provider "$PROVIDER" > "${ARTIFACT_ROOT}/cell-status.out" 2> "${ARTIFACT_ROOT}/cell-status.err"; then
      cp "${ARTIFACT_ROOT}/cell-status.out" "${ARTIFACT_ROOT}/cell-status-attempt-${attempt}.out"
      cp "${ARTIFACT_ROOT}/cell-status.err" "${ARTIFACT_ROOT}/cell-status-attempt-${attempt}.err"
      echo "attempt=${attempt} result=failed" >> "${ARTIFACT_ROOT}/cell-status-wait.log"
      return 1
    fi

    status="$(cell_status_value "${ARTIFACT_ROOT}/cell-status.out")"
    cp "${ARTIFACT_ROOT}/cell-status.out" "${ARTIFACT_ROOT}/cell-status-attempt-${attempt}.out"
    cp "${ARTIFACT_ROOT}/cell-status.err" "${ARTIFACT_ROOT}/cell-status-attempt-${attempt}.err"
    echo "attempt=${attempt} status=${status:-missing}" >> "${ARTIFACT_ROOT}/cell-status-wait.log"

    case "$status" in
      running)
        return 0
        ;;
      # Provisioning statuses that should naturally settle before exec/logs/attach.
      # transient statuses: "creating"|"provisioning"|"pending"|"starting"
      creating|provisioning|pending|starting)
        ;;
      *)
        return 1
        ;;
    esac

    if [ "$attempt" -lt "$max_attempts" ] && [ "$delay_seconds" -gt 0 ]; then
      sleep "$delay_seconds"
    fi
  done

  return 1
}

run_cell_exec_with_retries() {
  local expected="$1"
  local max_attempts="${COCXY_CELLS_CLOUD_EXEC_ATTEMPTS:-$(default_exec_attempts)}"
  local delay_seconds="${COCXY_CELLS_CLOUD_EXEC_RETRY_DELAY_SECONDS:-20}"
  local attempt

  : > "${ARTIFACT_ROOT}/cell-exec-retries.log"
  for attempt in $(seq 1 "$max_attempts"); do
    if "$CLI" cell exec "$CELL_ID" --provider "$PROVIDER" -- printf "$expected" > "${ARTIFACT_ROOT}/cell-exec.out" 2> "${ARTIFACT_ROOT}/cell-exec.err"; then
      echo "attempt=${attempt} result=ok" >> "${ARTIFACT_ROOT}/cell-exec-retries.log"
      return 0
    fi
    cp "${ARTIFACT_ROOT}/cell-exec.out" "${ARTIFACT_ROOT}/cell-exec-attempt-${attempt}.out"
    cp "${ARTIFACT_ROOT}/cell-exec.err" "${ARTIFACT_ROOT}/cell-exec-attempt-${attempt}.err"
    echo "attempt=${attempt} result=failed" >> "${ARTIFACT_ROOT}/cell-exec-retries.log"
    if [ "$attempt" -lt "$max_attempts" ]; then
      sleep "$delay_seconds"
    fi
  done
  return 1
}

cleanup() {
  set +e
  if [ -n "$CELL_ID" ] && [ -x "$CLI" ]; then
    "$CLI" cell destroy "$CELL_ID" --provider "$PROVIDER" --force > "${ARTIFACT_ROOT}/cleanup-cell-destroy.out" 2> "${ARTIFACT_ROOT}/cleanup-cell-destroy.err"
  fi
}
trap cleanup EXIT

if [ -z "$PROVIDER" ] || [ "$PROVIDER" = "-h" ] || [ "$PROVIDER" = "--help" ]; then
  usage
  exit 2
fi

case "$PROVIDER" in
  e2b|fly|aws|gcp|azure) ;;
  *)
    usage
    skip "unsupported provider: ${PROVIDER}"
    ;;
esac

ARTIFACT_ROOT="${COCXY_CELLS_CLOUD_ARTIFACTS:-${PROJECT_ROOT}/build/cells-cloud-${PROVIDER}/${TIMESTAMP}}"
mkdir -p "$ARTIFACT_ROOT"

if [ "${COCXY_CELLS_CLOUD_E2E:-0}" != "1" ]; then
  skip "set COCXY_CELLS_CLOUD_E2E=1 to allow account-backed cloud resource creation"
fi

case "$PROVIDER" in
  e2b) REQUIRED_TOOL="e2b" ;;
  fly) REQUIRED_TOOL="fly" ;;
  aws) REQUIRED_TOOL="aws" ;;
  gcp) REQUIRED_TOOL="gcloud" ;;
  azure) REQUIRED_TOOL="az" ;;
esac
if ! command -v "$REQUIRED_TOOL" >/dev/null 2>&1; then
  skip "required tool not found: ${REQUIRED_TOOL}"
fi

if [ -z "$CLI" ]; then
  if [ -x "$BUNDLE_CLI" ]; then
    CLI="$BUNDLE_CLI"
  elif [ -x "$DEBUG_CLI" ]; then
    CLI="$DEBUG_CLI"
  else
    skip "no bundle-local or debug Cocxy CLI found"
  fi
elif [ ! -x "$CLI" ]; then
  skip "configured Cocxy CLI is not executable: ${CLI}"
fi

if [ ! -S "$SOCKET_PATH" ]; then
  skip "Cocxy app socket is missing: ${SOCKET_PATH}"
fi
if ! "$CLI" status > "${ARTIFACT_ROOT}/cocxy-status.out" 2> "${ARTIFACT_ROOT}/cocxy-status.err"; then
  skip "Cocxy app socket is not responding"
fi

PROFILE="cells-cloud-${PROVIDER}-${TIMESTAMP}-$$"
CREATE_ARGS=(cell create --provider "$PROVIDER" --profile "$PROFILE")

case "$PROVIDER" in
  e2b)
    require_env COCXY_E2B_TEMPLATE
    CREATE_ARGS+=(--template "$COCXY_E2B_TEMPLATE")
    append_arg_if_set --path "${COCXY_E2B_PATH:-}"
    append_arg_if_set --config "${COCXY_E2B_CONFIG:-}"
    ;;
  fly)
    require_env COCXY_FLY_APP
    CREATE_ARGS+=(--app "$COCXY_FLY_APP" --image "${COCXY_FLY_IMAGE:-alpine:3.20}")
    append_arg_if_set --region "${COCXY_FLY_REGION:-}"
    append_arg_if_set --vm-size "${COCXY_FLY_VM_SIZE:-}"
    append_arg_if_set --vm-memory "${COCXY_FLY_VM_MEMORY:-}"
    append_arg_if_set --vm-cpus "${COCXY_FLY_VM_CPUS:-}"
    ;;
  aws)
    require_env COCXY_AWS_IMAGE
    require_env COCXY_AWS_REGION
    require_env COCXY_AWS_INSTANCE_PROFILE
    CREATE_ARGS+=(--image "$COCXY_AWS_IMAGE" --region "$COCXY_AWS_REGION")
    append_arg_if_set --cloud-profile "${COCXY_AWS_PROFILE:-}"
    append_arg_if_set --subnet "${COCXY_AWS_SUBNET:-}"
    append_arg_if_set --security-group "${COCXY_AWS_SECURITY_GROUP:-}"
    append_arg_if_set --key-name "${COCXY_AWS_KEY_NAME:-}"
    append_arg_if_set --instance-profile "${COCXY_AWS_INSTANCE_PROFILE:-}"
    append_arg_if_set --vm-size "${COCXY_AWS_VM_SIZE:-}"
    append_arg_if_set --cloud-init "${COCXY_AWS_CLOUD_INIT:-}"
    ;;
  gcp)
    require_env COCXY_GCP_IMAGE
    require_env COCXY_GCP_PROJECT
    require_env COCXY_GCP_ZONE
    CREATE_ARGS+=(--image "$COCXY_GCP_IMAGE" --project "$COCXY_GCP_PROJECT" --zone "$COCXY_GCP_ZONE")
    append_arg_if_set --user "${COCXY_GCP_USER:-}"
    append_arg_if_set --identity "${COCXY_GCP_IDENTITY:-}"
    append_arg_if_set --network "${COCXY_GCP_NETWORK:-}"
    append_arg_if_set --subnet "${COCXY_GCP_SUBNET:-}"
    append_arg_if_set --vm-size "${COCXY_GCP_VM_SIZE:-}"
    append_arg_if_set --cloud-init "${COCXY_GCP_CLOUD_INIT:-}"
    ;;
  azure)
    require_env COCXY_AZURE_IMAGE
    require_env COCXY_AZURE_RESOURCE_GROUP
    CREATE_ARGS+=(--image "$COCXY_AZURE_IMAGE" --resource-group "$COCXY_AZURE_RESOURCE_GROUP")
    append_arg_if_set --cloud-profile "${COCXY_AZURE_SUBSCRIPTION:-}"
    append_arg_if_set --region "${COCXY_AZURE_LOCATION:-}"
    append_arg_if_set --user "${COCXY_AZURE_USER:-}"
    append_arg_if_set --identity "${COCXY_AZURE_IDENTITY:-}"
    append_arg_if_set --network "${COCXY_AZURE_NETWORK:-}"
    append_arg_if_set --subnet "${COCXY_AZURE_SUBNET:-}"
    append_arg_if_set --vm-size "${COCXY_AZURE_VM_SIZE:-}"
    append_arg_if_set --cloud-init "${COCXY_AZURE_CLOUD_INIT:-}"
    ;;
esac

printf '%q ' "$CLI" "${CREATE_ARGS[@]}" > "${ARTIFACT_ROOT}/cell-create.command"
printf '\n' >> "${ARTIFACT_ROOT}/cell-create.command"
if ! "$CLI" "${CREATE_ARGS[@]}" > "${ARTIFACT_ROOT}/cell-create.out" 2> "${ARTIFACT_ROOT}/cell-create.err"; then
  fail_with_output "cell create failed" "${ARTIFACT_ROOT}/cell-create.err"
fi
CELL_ID="$(sed -n 's/^Cell created: //p' "${ARTIFACT_ROOT}/cell-create.out" | head -1)"
if [ -z "$CELL_ID" ]; then
  fail_with_output "cell create did not return a cell id" "${ARTIFACT_ROOT}/cell-create.out"
fi

if ! wait_for_cell_running; then
  fail_with_output "cell did not report running status" "${ARTIFACT_ROOT}/cell-status.out"
fi

EXPECTED="cells-cloud-${PROVIDER}-ok"
if ! run_cell_exec_with_retries "$EXPECTED"; then
  fail_with_output "cell exec failed" "${ARTIFACT_ROOT}/cell-exec.err"
fi
if ! grep -q "$EXPECTED" "${ARTIFACT_ROOT}/cell-exec.out"; then
  fail_with_output "cell exec did not return expected output" "${ARTIFACT_ROOT}/cell-exec.out"
fi

if ! "$CLI" cell logs "$CELL_ID" --provider "$PROVIDER" > "${ARTIFACT_ROOT}/cell-logs.out" 2> "${ARTIFACT_ROOT}/cell-logs.err"; then
  fail_with_output "cell logs failed" "${ARTIFACT_ROOT}/cell-logs.err"
fi

if ! "$CLI" cell attach "$CELL_ID" --provider "$PROVIDER" > "${ARTIFACT_ROOT}/cell-attach.out" 2> "${ARTIFACT_ROOT}/cell-attach.err"; then
  fail_with_output "cell attach failed" "${ARTIFACT_ROOT}/cell-attach.err"
fi
if ! grep -q '"status" : "attach-ready"' "${ARTIFACT_ROOT}/cell-attach.out" ||
   ! grep -q '"pty-command"' "${ARTIFACT_ROOT}/cell-attach.out"; then
  fail_with_output "cell attach did not return PTY command fields" "${ARTIFACT_ROOT}/cell-attach.out"
fi

if ! "$CLI" cell list > "${ARTIFACT_ROOT}/cell-list.out" 2> "${ARTIFACT_ROOT}/cell-list.err"; then
  fail_with_output "cell list failed" "${ARTIFACT_ROOT}/cell-list.err"
fi
if ! grep -q "$CELL_ID" "${ARTIFACT_ROOT}/cell-list.out"; then
  fail_with_output "cell list did not include created cloud cell" "${ARTIFACT_ROOT}/cell-list.out"
fi

if ! "$CLI" cell destroy "$CELL_ID" --provider "$PROVIDER" --force > "${ARTIFACT_ROOT}/cell-destroy.out" 2> "${ARTIFACT_ROOT}/cell-destroy.err"; then
  fail_with_output "cell destroy failed" "${ARTIFACT_ROOT}/cell-destroy.err"
fi
CELL_ID=""

{
  echo "status=ok"
  echo "provider=${PROVIDER}"
  echo "artifactRoot=${ARTIFACT_ROOT}"
  echo "create=ok"
  echo "status-check=ok"
  echo "exec=ok"
  echo "logs=ok"
  echo "attach=ok"
  echo "list=ok"
  echo "destroy=ok"
  record_output_evidence "createOutput" "${ARTIFACT_ROOT}/cell-create.out"
  record_output_evidence "statusOutput" "${ARTIFACT_ROOT}/cell-status.out"
  record_output_evidence "execOutput" "${ARTIFACT_ROOT}/cell-exec.out"
  record_output_evidence "logsOutput" "${ARTIFACT_ROOT}/cell-logs.out"
  record_output_evidence "attachOutput" "${ARTIFACT_ROOT}/cell-attach.out"
  record_output_evidence "listOutput" "${ARTIFACT_ROOT}/cell-list.out"
  record_output_evidence "destroyOutput" "${ARTIFACT_ROOT}/cell-destroy.out"
  echo "cellProfile=${PROFILE}"
  echo "result=cells-cloud-${PROVIDER}-ok"
} | tee "$ARTIFACT_ROOT/summary.txt"
