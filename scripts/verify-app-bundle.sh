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
LAUNCH_SERVICES="${CONTENTS}/Library/LaunchServices"
PTY_DAEMON_APP="${LAUNCH_SERVICES}/cocxyd.app"
PTY_DAEMON_PLIST="${PTY_DAEMON_APP}/Contents/Info.plist"
PTY_DAEMON_EXECUTABLE="${PTY_DAEMON_APP}/Contents/MacOS/cocxyd"

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

check_optional() {
    local path="$1"
    local label="$2"
    if [ -e "$path" ]; then
        echo "  OK  $label"
    else
        echo "  WARN  $label  (missing: $path)"
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

check_plist_bool_true() {
    local plist="$1"
    local keypath="$2"
    local label="$3"
    local value
    value="$(plutil -extract "$keypath" raw -o - "$plist" 2>/dev/null || true)"
    if [ "$value" = "1" ] || [ "$value" = "true" ]; then
        echo "  OK  $label"
    else
        echo "  FAIL  $label  (expected true, got: ${value:-<missing>})"
        ERRORS=$((ERRORS + 1))
    fi
}

check_codesign_valid() {
    local path="$1"
    local label="$2"
    if codesign --verify --strict "$path" >/dev/null 2>&1; then
        echo "  OK  $label"
    else
        echo "  FAIL  $label  (codesign verification failed)"
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

check_codesign_entitlement_absent() {
    local bundle_path="$1"
    local keypath="$2"
    local label="$3"
    if codesign -d --entitlements :- "$bundle_path" 2>/dev/null | grep -q "<key>${keypath}</key>"; then
        echo "  FAIL  $label  (unexpected entitlement present)"
        ERRORS=$((ERRORS + 1))
    else
        echo "  OK  $label"
    fi
}

echo "==> Verifying app bundle: $APP_BUNDLE"
echo ""

# 1. Top-level structure
echo "[Structure]"
check_exists "$CONTENTS/Info.plist" "Info.plist"
check_exists "$CONTENTS/MacOS" "MacOS directory"
check_dir_not_empty "$CONTENTS/MacOS" "Executable binary"

bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$CONTENTS/Info.plist" 2>/dev/null || true)"
case "$bundle_id" in
    dev.cocxy.terminal.preview)
        expected_feed_url="https://cocxy.dev/appcast-preview.xml"
        ;;
    dev.cocxy.terminal.nightly)
        expected_feed_url="https://cocxy.dev/appcast-nightly.xml"
        ;;
    *)
        expected_feed_url="https://cocxy.dev/appcast.xml"
        ;;
esac
check_plist_string "$CONTENTS/Info.plist" "SUFeedURL" "$expected_feed_url" "Sparkle feed URL"
check_plist_exists "$CONTENTS/Info.plist" "SUPublicEDKey" "Sparkle public key"
check_plist_exists "$CONTENTS/Info.plist" "OSAScriptingDefinition" "AppleScript definition key"
check_plist_exists "$CONTENTS/Info.plist" "NSCameraUsageDescription" "Camera privacy description"
check_plist_bool_true "$CONTENTS/Info.plist" "NSCameraUseContinuityCameraDeviceType" "Continuity Camera device type opt-in"
check_plist_exists "$CONTENTS/Info.plist" "NSMicrophoneUsageDescription" "Microphone privacy description"
check_plist_exists "$CONTENTS/Info.plist" "NSSpeechRecognitionUsageDescription" "Speech recognition privacy description"
check_plist_string "$CONTENTS/Info.plist" "NSUserActivityTypes.0" "dev.cocxy.terminal.continue" "Handoff activity type"
check_plist_string "$CONTENTS/Info.plist" "UTExportedTypeDeclarations.0.UTTypeIdentifier" "dev.cocxy.notebook" "Cocxy notebook exported UTI"
check_plist_string "$CONTENTS/Info.plist" "UTExportedTypeDeclarations.0.UTTypeTagSpecification.public\\.filename-extension.0" "cocxynb" "Cocxy notebook extension"
check_plist_string "$CONTENTS/Info.plist" "CFBundleDocumentTypes.0.LSItemContentTypes.0" "dev.cocxy.notebook" "Cocxy notebook document type"

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

# 4. Localization bundles
echo ""
echo "[Localization]"
check_exists "$RESOURCES/en.lproj/Localizable.strings" "English localization"
check_exists "$RESOURCES/es.lproj/Localizable.strings" "Spanish localization"

# 5. Shell integration (required for command tracking and CWD detection)
echo ""
echo "[Shell Integration]"
check_exists "$RESOURCES/shell-integration" "shell-integration directory"
check_exists "$RESOURCES/shell-integration/zsh" "zsh integration"
check_exists "$RESOURCES/shell-integration/bash" "bash integration"
check_exists "$RESOURCES/shell-integration/fish" "fish integration"

# 6. Default configuration
echo ""
echo "[Defaults]"
check_exists "$RESOURCES/defaults" "defaults directory"

# 7. CLI companion
echo ""
echo "[CLI]"
check_exists "$RESOURCES/cocxy" "CLI companion binary"
check_exists "$RESOURCES/cocxyd" "PTY daemon helper binary (compatibility path)"
check_codesign_valid "$RESOURCES/cocxyd" "PTY daemon helper binary signature"

# 6b. PTY daemon helper app. Sparkle installs the whole app bundle
# atomically, so the helper's version must match the host bundle and the
# runtime path must be a signed LSUIElement app that will not appear in Dock.
echo ""
echo "[PTY Daemon Helper App]"
check_exists "$PTY_DAEMON_APP" "PTY daemon helper app"
check_exists "$PTY_DAEMON_PLIST" "PTY daemon helper Info.plist"
check_exists "$PTY_DAEMON_EXECUTABLE" "PTY daemon helper app executable"
main_bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$CONTENTS/Info.plist" 2>/dev/null || true)"
main_short_version="$(plutil -extract CFBundleShortVersionString raw -o - "$CONTENTS/Info.plist" 2>/dev/null || true)"
main_build_version="$(plutil -extract CFBundleVersion raw -o - "$CONTENTS/Info.plist" 2>/dev/null || true)"
if [ -f "$PTY_DAEMON_PLIST" ]; then
    check_plist_string "$PTY_DAEMON_PLIST" "CFBundleIdentifier" "${main_bundle_id}.cocxyd" "PTY daemon helper bundle id"
    check_plist_string "$PTY_DAEMON_PLIST" "CFBundleExecutable" "cocxyd" "PTY daemon helper executable key"
    check_plist_string "$PTY_DAEMON_PLIST" "CFBundleShortVersionString" "$main_short_version" "PTY daemon helper short version matches app"
    check_plist_string "$PTY_DAEMON_PLIST" "CFBundleVersion" "$main_build_version" "PTY daemon helper build version matches app"
    check_plist_bool_true "$PTY_DAEMON_PLIST" "LSUIElement" "PTY daemon helper hides Dock icon"
fi
check_codesign_valid "$PTY_DAEMON_EXECUTABLE" "PTY daemon helper app executable signature"
check_codesign_valid "$PTY_DAEMON_APP" "PTY daemon helper app signature"

check_universal_binary() {
    local path="$1"
    local label="$2"
    local archs
    archs="$(lipo -archs "$path" 2>/dev/null || true)"
    if [[ " ${archs} " == *" arm64 "* ]] && [[ " ${archs} " == *" x86_64 "* ]]; then
        echo "  OK  $label"
    else
        echo "  FAIL  $label  (expected arm64+x86_64, got: ${archs:-<missing>})"
        ERRORS=$((ERRORS + 1))
    fi
}

echo ""
echo "[Bundled Tools]"
check_exists "$RESOURCES/rg" "Bundled ripgrep binary"
if [ -x "$RESOURCES/rg" ]; then
    if "$RESOURCES/rg" --version 2>/dev/null | head -1 | grep -q '^ripgrep '; then
        echo "  OK  Bundled ripgrep version"
    else
        echo "  FAIL  Bundled ripgrep version"
        ERRORS=$((ERRORS + 1))
    fi
    check_universal_binary "$RESOURCES/rg" "Bundled ripgrep universal binary"
    check_codesign_valid "$RESOURCES/rg" "Bundled ripgrep signature"
fi
check_exists "$RESOURCES/Ripgrep/LICENSE-MIT" "ripgrep MIT license"
check_exists "$RESOURCES/Ripgrep/UNLICENSE" "ripgrep Unlicense"

# 7. App icon
echo ""
echo "[Assets]"
check_exists "$RESOURCES/AppIcon.png" "App icon"
check_exists "$RESOURCES/CocxyTerminal.sdef" "AppleScript definition"
check_codesign_entitlement_true "$APP_BUNDLE" "com.apple.security.device.audio-input" "App audio input entitlement"

# 7b. Shortcuts/App Intents metadata. Optional: only present when the build
# toolchain ships AppIntents.json (Xcode with App Intents support). Builds
# made on older toolchains skip metadata generation; the binary still works.
echo ""
echo "[Shortcuts]"
check_optional "$RESOURCES/Metadata.appintents" "Shortcuts metadata bundle"
check_optional "$RESOURCES/Metadata.appintents/version.json" "Shortcuts metadata version"
check_optional "$RESOURCES/Metadata.appintents/extract.actionsdata" "Shortcuts actions metadata"

# 8. Markdown preview resources (Mermaid, KaTeX)
echo ""
echo "[Syntax Grammars]"
check_exists "$RESOURCES/TreeSitter" "Tree-sitter core resources directory"
check_exists "$RESOURCES/TreeSitter/libtree-sitter.dylib" "Tree-sitter core dylib"
check_codesign_valid "$RESOURCES/TreeSitter/libtree-sitter.dylib" "Tree-sitter core dylib signature"
check_exists "$RESOURCES/Grammars" "Syntax grammars resources directory"
check_exists "$RESOURCES/Grammars/manifest.json" "Syntax grammar manifest"
check_exists "$RESOURCES/Grammars/LICENSES" "Syntax grammar license records"
check_exists "$RESOURCES/Grammars/LICENSES/tree-sitter-core-LICENSE.txt" "Tree-sitter core license"
check_exists "$RESOURCES/Grammars/LICENSES/tree-sitter-core-unicode-LICENSE.txt" "Tree-sitter Unicode license"
check_exists "$RESOURCES/Grammars/LICENSES/tree-sitter-swift-LICENSE.txt" "Swift grammar license"
check_exists "$RESOURCES/Grammars/LICENSES/tree-sitter-rust-LICENSE.txt" "Rust grammar license"
check_exists "$RESOURCES/Grammars/LICENSES/tree-sitter-python-LICENSE.txt" "Python grammar license"
check_exists "$RESOURCES/Grammars/LICENSES/tree-sitter-typescript-LICENSE.txt" "TypeScript grammar license"
check_exists "$RESOURCES/Grammars/LICENSES/tree-sitter-go-LICENSE.txt" "Go grammar license"
check_exists "$RESOURCES/Grammars/swift/highlights.scm" "Swift highlight query"
check_exists "$RESOURCES/Grammars/swift/parser.dylib" "Swift parser dylib"
check_codesign_valid "$RESOURCES/Grammars/swift/parser.dylib" "Swift parser dylib signature"
check_exists "$RESOURCES/Grammars/rust/highlights.scm" "Rust highlight query"
check_exists "$RESOURCES/Grammars/rust/parser.dylib" "Rust parser dylib"
check_codesign_valid "$RESOURCES/Grammars/rust/parser.dylib" "Rust parser dylib signature"
check_exists "$RESOURCES/Grammars/python/highlights.scm" "Python highlight query"
check_exists "$RESOURCES/Grammars/python/parser.dylib" "Python parser dylib"
check_codesign_valid "$RESOURCES/Grammars/python/parser.dylib" "Python parser dylib signature"
check_exists "$RESOURCES/Grammars/typescript/highlights.scm" "TypeScript highlight query"
check_exists "$RESOURCES/Grammars/typescript/parser.dylib" "TypeScript parser dylib"
check_codesign_valid "$RESOURCES/Grammars/typescript/parser.dylib" "TypeScript parser dylib signature"
check_exists "$RESOURCES/Grammars/go/highlights.scm" "Go highlight query"
check_exists "$RESOURCES/Grammars/go/parser.dylib" "Go parser dylib"
check_codesign_valid "$RESOURCES/Grammars/go/parser.dylib" "Go parser dylib signature"

# 9. Markdown preview resources (Mermaid, KaTeX)
echo ""
echo "[Markdown Preview]"
check_exists "$RESOURCES/Markdown" "Markdown resources directory"
check_exists "$RESOURCES/Markdown/mermaid.min.js" "Mermaid JS"
check_exists "$RESOURCES/Markdown/katex.min.js" "KaTeX JS"
check_exists "$RESOURCES/Markdown/katex.min.css" "KaTeX CSS"
check_exists "$RESOURCES/Markdown/katex-auto-render.min.js" "KaTeX auto-render"
check_exists "$RESOURCES/Markdown/highlight.min.js" "Highlight.js"
check_exists "$RESOURCES/Markdown/highlight-cocxy.css" "Highlight.js theme"

# 9b. Browser panel JS bundles (DOM grab and future browser-side features)
echo ""
echo "[Browser JS]"
check_exists "$RESOURCES/JS" "Browser JS resources directory"
check_exists "$RESOURCES/JS/dom-grab.js" "DOM grab JS"

# 9c. Hook integration script templates.
echo ""
echo "[Hook Scripts]"
check_exists "$RESOURCES/HookScripts" "Hook scripts resources directory"
check_exists "$RESOURCES/HookScripts/opencode-cocxy-session.js" "OpenCode project bridge script"
check_exists "$RESOURCES/HookScripts/pi-cocxy-session.ts" "Pi extension bridge script"
check_exists "$RESOURCES/HookScripts/rovo-event-hooks.yml.template" "Rovo Dev event hook template"

# 9d. Bundled skills for local Agent guidance.
echo ""
echo "[Skills]"
check_exists "$RESOURCES/Skills" "Skills resources directory"
check_exists "$RESOURCES/Skills/debug-systematic/SKILL.md" "debug-systematic skill"
check_exists "$RESOURCES/Skills/dependency-audit/SKILL.md" "dependency-audit skill"
check_exists "$RESOURCES/Skills/document/SKILL.md" "document skill"
check_exists "$RESOURCES/Skills/fix-error/SKILL.md" "fix-error skill"
check_exists "$RESOURCES/Skills/git-blame-explain/SKILL.md" "git-blame-explain skill"
check_exists "$RESOURCES/Skills/performance-profile/SKILL.md" "performance-profile skill"
check_exists "$RESOURCES/Skills/refactor-extract/SKILL.md" "refactor-extract skill"
check_exists "$RESOURCES/Skills/release-checklist/SKILL.md" "release-checklist skill"
check_exists "$RESOURCES/Skills/review-pr/SKILL.md" "review-pr skill"
check_exists "$RESOURCES/Skills/security-review/SKILL.md" "security-review skill"
check_exists "$RESOURCES/Skills/triage-issue/SKILL.md" "triage-issue skill"
check_exists "$RESOURCES/Skills/write-tests/SKILL.md" "write-tests skill"

# 9e. Bundled local project templates.
echo ""
echo "[Templates]"
check_exists "$RESOURCES/Templates" "Templates resources directory"
check_exists "$RESOURCES/Templates/swift-package/template.json" "swift-package template manifest"
check_exists "$RESOURCES/Templates/swift-package/files/Package.swift" "swift-package Package.swift"
check_exists "$RESOURCES/Templates/swift-package/files/Sources/{{module_name}}/main.swift" "swift-package executable source"
check_exists "$RESOURCES/Templates/python-package/template.json" "python-package template manifest"
check_exists "$RESOURCES/Templates/python-package/files/pyproject.toml" "python-package pyproject"
check_exists "$RESOURCES/Templates/python-package/files/src/{{package_name}}/__init__.py" "python-package module source"
check_exists "$RESOURCES/Templates/python-package/files/tests/test_import.py" "python-package test"
check_exists "$RESOURCES/Templates/rust-package/template.json" "rust-package template manifest"
check_exists "$RESOURCES/Templates/rust-package/files/Cargo.toml" "rust-package Cargo manifest"
check_exists "$RESOURCES/Templates/node-typescript/template.json" "node-typescript template manifest"
check_exists "$RESOURCES/Templates/node-typescript/files/package.json" "node-typescript package manifest"
check_exists "$RESOURCES/Templates/go-module/template.json" "go-module template manifest"
check_exists "$RESOURCES/Templates/go-module/files/go.mod" "go-module manifest"
check_exists "$RESOURCES/Templates/php-composer/template.json" "php-composer template manifest"
check_exists "$RESOURCES/Templates/php-composer/files/composer.json" "php-composer manifest"
check_exists "$RESOURCES/Templates/ruby-gem/template.json" "ruby-gem template manifest"
check_exists "$RESOURCES/Templates/ruby-gem/files/lib/{{gem_name}}.rb" "ruby-gem library entrypoint"
check_exists "$RESOURCES/Templates/static-site/template.json" "static-site template manifest"
check_exists "$RESOURCES/Templates/static-site/files/index.html" "static-site HTML entrypoint"
check_exists "$RESOURCES/Templates/docker-service/template.json" "docker-service template manifest"
check_exists "$RESOURCES/Templates/docker-service/files/Dockerfile" "docker-service Dockerfile"
check_exists "$RESOURCES/Templates/flutter-app/template.json" "flutter-app template manifest"
check_exists "$RESOURCES/Templates/flutter-app/files/pubspec.yaml" "flutter-app pubspec"

# 9f. Bundled plugin repos for the local marketplace.
echo ""
echo "[Plugins]"
check_exists "$RESOURCES/Plugins" "Plugins resources directory"
check_exists "$RESOURCES/Plugins/cocxy-github-pane/cocxy-plugin.toml" "GitHub pane bundled plugin"
check_exists "$RESOURCES/Plugins/cocxy-linear/cocxy-plugin.toml" "Linear bundled plugin"
check_exists "$RESOURCES/Plugins/cocxy-jira/cocxy-plugin.toml" "Jira bundled plugin"
check_exists "$RESOURCES/Plugins/cocxy-aws-cli-helper/cocxy-plugin.toml" "AWS CLI bundled plugin"
check_exists "$RESOURCES/Plugins/cocxy-docker-helper/cocxy-plugin.toml" "Docker bundled plugin"
check_exists "$RESOURCES/Plugins/cocxy-db-postgres/cocxy-plugin.toml" "PostgreSQL bundled plugin"
check_exists "$RESOURCES/Plugins/cocxy-db-mysql/cocxy-plugin.toml" "MySQL bundled plugin"
check_exists "$RESOURCES/Plugins/cocxy-db-sqlite/cocxy-plugin.toml" "SQLite bundled plugin"
check_exists "$RESOURCES/Plugins/cocxy-db-redis/cocxy-plugin.toml" "Redis bundled plugin"
check_exists "$RESOURCES/Plugins/cocxy-gcp-cli/cocxy-plugin.toml" "GCP CLI bundled plugin"
check_exists "$RESOURCES/Plugins/cocxy-azure-cli/cocxy-plugin.toml" "Azure CLI bundled plugin"
check_exists "$RESOURCES/Plugins/cocxy-kubernetes/cocxy-plugin.toml" "Kubernetes bundled plugin"
check_exists "$RESOURCES/Plugins/cocxy-cloudflare/cocxy-plugin.toml" "Cloudflare bundled plugin"

# 10. QuickLook extension
echo ""
echo "[QuickLook]"
check_exists "$CONTENTS/PlugIns/CocxyQuickLook.appex" "QuickLook extension"
check_exists "$CONTENTS/PlugIns/CocxyQuickLook.appex/Contents/Info.plist" "QuickLook Info.plist"
check_plist_string "$CONTENTS/PlugIns/CocxyQuickLook.appex/Contents/Info.plist" "NSExtension.NSExtensionPointIdentifier" "com.apple.quicklook.preview" "QuickLook extension point"
check_plist_exists "$CONTENTS/PlugIns/CocxyQuickLook.appex/Contents/Info.plist" "NSExtension.NSExtensionPrincipalClass" "QuickLook principal class"
check_plist_string "$CONTENTS/PlugIns/CocxyQuickLook.appex/Contents/Info.plist" "NSExtension.NSExtensionAttributes.QLSupportedContentTypes.0" "net.daringfireball.markdown" "QuickLook markdown content type"
check_plist_string "$CONTENTS/PlugIns/CocxyQuickLook.appex/Contents/Info.plist" "NSExtension.NSExtensionAttributes.QLSupportedContentTypes.1" "dev.cocxy.notebook" "QuickLook Cocxy notebook content type"
check_codesign_entitlement_true "$CONTENTS/PlugIns/CocxyQuickLook.appex" "com.apple.security.app-sandbox" "QuickLook sandbox entitlement"
check_codesign_entitlement_absent "$CONTENTS/PlugIns/CocxyQuickLook.appex" "com.apple.security.network.client" "QuickLook offline network entitlement"
check_exists "$CONTENTS/PlugIns/CocxyQuickLook.appex/Contents/Resources/Markdown" "QuickLook markdown resources"
check_exists "$CONTENTS/PlugIns/CocxyQuickLook.appex/Contents/Resources/Markdown/mermaid.min.js" "QuickLook Mermaid JS"
check_exists "$CONTENTS/PlugIns/CocxyQuickLook.appex/Contents/Resources/Markdown/highlight.min.js" "QuickLook Highlight.js"

# 11. Themes (optional but expected)
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
