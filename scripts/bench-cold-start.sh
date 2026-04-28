#!/usr/bin/env zsh
set -euo pipefail

APP_PATH="${APP_PATH:-build/CocxyTerminal.app}"
RUNS="${RUNS:-5}"
BUDGET_MS="${BUDGET_MS:-2000}"
TOLERANCE_RATIO="${TOLERANCE_RATIO:-0.10}"
REQUIRED_CONSECUTIVE_FAILURES="${REQUIRED_CONSECUTIVE_FAILURES:-3}"
ENFORCE="${COCXY_ENFORCE_COLD_START:-0}"
BENCHMARK_KIND="app-readiness"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP_PATH="$2"; shift 2 ;;
    --runs) RUNS="$2"; shift 2 ;;
    --budget-ms) BUDGET_MS="$2"; shift 2 ;;
    --required-consecutive-failures) REQUIRED_CONSECUTIVE_FAILURES="$2"; shift 2 ;;
    --enforce) ENFORCE="1"; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 2
fi

CLI="$APP_PATH/Contents/Resources/cocxy"
if [[ ! -x "$CLI" ]]; then
  echo "CLI helper not found in bundle: $CLI" >&2
  exit 2
fi

quit_existing_app() {
  /usr/bin/osascript -e 'quit app "Cocxy Terminal"' >/dev/null 2>&1 &
  local quit_pid=$!
  local deadline=$((SECONDS + 2))
  while kill -0 "$quit_pid" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      kill "$quit_pid" >/dev/null 2>&1 || true
      break
    fi
    sleep 0.05
  done
  wait "$quit_pid" >/dev/null 2>&1 || true

  local shutdown_deadline=$((SECONDS + 2))
  while pgrep -x CocxyTerminal >/dev/null 2>&1; do
    if (( SECONDS >= shutdown_deadline )); then
      pkill -x CocxyTerminal >/dev/null 2>&1 || true
      break
    fi
    sleep 0.05
  done
}

samples=()
for ((i = 1; i <= RUNS; i++)); do
  quit_existing_app
  sleep 0.35

  start_ns="$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time() * 1000000000')"
  /usr/bin/open -n "$APP_PATH"
  deadline=$((SECONDS + 10))
  until "$CLI" status >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for Cocxy status on run $i" >&2
      exit 1
    fi
    sleep 0.05
  done
  end_ns="$(perl -MTime::HiRes=time -e 'printf "%.0f\n", time() * 1000000000')"
  elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
  samples+=("$elapsed_ms")
done

sorted=("${(@f)$(printf '%s\n' "${samples[@]}" | sort -n)}")
count="${#sorted[@]}"
if (( count == 0 )); then
  echo "No samples collected" >&2
  exit 1
fi

if (( count % 2 == 1 )); then
  median="${sorted[$((count / 2 + 1))]}"
else
  left="${sorted[$((count / 2))]}"
  right="${sorted[$((count / 2 + 1))]}"
  median="$(awk "BEGIN { print ($left + $right) / 2 }")"
fi

tolerated="$(awk "BEGIN { print $BUDGET_MS * (1 + $TOLERANCE_RATIO) }")"
within="$(awk "BEGIN { print ($median <= $tolerated) ? 1 : 0 }")"
trailing_failures=0
for sample in "${samples[@]}"; do
  sample_over="$(awk "BEGIN { print ($sample > $tolerated) ? 1 : 0 }")"
  if [[ "$sample_over" == "1" ]]; then
    trailing_failures=$((trailing_failures + 1))
  else
    trailing_failures=0
  fi
done
gate_passed="$(awk "BEGIN { print ($trailing_failures < $REQUIRED_CONSECUTIVE_FAILURES) ? 1 : 0 }")"

printf '{\n'
printf '  "app": "%s",\n' "$APP_PATH"
printf '  "benchmark_kind": "%s",\n' "$BENCHMARK_KIND"
printf '  "runs": %s,\n' "$RUNS"
printf '  "samples_ms": [%s],\n' "${(j:,:)samples}"
printf '  "median_ms": %s,\n' "$median"
printf '  "budget_ms": %s,\n' "$BUDGET_MS"
printf '  "tolerated_budget_ms": %s,\n' "$tolerated"
printf '  "within_budget": %s,\n' "$([[ "$within" == "1" ]] && echo true || echo false)"
printf '  "required_consecutive_failures": %s,\n' "$REQUIRED_CONSECUTIVE_FAILURES"
printf '  "trailing_failures": %s,\n' "$trailing_failures"
printf '  "gate_passed": %s\n' "$([[ "$gate_passed" == "1" ]] && echo true || echo false)"
printf '}\n'

if [[ "$ENFORCE" == "1" && "$gate_passed" != "1" ]]; then
  exit 1
fi
