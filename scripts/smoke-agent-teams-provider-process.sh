#!/usr/bin/env bash
# Manual Agent Teams provider-process smoke.
#
# This smoke is intentionally kept out of unauthenticated CI because it runs
# real installed provider binaries. It never writes to the user's real agent
# config directories: COCXY_HOOKS_HOME points every setup-hooks operation at a
# temporary fixture home under build/.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_ROOT="${COCXY_AGENT_TEAMS_SMOKE_ARTIFACTS:-${ROOT_DIR}/build/agent-teams-provider-process/$(date +%Y%m%d-%H%M%S)}"
HOOKS_HOME="${ARTIFACT_ROOT}/hooks-home"
PROVIDER_TIMEOUT="${COCXY_AGENT_TEAMS_PROVIDER_TIMEOUT:-45}"
STRICT_PROVIDER_SMOKE="${COCXY_AGENT_TEAMS_STRICT_PROVIDER_SMOKE:-0}"

mkdir -p "${ARTIFACT_ROOT}" "${HOOKS_HOME}"

if [[ "${HOOKS_HOME}" != "${ARTIFACT_ROOT}"/* ]]; then
  echo "status=failed"
  echo "reason=unsafe hooks home: ${HOOKS_HOME}" >&2
  exit 1
fi

find_cocxy_cli() {
  if [[ -n "${COCXY_CLI:-}" && -x "${COCXY_CLI}" ]]; then
    printf '%s\n' "${COCXY_CLI}"
    return 0
  fi

  (cd "${ROOT_DIR}" && swift build --product cocxy >/dev/null)
  local bin_path
  bin_path="$(cd "${ROOT_DIR}" && swift build --show-bin-path 2>/dev/null | tail -n 1)"
  local built_cli="${bin_path}/cocxy"
  if [[ -x "${built_cli}" ]]; then
    printf '%s\n' "${built_cli}"
    return 0
  fi

  local bundle_cli="${ROOT_DIR}/build/CocxyTerminal.app/Contents/Resources/cocxy"
  if [[ -x "${bundle_cli}" ]]; then
    printf '%s\n' "${bundle_cli}"
    return 0
  fi

  echo "Unable to locate or build cocxy CLI" >&2
  return 1
}

COCXY_CLI="$(find_cocxy_cli)"
export COCXY_CLI

run_cocxy() {
  COCXY_HOOKS_HOME="${HOOKS_HOME}" "${COCXY_CLI}" "$@"
}

find_provider_binary() {
  local candidates_csv="$1"
  local candidate
  IFS=',' read -r -a candidates <<< "${candidates_csv}"
  for candidate in "${candidates[@]}"; do
    if command -v "${candidate}" >/dev/null 2>&1; then
      command -v "${candidate}"
      return 0
    fi
  done
  return 1
}

probe_provider_process() {
  local provider="$1"
  local binary="$2"
  local output="${ARTIFACT_ROOT}/${provider}-provider-process.out"

  /usr/bin/python3 - "${binary}" "${PROVIDER_TIMEOUT}" "${output}" <<'PY'
import pathlib
import os
import subprocess
import sys

binary = sys.argv[1]
timeout = float(sys.argv[2])
output = pathlib.Path(sys.argv[3])
env = dict(os.environ)
env["PATH"] = str(pathlib.Path(binary).parent) + ":" + env.get("PATH", "")
attempts = [
    ["--version"],
    ["version"],
    ["--help"],
    ["help"],
]

lines = []
for args in attempts:
    try:
        result = subprocess.run(
            [binary, *args],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
            env=env,
        )
    except subprocess.TimeoutExpired:
        lines.append(f"{binary} {' '.join(args)} timed out")
        continue
    except OSError as exc:
        lines.append(f"{binary} {' '.join(args)} failed to start: {exc}")
        continue

    first_line = (result.stdout or "").splitlines()[:1]
    summary = first_line[0] if first_line else ""
    lines.append(f"{binary} {' '.join(args)} exit={result.returncode} {summary}")
    if result.returncode == 0:
        output.write_text("\n".join(lines) + "\n", encoding="utf-8")
        sys.exit(0)

output.write_text("\n".join(lines) + "\n", encoding="utf-8")
sys.exit(1)
PY
}

AGENTS=(
  "claude-code|claude|Claude Code|claude,claude-code"
  "codex|codex|Codex CLI|codex"
  "gemini|gemini|Gemini CLI|gemini"
  "kiro|kiro|Kiro|kiro,kiro-cli"
  "opencode|opencode|OpenCode|opencode,open-code"
  "pi|pi|Pi|pi"
  "cursor|cursor|Cursor|cursor-agent,cursor"
  "rovo-dev|rovo-dev|Rovo Dev|acli,rovodev,rovo"
  "copilot|copilot|Copilot|copilot"
  "codebuddy|codebuddy|CodeBuddy|codebuddy"
  "factory|factory|Factory|droid,factory"
  "qoder|qoder|Qoder|qodercli,qoder"
)

installed_count=0
passed_count=0
process_preflight_failed_count=0
EVIDENCE_MANIFEST="${ARTIFACT_ROOT}/provider-evidence.tsv"
printf 'providerID\thookAgent\tbinary\tprocessOutput\tprocessOutputSha256\tdryRunOutput\tdryRunOutputSha256\tinstallOutput\tinstallOutputSha256\tcheckOutput\tcheckOutputSha256\thookHandlerOutput\thookHandlerOutputSha256\tremoveOutput\tremoveOutputSha256\n' > "${EVIDENCE_MANIFEST}"

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

evidence_pair() {
  local file="$1"
  printf '%s\t%s' "${file#${ROOT_DIR}/}" "$(sha256_file "$file")"
}

for row in "${AGENTS[@]}"; do
  IFS='|' read -r provider_id hook_target display candidates <<< "${row}"
  binary="$(find_provider_binary "${candidates}" || true)"
  if [[ -z "${binary}" ]]; then
    continue
  fi

  installed_count=$((installed_count + 1))
  echo "provider=${provider_id}"
  echo "hook-agent=${hook_target}"
  echo "display=${display}"
  echo "binary=${binary}"

  if ! probe_provider_process "${provider_id}" "${binary}"; then
    process_preflight_failed_count=$((process_preflight_failed_count + 1))
    echo "provider-process-preflight-failed=${provider_id}"
    cat "${ARTIFACT_ROOT}/${provider_id}-provider-process.out" >&2 || true
    if [[ "${STRICT_PROVIDER_SMOKE}" == "1" ]]; then
      echo "status=failed"
      echo "reason=${display} process preflight failed"
      exit 1
    fi
  else
    echo "provider-process-preflight-ok=${provider_id}"
  fi

  if ! run_cocxy setup-hooks --agent "${hook_target}" --dry-run > "${ARTIFACT_ROOT}/${provider_id}-dry-run.out" 2> "${ARTIFACT_ROOT}/${provider_id}-dry-run.err"; then
    echo "status=failed"
    echo "reason=${display} dry-run failed"
    cat "${ARTIFACT_ROOT}/${provider_id}-dry-run.err" >&2 || true
    exit 1
  fi
  if ! grep -q "would install" "${ARTIFACT_ROOT}/${provider_id}-dry-run.out"; then
    echo "status=failed"
    echo "reason=${display} dry-run did not preview install"
    cat "${ARTIFACT_ROOT}/${provider_id}-dry-run.out" >&2
    exit 1
  fi

  if ! run_cocxy setup-hooks --agent "${hook_target}" > "${ARTIFACT_ROOT}/${provider_id}-install.out" 2> "${ARTIFACT_ROOT}/${provider_id}-install.err"; then
    echo "status=failed"
    echo "reason=${display} install failed"
    cat "${ARTIFACT_ROOT}/${provider_id}-install.err" >&2 || true
    exit 1
  fi

  if ! run_cocxy setup-hooks --agent "${hook_target}" --check > "${ARTIFACT_ROOT}/${provider_id}-check.out" 2> "${ARTIFACT_ROOT}/${provider_id}-check.err"; then
    echo "status=failed"
    echo "reason=${display} check failed"
    cat "${ARTIFACT_ROOT}/${provider_id}-check.out" >&2 || true
    cat "${ARTIFACT_ROOT}/${provider_id}-check.err" >&2 || true
    exit 1
  fi
  if ! grep -q "hooks OK" "${ARTIFACT_ROOT}/${provider_id}-check.out"; then
    echo "status=failed"
    echo "reason=${display} check did not report hooks OK"
    cat "${ARTIFACT_ROOT}/${provider_id}-check.out" >&2
    exit 1
  fi

  payload="{\"hook_event_name\":\"SessionStart\",\"session_id\":\"${provider_id}-smoke\",\"cwd\":\"${ROOT_DIR}\"}"
  if ! printf '%s' "${payload}" \
      | COCXY_HOOKS_HOME="${HOOKS_HOME}" COCXY_CLAUDE_HOOKS=1 COCXY_HOOK_AGENT="${hook_target}" "${COCXY_CLI}" hook-handler \
      > "${ARTIFACT_ROOT}/${provider_id}-hook-handler.out" 2> "${ARTIFACT_ROOT}/${provider_id}-hook-handler.err"; then
    echo "status=failed"
    echo "reason=${display} hook-handler exited non-zero"
    cat "${ARTIFACT_ROOT}/${provider_id}-hook-handler.err" >&2 || true
    exit 1
  fi

  if ! run_cocxy setup-hooks --agent "${hook_target}" --remove > "${ARTIFACT_ROOT}/${provider_id}-remove.out" 2> "${ARTIFACT_ROOT}/${provider_id}-remove.err"; then
    echo "status=failed"
    echo "reason=${display} remove failed"
    cat "${ARTIFACT_ROOT}/${provider_id}-remove.err" >&2 || true
    exit 1
  fi

  echo "hook-preflight-ok=${provider_id}"
  echo "hook-handler-exit-ok=${provider_id}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${provider_id}" \
    "${hook_target}" \
    "${binary}" \
    "$(evidence_pair "${ARTIFACT_ROOT}/${provider_id}-provider-process.out")" \
    "$(evidence_pair "${ARTIFACT_ROOT}/${provider_id}-dry-run.out")" \
    "$(evidence_pair "${ARTIFACT_ROOT}/${provider_id}-install.out")" \
    "$(evidence_pair "${ARTIFACT_ROOT}/${provider_id}-check.out")" \
    "$(evidence_pair "${ARTIFACT_ROOT}/${provider_id}-hook-handler.out")" \
    "$(evidence_pair "${ARTIFACT_ROOT}/${provider_id}-remove.out")" \
    >> "${EVIDENCE_MANIFEST}"
  passed_count=$((passed_count + 1))
done

if [[ "${installed_count}" -eq 0 ]]; then
  {
    echo "status=skipped"
    echo "reason=no supported provider binaries found in PATH"
    echo "artifactRoot=${ARTIFACT_ROOT}"
  } | tee "${ARTIFACT_ROOT}/summary.txt"
  exit 0
fi

{
  if [[ "${process_preflight_failed_count}" -gt 0 ]]; then
    echo "status=degraded"
    echo "reason=one or more installed provider binaries failed non-interactive process preflight"
    echo "failedProviderProcesses=${process_preflight_failed_count}"
  else
    echo "status=ok"
  fi
  echo "installedProviders=${installed_count}"
  echo "passedProviders=${passed_count}"
  echo "providerEvidence=${EVIDENCE_MANIFEST#${ROOT_DIR}/}"
  echo "providerEvidenceSha256=$(sha256_file "${EVIDENCE_MANIFEST}")"
  echo "hooksHome=${HOOKS_HOME}"
  echo "artifactRoot=${ARTIFACT_ROOT}"
  echo "result=agent-teams-provider-process-ok"
} | tee "${ARTIFACT_ROOT}/summary.txt"
