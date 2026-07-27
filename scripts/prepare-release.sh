#!/bin/bash
# prepare-release.sh - Trigger the `Prepare Release` workflow remotely.
#
# Usage:
#   ./scripts/prepare-release.sh [--dry-run] <version>
#
# Example:
#   ./scripts/prepare-release.sh 0.1.80
#
# The script validates the version format locally to fail fast, then
# sends a repository dispatch via `gh` so the bump + tag happen on a
# clean GitHub runner instead of the dev's machine. The workflow
# itself is idempotent and re-runnable — if it fails mid-way the dev
# can re-trigger without leaving the repo in a broken state.
#
# After the workflow finishes the release pipeline (build / sign /
# notarize / DMG / GitHub Release / website / Homebrew) is dispatched
# from the trusted default-branch workflow after the tag push lands.
#
# Requirements: `gh` CLI authenticated against the repo with at least
# `repo:write` permission (same token already used for pushes).
#
# Copyright (c) 2026 Said Arturo Lopez. MIT License.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DRY_RUN=0
VERSION=""
GH_BIN=""

usage() {
    echo "usage: $0 [--dry-run] <version>" >&2
    echo "example: $0 0.1.80" >&2
}

version_greater_than() {
    local candidate="$1"
    local current="$2"
    local candidate_major candidate_minor candidate_patch
    local current_major current_minor current_patch

    IFS=. read -r candidate_major candidate_minor candidate_patch <<< "$candidate"
    IFS=. read -r current_major current_minor current_patch <<< "$current"

    if [ "$((10#$candidate_major))" -ne "$((10#$current_major))" ]; then
        [ "$((10#$candidate_major))" -gt "$((10#$current_major))" ]
        return
    fi
    if [ "$((10#$candidate_minor))" -ne "$((10#$current_minor))" ]; then
        [ "$((10#$candidate_minor))" -gt "$((10#$current_minor))" ]
        return
    fi
    [ "$((10#$candidate_patch))" -gt "$((10#$current_patch))" ]
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "error: unknown option '$1'" >&2
            usage
            exit 64
            ;;
        *)
            if [ -n "$VERSION" ]; then
                echo "error: unexpected extra argument '$1'" >&2
                usage
                exit 64
            fi
            VERSION="$1"
            shift
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    usage
    exit 64
fi

cd "$ROOT_DIR"

# Strip an accidental leading 'v' so the workflow input is clean.
VERSION="${VERSION#v}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: invalid version '$VERSION' (expected semver X.Y.Z, no leading v)" >&2
    exit 65
fi

CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)"
if ! [[ "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: invalid current Info.plist version '$CURRENT_VERSION'" >&2
    exit 73
fi
if [ "$VERSION" != "$CURRENT_VERSION" ] \
    && ! version_greater_than "$VERSION" "$CURRENT_VERSION"; then
    echo "error: target version '$VERSION' must not be older than current Info.plist version '$CURRENT_VERSION'" >&2
    exit 71
fi

# Refuse locally if the tag already exists — avoids a trip to the
# runner just to hit the same guard there.
if git show-ref --tags --verify --quiet "refs/tags/v${VERSION}" 2>/dev/null; then
    echo "error: tag v${VERSION} already exists locally" >&2
    exit 66
fi

REMOTE_TAGS="$(git ls-remote --tags origin "refs/tags/v${VERSION}" 2>&1)"
REMOTE_STATUS=$?
if [ "$REMOTE_STATUS" -ne 0 ]; then
    echo "error: unable to check remote tags on origin" >&2
    echo "$REMOTE_TAGS" >&2
    exit 67
fi
if [ -n "$REMOTE_TAGS" ]; then
    echo "error: tag v${VERSION} already exists on origin" >&2
    exit 68
fi

for candidate in /opt/homebrew/bin/gh /usr/local/bin/gh; do
    if [ -x "$candidate" ]; then
        GH_BIN="$candidate"
        break
    fi
done

if [ -z "$GH_BIN" ] && command -v gh >/dev/null 2>&1; then
    GH_BIN="$(command -v gh)"
fi

if [ -z "$GH_BIN" ]; then
    echo "error: gh CLI not found; install it from https://cli.github.com/" >&2
    exit 69
fi

if ! "$GH_BIN" auth status >/dev/null 2>&1; then
    echo "error: gh CLI is not authenticated for GitHub release dispatch" >&2
    exit 70
fi

if [ ! -f ".github/workflows/prepare-release.yml" ]; then
    echo "error: missing .github/workflows/prepare-release.yml" >&2
    exit 72
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "Dry run passed: Prepare Release workflow would be dispatched for v${VERSION}."
    echo "No GitHub workflow was triggered."
    exit 0
fi

echo "Dispatching Prepare Release workflow for v${VERSION}..."
REPOSITORY="$("$GH_BIN" repo view --json nameWithOwner --jq '.nameWithOwner')"
if [ -z "$REPOSITORY" ]; then
    echo "error: unable to resolve the GitHub repository for release dispatch" >&2
    exit 74
fi
"$GH_BIN" api --method POST "repos/${REPOSITORY}/dispatches" \
    -f event_type=prepare-stable-release \
    -f "client_payload[version]=${VERSION}"

echo
echo "Triggered. Watch the run with:"
echo "  gh run watch \$(gh run list --workflow=prepare-release.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
echo
echo "When it finishes it will dispatch the trusted Release workflow."
