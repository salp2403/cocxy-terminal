#!/bin/bash
# check-release-readiness.sh - Local preflight for release blockers.
#
# Usage:
#   ./scripts/check-release-readiness.sh [--enforce] [--version X.Y.Z]
#   ./scripts/check-release-readiness.sh --app build/CocxyTerminal.app
#   ./scripts/check-release-readiness.sh --require-public-release --version X.Y.Z
#   ./scripts/check-release-readiness.sh --require-critical-coverage --critical-coverage coverage.json
#
# Report mode exits 0 so it can be used while preparing a release. Enforce mode
# exits non-zero if a hard blocker remains.
#
# Copyright (c) 2026 Said Arturo Lopez. MIT License.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENFORCE=0
VERSION=""
APP_BUNDLE="build/CocxyTerminal.app"
DMG_PATH=""
APPCAST_PATH="build/appcast.xml"
REQUIRE_PUBLIC_RELEASE=0
REQUIRE_CRITICAL_COVERAGE=0
CRITICAL_COVERAGE_PATHS=()
REPO_FULL_NAME="salp2403/cocxy-terminal"

usage() {
    sed -n '1,8p' "$0"
}

resolve_path() {
    local path="$1"
    case "$path" in
        /*) echo "$path" ;;
        *) echo "$ROOT_DIR/$path" ;;
    esac
}

detect_version() {
    local plist="$ROOT_DIR/Resources/Info.plist"
    if [ -f "$plist" ] && [ -x /usr/libexec/PlistBuddy ]; then
        /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist" 2>/dev/null || true
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --enforce)
            ENFORCE=1
            shift
            ;;
        --version)
            VERSION="${2:?missing version}"
            shift 2
            ;;
        --app)
            APP_BUNDLE="${2:?missing app bundle path}"
            shift 2
            ;;
        --dmg)
            DMG_PATH="${2:?missing dmg path}"
            shift 2
            ;;
        --appcast)
            APPCAST_PATH="${2:?missing appcast path}"
            shift 2
            ;;
        --require-public-release)
            REQUIRE_PUBLIC_RELEASE=1
            shift
            ;;
        --require-critical-coverage)
            REQUIRE_CRITICAL_COVERAGE=1
            shift
            ;;
        --critical-coverage)
            CRITICAL_COVERAGE_PATHS+=("${2:?missing critical coverage path}")
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
done

cd "$ROOT_DIR"

if [ -z "$VERSION" ]; then
    VERSION="$(detect_version)"
fi

if [ -z "$VERSION" ]; then
    VERSION="unknown"
fi

if [ -z "$DMG_PATH" ]; then
    DMG_PATH="build/CocxyTerminal-${VERSION}.dmg"
fi

APP_BUNDLE="$(resolve_path "$APP_BUNDLE")"
DMG_PATH="$(resolve_path "$DMG_PATH")"
APPCAST_PATH="$(resolve_path "$APPCAST_PATH")"

BLOCKERS=0
WARNINGS=0

ok() {
    echo "OK   $*"
}

warn() {
    echo "WARN $*"
    WARNINGS=$((WARNINGS + 1))
}

block() {
    echo "FAIL $*"
    BLOCKERS=$((BLOCKERS + 1))
}

check_tool() {
    local name="$1"
    if command -v "$name" >/dev/null 2>&1; then
        ok "$name available"
    else
        block "$name missing"
    fi
}

check_secret() {
    local name="$1"
    if [ -n "${!name:-}" ]; then
        ok "$name=set"
    else
        block "$name=missing"
    fi
}

check_optional_secret() {
    local name="$1"
    if [ -n "${!name:-}" ]; then
        ok "$name=set"
    else
        warn "$name=missing"
    fi
}

check_public_release_surfaces() {
    local appcast_payload appcast_version brew_payload brew_version
    local homepage_payload homepage_version latest_release_tag releases_payload releases_version
    local spanish_homepage_payload spanish_homepage_version spanish_releases_payload spanish_releases_version

    echo ""
    echo "[Public release surfaces]"
    check_tool curl
    check_tool brew

    if gh release view "v${VERSION}" --repo "$REPO_FULL_NAME" >/dev/null 2>&1; then
        ok "GitHub Release v${VERSION} exists"
    else
        latest_release_tag="$(gh release view --repo "$REPO_FULL_NAME" --json tagName --jq .tagName 2>/dev/null || true)"
        block "GitHub Release v${VERSION} missing (latest ${latest_release_tag:-unknown})"
    fi

    appcast_payload="$(curl -fsSL --max-time 10 https://cocxy.dev/appcast.xml 2>/dev/null || true)"
    appcast_version="$(printf "%s" "$appcast_payload" | sed -n 's/.*sparkle:shortVersionString="\([^"]*\)".*/\1/p' | head -1)"
    if echo "$appcast_payload" | grep -q "sparkle:shortVersionString=\"${VERSION}\""; then
        ok "public Sparkle appcast points at ${VERSION}"
    else
        block "public Sparkle appcast does not point at ${VERSION} (current ${appcast_version:-unknown})"
    fi

    brew_payload="$(brew info --cask salp2403/tap/cocxy 2>/dev/null || true)"
    brew_version="$(printf "%s" "$brew_payload" | sed -n 's/^==> cocxy.*): \([^[:space:]]*\)$/\1/p' | head -1)"
    if echo "$brew_payload" | grep -q "): ${VERSION}$"; then
        ok "Homebrew cask reports ${VERSION}"
    else
        block "Homebrew cask does not report ${VERSION} (current ${brew_version:-unknown})"
    fi

    homepage_payload="$(curl -fsSL --max-time 10 https://cocxy.dev/ 2>/dev/null || true)"
    homepage_version="$(printf "%s" "$homepage_payload" | sed -n 's/.*"softwareVersion": "\([^"]*\)".*/\1/p' | head -1)"
    if echo "$homepage_payload" | grep -q "CocxyTerminal-${VERSION}.dmg"; then
        ok "public homepage download points at ${VERSION}"
    else
        block "public homepage download does not point at ${VERSION} (current ${homepage_version:-unknown})"
    fi

    releases_payload="$(curl -fsSL --max-time 10 https://cocxy.dev/releases.html 2>/dev/null || true)"
    releases_version="$(printf "%s" "$releases_payload" | sed -n 's/.*>v\([0-9][^<]*\)<.*/\1/p' | head -1)"
    if echo "$releases_payload" | grep -q "CocxyTerminal-${VERSION}.dmg"; then
        ok "public releases page includes ${VERSION}"
    else
        block "public releases page does not include ${VERSION} (latest listed ${releases_version:-unknown})"
    fi

    spanish_homepage_payload="$(curl -fsSL --max-time 10 https://cocxy.dev/es/ 2>/dev/null || true)"
    spanish_homepage_version="$(printf "%s" "$spanish_homepage_payload" | sed -n 's/.*"softwareVersion": "\([^"]*\)".*/\1/p' | head -1)"
    if echo "$spanish_homepage_payload" | grep -q "CocxyTerminal-${VERSION}.dmg"; then
        ok "public Spanish homepage download points at ${VERSION}"
    else
        block "public Spanish homepage download does not point at ${VERSION} (current ${spanish_homepage_version:-unknown})"
    fi

    spanish_releases_payload="$(curl -fsSL --max-time 10 https://cocxy.dev/es/releases.html 2>/dev/null || true)"
    spanish_releases_version="$(printf "%s" "$spanish_releases_payload" | sed -n 's/.*>v\([0-9][^<]*\)<.*/\1/p' | head -1)"
    if echo "$spanish_releases_payload" | grep -q "CocxyTerminal-${VERSION}.dmg"; then
        ok "public Spanish releases page includes ${VERSION}"
    else
        block "public Spanish releases page does not include ${VERSION} (latest listed ${spanish_releases_version:-unknown})"
    fi
}

check_critical_coverage() {
    local coverage_args=()
    local coverage_output
    local missing=0
    local path

    echo ""
    echo "[Critical coverage]"

    if ! command -v python3 >/dev/null 2>&1; then
        block "python3 missing for critical coverage gate"
        return
    fi

    if [ ! -x "$ROOT_DIR/scripts/check-critical-coverage.py" ]; then
        block "critical coverage checker is not executable"
        return
    fi

    if [ "${#CRITICAL_COVERAGE_PATHS[@]}" -eq 0 ]; then
        block "critical coverage artifacts missing; pass --critical-coverage <llvm-cov-json>"
        return
    fi

    for path in "${CRITICAL_COVERAGE_PATHS[@]}"; do
        path="$(resolve_path "$path")"
        if [ -f "$path" ]; then
            coverage_args+=("--coverage" "$path")
        else
            block "critical coverage artifact missing at $path"
            missing=1
        fi
    done

    if [ "$missing" -ne 0 ]; then
        return
    fi

    if coverage_output="$(python3 "$ROOT_DIR/scripts/check-critical-coverage.py" "${coverage_args[@]}" --enforce 2>&1)"; then
        printf "%s\n" "$coverage_output"
        ok "critical coverage gate passed"
    else
        printf "%s\n" "$coverage_output"
        block "critical coverage gate failed"
    fi
}

echo "==> Cocxy release readiness report"
echo "Version: $VERSION"
echo ""

echo "[Local tooling]"
check_tool gh
check_tool xcrun
check_tool hdiutil
check_tool codesign

echo ""
echo "[Git hygiene]"
git_user_name="$(git config user.name || true)"
git_user_email="$(git config user.email || true)"

if [ "$git_user_name" = "Said Arturo Lopez" ]; then
    ok "git user.name matches release identity"
else
    block "git user.name must be Said Arturo Lopez"
fi

if [ "$git_user_email" = "dev@cocxy.dev" ]; then
    ok "git user.email matches release identity"
else
    block "git user.email must be dev@cocxy.dev"
fi

if [ -z "$(git status --porcelain --untracked-files=no)" ]; then
    ok "tracked public worktree is clean"
else
    block "tracked public worktree has uncommitted changes"
fi

private_trace_one='clau''de code'
private_trace_two='anth''ropic'
private_trace_three='wa''rp'
private_trace_four='co-''authored'
private_trace_five='generated'' with'
private_path_one='do''cs/(project|adr|audit|user)'
private_path_two='/Users/''Galf'
private_path_three='KNOW''LEDGE\.md'
private_path_four='CL''AUDE\.md'
private_path_five='\.clau''de'
private_path_six='alfred-''memory'
private_trace_pattern="${private_trace_four}|noreply@|${private_trace_five}|${private_trace_one}|${private_trace_two}|${private_trace_three}|${private_path_one}|${private_path_two}|${private_path_three}|${private_path_four}|${private_path_five}|${private_path_six}"

if git rev-parse --verify origin/main >/dev/null 2>&1; then
    commit_trace_matches="$(git log origin/main..HEAD --format="%B" | grep -iE "$private_trace_pattern" || true)"
    if [ -z "$commit_trace_matches" ]; then
        ok "pending commit messages are clean"
    else
        block "pending commit messages contain private process traces"
    fi
else
    warn "origin/main is unavailable; skipped pending commit message scan"
fi

echo ""
echo "[Release secrets]"
check_secret SIGNING_IDENTITY
check_secret APPLE_ID
check_secret APPLE_TEAM_ID
check_secret APPLE_APP_PASSWORD
check_secret SPARKLE_PRIVATE_KEY
check_secret HOMEBREW_TAP_TOKEN
check_secret LIGHTSAIL_SSH_KEY
check_secret DEPLOY_USER
check_secret DEPLOY_HOST
check_secret DEPLOY_PATH

echo ""
echo "[Optional external real-run inputs]"
check_optional_secret POSTGRES_URL
check_optional_secret AWS_ACCESS_KEY_ID
check_optional_secret AWS_SECRET_ACCESS_KEY
check_optional_secret AWS_REGION

echo ""
echo "[Release artifacts]"
if [ -d "$APP_BUNDLE" ]; then
    ok "app bundle exists at $APP_BUNDLE"
    if [ -x "$APP_BUNDLE/Contents/MacOS/CocxyTerminal" ]; then
        ok "app executable is present"
    else
        block "app executable missing from bundle"
    fi
    if [ -x "$APP_BUNDLE/Contents/Resources/cocxy" ]; then
        ok "bundle-local CLI is present"
    else
        block "bundle-local CLI missing"
    fi
else
    block "app bundle missing at $APP_BUNDLE"
fi

if [ -f "$DMG_PATH" ]; then
    ok "DMG exists at $DMG_PATH"
else
    block "DMG missing at $DMG_PATH"
fi

if [ -f "$APPCAST_PATH" ]; then
    ok "appcast exists at $APPCAST_PATH"
else
    block "appcast missing at $APPCAST_PATH"
fi

if [ "$REQUIRE_CRITICAL_COVERAGE" -eq 1 ] || [ "${#CRITICAL_COVERAGE_PATHS[@]}" -gt 0 ]; then
    check_critical_coverage
fi

if [ "$REQUIRE_PUBLIC_RELEASE" -eq 1 ]; then
    check_public_release_surfaces
fi

echo ""
if [ "$BLOCKERS" -eq 0 ]; then
    echo "Release readiness passed with $WARNINGS warning(s)."
    exit 0
fi

echo "Release readiness has $BLOCKERS blocker(s) and $WARNINGS warning(s)."
if [ "$ENFORCE" -eq 1 ]; then
    exit 1
fi
exit 0
