#!/bin/bash
# prepare-release.sh - Trigger the `Prepare Release` workflow remotely.
#
# Usage:
#   ./scripts/prepare-release.sh <version>
#
# Example:
#   ./scripts/prepare-release.sh 0.1.80
#
# The script validates the version format locally to fail fast, then
# dispatches the workflow via `gh` so the bump + tag happen on a
# clean GitHub runner instead of the dev's machine. The workflow
# itself is idempotent and re-runnable — if it fails mid-way the dev
# can re-trigger without leaving the repo in a broken state.
#
# After the workflow finishes the release pipeline (build / sign /
# notarize / DMG / GitHub Release / website / Homebrew) fires
# automatically when the tag push lands.
#
# Requirements: `gh` CLI authenticated against the repo with at least
# `repo:write` permission (same token already used for pushes).
#
# Copyright (c) 2026 Said Arturo Lopez. MIT License.

set -euo pipefail

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    echo "usage: $0 <version>" >&2
    echo "example: $0 0.1.80" >&2
    exit 64
fi

# Strip an accidental leading 'v' so the workflow input is clean.
VERSION="${VERSION#v}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: invalid version '$VERSION' (expected semver X.Y.Z, no leading v)" >&2
    exit 65
fi

# Refuse locally if the tag already exists — avoids a trip to the
# runner just to hit the same guard there.
if git show-ref --tags --verify --quiet "refs/tags/v${VERSION}" 2>/dev/null; then
    echo "error: tag v${VERSION} already exists locally" >&2
    exit 66
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "error: gh CLI not found; install it from https://cli.github.com/" >&2
    exit 69
fi

echo "Dispatching Prepare Release workflow for v${VERSION}..."
gh workflow run prepare-release.yml \
    --ref main \
    -f version="$VERSION"

echo
echo "Triggered. Watch the run with:"
echo "  gh run watch \$(gh run list --workflow=prepare-release.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
echo
echo "When it finishes the Release workflow will fire on the tag push."
