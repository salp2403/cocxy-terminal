#!/bin/bash
# verify-app-bundle.sh - Verify a Cocxy Terminal .app bundle is complete.
#
# Usage:
#   ./scripts/verify-app-bundle.sh path/to/CocxyTerminal.app
#   ./scripts/verify-app-bundle.sh  # defaults to build/CocxyTerminal.app
#
# Returns 0 if all required contents are present, 1 otherwise.
# Designed for use in CI and local builds.
#
# Copyright (c) 2026 Said Arturo Lopez. MIT License.

set -euo pipefail

APP_BUNDLE="${1:-build/CocxyTerminal.app}"
CONTENTS="${APP_BUNDLE}/Contents"
RESOURCES="${CONTENTS}/Resources"

ERRORS=0

check_exists() {
    local path="$1"
    local label="$2"
    if [ -e "$path" ]; then
        echo "  OK  $label"
    else
        echo "  FAIL  $label  (missing: $path)"
        ERRORS=$((ERRORS + 1))
    fi
}

check_dir_not_empty() {
    local dir="$1"
    local label="$2"
    local pattern="${3:-*}"
    if [ -d "$dir" ] && [ "$(ls "$dir"/$pattern 2>/dev/null | wc -l)" -gt 0 ]; then
        local count
        count=$(ls "$dir"/$pattern 2>/dev/null | wc -l | tr -d ' ')
        echo "  OK  $label  ($count entries)"
    else
        echo "  FAIL  $label  (empty or missing: $dir)"
        ERRORS=$((ERRORS + 1))
    fi
}

check_plist_string() {
    local plist="$1"
    local keypath="$2"
    local expected="$3"
    local label="$4"
    local value
    value="$(plutil -extract "$keypath" raw -o - "$plist" 2>/dev/null || true)"
    if [ "$value" = "$expected" ]; then
        echo "  OK  $label"
    else
        echo "  FAIL  $label  (expected: $expected, got: ${value:-<missing>})"
        ERRORS=$((ERRORS + 1))
    fi
}

check_plist_exists() {
    local plist="$1"
    local keypath="$2"
    local label="$3"
    if plutil -extract "$keypath" raw -o - "$plist" >/dev/null 2>&1; then
        echo "  OK  $label"
    else
        echo "  FAIL  $label  (missing key: $keypath)"
        ERRORS=$((ERRORS + 1))
    fi
}

check_codesign_entitlement_true() {
    local bundle_path="$1"
    local keypath="$2"
    local label="$3"
    if codesign -d --entitlements :- "$bundle_path" 2>/dev/null | grep -q "<key>${keypath}</key><true/>"; then
        echo "  OK  $label"
    else
        echo "  FAIL  $label  (expected entitlement true, got: <missing>)"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "==> Verifying app bundle: $APP_BUNDLE"
echo ""

# 1. Top-level structure
echo "[Structure]"
check_exists "$CONTENTS/Info.plist" "Info.plist"
check_exists "$CONTENTS/MacOS" "MacOS directory"
check_dir_not_empty "$CONTENTS/MacOS" "Executable binary"

# 2. Frameworks
echo ""
echo "[Frameworks]"
check_exists "$CONTENTS/Frameworks/Sparkle.framework" "Sparkle.framework"

# 3. Fonts (critical — crash in v0.1.53 was caused by missing fonts
#    triggering a Bundle.module fatalError)
echo ""
echo "[Fonts]"
check_exists "$RESOURCES/Fonts" "Fonts directory"
check_dir_not_empty "$RESOURCES/Fonts" "Font files (.ttf)" "*.ttf"
check_dir_not_empty "$RESOURCES/Fonts" "Font files (.otf)" "*.otf"

# 4. Shell integration (required for command tracking and CWD detection)
echo ""
echo "[Shell Integration]"
check_exists "$RESOURCES/shell-integration" "shell-integration directory"
check_exists "$RESOURCES/shell-integration/zsh" "zsh integration"
check_exists "$RESOURCES/shell-integration/bash" "bash integration"
check_exists "$RESOURCES/shell-integration/fish" "fish integration"

# 5. Default configuration
echo ""
echo "[Defaults]"
check_exists "$RESOURCES/defaults" "defaults directory"

# 6. CLI companion
echo ""
echo "[CLI]"
check_exists "$RESOURCES/cocxy" "CLI companion binary"

# 7. App icon
echo ""
echo "[Assets]"
check_exists "$RESOURCES/AppIcon.png" "App icon"

# 8. Markdown preview resources (Mermaid, KaTeX)
echo ""
echo "[Markdown Preview]"
check_exists "$RESOURCES/Markdown" "Markdown resources directory"
check_exists "$RESOURCES/Markdown/mermaid.min.js" "Mermaid JS"
check_exists "$RESOURCES/Markdown/katex.min.js" "KaTeX JS"
check_exists "$RESOURCES/Markdown/katex.min.css" "KaTeX CSS"
check_exists "$RESOURCES/Markdown/katex-auto-render.min.js" "KaTeX auto-render"
check_exists "$RESOURCES/Markdown/highlight.min.js" "Highlight.js"
check_exists "$RESOURCES/Markdown/highlight-cocxy.css" "Highlight.js theme"

# 9. QuickLook extension
echo ""
echo "[QuickLook]"
check_exists "$CONTENTS/PlugIns/CocxyQuickLook.appex" "QuickLook extension"
check_exists "$CONTENTS/PlugIns/CocxyQuickLook.appex/Contents/Info.plist" "QuickLook Info.plist"
check_plist_string "$CONTENTS/PlugIns/CocxyQuickLook.appex/Contents/Info.plist" "NSExtension.NSExtensionPointIdentifier" "com.apple.quicklook.preview" "QuickLook extension point"
check_plist_exists "$CONTENTS/PlugIns/CocxyQuickLook.appex/Contents/Info.plist" "NSExtension.NSExtensionPrincipalClass" "QuickLook principal class"
check_plist_string "$CONTENTS/PlugIns/CocxyQuickLook.appex/Contents/Info.plist" "NSExtension.NSExtensionAttributes.QLSupportedContentTypes.0" "net.daringfireball.markdown" "QuickLook markdown content type"
check_codesign_entitlement_true "$CONTENTS/PlugIns/CocxyQuickLook.appex" "com.apple.security.app-sandbox" "QuickLook sandbox entitlement"
check_codesign_entitlement_true "$CONTENTS/PlugIns/CocxyQuickLook.appex" "com.apple.security.network.client" "QuickLook network entitlement"
check_exists "$CONTENTS/PlugIns/CocxyQuickLook.appex/Contents/Resources/Markdown" "QuickLook markdown resources"
check_exists "$CONTENTS/PlugIns/CocxyQuickLook.appex/Contents/Resources/Markdown/mermaid.min.js" "QuickLook Mermaid JS"
check_exists "$CONTENTS/PlugIns/CocxyQuickLook.appex/Contents/Resources/Markdown/highlight.min.js" "QuickLook Highlight.js"

# 10. Themes (optional but expected)
echo ""
echo "[Themes]"
if [ -d "$RESOURCES/Themes" ]; then
    check_dir_not_empty "$RESOURCES/Themes" "Theme files"
else
    echo "  WARN  Themes directory missing (non-critical)"
fi

# 11. Sounds (optional)
if [ -d "$RESOURCES/Sounds" ]; then
    echo ""
    echo "[Sounds]"
    check_dir_not_empty "$RESOURCES/Sounds" "Sound files"
fi

echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "==> FAILED: $ERRORS required items missing from app bundle."
    exit 1
else
    echo "==> PASSED: App bundle verification complete."
    exit 0
fi
