// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CITestGateScriptSwiftTestingTests.swift - Local/CI test gate drift checks.

import Foundation
import Testing

@Suite("CI test gate script")
struct CITestGateScriptSwiftTestingTests {

    @Test("local test gate mirrors the CI split XCTest and Swift Testing commands")
    func localTestGateMirrorsCISplitCommands() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/run-tests.sh")
        let script = try String(
            contentsOf: scriptURL,
            encoding: .utf8
        )
        let ci = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )
        let pullRequestTemplate = try String(
            contentsOf: root.appendingPathComponent(".github/PULL_REQUEST_TEMPLATE.md"),
            encoding: .utf8
        )

        #expect(script.contains("set -euo pipefail"))
        #expect(FileManager.default.isExecutableFile(atPath: scriptURL.path))
        #expect(script.contains("swift test --disable-swift-testing --skip PerformanceTests --skip CocxyCorePerformanceBenchmarks"))
        #expect(script.contains("./scripts/run-swift-testing-serial.sh"))
        #expect(ci.contains("./scripts/run-tests.sh"))
        #expect(pullRequestTemplate.contains("`./scripts/run-tests.sh` passes locally"))
    }

    @Test("performance workflow enforces benchmark regression baselines")
    func performanceWorkflowEnforcesBenchmarkRegressionBaselines() throws {
        let root = repositoryRoot()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/performance.yml"),
            encoding: .utf8
        )
        let scriptURL = root.appendingPathComponent("scripts/check-performance-regression.py")
        let baselinesURL = root.appendingPathComponent("scripts/performance-baselines.json")
        let baselinePayload = try JSONSerialization.jsonObject(
            with: Data(contentsOf: baselinesURL),
            options: []
        ) as? [String: Any]

        #expect(FileManager.default.isExecutableFile(atPath: scriptURL.path))
        #expect(workflow.contains("tee build/performance/cold-start.json"))
        #expect(workflow.contains("tee build/performance/memory-baseline.json"))
        #expect(workflow.contains("tee build/performance/benchmark-suite.log"))
        #expect(workflow.contains("scripts/check-performance-regression.py"))
        #expect(workflow.contains("--enforce"))
        #expect(baselinePayload?["default_tolerance_ratio"] as? Double == 0.1)
        #expect((baselinePayload?["metrics"] as? [[String: Any]])?.isEmpty == false)
    }

    @Test("cold start enforce fails when the internal critical path is over budget")
    func coldStartEnforceFailsOnInternalCriticalPathRegression() throws {
        let root = repositoryRoot()
        let script = try String(
            contentsOf: root.appendingPathComponent("scripts/bench-cold-start.sh"),
            encoding: .utf8
        )

        #expect(script.contains("combined_gate_passed"))
        #expect(script.contains("internal_critical_path_within_budget\" == \"0\""))
        #expect(script.contains("\"$ENFORCE\" == \"1\" && \"$combined_gate_passed\" != \"1\""))
    }

    @Test("privacy audit script is executable and wired into bundle workflows")
    func privacyAuditScriptIsExecutableAndWiredIntoBundleWorkflows() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/run-privacy-audit.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let ci = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )
        let nightly = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/nightly.yml"),
            encoding: .utf8
        )
        let release = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        #expect(FileManager.default.isExecutableFile(atPath: scriptURL.path))
        #expect(script.contains("No telemetry SDKs or auto crash upload"))
        #expect(script.contains("Provider endpoint boundaries"))
        #expect(script.contains("--runtime-seconds"))
        #expect(script.contains("PostHog|Sentry|Crashlytics|Mixpanel|Amplitude"))
        #expect(script.contains("network entitlement " + "beyond"))
        #expect(script.contains("zero data to any " + "external server"))
        #expect(script.contains("never sends data " + "to external servers"))
        #expect(script.contains("api\\.openai\\.com|api\\.anthro[p]ic\\.com|generativelanguage\\.googleapis\\.com"))
        #expect(ci.contains("./scripts/run-privacy-audit.sh --app build/CocxyTerminal.app"))
        #expect(nightly.contains("./scripts/run-privacy-audit.sh --app \"$APP_DIR\""))
        #expect(release.contains("./scripts/run-privacy-audit.sh --app \"$APP_DIR\""))

        let result = try runProcess(scriptURL, arguments: [])
        #expect(result.terminationStatus == 0)
        #expect(result.stdout.contains("Privacy audit passed"))
    }

    @Test("public privacy copy does not overstate explicit network boundaries")
    func publicPrivacyCopyDoesNotOverstateExplicitNetworkBoundaries() throws {
        let root = repositoryRoot()
        let webRoot = root.appendingPathComponent("web/public", isDirectory: true)
        var files = [
            root.appendingPathComponent("README.md"),
        ]
        files += try Self.files(under: webRoot, fileExtension: "html")

        let forbiddenFragments = [
            "never sends data " + "to external servers",
            "zero data to any " + "external server",
            "no network " + "entitlement " + "beyond",
            "network entitlement " + "beyond",
        ]

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8).lowercased()
            for fragment in forbiddenFragments {
                #expect(
                    !contents.contains(fragment),
                    "\(Self.relativePath(file, root: root)) contains overbroad privacy copy: \(fragment)"
                )
            }
        }
    }

    @Test("internal security audit script aggregates privacy bundle and focused regression gates")
    func internalSecurityAuditScriptAggregatesFocusedGates() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/run-security-audit.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let ci = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )

        #expect(FileManager.default.isExecutableFile(atPath: scriptURL.path))
        #expect(script.contains("set -euo pipefail"))
        #expect(script.contains("./scripts/run-privacy-audit.sh"))
        #expect(script.contains("./scripts/verify-app-bundle.sh"))
        #expect(script.contains("codesign --verify --deep --strict"))
        #expect(script.contains("QuickLookOfflineSecuritySwiftTestingTests"))
        #expect(script.contains("Phase7SocketSecurityTests"))
        #expect(script.contains("SocketServerRegressionSwiftTestingTests"))
        #expect(script.contains("LSPProcessPrivacySwiftTestingTests"))
        #expect(script.contains("AgentToolPermissionSwiftTestingTests"))
        #expect(script.contains("AgentSecretsSwiftTestingTests"))
        #expect(script.contains("ICloudSyncSecretsSwiftTestingTests"))
        #expect(script.contains("PluginEventWiringSwiftTestingTests"))
        #expect(script.contains("NotebookExecutionSwiftTestingTests"))
        #expect(script.contains("reviewThreadSuggestionsRejectSymlinkEscapes"))
        #expect(!ci.contains("run-security-audit.sh --skip-tests"))

        let result = try runProcess(scriptURL, arguments: ["--help"])
        #expect(result.terminationStatus == 0)
        #expect(result.stdout.contains("--app build/CocxyTerminal.app"))
    }

    @Test("local SSH smoke script covers direct jump and forward gates without CI flakiness")
    func localSSHSmokeScriptCoversDirectJumpAndForwardGates() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/smoke-local-ssh.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let ci = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )
        let nightly = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/nightly.yml"),
            encoding: .utf8
        )
        let release = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        #expect(FileManager.default.isExecutableFile(atPath: scriptURL.path))
        #expect(script.contains("/usr/sbin/sshd"))
        #expect(script.contains("ProxyJump cocxy-jump"))
        #expect(script.contains("-N -L"))
        #expect(script.contains("direct-ok"))
        #expect(script.contains("jump-ok"))
        #expect(script.contains("forward-ok"))
        #expect(script.contains("No external network, system service changes, or persistent keys are used."))
        #expect(!ci.contains("smoke-local-ssh.sh"))
        #expect(!nightly.contains("smoke-local-ssh.sh"))
        #expect(!release.contains("smoke-local-ssh.sh"))
    }

    @Test("GitHub PR smoke script is read-only and kept out of unauthenticated CI")
    func gitHubPRSmokeScriptIsReadOnlyAndManualOnly() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/smoke-github-pr-readonly.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let ci = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )
        let nightly = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/nightly.yml"),
            encoding: .utf8
        )
        let release = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        #expect(FileManager.default.isExecutableFile(atPath: scriptURL.path))
        #expect(script.contains("read-only `gh` operations only"))
        #expect(script.contains("gh pr view"))
        #expect(script.contains("gh pr diff"))
        #expect(script.contains("gh pr checks"))
        #expect(script.contains("reviewThreads"))
        #expect(!script.contains("gh pr create"))
        #expect(!script.contains("gh pr review"))
        #expect(!script.contains("gh pr merge"))
        #expect(!script.contains("mutation "))
        #expect(!script.contains("resolveReviewThread"))
        #expect(!script.contains("unresolveReviewThread"))
        #expect(!ci.contains("smoke-github-pr-readonly.sh"))
        #expect(!nightly.contains("smoke-github-pr-readonly.sh"))
        #expect(!release.contains("smoke-github-pr-readonly.sh"))

        let result = try runProcess(scriptURL, arguments: ["--help"])
        #expect(result.terminationStatus == 0)
        #expect(result.stdout.contains("--repo owner/name --pr 123"))
    }

    @Test("release website deploy keeps Spanish public site wired")
    func releaseWebsiteDeployKeepsSpanishPublicSiteWired() throws {
        let root = repositoryRoot()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        #expect(workflow.contains("web/public/es/*.html ${DEPLOY_TARGET}:${DEPLOY_PATH}es/"))
        #expect(workflow.contains(#"<link rel="alternate" hreflang="es" href="https://cocxy.dev/es/releases.html">"#))
        #expect(workflow.contains(#"<a href="/es/releases.html" hreflang="es" lang="es">Espa&ntilde;ol</a>"#))
        #expect(workflow.contains("${DEPLOY_PATH}es/index.html"))
        #expect(workflow.contains("${DEPLOY_PATH}es/getting-started.html"))
        #expect(workflow.contains("${DEPLOY_PATH}es/features.html"))
        #expect(workflow.contains("${DEPLOY_PATH}es/faq.html"))
        #expect(workflow.contains("${DEPLOY_PATH}es/releases.html"))
        #expect(workflow.contains(#"\"softwareVersion\": \"${VERSION}\"|g' ${DEPLOY_PATH}es/index.html"#))

        let rewriteStart = try #require(workflow.range(of: "# Update version-specific values"))
        let cleanupStart = try #require(
            workflow.range(of: "rm /tmp/deploy_key", range: rewriteStart.upperBound..<workflow.endIndex)
        )
        let versionRewriteBlock = String(workflow[rewriteStart.lowerBound..<cleanupStart.lowerBound])
        #expect(versionRewriteBlock.contains("set -e;"))
        #expect(!versionRewriteBlock.contains("|| true"))
    }

    @Test("public release website gate keeps badge and structured data wired")
    func publicReleaseWebsiteGateKeepsBadgeAndStructuredDataWired() throws {
        let root = repositoryRoot()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )
        let englishHome = try String(
            contentsOf: root.appendingPathComponent("web/public/index.html"),
            encoding: .utf8
        )
        let spanishHome = try String(
            contentsOf: root.appendingPathComponent("web/public/es/index.html"),
            encoding: .utf8
        )
        let englishReleases = try String(
            contentsOf: root.appendingPathComponent("web/public/releases.html"),
            encoding: .utf8
        )
        let spanishReleases = try String(
            contentsOf: root.appendingPathComponent("web/public/es/releases.html"),
            encoding: .utf8
        )

        for homepage in [englishHome, spanishHome] {
            #expect(homepage.contains(#"<div class="hero-version">"#))
            #expect(homepage.contains(#"<span class="version-badge">v0.0.0</span>"#))
            #expect(homepage.contains(#""@type": "SoftwareApplication""#))
            #expect(homepage.contains(#""softwareVersion": "0.0.0""#))
        }

        for releasePage in [englishReleases, spanishReleases] {
            #expect(releasePage.contains(#""@type": "BreadcrumbList""#))
            #expect(releasePage.contains(#""@type": "CollectionPage""#))
            #expect(releasePage.contains(#""@type": "ItemList""#))
            #expect(releasePage.contains(#""softwareVersion": "0.0.0""#))
            #expect(releasePage.contains(#"href="/appcast.xml""#))
            #expect(releasePage.contains("https://github.com/salp2403/cocxy-terminal/releases/latest"))
        }

        #expect(workflow.contains("release_items = []"))
        #expect(workflow.contains(#""@type": "CollectionPage""#))
        #expect(workflow.contains(#""@type": "ItemList""#))
        #expect(workflow.contains(#""softwareVersion": version"#))
        #expect(workflow.contains(#"<link rel="alternate" type="application/rss+xml" title="Cocxy Terminal Releases" href="/appcast.xml">"#))
        #expect(workflow.contains(#"\"softwareVersion\": \"${VERSION}\"|g' ${DEPLOY_PATH}releases.html"#))
        #expect(workflow.contains(#"\"softwareVersion\": \"${VERSION}\"|g' ${DEPLOY_PATH}es/releases.html"#))
    }

    @Test("primary public docs do not pin the retired CLI command count")
    func primaryPublicDocsDoNotPinRetiredCLICommandCount() throws {
        let root = repositoryRoot()
        let paths = [
            "README.md",
            "web/public/index.html",
            "web/public/features.html",
            "web/public/faq.html",
            "web/public/getting-started.html",
        ]

        for path in paths {
            let rawContents = try String(
                contentsOf: root.appendingPathComponent(path),
                encoding: .utf8
            )
            let contents = rawContents.lowercased()

            #expect(!contents.contains("ninety-three"))
            #expect(!contents.contains("93-command"))
            #expect(!contents.contains("93 commands"))
            #expect(!contents.contains("full list of 93"))
        }
    }

    @Test("public marketing copy avoids named third-party agent brands")
    func publicMarketingCopyAvoidsNamedThirdPartyAgentBrands() throws {
        let root = repositoryRoot()
        let webRoot = root.appendingPathComponent("web/public", isDirectory: true)
        var files = [
            root.appendingPathComponent("README.md"),
        ]
        files += try Self.files(under: webRoot, fileExtension: "html")
        files += try Self.files(under: webRoot, fileExtension: "js")

        let pattern = try NSRegularExpression(
            pattern: #"\b(claude|codex|gemini|aider|kiro|opencode|anthropic|openai|warp)\b"#,
            options: [.caseInsensitive]
        )

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(location: 0, length: (contents as NSString).length)
            #expect(
                pattern.firstMatch(in: contents, range: range) == nil,
                "\(Self.relativePath(file, root: root)) should describe bundled local agent profiles generically"
            )
        }
    }

    @Test("public getting started docs include v0 migration guidance in both locales")
    func publicGettingStartedDocsIncludeMigrationGuidanceInBothLocales() throws {
        let root = repositoryRoot()
        let english = try String(
            contentsOf: root.appendingPathComponent("web/public/getting-started.html"),
            encoding: .utf8
        )
        let spanish = try String(
            contentsOf: root.appendingPathComponent("web/public/es/getting-started.html"),
            encoding: .utf8
        )

        #expect(english.contains(#"<h2 id="migration-guide">Migration from v0.x</h2>"#))
        #expect(english.contains(##"<a href="#migration-guide" class="sidebar-link">Migration Guide</a>"##))
        #expect(english.contains("~/.config/cocxy/"))
        #expect(english.contains("brew update && brew upgrade --cask cocxy"))
        #expect(spanish.contains("Migrar desde versiones v0.x"))
        #expect(spanish.contains("~/.config/cocxy/"))
    }

    @Test("Spanish getting started docs cover the same core user guide surfaces")
    func spanishGettingStartedDocsCoverCoreUserGuideSurfaces() throws {
        let root = repositoryRoot()
        let spanish = try String(
            contentsOf: root.appendingPathComponent("web/public/es/getting-started.html"),
            encoding: .utf8
        )
        let requiredAnchors = [
            "install",
            "visual-tour",
            "concepts",
            "configuration",
            "keyboard-shortcuts",
            "agent-detection",
            "code-review",
            "markdown",
            "quicklook",
            "browser",
            "remote-workspaces",
            "web-terminal",
            "shell-integration",
            "per-project-config",
            "applescript",
            "plugin-system",
            "splits",
            "quick-terminal",
            "notifications",
            "command-palette",
            "sessions",
            "cli-companion",
            "themes",
            "agents-toml",
            "migration-guide",
            "troubleshooting",
        ]

        for anchor in requiredAnchors {
            #expect(
                spanish.contains(#"id="\#(anchor)""#),
                "Spanish getting-started docs should include #\(anchor)"
            )
        }

        #expect(spanish.contains("cocxy setup-hooks"))
        #expect(spanish.contains("cocxy status"))
        #expect(spanish.contains("Sin telemetr&iacute;a"))
        #expect(!spanish.contains("AI agent workflows"))
    }

    @Test("Spanish feature docs cover every primary public feature anchor")
    func spanishFeatureDocsCoverEveryPrimaryPublicFeatureAnchor() throws {
        let root = repositoryRoot()
        let spanish = try String(
            contentsOf: root.appendingPathComponent("web/public/es/features.html"),
            encoding: .utf8
        )
        let requiredAnchors = [
            "agent-detection",
            "code-review",
            "github-pane",
            "markdown",
            "quicklook",
            "gpu",
            "remote",
            "browser",
            "web-terminal",
            "plugins",
            "per-project",
            "applescript",
            "shell",
            "privacy",
            "cli",
        ]

        for anchor in requiredAnchors {
            #expect(
                spanish.contains(#"id="\#(anchor)""#),
                "Spanish features docs should include #\(anchor)"
            )
            #expect(
                spanish.contains("href=\"#\(anchor)\""),
                "Spanish features table of contents should link to #\(anchor)"
            )
        }

        #expect(spanish.contains("CocxyCore"))
        #expect(spanish.contains("cocxy setup-hooks"))
        #expect(spanish.contains("cocxy github"))
        #expect(spanish.contains("cero telemetr&iacute;a"))
    }

    @Test("Spanish public docs avoid untranslated visible product terms")
    func spanishPublicDocsAvoidUntranslatedVisibleProductTerms() throws {
        let root = repositoryRoot()
        let webRoot = root.appendingPathComponent("web/public/es", isDirectory: true)
        let files = try Self.files(under: webRoot, fileExtension: "html")
        let forbiddenFragments = [
            "workspace markdown",
            "workspaces",
            "remote workspaces",
            "browser integrado",
            "shell integration",
            "browser data",
            "feedback",
            "preview",
            "hot-reload",
            "copy-on-select",
            "protecci&oacute;n de paste",
            "providers remotos",
            "snippets",
            "tabs,",
            "splits",
            "preferences",
            "smart routing",
            "quick terminal",
            "web terminal",
            "restore-on-launch",
            "crash recovery",
            "sidebar",
            "dashboard",
            "overlays",
            "keybindings",
            "overrides",
            "bookmarks",
            "devtools",
            "hotkey",
            "badges",
            "tab creado",
            "tab cerrado",
            "snapshots",
            "clic derecho y open",
            "open source",
            "lock-in",
            "runtime",
            "framework",
            "pair programming",
            "frame rate",
            "attach",
            "tu setup",
            "copy p&uacute;blico",
            "audits del repo",
            "analytics",
            "tracking",
            "crashes",
            "crash upload",
            "review threads",
            "inline",
            "hunk",
            "hunks",
            "quicklook offline",
            "auto-updates",
            "bundle incluye",
            "releases con firma",
        ]

        for file in files {
            let contents = Self.htmlSearchableText(
                try String(contentsOf: file, encoding: .utf8)
            ).lowercased()
            for fragment in forbiddenFragments {
                #expect(
                    !contents.contains(fragment),
                    "\(Self.relativePath(file, root: root)) contains untranslated Spanish public copy: \(fragment)"
                )
            }
        }
    }

    @Test("Spanish public docs use localized documentation labels")
    func spanishPublicDocsUseLocalizedDocumentationLabels() throws {
        let root = repositoryRoot()
        let webRoot = root.appendingPathComponent("web/public/es", isDirectory: true)
        let files = try Self.files(under: webRoot, fileExtension: "html")

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            #expect(
                !contents.contains(#">Docs</a>"#),
                "\(Self.relativePath(file, root: root)) should localize nav/footer documentation labels"
            )
            #expect(
                !contents.contains("Leer docs"),
                "\(Self.relativePath(file, root: root)) should localize documentation CTA labels"
            )
        }

        let spanishHomepage = try String(
            contentsOf: root.appendingPathComponent("web/public/es/index.html"),
            encoding: .utf8
        )
        let spanishGettingStarted = try String(
            contentsOf: root.appendingPathComponent("web/public/es/getting-started.html"),
            encoding: .utf8
        )
        #expect(!spanishHomepage.contains("revisi&oacute;n, docs, remoto"))
        #expect(!spanishGettingStarted.contains("servidores locales, docs y apps web"))
    }

    @Test("Spanish public docs keep primary navigation inside the Spanish site")
    func spanishPublicDocsKeepPrimaryNavigationInsideSpanishSite() throws {
        let root = repositoryRoot()
        let paths = [
            "web/public/es/getting-started.html",
            "web/public/es/faq.html",
        ]

        for path in paths {
            let contents = try String(
                contentsOf: root.appendingPathComponent(path),
                encoding: .utf8
            )

            #expect(contents.contains(#"href="/es/""#))
            #expect(contents.contains(#"href="/es/features.html""#))
            #expect(contents.contains(#"href="/es/releases.html""#))
            #expect(!contents.contains(#"<a href="/features.html">Funciones</a>"#))
            #expect(!contents.contains(#"<a href="/releases.html">Versiones</a>"#))
        }
    }

    @Test("Spanish homepage covers the same primary public sections")
    func spanishHomepageCoversSamePrimaryPublicSections() throws {
        let root = repositoryRoot()
        let english = try String(
            contentsOf: root.appendingPathComponent("web/public/index.html"),
            encoding: .utf8
        )
        let spanish = try String(
            contentsOf: root.appendingPathComponent("web/public/es/index.html"),
            encoding: .utf8
        )
        let requiredSections = [
            "hero",
            "features",
            "demo",
            "comparison",
            "faq",
            "download",
            "opensource",
        ]

        for section in requiredSections {
            #expect(
                english.contains(#"id="\#(section)""#),
                "English homepage should include #\(section)"
            )
            #expect(
                spanish.contains(#"id="\#(section)""#),
                "Spanish homepage should include #\(section)"
            )
        }

        let requiredFeatureClasses = [
            "feature-icon--agents",
            "feature-icon--review",
            "feature-icon--markdown",
            "feature-icon--ssh",
            "feature-icon--browser",
            "feature-icon--privacy",
            "feature-icon--gpu",
            "feature-icon--cli",
            "feature-icon--plugin",
            "feature-icon--config",
            "feature-icon--web",
            "feature-icon--shell",
        ]

        for featureClass in requiredFeatureClasses {
            #expect(
                english.contains(featureClass),
                "English homepage should include \(featureClass)"
            )
            #expect(
                spanish.contains(featureClass),
                "Spanish homepage should include \(featureClass)"
            )
        }

        #expect(spanish.contains("100% c&oacute;digo abierto"))
        #expect(spanish.contains("cero telemetr&iacute;a"))
        #expect(spanish.contains("Metal GPU"))
    }

    @Test("public website local links resolve in the repo checkout")
    func publicWebsiteLocalLinksResolve() throws {
        let root = repositoryRoot().appendingPathComponent("web/public", isDirectory: true)
        let htmlFiles = try Self.files(under: root, fileExtension: "html")
        let idsByFile = try Dictionary(uniqueKeysWithValues: htmlFiles.map { file in
            (file.standardizedFileURL, Self.htmlIDs(in: try String(contentsOf: file, encoding: .utf8)))
        })

        for file in htmlFiles {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for reference in Self.htmlReferences(in: contents) {
                guard let local = Self.localWebsiteReference(
                    reference,
                    from: file,
                    root: root
                ) else { continue }

                guard local.target.lastPathComponent != "appcast.xml" else {
                    // Release builds generate and deploy build/appcast.xml.
                    continue
                }

                #expect(
                    local.target.path.hasPrefix(root.path + "/"),
                    "\(Self.relativePath(file, root: root)) reference escapes public site root \(reference)"
                )
                #expect(
                    FileManager.default.fileExists(atPath: local.target.path),
                    "\(Self.relativePath(file, root: root)) references missing local target \(reference)"
                )

                if let fragment = local.fragment,
                   local.target.pathExtension == "html",
                   let ids = idsByFile[local.target.standardizedFileURL] {
                    #expect(
                        ids.contains(fragment),
                        "\(Self.relativePath(file, root: root)) references missing anchor \(reference)"
                    )
                }
            }
        }
    }

    @Test("changelog keeps non-empty unreleased notes before the latest tagged release")
    func changelogKeepsCurrentUnreleasedNotes() throws {
        let root = repositoryRoot()
        let changelog = try String(
            contentsOf: root.appendingPathComponent("CHANGELOG.md"),
            encoding: .utf8
        )

        #expect(changelog.components(separatedBy: "## [Unreleased]").count == 2)
        let unreleasedRange = try #require(changelog.range(of: "## [Unreleased]"))
        let latestReleaseRange = try #require(changelog.range(of: "## [0.1.92]"))
        #expect(unreleasedRange.lowerBound < latestReleaseRange.lowerBound)

        let unreleasedSection = String(changelog[unreleasedRange.upperBound..<latestReleaseRange.lowerBound])
        #expect(unreleasedSection.contains("### Added"))
        #expect(unreleasedSection.contains("### Fixed"))
        #expect(unreleasedSection.contains("CocxyCoreKit 0.15.0"))
        #expect(unreleasedSection.contains("100+"))
        #expect(!unreleasedSection.contains("docs/" + "project"))
        #expect(!unreleasedSection.contains("/Users/" + "Galf"))
    }

    @Test("performance regression checker accepts metrics inside tolerance")
    func performanceRegressionCheckerAcceptsMetricsInsideTolerance() throws {
        let root = repositoryRoot()
        let fixture = try makePerformanceFixture(
            baseline: """
            {
              "default_tolerance_ratio": 0.1,
              "metrics": [
                {"name": "app_readiness_median_ms", "baseline": 400, "direction": "lower"},
                {"name": "physical_footprint_mb", "baseline": 250, "direction": "lower"},
                {"name": "editor_scroll_frame_ms", "baseline": 4, "direction": "lower"},
                {"name": "cocxycore_output_throughput_mbps", "baseline": 2, "direction": "higher"}
              ]
            }
            """,
            coldStart: #"{"benchmark_kind":"app-readiness","median_ms":410}"#,
            memory: #"{"benchmark_kind":"memory-baseline","physical_footprint_mb":252}"#,
            log: """
            Editor 5000-line average scroll frame time: 4.1ms
            CocxyCore output throughput: 1.9 MB/s
            """
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runProcess(
            root.appendingPathComponent("scripts/check-performance-regression.py"),
            arguments: [
                "--baseline", fixture.baseline.path,
                "--metric-file", fixture.coldStart.path,
                "--metric-file", fixture.memory.path,
                "--log-file", fixture.log.path,
                "--enforce",
            ]
        )

        #expect(result.terminationStatus == 0)
        #expect(result.stdout.contains("Performance regression gate passed."))
    }

    @Test("performance regression checker fails beyond tolerance")
    func performanceRegressionCheckerFailsBeyondTolerance() throws {
        let root = repositoryRoot()
        let fixture = try makePerformanceFixture(
            baseline: """
            {
              "default_tolerance_ratio": 0.1,
              "metrics": [
                {"name": "app_readiness_median_ms", "baseline": 400, "direction": "lower"}
              ]
            }
            """,
            coldStart: #"{"benchmark_kind":"app-readiness","median_ms":445}"#,
            memory: #"{"benchmark_kind":"memory-baseline","physical_footprint_mb":200}"#,
            log: ""
        )
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try runProcess(
            root.appendingPathComponent("scripts/check-performance-regression.py"),
            arguments: [
                "--baseline", fixture.baseline.path,
                "--metric-file", fixture.coldStart.path,
                "--enforce",
            ]
        )

        #expect(result.terminationStatus != 0)
        #expect(result.stderr.contains("app_readiness_median_ms"))
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    private struct PerformanceFixture {
        let root: URL
        let baseline: URL
        let coldStart: URL
        let memory: URL
        let log: URL
    }

    private struct ProcessResult {
        let stdout: String
        let stderr: String
        let terminationStatus: Int32
    }

    private struct LocalWebsiteReference {
        let target: URL
        let fragment: String?
    }

    private static func files(under root: URL, fileExtension: String) throws -> [URL] {
        let urls = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )?.compactMap { $0 as? URL } ?? []

        return try urls
            .filter { url in
                let values = try url.resourceValues(forKeys: [.isRegularFileKey])
                return values.isRegularFile == true && url.pathExtension == fileExtension
            }
            .map(\.standardizedFileURL)
            .sorted { $0.path < $1.path }
    }

    private static func htmlReferences(in contents: String) -> [String] {
        let regex = try? NSRegularExpression(pattern: #"(?:href|src)="([^"]+)""#)
        let range = NSRange(location: 0, length: (contents as NSString).length)
        let references: [String] = regex?.matches(in: contents, range: range).compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            return (contents as NSString).substring(with: match.range(at: 1))
        } ?? []
        return references
    }

    private static func htmlIDs(in contents: String) -> Set<String> {
        let regex = try? NSRegularExpression(pattern: #"id="([^"]+)""#)
        let range = NSRange(location: 0, length: (contents as NSString).length)
        let ids: [String] = regex?.matches(in: contents, range: range).compactMap { match in
            guard match.numberOfRanges >= 2 else { return nil }
            return (contents as NSString).substring(with: match.range(at: 1))
        } ?? []
        return Set(ids)
    }

    private static func htmlSearchableText(_ contents: String) -> String {
        let withoutScripts = replacing(
            #"(?is)<script\b[^>]*>.*?</script>"#,
            in: contents,
            with: " "
        )
        let withoutStyles = replacing(
            #"(?is)<style\b[^>]*>.*?</style>"#,
            in: withoutScripts,
            with: " "
        )
        let withoutComments = replacing(
            #"(?is)<!--.*?-->"#,
            in: withoutStyles,
            with: " "
        )
        return replacing(#"(?is)<[^>]+>"#, in: withoutComments, with: " ")
    }

    private static func replacing(_ pattern: String, in contents: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return contents
        }
        let range = NSRange(location: 0, length: (contents as NSString).length)
        return regex.stringByReplacingMatches(
            in: contents,
            range: range,
            withTemplate: replacement
        )
    }

    private static func localWebsiteReference(
        _ rawReference: String,
        from file: URL,
        root: URL
    ) -> LocalWebsiteReference? {
        let reference = rawReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else { return nil }

        let lowercased = reference.lowercased()
        guard !lowercased.hasPrefix("http://"),
              !lowercased.hasPrefix("https://"),
              !lowercased.hasPrefix("mailto:"),
              !lowercased.hasPrefix("tel:"),
              !reference.hasPrefix("//") else {
            return nil
        }

        let parts = reference.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let pathWithQuery = String(parts.first ?? "")
        let pathPart = String(
            pathWithQuery.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        )
        let fragment = parts.count == 2
            ? String(parts[1]).removingPercentEncoding ?? String(parts[1])
            : nil

        var target: URL
        if pathPart.isEmpty {
            target = file
        } else if pathPart.hasPrefix("/") {
            target = root.appendingPathComponent(String(pathPart.dropFirst()))
        } else {
            target = file.deletingLastPathComponent().appendingPathComponent(pathPart)
        }
        if pathPart.hasSuffix("/") {
            target.appendPathComponent("index.html")
        }

        return LocalWebsiteReference(
            target: target.standardizedFileURL,
            fragment: fragment?.isEmpty == false ? fragment : nil
        )
    }

    private static func relativePath(_ url: URL, root: URL) -> String {
        let path = url.standardizedFileURL.path
        let prefix = root.standardizedFileURL.path + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    private func makePerformanceFixture(
        baseline: String,
        coldStart: String,
        memory: String,
        log: String
    ) throws -> PerformanceFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-performance-fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let baselineURL = root.appendingPathComponent("baseline.json")
        let coldStartURL = root.appendingPathComponent("cold-start.json")
        let memoryURL = root.appendingPathComponent("memory.json")
        let logURL = root.appendingPathComponent("benchmarks.log")
        try baseline.write(to: baselineURL, atomically: true, encoding: .utf8)
        try coldStart.write(to: coldStartURL, atomically: true, encoding: .utf8)
        try memory.write(to: memoryURL, atomically: true, encoding: .utf8)
        try log.write(to: logURL, atomically: true, encoding: .utf8)

        return PerformanceFixture(
            root: root,
            baseline: baselineURL,
            coldStart: coldStartURL,
            memory: memoryURL,
            log: logURL
        )
    }

    private func runProcess(_ executableURL: URL, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        return ProcessResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            terminationStatus: process.terminationStatus
        )
    }
}
