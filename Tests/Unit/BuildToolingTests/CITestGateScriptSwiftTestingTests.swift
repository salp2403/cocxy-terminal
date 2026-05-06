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
        #expect(script.contains("api\\.openai\\.com|api\\.anthro[p]ic\\.com|generativelanguage\\.googleapis\\.com"))
        #expect(ci.contains("./scripts/run-privacy-audit.sh --app build/CocxyTerminal.app"))
        #expect(nightly.contains("./scripts/run-privacy-audit.sh --app \"$APP_DIR\""))
        #expect(release.contains("./scripts/run-privacy-audit.sh --app \"$APP_DIR\""))

        let result = try runProcess(scriptURL, arguments: [])
        #expect(result.terminationStatus == 0)
        #expect(result.stdout.contains("Privacy audit passed"))
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
