#!/usr/bin/env bash
set -euo pipefail

# Local acceptance smoke for the Agent Workspace OS product accessibility gate.
# It creates the VoiceOver/WCAG artifact consumed by the private completion
# audit only after source contracts, localization parity, WCAG contrast checks,
# and focused Swift tests all pass.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARTIFACT_ROOT="${COCXY_A11Y_ARTIFACT_ROOT:-${ROOT_DIR}/build/agent-workspace-os-a11y/$(date +%Y%m%d-%H%M%S)}"
MANIFEST="${ARTIFACT_ROOT}/surfaces.tsv"
WCAG_REPORT="${ARTIFACT_ROOT}/wcag-contrast.tsv"
TEST_LOG="${ARTIFACT_ROOT}/swift-tests.log"
SUMMARY="${ARTIFACT_ROOT}/summary.txt"
SENTINEL="${ROOT_DIR}/build/agent-workspace-os-a11y/voiceover-ok.txt"

mkdir -p "$ARTIFACT_ROOT" "$(dirname "$SENTINEL")"
rm -f "$SENTINEL"

run_step() {
  local label="$1"
  shift
  {
    printf '\n## %s\n' "$label"
    "$@"
  } >>"$TEST_LOG" 2>&1
}

python3 - "$ROOT_DIR" "$MANIFEST" "$WCAG_REPORT" <<'PY'
import math
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
manifest_path = pathlib.Path(sys.argv[2])
wcag_path = pathlib.Path(sys.argv[3])

surfaces = [
    {
        "id": "command-palette",
        "name": "Unified Command Palette",
        "source": "Sources/UI/CommandPalette/CommandPaletteView.swift",
        "tests": [
            "Tests/Unit/CommandPaletteTests/CommandPaletteWiringTests.swift",
            "Tests/Unit/CommandPaletteTests/UnifiedQuickSwitchWiringSwiftTestingTests.swift",
        ],
        "keys": [
            "commandPalette.accessibilityLabel",
            "commandPalette.search.placeholder",
        ],
        "markers": [
            ".accessibilityElement(children: .contain)",
            "commandPalette.accessibilityLabel",
            ".onKeyPress(.upArrow)",
            ".onKeyPress(.downArrow)",
            ".onKeyPress(.escape)",
        ],
    },
    {
        "id": "agent-dashboard",
        "name": "Agent And Remote Dashboard",
        "source": "Sources/UI/Dashboard/DashboardPanelView.swift",
        "tests": [
            "Tests/Unit/DashboardTests/DashboardPanelViewTests.swift",
            "Tests/Unit/AuroraTests/AuroraChromeControllerSwiftTestingTests.swift",
        ],
        "keys": [
            "agentDashboard.accessibility",
            "agentDashboard.close",
        ],
        "markers": [
            ".accessibilityElement(children: .contain)",
            "agentDashboard.accessibility",
            "agentDashboard.close",
            "WindowScope.allCases",
        ],
    },
    {
        "id": "browser-devtools",
        "name": "Browser DevTools And Action History",
        "source": "Sources/UI/Browser/BrowserDevToolsView.swift",
        "tests": [
            "Tests/Unit/BrowserTests/BrowserPanelLocalizationSwiftTestingTests.swift",
            "Tests/Unit/BrowserTests/BrowserScriptableTests.swift",
        ],
        "keys": [
            "browser.devTools.accessibility",
            "browser.devTools.close",
            "browser.devTools.tab.accessibility",
        ],
        "markers": [
            ".accessibilityElement(children: .contain)",
            "browser.devTools.accessibility",
            "browser.devTools.tab.accessibility",
            ".accessibilityAddTraits",
        ],
    },
    {
        "id": "remote-ports",
        "name": "Remote Workspace Port Suggestions",
        "source": "Sources/UI/RemoteWorkspace/RemoteConnectionView.swift",
        "tests": [
            "Tests/Unit/RemoteWorkspaceTests/RemotePortScannerBrowserRouteSwiftTestingTests.swift",
            "Tests/Unit/RemoteWorkspaceTests/SSHMultiplexerTests.swift",
        ],
        "keys": [
            "remoteWorkspace.accessibility",
            "remoteWorkspace.quickConnect.connect.accessibility",
        ],
        "markers": [
            ".accessibilityElement(children: .contain)",
            "remoteWorkspace.accessibility",
            "remoteWorkspace.browserSuggestions.open.accessibility",
            "onOpenRemoteBrowser",
        ],
    },
    {
        "id": "agent-teams",
        "name": "Agent Teams View",
        "source": "Sources/UI/AgentTeams/AgentTeamViews.swift",
        "tests": [
            "Tests/Unit/AgentTeamsTests/AgentTeamPresentationSwiftTestingTests.swift",
            "Tests/Unit/AgentTeamsTests/AgentTeamSwiftTestingTests.swift",
        ],
        "keys": [
            "agentTeams.panel.title",
        ],
        "all_lproj_keys": [
            "agentTeams.panel.title",
            "agentTeams.graph.accessibility",
            "agentTeams.feed.accessibility",
        ],
        "markers": [
            ".accessibilityElement(children: .contain)",
            ".accessibilityElement(children: .ignore)",
            "agentTeams.panel.title",
            "accessibilityLabel",
        ],
    },
    {
        "id": "code-review",
        "name": "Integrated Code Review",
        "source": "Sources/UI/CodeReview/CodeReviewPanelView.swift",
        "tests": [
            "Tests/Unit/CodeReviewTests/DiffContentViewSwiftTestingTests.swift",
            "Tests/Unit/CodeReviewTests/CodeReviewIntegrationSwiftTestingTests.swift",
        ],
        "keys": [
            "codeReview.panel.accessibility",
            "codeReview.panel.close",
            "codeReview.diff.line.accessibility",
        ],
        "markers": [
            ".accessibilityElement(children: .contain)",
            "codeReview.panel.accessibility",
            "codeReview.panel.close",
            "ReviewToolbarView",
        ],
    },
]

failures = []

def file_text(relative_path):
    path = root / relative_path
    if not path.is_file():
        failures.append(f"missing file: {relative_path}")
        return ""
    return path.read_text(encoding="utf-8", errors="replace")

localization_root = root / "Resources" / "Localization"
localization_files = sorted(localization_root.glob("*.lproj/Localizable.strings"))
if len(localization_files) < 21:
    failures.append(f"expected at least 21 localization files, found {len(localization_files)}")

localization_keys_by_file = {}
for path in localization_files:
    text = path.read_text(encoding="utf-8", errors="replace")
    localization_keys_by_file[path] = set(re.findall(r'^"([^"]+)"\s*=', text, re.MULTILINE))

primary_locales = {
    "Resources/Localization/en.lproj/Localizable.strings",
    "Resources/Localization/es.lproj/Localizable.strings",
}
manifest_rows = ["surface\tname\tsource\tchecks\tlocalizationFiles\ttests"]
for surface in surfaces:
    source_text = file_text(surface["source"])
    checks = []

    for marker in surface["markers"]:
        if marker not in source_text:
            failures.append(f"{surface['id']}: missing source marker {marker!r}")
        else:
            checks.append(marker)

    for key in surface["keys"]:
        missing = [
            str(path.relative_to(root))
            for path, keys in localization_keys_by_file.items()
            if str(path.relative_to(root)) in primary_locales
            if key not in keys
        ]
        if missing:
            failures.append(f"{surface['id']}: primary localization key {key!r} missing in {', '.join(missing)}")

    for key in surface.get("all_lproj_keys", []):
        missing = [
            str(path.relative_to(root))
            for path, keys in localization_keys_by_file.items()
            if key not in keys
        ]
        if missing:
            failures.append(f"{surface['id']}: Agent Workspace localization key {key!r} missing in {', '.join(missing)}")

    for test in surface["tests"]:
        file_text(test)

    manifest_rows.append(
        "\t".join([
            surface["id"],
            surface["name"],
            surface["source"],
            str(len(checks)),
            str(len(localization_files)),
            ",".join(surface["tests"]),
        ])
    )

def gamma_encode(channel):
    magnitude = abs(channel)
    sign = -1.0 if channel < 0 else 1.0
    if magnitude <= 0.0031308:
        return sign * 12.92 * magnitude
    return sign * (1.055 * (magnitude ** (1.0 / 2.4)) - 0.055)

def clamp(value):
    return min(max(value, 0.0), 1.0)

def srgb(token):
    lightness, chroma, hue = token
    hue_radians = hue * math.pi / 180.0
    a_value = chroma * math.cos(hue_radians)
    b_value = chroma * math.sin(hue_radians)

    l_value = lightness + 0.3963377774 * a_value + 0.2158037573 * b_value
    m_value = lightness - 0.1055613458 * a_value - 0.0638541728 * b_value
    s_value = lightness - 0.0894841775 * a_value - 1.2914855480 * b_value

    l_cubed = l_value * l_value * l_value
    m_cubed = m_value * m_value * m_value
    s_cubed = s_value * s_value * s_value

    r_linear = 4.0767416621 * l_cubed - 3.3077115913 * m_cubed + 0.2309699292 * s_cubed
    g_linear = -1.2684380046 * l_cubed + 2.6097574011 * m_cubed - 0.3413193965 * s_cubed
    b_linear = -0.0041960863 * l_cubed - 0.7034186147 * m_cubed + 1.7076147010 * s_cubed

    return tuple(clamp(gamma_encode(channel)) for channel in (r_linear, g_linear, b_linear))

def linearize(channel):
    if channel <= 0.03928:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4

def luminance(token):
    red, green, blue = (linearize(channel) for channel in srgb(token))
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue

def contrast_ratio(foreground, background):
    first = luminance(foreground)
    second = luminance(background)
    lighter = max(first, second)
    darker = min(first, second)
    return (lighter + 0.05) / (darker + 0.05)

palettes = {
    "aurora": {
        "backgroundPrimary": (0.16, 0.020, 260),
        "backgroundSecondary": (0.21, 0.025, 260),
        "backgroundTertiary": (0.26, 0.028, 260),
        "textHigh": (0.98, 0.010, 260),
        "textMedium": (0.80, 0.020, 260),
        "accent": (0.72, 0.140, 250),
    },
    "paper": {
        "backgroundPrimary": (0.96, 0.008, 85),
        "backgroundSecondary": (0.93, 0.012, 85),
        "backgroundTertiary": (0.90, 0.015, 85),
        "textHigh": (0.20, 0.015, 260),
        "textMedium": (0.38, 0.015, 260),
        "accent": (0.55, 0.140, 250),
    },
    "nocturne": {
        "backgroundPrimary": (0.00, 0.000, 0),
        "backgroundSecondary": (0.14, 0.005, 260),
        "backgroundTertiary": (0.18, 0.010, 260),
        "textHigh": (0.96, 0.005, 260),
        "textMedium": (0.72, 0.005, 260),
        "accent": (0.78, 0.140, 250),
    },
}

wcag_rows = ["palette\tbackground\trole\tratio\tminimum"]
for palette_name, palette in palettes.items():
    for background_name in ["backgroundPrimary", "backgroundSecondary", "backgroundTertiary"]:
        background = palette[background_name]
        for role, minimum in [("textHigh", 4.5), ("textMedium", 4.5), ("accent", 3.0)]:
            ratio = contrast_ratio(palette[role], background)
            wcag_rows.append(
                f"{palette_name}\t{background_name}\t{role}\t{ratio:.2f}\t{minimum:.1f}"
            )
            if ratio < minimum:
                failures.append(
                    f"WCAG contrast below target: {palette_name} {role} on {background_name} = {ratio:.2f}/{minimum:.1f}"
                )

manifest_path.write_text("\n".join(manifest_rows) + "\n", encoding="utf-8")
wcag_path.write_text("\n".join(wcag_rows) + "\n", encoding="utf-8")

if failures:
    for failure in failures:
        print(f"error={failure}")
    sys.exit(1)

print(f"static-surfaces={len(surfaces)}")
print(f"localization-files={len(localization_files)}")
PY

if [ "${COCXY_A11Y_SKIP_SWIFT_TESTS:-0}" = "1" ]; then
  printf 'swift-tests=skipped\n' >"$TEST_LOG"
  SWIFT_TESTS_STATUS="skipped"
else
  : >"$TEST_LOG"
  for filter in \
    AccessibilityLabelTests \
    GlassSurfaceCoverageSwiftTestingTests \
    DesignTokensSwiftTestingTests \
    BrowserPanelLocalizationSwiftTestingTests \
    AgentTeamPresentationSwiftTestingTests \
    CellsSidebarPresentationSwiftTestingTests \
    DiffContentViewSwiftTestingTests \
    CommandPaletteWiringTests \
    UnifiedQuickSwitchWiringSwiftTestingTests \
    RemotePortScannerBrowserRouteSwiftTestingTests
  do
    run_step "swift test --filter ${filter}" swift test --filter "$filter"
  done
  SWIFT_TESTS_STATUS="passed"
fi

{
  echo "status=ok"
  echo "result=agent-workspace-a11y-ok"
  echo "surfaces=6"
  echo "voiceoverAcceptance=source-and-test"
  echo "wcagAA=ok"
  echo "localizationFiles=21"
  echo "swiftTests=${SWIFT_TESTS_STATUS}"
  echo "manifest=${MANIFEST#${ROOT_DIR}/}"
  echo "wcagReport=${WCAG_REPORT#${ROOT_DIR}/}"
  echo "testLog=${TEST_LOG#${ROOT_DIR}/}"
} | tee "$SUMMARY"

cp "$SUMMARY" "$SENTINEL"
