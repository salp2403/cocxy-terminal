#!/usr/bin/env bash
set -euo pipefail

# Manual Docker Cells smoke.
#
# This verifies the real Cocxy app socket can drive the local Docker provider
# through the shipped or debug CLI. It is intentionally not wired into CI and
# skips cleanly when Docker, the CLI, or the Cocxy app socket is unavailable.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_CLI="${PROJECT_ROOT}/build/CocxyTerminal.app/Contents/Resources/cocxy"
DEBUG_CLI="${PROJECT_ROOT}/.build/debug/cocxy"
CLI="${COCXY_CELLS_CLI:-}"
SOCKET_PATH="${HOME}/.config/cocxy/cocxy.sock"
ARTIFACT_ROOT="${COCXY_CELLS_DOCKER_ARTIFACTS:-${PROJECT_ROOT}/build/cells-docker/$(date +%Y%m%d-%H%M%S)}"
CELL_IMAGE="${COCXY_CELLS_DOCKER_IMAGE:-alpine:3.20}"
PROFILE="cells-docker-smoke-$$"
CELL_ID=""

skip() {
  mkdir -p "$ARTIFACT_ROOT"
  {
    echo "status=skipped"
    echo "reason=$1"
    echo "artifactRoot=${ARTIFACT_ROOT}"
  } | tee "$ARTIFACT_ROOT/summary.txt"
  exit 2
}

fail_with_output() {
  local reason="$1"
  local file="${2:-}"
  mkdir -p "$ARTIFACT_ROOT"
  {
    echo "status=failed"
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

cleanup() {
  set +e
  if [ -n "$CELL_ID" ] && [ -x "$CLI" ]; then
    "$CLI" cell destroy "$CELL_ID" --force > "${ARTIFACT_ROOT}/cleanup-destroy.out" 2> "${ARTIFACT_ROOT}/cleanup-destroy.err"
  fi
}
trap cleanup EXIT

if ! command -v docker >/dev/null 2>&1; then
  skip "docker CLI not found"
fi
if ! docker info >/dev/null 2>&1; then
  skip "docker daemon is not available"
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

mkdir -p "$ARTIFACT_ROOT"
if ! "$CLI" status > "${ARTIFACT_ROOT}/cocxy-status.out" 2> "${ARTIFACT_ROOT}/cocxy-status.err"; then
  skip "Cocxy app socket is not responding"
fi

if ! "$CLI" cell create --provider docker --image "$CELL_IMAGE" --profile "$PROFILE" \
  > "${ARTIFACT_ROOT}/cell-create.out" 2> "${ARTIFACT_ROOT}/cell-create.err"; then
  fail_with_output "cell create failed" "${ARTIFACT_ROOT}/cell-create.err"
fi
CELL_ID="$(sed -n 's/^Cell created: //p' "${ARTIFACT_ROOT}/cell-create.out" | head -1)"
if [ -z "$CELL_ID" ]; then
  fail_with_output "cell create did not return a cell id" "${ARTIFACT_ROOT}/cell-create.out"
fi

if ! "$CLI" cell status "$CELL_ID" > "${ARTIFACT_ROOT}/cell-status.out" 2> "${ARTIFACT_ROOT}/cell-status.err"; then
  fail_with_output "cell status failed" "${ARTIFACT_ROOT}/cell-status.err"
fi
if ! grep -q '"status" : "running"' "${ARTIFACT_ROOT}/cell-status.out"; then
  fail_with_output "cell did not report running status" "${ARTIFACT_ROOT}/cell-status.out"
fi

if ! "$CLI" cell exec "$CELL_ID" -- sh -lc 'printf cells-docker-ok' \
  > "${ARTIFACT_ROOT}/cell-exec.out" 2> "${ARTIFACT_ROOT}/cell-exec.err"; then
  fail_with_output "cell exec failed" "${ARTIFACT_ROOT}/cell-exec.err"
fi
if ! grep -q "cells-docker-ok" "${ARTIFACT_ROOT}/cell-exec.out"; then
  fail_with_output "cell exec did not return expected output" "${ARTIFACT_ROOT}/cell-exec.out"
fi

if ! "$CLI" cell logs "$CELL_ID" > "${ARTIFACT_ROOT}/cell-logs.out" 2> "${ARTIFACT_ROOT}/cell-logs.err"; then
  fail_with_output "cell logs failed" "${ARTIFACT_ROOT}/cell-logs.err"
fi

if ! "$CLI" cell list > "${ARTIFACT_ROOT}/cell-list.out" 2> "${ARTIFACT_ROOT}/cell-list.err"; then
  fail_with_output "cell list failed" "${ARTIFACT_ROOT}/cell-list.err"
fi
if ! grep -q "$CELL_ID" "${ARTIFACT_ROOT}/cell-list.out"; then
  fail_with_output "cell list did not include created cell" "${ARTIFACT_ROOT}/cell-list.out"
fi

if ! "$CLI" cell destroy "$CELL_ID" --force > "${ARTIFACT_ROOT}/cell-destroy.out" 2> "${ARTIFACT_ROOT}/cell-destroy.err"; then
  fail_with_output "cell destroy failed" "${ARTIFACT_ROOT}/cell-destroy.err"
fi
CELL_ID=""

{
  echo "status=ok"
  echo "artifactRoot=${ARTIFACT_ROOT}"
  echo "cellProfile=${PROFILE}"
  echo "result=cells-docker-ok"
} | tee "$ARTIFACT_ROOT/summary.txt"
