#!/bin/bash
# run-security-audit.sh - Local internal security gate for Cocxy Terminal.
#
# Usage:
#   ./scripts/run-security-audit.sh
#   ./scripts/run-security-audit.sh --app build/CocxyTerminal.app
#   ./scripts/run-security-audit.sh --skip-tests
#
# The audit is local-only. It performs no network calls by itself.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE=""
RUN_TESTS=1

while [ "$#" -gt 0 ]; do
    case "$1" in
        --app)
            APP_BUNDLE="${2:?missing app bundle path}"
            shift 2
            ;;
        --skip-tests)
            RUN_TESTS=0
            shift
            ;;
        -h|--help)
            sed -n '1,14p' "$0"
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            exit 2
            ;;
    esac
done

cd "$ROOT_DIR"

echo "==> Cocxy internal security audit"
echo ""

echo "[Static privacy boundary]"
if [ -n "$APP_BUNDLE" ]; then
    ./scripts/run-privacy-audit.sh --app "$APP_BUNDLE"
else
    ./scripts/run-privacy-audit.sh
fi

if [ -n "$APP_BUNDLE" ]; then
    echo ""
    echo "[Bundle integrity and entitlements]"
    ./scripts/verify-app-bundle.sh "$APP_BUNDLE"
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
fi

if [ "$RUN_TESTS" -eq 1 ]; then
    echo ""
    echo "[Focused security regression tests]"
    security_filters=(
        'Phase7SocketSecurityTests|Phase7CLIIntegrationTests'
        'QuickLookOfflineSecuritySwiftTestingTests'
        'SocketServerRegressionSwiftTestingTests'
        'LSPProcessPrivacySwiftTestingTests'
        'AgentToolPermissionSwiftTestingTests'
        'AgentSecretsSwiftTestingTests'
        'ICloudSyncSecretsSwiftTestingTests'
        'RelayTokenTests|ReplayTrackerTests'
        'PluginMarketplaceSwiftTestingTests'
        'PluginEventWiringSwiftTestingTests'
        'NotebookExecutionSwiftTestingTests'
        'ProjectTemplateSwiftTestingTests'
        'PRReviewSuggestionSwiftTestingTests'
        'GitHubPaneViewModelSwiftTestingTests/reviewThreadSuggestionsRejectSymlinkEscapes'
    )
    first_filter=1
    for filter in "${security_filters[@]}"; do
        if [ "$first_filter" -eq 1 ]; then
            swift test --filter "$filter"
            first_filter=0
        else
            swift test --skip-build --filter "$filter"
        fi
    done
fi

echo ""
echo "[Diff hygiene]"
git diff --check

echo ""
echo "Security audit passed"
