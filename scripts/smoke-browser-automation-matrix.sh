#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${COCXY_BROWSER_MATRIX_APP:-${PROJECT_ROOT}/build/CocxyTerminal.app}"
CLI="${APP}/Contents/Resources/cocxy"
ARTIFACT_ROOT="${COCXY_BROWSER_MATRIX_ARTIFACTS:-${PROJECT_ROOT}/build/browser-automation-matrix/$(date +%Y%m%d-%H%M%S)}"
SCREENSHOT_DIR="${ARTIFACT_ROOT}/action-screenshots"
MATRIX_TSV="${ARTIFACT_ROOT}/matrix.tsv"
SITE_DIR="${ARTIFACT_ROOT}/site"
PORT="${COCXY_BROWSER_MATRIX_PORT:-$((47000 + (RANDOM % 1000)))}"
BROWSER_MATRIX_MIN_SCENARIOS=80
BROWSER_MATRIX_ENV="COCXY_BROWSER_MATRIX_SMOKE=1"
SERVER_PID=""
APP_PID=""

json_field() {
  local field="$1"
  local file="$2"
  sed -n "s/.*\"${field}\" : \"\\([^\"]*\\)\".*/\\1/p" "$file" | head -1 | sed 's#\\/#/#g'
}

record_row() {
  local scenario="$1"
  local command="$2"
  local status="$3"
  local screenshot_status="${4:-}"
  local screenshot_path="${5:-}"
  printf '%s\t%s\t%s\t%s\t%s\n' "$scenario" "$command" "$status" "$screenshot_status" "$screenshot_path" >> "$MATRIX_TSV"
}

fail_with_output() {
  local message="$1"
  local file="$2"
  echo "status=failed"
  echo "reason=${message}"
  echo "artifactRoot=${ARTIFACT_ROOT}"
  if [ -f "$file" ]; then
    echo "output=${file}"
    sed -n '1,220p' "$file"
  fi
  exit 1
}

run_json() {
  local scenario="$1"
  local expected_status="$2"
  shift 2
  local output="${ARTIFACT_ROOT}/${scenario}.json"
  local stderr="${output}.stderr"
  if ! "$CLI" "$@" > "$output" 2> "$stderr"; then
    cat "$stderr" >> "$output"
    fail_with_output "${scenario} command failed" "$output"
  fi
  rm -f "$stderr"
  local status
  status="$(json_field status "$output")"
  if [ "$status" != "$expected_status" ]; then
    fail_with_output "${scenario} expected status ${expected_status}, got ${status:-<missing>}" "$output"
  fi
  record_row "$scenario" "$*" "$status" "" ""
}

run_success() {
  local scenario="$1"
  shift 1
  local output="${ARTIFACT_ROOT}/${scenario}.txt"
  local stderr="${output}.stderr"
  if ! "$CLI" "$@" > "$output" 2> "$stderr"; then
    cat "$stderr" >> "$output"
    fail_with_output "${scenario} command failed" "$output"
  fi
  rm -f "$stderr"
  record_row "$scenario" "$*" "ok" "" ""
}

run_eval_json() {
  local scenario="$1"
  local script="$2"
  local output="${ARTIFACT_ROOT}/${scenario}.json"
  local stderr="${output}.stderr"
  if ! "$CLI" browser eval "$script" > "$output" 2> "$stderr"; then
    cat "$stderr" >> "$output"
    fail_with_output "${scenario} eval command failed" "$output"
  fi
  rm -f "$stderr"
  local status
  status="$(json_field status "$output")"
  if [ "$status" != "evaluated" ]; then
    fail_with_output "${scenario} expected status evaluated, got ${status:-<missing>}" "$output"
  fi
  record_row "$scenario" "browser eval ${scenario}" "$status" "" ""
}

wait_for_fixture_ready() {
  local scenario="${1:-setup-ready}"
  local output stderr result
  for attempt in $(seq 1 40); do
    output="${ARTIFACT_ROOT}/${scenario}-${attempt}.json"
    stderr="${output}.stderr"
    if "$CLI" browser eval "(function(){ const marker = document.getElementById('name'); return [document.readyState, window.location.href, marker ? 'ready' : 'missing'].join('|'); })();" > "$output" 2> "$stderr"; then
      rm -f "$stderr"
      result="$(json_field result "$output")"
      if [[ "$result" == *"|ready" ]]; then
        record_row "$scenario" "browser eval fixture ready" evaluated "" ""
        return 0
      fi
    else
      cat "$stderr" >> "$output"
    fi
    sleep 0.5
  done
  fail_with_output "fixture DOM did not become ready" "$output"
}

require_json_field() {
  local scenario="$1"
  local field="$2"
  local expected="$3"
  local file="${ARTIFACT_ROOT}/${scenario}.json"
  local actual
  actual="$(json_field "$field" "$file")"
  if [ "$actual" != "$expected" ]; then
    fail_with_output "${scenario} expected ${field}=${expected}, got ${actual:-<missing>}" "$file"
  fi
}

run_action() {
  local scenario="$1"
  local expected_status="$2"
  shift 2
  local output="${ARTIFACT_ROOT}/${scenario}.json"
  local stderr="${output}.stderr"
  if ! COCXY_BROWSER_ACTION_EVIDENCE_DIR="$SCREENSHOT_DIR" "$CLI" "$@" > "$output" 2> "$stderr"; then
    cat "$stderr" >> "$output"
    fail_with_output "${scenario} command failed" "$output"
  fi
  rm -f "$stderr"
  local status screenshot_status screenshot_path
  status="$(json_field status "$output")"
  screenshot_status="$(json_field screenshotStatus "$output")"
  screenshot_path="$(json_field screenshotPath "$output")"
  if [ "$status" != "$expected_status" ]; then
    fail_with_output "${scenario} expected status ${expected_status}, got ${status:-<missing>}" "$output"
  fi
  if [ "$screenshot_status" != "captured" ] || [ ! -s "$screenshot_path" ]; then
    fail_with_output "${scenario} did not capture action screenshot evidence" "$output"
  fi
  record_row "$scenario" "$*" "$status" "$screenshot_status" "$screenshot_path"
}

process_line_for_pid() {
  local pid="$1"
  /bin/ps eww -p "$pid" 2>/dev/null || true
}

ensure_no_unrelated_app() {
  local pid process_line
  while read -r pid; do
    [ -n "$pid" ] || continue
    process_line="$(process_line_for_pid "$pid")"
    if [[ "$process_line" != *"$BROWSER_MATRIX_ENV"* ]]; then
      echo "status=failed"
      echo "reason=Cocxy Terminal is already running outside this browser matrix smoke."
      echo "pid=${pid}"
      echo "artifactRoot=${ARTIFACT_ROOT}"
      exit 1
    fi
    kill "$pid" >/dev/null 2>&1 || true
  done < <(pgrep -x CocxyTerminal || true)
}

find_browser_matrix_pid() {
  local pid process_line
  while read -r pid; do
    [ -n "$pid" ] || continue
    process_line="$(process_line_for_pid "$pid")"
    if [[ "$process_line" == *"$BROWSER_MATRIX_ENV"* ]]; then
      echo "$pid"
      return 0
    fi
  done < <(pgrep -x CocxyTerminal || true)
  return 1
}

cleanup() {
  if [ -n "$APP_PID" ]; then
    kill "$APP_PID" >/dev/null 2>&1 || true
  fi
  if [ -n "$SERVER_PID" ]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
  fi
}

if [ ! -d "$APP" ]; then
  echo "status=failed"
  echo "reason=app bundle not found: ${APP}"
  exit 1
fi
if [ ! -x "$CLI" ]; then
  echo "status=failed"
  echo "reason=bundle-local CLI not executable: ${CLI}"
  exit 1
fi

mkdir -p "$SCREENSHOT_DIR" "$SITE_DIR"
printf 'scenario\tcommand\tstatus\tscreenshotStatus\tscreenshotPath\n' > "$MATRIX_TSV"
cat > "${SITE_DIR}/index.html" <<'HTML'
<!doctype html>
<meta charset="utf-8">
<title>Browser Matrix</title>
<link rel="stylesheet" href="/matrix.css">
<script src="/matrix.js" defer></script>
<style>
  body { height: 1400px; font: 14px -apple-system, BlinkMacSystemFont, sans-serif; }
  .target { margin-top: 900px; }
  .hidden-box { display: none; }
</style>
<main id="matrix" role="main" aria-label="Browser Matrix">
  <label for="name">Name</label>
  <input id="name" name="name" placeholder="Name">
  <input id="email" name="email" placeholder="Email">
  <textarea id="notes" title="Notes Title">Initial notes</textarea>
  <div id="editable" contenteditable="true" title="Editable Title">Edit me</div>
  <input id="flag" type="checkbox">
  <input id="radio-a" type="radio" name="mode" value="a">
  <input id="file" type="file">
  <select id="choice">
    <option value="one">One</option>
    <option value="two" label="Second Option">Two</option>
    <option value="three">Three</option>
  </select>
  <button id="save" data-testid="save-button" title="Save Title" onclick="window.__clicks=(window.__clicks||0)+1; this.textContent='Saved'">Save</button>
  <button id="disabled" disabled title="Disabled Button">Disabled</button>
  <button id="dbl" ondblclick="window.__dbl=(window.__dbl||0)+1">Double</button>
  <img id="logo" alt="Matrix Logo" title="Logo Title" src="/pixel.svg">
  <a id="download" href="/download.txt" download>Download fixture</a>
  <ul id="items">
    <li class="entry">Alpha item</li>
    <li class="entry">Beta item</li>
    <li class="entry">Gamma item</li>
  </ul>
  <div id="hidden" class="hidden-box">Hidden Text</div>
  <iframe id="frame" srcdoc="<button id=frameButton>Frame</button>"></iframe>
  <div id="target" class="target">Scroll target</div>
</main>
<script>
  window.__matrixUpload = 'missing';
  const matrixFile = document.getElementById('file');
  const recordMatrixUpload = (files) => {
    const file = files && files[0];
    window.__matrixUpload = file ? `${file.name}:${file.size}` : 'empty';
  };
  matrixFile.addEventListener('change', (event) => recordMatrixUpload(event.target.files));
  matrixFile.addEventListener('drop', (event) => {
    event.preventDefault();
    recordMatrixUpload(event.dataTransfer && event.dataTransfer.files);
  });
</script>
HTML
cat > "${SITE_DIR}/matrix.css" <<'CSS'
#save { color: rgb(10, 20, 30); display: inline-block; }
CSS
cat > "${SITE_DIR}/matrix.js" <<'JS'
window.__matrixExternalScript = true;
console.info('matrix-external-script');
JS
cat > "${SITE_DIR}/pixel.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="2" height="2"><rect width="2" height="2" fill="#4f8cff"/></svg>
SVG
printf 'download fixture\n' > "${SITE_DIR}/download.txt"
UPLOAD_FIXTURE="${ARTIFACT_ROOT}/upload-fixture.txt"
printf 'matrix upload fixture\n' > "$UPLOAD_FIXTURE"

trap cleanup EXIT
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$SITE_DIR" > "${ARTIFACT_ROOT}/server.log" 2>&1 &
SERVER_PID="$!"
for attempt in $(seq 1 30); do
  if curl -fsS "http://127.0.0.1:${PORT}/index.html" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
    fail_with_output "local fixture server exited before readiness" "${ARTIFACT_ROOT}/server.log"
  fi
  sleep 1
  if [ "$attempt" = "30" ]; then
    fail_with_output "local fixture server did not become ready" "${ARTIFACT_ROOT}/server.log"
  fi
done
ensure_no_unrelated_app
/usr/bin/open -n --env "$BROWSER_MATRIX_ENV" "$APP"
for attempt in $(seq 1 30); do
  if "$CLI" status >/dev/null 2>&1; then
    break
  fi
  sleep 1
  if [ "$attempt" = "30" ]; then
    echo "status=failed"
    echo "reason=app did not respond to bundle-local CLI status"
    echo "artifactRoot=${ARTIFACT_ROOT}"
    exit 1
  fi
done
APP_PID="$(find_browser_matrix_pid || true)"
if [ -z "$APP_PID" ]; then
  echo "status=failed"
  echo "reason=app process not found after launch"
  echo "artifactRoot=${ARTIFACT_ROOT}"
  exit 1
fi

run_success navigate browser navigate "http://127.0.0.1:${PORT}/index.html"
wait_for_fixture_ready initial-ready
run_success navigate-hash browser navigate "http://127.0.0.1:${PORT}/index.html#history"
run_success back browser back
run_success forward browser forward
run_success reload browser reload
run_success navigate-reset browser navigate "http://127.0.0.1:${PORT}/index.html"
run_success preflight-state browser state
run_success preflight-tabs browser tabs
wait_for_fixture_ready setup-ready
run_eval_json setup-eval "(function(){ const name = document.getElementById('name'); if (!name) { return 'missing-name'; } name.focus(); console.log('matrix-ready'); return 'ready'; })();"
require_json_field setup-eval result ready

run_json snapshot captured browser snapshot
run_json context ok browser context --target id-matrix --around 4 --console 5 --network 10
run_json find-role ok browser find role button Save
run_json find-label ok browser find label Name
run_json find-testid ok browser find testid save-button
run_json find-text ok browser find text "Alpha item"
run_json find-placeholder ok browser find placeholder Email
run_json find-alt ok browser find alt "Matrix Logo"
run_json find-title ok browser find title "Save Title"
run_json find-first ok browser find first ".entry"
run_json find-last ok browser find last ".entry"
run_json find-nth ok browser find nth 1 ".entry"
run_json frames ok browser frames
run_success tabs browser tabs
run_json text evaluated browser text
run_json dialogs-empty ok browser dialogs
run_json downloads-empty ok browser downloads
run_success state-get browser state
STATE_FILE="${ARTIFACT_ROOT}/browser-state.json"
run_json state-save saved browser state save "$STATE_FILE"
if [ ! -s "$STATE_FILE" ]; then
  fail_with_output "state-save did not write browser state file" "${ARTIFACT_ROOT}/state-save.json"
fi
run_json state-load loaded browser state load "$STATE_FILE"
run_json get-title ok browser get title
require_json_field get-title title "Browser Matrix"
run_json get-html-page ok browser get html
run_json get-html-save ok browser get html id-save
run_json get-attr-save-title ok browser get attr id-save title
require_json_field get-attr-save-title value "Save Title"
run_json get-attr-logo-alt ok browser get attr id-logo alt
require_json_field get-attr-logo-alt value "Matrix Logo"
run_json get-count-buttons ok browser get count button
require_json_field get-count-buttons count "3"
run_json get-count-entry ok browser get count ".entry"
require_json_field get-count-entry count "3"
run_json get-box-save ok browser get box id-save
run_json get-styles-save-named ok browser get styles id-save color display
run_json get-styles-save-all ok browser get styles id-save
run_json is-visible-save ok browser is visible id-save
require_json_field is-visible-save visible true
run_json is-visible-hidden ok browser is visible id-hidden
require_json_field is-visible-hidden visible false
run_json is-enabled-save ok browser is enabled id-save
require_json_field is-enabled-save enabled true
run_json is-enabled-disabled ok browser is enabled id-disabled
require_json_field is-enabled-disabled enabled false
SCREENSHOT_DATA_FILE="${ARTIFACT_ROOT}/browser-screenshot-inline-safe.png"
run_json screenshot-data captured browser screenshot --output "$SCREENSHOT_DATA_FILE"
if [ ! -s "$SCREENSHOT_DATA_FILE" ]; then
  fail_with_output "screenshot-data did not write screenshot" "${ARTIFACT_ROOT}/screenshot-data.json"
fi
SCREENSHOT_FILE="${ARTIFACT_ROOT}/browser-screenshot.png"
run_json screenshot-file captured browser screenshot --output "$SCREENSHOT_FILE"
if [ ! -s "$SCREENSHOT_FILE" ]; then
  fail_with_output "screenshot-file did not write screenshot" "${ARTIFACT_ROOT}/screenshot-file.json"
fi
run_success console browser console
run_json wait-found found browser wait "#save" --timeout 0
run_json wait-timeout timeout browser wait "#missing-matrix-selector" --timeout 0
run_json cookies-set set browser cookies set matrix_cookie matrix_value --path /
run_success cookies-list browser cookies list
run_success cookies-list-domain browser cookies list --domain 127.0.0.1
run_json cookies-delete deleted browser cookies delete matrix_cookie --path /
run_success network-all browser network
run_success network-filter browser network --filter matrix
run_success network-tail browser network --tail 5
run_json storage-set set browser storage set matrix-key matrix-value --area local
run_json storage-get ok browser storage get matrix-key --area local
require_json_field storage-get value matrix-value
run_json storage-list ok browser storage list --area local
run_json storage-delete deleted browser storage delete matrix-key --area local
run_json storage-session-set set browser storage set session-key session-value --area session
run_json storage-session-get ok browser storage get session-key --area session
require_json_field storage-session-get value session-value
run_json storage-session-list ok browser storage list --area session
run_json storage-session-delete deleted browser storage delete session-key --area session
run_json add-script added browser add script "window.__matrixAddedScript = true;"
run_json add-style added browser add style "body { outline: 0 solid transparent; }"
run_json init-script-add added browser init scripts add "window.__matrixInitScript = true;"
run_json init-scripts-list ok browser init scripts list

run_action focus focused browser focus id-name --timeout 2000
run_action fill filled browser fill id-name Matrix --timeout 2000
run_action type typed browser type id-name " Test" --timeout 2000
run_json get-value-name ok browser get value id-name
require_json_field get-value-name value "Matrix Test"
run_action fill-editable filled browser fill id-editable "Editable Matrix" --timeout 2000
run_action type-page typed browser type " Page" --timeout 2000
run_action press pressed browser press Enter --timeout 2000
run_action keydown keydown browser keydown Shift --timeout 2000
run_action keyup keyup browser keyup Shift --timeout 2000
run_action hover hovered browser hover id-save --timeout 2000
run_action click clicked browser click id-save --timeout 2000
run_action dblclick dblclicked browser dblclick id-dbl --timeout 2000
run_action check checked browser check id-flag --timeout 2000
run_json is-checked-true ok browser is checked id-flag
require_json_field is-checked-true checked true
run_action uncheck unchecked browser uncheck id-flag --timeout 2000
run_json is-checked-false ok browser is checked id-flag
require_json_field is-checked-false checked false
run_action check-radio checked browser check id-radio-a --timeout 2000
run_json is-checked-radio ok browser is checked id-radio-a
require_json_field is-checked-radio checked true
run_action upload uploaded browser upload id-file "$UPLOAD_FIXTURE" --timeout 2000
UPLOAD_BYTES="$(wc -c < "$UPLOAD_FIXTURE" | tr -d ' ')"
if ! "$CLI" browser eval "window.__matrixUpload || 'missing';" > "${ARTIFACT_ROOT}/upload-check.json" 2> "${ARTIFACT_ROOT}/upload-check.stderr"; then
  cat "${ARTIFACT_ROOT}/upload-check.stderr" >> "${ARTIFACT_ROOT}/upload-check.json"
  fail_with_output "upload-check eval command failed" "${ARTIFACT_ROOT}/upload-check.json"
fi
rm -f "${ARTIFACT_ROOT}/upload-check.stderr"
upload_result="$(json_field result "${ARTIFACT_ROOT}/upload-check.json")"
if [ "$upload_result" != "upload-fixture.txt:${UPLOAD_BYTES}" ]; then
  fail_with_output "upload-check did not observe the uploaded file" "${ARTIFACT_ROOT}/upload-check.json"
fi
record_row upload-check "browser eval window.__matrixUpload" evaluated "" ""
run_action select selected browser select id-choice two --timeout 2000
run_json get-value-select ok browser get value id-choice
require_json_field get-value-select value two
run_action select-label selected browser select id-choice "Second Option" --timeout 2000
run_action select-index selected browser select id-choice 2 --timeout 2000
run_action scroll scrolled browser scroll --x 0 --y 120 --timeout 2000
run_action scroll-into-view scrolled browser scroll-into-view id-target --timeout 2000

scenario_count="$(($(wc -l < "$MATRIX_TSV") - 1))"
if (( scenario_count < BROWSER_MATRIX_MIN_SCENARIOS )); then
  fail_with_output "browser automation matrix recorded ${scenario_count} scenarios; target=${BROWSER_MATRIX_MIN_SCENARIOS}" "$MATRIX_TSV"
fi

echo "status=ok"
echo "artifactRoot=${ARTIFACT_ROOT}"
echo "matrix=${MATRIX_TSV}"
echo "screenshots=${SCREENSHOT_DIR}"
echo "scenarios=${scenario_count}"
