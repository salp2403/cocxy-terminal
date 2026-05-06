#!/bin/bash
# run-privacy-audit.sh - Static and optional runtime privacy gate.
#
# Usage:
#   ./scripts/run-privacy-audit.sh
#   ./scripts/run-privacy-audit.sh --app build/CocxyTerminal.app
#   ./scripts/run-privacy-audit.sh --pid 12345 --runtime-seconds 60
#
# The default run is static-only and performs no network calls.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE=""
RUNTIME_PID=""
RUNTIME_SECONDS=0
ERRORS=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --app)
            APP_BUNDLE="${2:?missing app bundle path}"
            shift 2
            ;;
        --pid)
            RUNTIME_PID="${2:?missing pid}"
            shift 2
            ;;
        --runtime-seconds)
            RUNTIME_SECONDS="${2:?missing duration}"
            shift 2
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

fail() {
    echo "  FAIL  $1"
    ERRORS=$((ERRORS + 1))
}

ok() {
    echo "  OK  $1"
}

warn() {
    echo "  WARN  $1"
}

plist_path() {
    if [ -n "$APP_BUNDLE" ]; then
        echo "$APP_BUNDLE/Contents/Info.plist"
    else
        echo "$ROOT_DIR/Resources/Info.plist"
    fi
}

plist_raw() {
    local plist="$1"
    local key="$2"
    plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true
}

grep_repo() {
    local pattern="$1"
    shift
    (cd "$ROOT_DIR" && grep -RInE \
        --exclude="run-privacy-audit.sh" \
        --exclude-dir=".build" \
        --exclude-dir=".git" \
        --exclude-dir="build" \
        "$pattern" "$@") || true
}

echo "==> Cocxy privacy audit"
echo ""

INFO_PLIST="$(plist_path)"
echo "[Bundle endpoint contract]"
if [ ! -f "$INFO_PLIST" ]; then
    fail "Info.plist exists ($INFO_PLIST)"
else
    ok "Info.plist exists"
    bundle_id="$(plist_raw "$INFO_PLIST" CFBundleIdentifier)"
    feed_url="$(plist_raw "$INFO_PLIST" SUFeedURL)"
    public_key="$(plist_raw "$INFO_PLIST" SUPublicEDKey)"
    auto_update="$(plist_raw "$INFO_PLIST" SUAutomaticallyUpdate)"
    auto_checks="$(plist_raw "$INFO_PLIST" SUEnableAutomaticChecks)"

    case "$bundle_id" in
        dev.cocxy.terminal.nightly)
            expected_feed_url="https://cocxy.dev/appcast-nightly.xml"
            ;;
        *)
            expected_feed_url="https://cocxy.dev/appcast.xml"
            ;;
    esac

    if [ "$feed_url" = "$expected_feed_url" ]; then
        ok "Sparkle appcast is the expected Cocxy-owned endpoint"
    else
        fail "Sparkle appcast endpoint mismatch (expected $expected_feed_url, got ${feed_url:-<missing>})"
    fi

    if [ -n "$public_key" ]; then
        ok "Sparkle public key is present"
    else
        fail "Sparkle public key is present"
    fi

    if [ "$auto_update" = "0" ] || [ "$auto_update" = "false" ]; then
        ok "Sparkle automatic downloads remain disabled"
    else
        fail "Sparkle automatic downloads disabled (got ${auto_update:-<missing>})"
    fi

    if [ "$auto_checks" = "1" ] || [ "$auto_checks" = "true" ]; then
        ok "Sparkle automatic checks are constrained to the signed appcast"
    else
        warn "Sparkle automatic checks disabled or missing (got ${auto_checks:-<missing>})"
    fi
fi

echo ""
echo "[No telemetry SDKs or auto crash upload]"
telemetry_hits="$(grep_repo 'PostHog|Sentry|Crashlytics|Mixpanel|Amplitude|FirebaseAnalytics|TelemetryDeck|Bugsnag|Datadog|NewRelic' \
    Package.swift Sources Resources .github scripts)"
if [ -z "$telemetry_hits" ]; then
    ok "No known telemetry or crash-upload SDK identifiers found"
else
    echo "$telemetry_hits"
    fail "Known telemetry or crash-upload SDK identifiers absent"
fi

upload_hits="$(grep_repo 'crash[ _-]*(upload|submission)|upload[ _-]*crash|automatic[ _-]*crash[ _-]*report' \
    Sources Resources .github scripts)"
if [ -z "$upload_hits" ]; then
    ok "No automatic crash-upload wording or implementation found"
else
    echo "$upload_hits"
    fail "Automatic crash-upload implementation absent"
fi

phone_home_hits="$(grep_repo 'does not phone home|phone home|ping[- ]home|zero data to any external server|no network entitlement|network entitlement beyond|no contacta servidores autom[aá]ticamente' \
    README.md Sources Resources Tests .github scripts web/public)"
if [ -z "$phone_home_hits" ]; then
    ok "No overbroad phone-home copy remains"
else
    echo "$phone_home_hits"
    fail "Overbroad phone-home copy absent"
fi

echo ""
echo "[Provider endpoint boundaries]"
provider_hits="$(grep_repo 'api\.openai\.com|api\.anthro[p]ic\.com|generativelanguage\.googleapis\.com' Sources Resources \
    | grep -v '^Sources/Domain/Agent/AgentProviderClient.swift:' || true)"
if [ -z "$provider_hits" ]; then
    ok "Cloud provider endpoints are confined to the explicit Agent provider client"
else
    echo "$provider_hits"
    fail "Cloud provider endpoints confined to explicit Agent provider client"
fi

if grep -q 'enabled: false' "$ROOT_DIR/Sources/Domain/Protocols/ConfigProviding.swift" \
    && grep -q 'preferredProvider: \.foundationModelsOnDevice' "$ROOT_DIR/Sources/Domain/Protocols/ConfigProviding.swift" \
    && grep -q 'foundationModelsFallback: \.requireExplicitChoice' "$ROOT_DIR/Sources/Domain/Protocols/ConfigProviding.swift"; then
    ok "Agent defaults remain disabled, on-device first, and explicit-choice fallback"
else
    fail "Agent defaults remain disabled, on-device first, and explicit-choice fallback"
fi

echo ""
echo "[Optional runtime idle sample]"
if [ -n "$RUNTIME_PID" ] && [ "$RUNTIME_SECONDS" -gt 0 ]; then
    samples=$(( (RUNTIME_SECONDS + 9) / 10 ))
    runtime_hits=""
    i=1
    while [ "$i" -le "$samples" ]; do
        timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        established="$(lsof -nP -iTCP -sTCP:ESTABLISHED 2>/dev/null | awk -v pid="$RUNTIME_PID" '$2 == pid { print }')"
        listening="$(lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk -v pid="$RUNTIME_PID" '$2 == pid { print }')"
        udp="$(lsof -nP -iUDP 2>/dev/null | awk -v pid="$RUNTIME_PID" '$2 == pid { print }')"
        if [ -n "$established$listening$udp" ]; then
            runtime_hits="${runtime_hits}sample=$i time=$timestamp
established:
$established
listen:
$listening
udp:
$udp
"
        fi
        i=$((i + 1))
        [ "$i" -le "$samples" ] && sleep 10
    done

    if [ -z "$runtime_hits" ]; then
        ok "No TCP established/listen or UDP sockets observed for PID $RUNTIME_PID"
    else
        echo "$runtime_hits"
        fail "No idle network sockets observed for PID $RUNTIME_PID"
    fi
else
    warn "Runtime lsof sample skipped; pass --pid <pid> --runtime-seconds <seconds> for local idle audit"
fi

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "Privacy audit passed"
else
    echo "Privacy audit failed with $ERRORS issue(s)"
fi
exit "$ERRORS"
