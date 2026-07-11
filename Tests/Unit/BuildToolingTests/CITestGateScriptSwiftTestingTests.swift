// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CITestGateScriptSwiftTestingTests.swift - Local/CI test gate drift checks.

import Foundation
import CryptoKit
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
        let serialScript = try String(
            contentsOf: root.appendingPathComponent("scripts/run-swift-testing-serial.sh"),
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
        #expect(script.contains("--disable-automatic-resolution"))
        #expect(script.contains("./scripts/run-swift-testing-serial.sh"))
        #expect(serialScript.contains("--disable-automatic-resolution"))
        #expect(script.contains("web/scripts/build-site.mjs"))
        #expect(script.contains("Node.js 18+ is required to generate public website test fixtures"))
        #expect(serialScript.contains("swift-testing-serial-profraw"))
        #expect(serialScript.contains("xcrun llvm-profdata merge -sparse"))
        #expect(serialScript.contains("xcrun llvm-cov export -format=text"))
        #expect(serialScript.contains("CocxyTerminal-SwiftTesting.json"))
        #expect(!serialScript.contains("mapfile"))
        #expect(ci.contains("./scripts/run-tests.sh"))
        #expect(pullRequestTemplate.contains("`./scripts/run-tests.sh` passes locally"))
    }

    @Test("workflow actions use reviewed immutable commits and checkouts drop credentials")
    func workflowActionsUseImmutableCommits() throws {
        let workflowDirectory = repositoryRoot().appendingPathComponent(".github/workflows", isDirectory: true)
        let workflowURLs = try FileManager.default.contentsOfDirectory(
            at: workflowDirectory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "yml" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let allowedPins: [String: Set<String>] = [
            "actions/checkout": [
                "34e114876b0b11c390a56381ad16ebd13914f8d5", // v4.3.1
                "df4cb1c069e1874edd31b4311f1884172cec0e10", // v6.0.3
            ],
            "actions/setup-node": [
                "49933ea5288caeca8642d1e84afbd3f7d6820020", // v4.4.0
                "48b55a011bda9f5d6aeb4c2d9c7362e8dae4041e", // v6.4.0
            ],
            "goto-bus-stop/setup-zig": [
                "abea47f85e598557f500fa1fd2ab7464fcb39406", // v2.2.1
            ],
            "softprops/action-gh-release": [
                "3bb12739c298aeb8a4eeaf626c5b8d85266b0e65", // v2.6.2
            ],
        ]
        var observedActions = Set<String>()

        for workflowURL in workflowURLs {
            let workflow = try String(contentsOf: workflowURL, encoding: .utf8)
            let lines = workflow.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("uses:") else { continue }
                let token = String(trimmed.dropFirst("uses:".count))
                    .trimmingCharacters(in: .whitespaces)
                    .split(whereSeparator: { $0.isWhitespace })
                    .first
                    .map(String.init) ?? ""
                let separator = try #require(token.lastIndex(of: "@"))
                let action = String(token[..<separator])
                let revision = String(token[token.index(after: separator)...])

                #expect(revision.count == 40, "\(workflowURL.lastPathComponent): \(token)")
                #expect(revision.allSatisfy { $0.isHexDigit && !$0.isUppercase })
                #expect(allowedPins[action]?.contains(revision) == true, "Unreviewed action pin: \(token)")
                observedActions.insert(action)

                if action == "actions/checkout" {
                    var blockEnd = index + 1
                    while blockEnd < lines.count,
                          !lines[blockEnd].trimmingCharacters(in: .whitespaces).hasPrefix("- name:") {
                        blockEnd += 1
                    }
                    let block = lines[index..<blockEnd].joined(separator: "\n")
                    #expect(
                        block.contains("persist-credentials: false"),
                        "Checkout must remove credentials before the next step in \(workflowURL.lastPathComponent)"
                    )
                }
            }
        }

        #expect(observedActions == Set(allowedPins.keys))
    }

    @Test("pull request workflows never share private CocxyCore authority")
    func pullRequestWorkflowsDoNotSharePrivateAuthority() throws {
        let root = repositoryRoot()
        let ci = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )
        let performance = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/performance.yml"),
            encoding: .utf8
        )
        let trustedJob = try #require(ci.range(of: "  trusted-bundle-audit:"))
        let unprivilegedJob = String(ci[..<trustedJob.lowerBound])
        let trustedJobBody = String(ci[trustedJob.lowerBound...])

        #expect(unprivilegedJob.contains("Build & Test (Unprivileged)"))
        #expect(unprivilegedJob.contains("prepare-ci-cocxycore-fixture.sh"))
        #expect(unprivilegedJob.contains("COCXY_CI_REMOTE_DAEMON_FIXTURE: \"1\""))
        #expect(!unprivilegedJob.contains("COCXYCORE_DEPLOY_KEY"))
        #expect(!unprivilegedJob.contains("repository: salp2403/cocxycore"))

        #expect(trustedJobBody.contains("if: github.event_name == 'push' && github.ref == 'refs/heads/main'"))
        #expect(trustedJobBody.contains("repository: salp2403/cocxycore"))
        #expect(trustedJobBody.contains("COCXYCORE_DEPLOY_KEY"))

        #expect(performance.contains("pull_request:"))
        #expect(performance.contains("prepare-ci-cocxycore-fixture.sh"))
        #expect(performance.contains("COCXY_CI_REMOTE_DAEMON_FIXTURE: \"1\""))
        #expect(!performance.contains("COCXYCORE_DEPLOY_KEY"))
        #expect(!performance.contains("repository: salp2403/cocxycore"))
        #expect(!performance.contains("cocxycore-source"))
    }

    @Test("private CocxyCore builds use one pinned source after pinned tooling")
    func privateCocxyCoreBuildsUsePinnedSourceAfterTooling() throws {
        let root = repositoryRoot()
        let pinnedCocxyCore = "5b1a6ecf1c96bb74a2921e92bad1e52664f83673"
        let workflowNames = ["ci.yml", "release.yml", "nightly.yml", "preview.yml"]

        for workflowName in workflowNames {
            let workflow = try String(
                contentsOf: root.appendingPathComponent(".github/workflows/\(workflowName)"),
                encoding: .utf8
            )
            let privateCheckout = try #require(workflow.range(of: "repository: salp2403/cocxycore"))
            let zigSetup = try #require(workflow.range(of: "goto-bus-stop/setup-zig@"))
            let xcodeGenSetup = try #require(workflow.range(of: "- name: Install pinned XcodeGen"))
            let privateTail = String(workflow[privateCheckout.lowerBound...])

            #expect(zigSetup.lowerBound < privateCheckout.lowerBound, "\(workflowName) installs Zig too late")
            #expect(xcodeGenSetup.lowerBound < privateCheckout.lowerBound, "\(workflowName) installs XcodeGen too late")
            #expect(privateTail.contains("ref: \(pinnedCocxyCore)"), "\(workflowName) has mutable CocxyCore provenance")
            #expect(privateTail.contains("persist-credentials: false"))
            #expect(!workflow.contains("brew install xcodegen"))
            #expect(!workflow.contains("ref: main\n          ssh-key: ${{ secrets.COCXYCORE_DEPLOY_KEY }}"))
        }
    }

    @Test("release channels authenticate source provenance before secrets")
    func releaseChannelsAuthenticateSourceProvenance() throws {
        let root = repositoryRoot()
        let release = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )
        let preview = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/preview.yml"),
            encoding: .utf8
        )
        let prepareRelease = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/prepare-release.yml"),
            encoding: .utf8
        )
        let deployWebsite = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/deploy-website.yml"),
            encoding: .utf8
        )

        let releaseProvenance = try #require(release.range(of: "- name: Verify release provenance"))
        let releasePrivateKey = try #require(release.range(of: "COCXYCORE_DEPLOY_KEY"))
        let releaseCertificate = try #require(release.range(of: "CERTIFICATE_P12"))
        #expect(releaseProvenance.lowerBound < releasePrivateKey.lowerBound)
        #expect(releaseProvenance.lowerBound < releaseCertificate.lowerBound)
        #expect(release.contains("repository_dispatch:"))
        #expect(release.contains("- stable-release"))
        #expect(!release.contains("push:\n    tags:"))
        #expect(release.contains(#"^[0-9]+\.[0-9]+\.[0-9]+$"#))
        #expect(release.contains("EXPECTED_COMMIT"))
        #expect(!release.contains("VERSION=\"${{ github.event.client_payload"))
        #expect(!release.contains("TAG=\"${{ github.event.client_payload"))
        #expect(!release.contains("EXPECTED_COMMIT=\"${{ github.event.client_payload"))
        #expect(release.contains("Stable releases require an annotated tag."))
        #expect(release.contains("git merge-base --is-ancestor \"$TAG_COMMIT\" refs/remotes/origin/main"))
        #expect(release.contains("git checkout --detach \"$TAG_COMMIT\""))
        #expect(release.contains("CFBundleShortVersionString"))

        let previewProvenance = try #require(preview.range(of: "- name: Verify preview provenance"))
        let previewPrivateKey = try #require(preview.range(of: "COCXYCORE_DEPLOY_KEY"))
        let previewCertificate = try #require(preview.range(of: "CERTIFICATE_P12"))
        #expect(previewProvenance.lowerBound < previewPrivateKey.lowerBound)
        #expect(previewProvenance.lowerBound < previewCertificate.lowerBound)
        #expect(preview.contains("- preview-release"))
        #expect(preview.contains("if: github.event_name == 'repository_dispatch' && github.ref == 'refs/heads/main'"))
        #expect(preview.contains(#"^[0-9]+\.[0-9]+\.[0-9]+-preview\.[0-9]+$"#))
        #expect(preview.contains("Manual preview requests must run from main."))
        #expect(!preview.contains("VERSION=\"${{ github.event.client_payload"))
        #expect(preview.contains("git merge-base --is-ancestor \"$GITHUB_SHA\" refs/remotes/origin/main"))

        #expect(prepareRelease.contains("if: github.ref == 'refs/heads/main'"))
        #expect(prepareRelease.contains("- prepare-stable-release"))
        #expect(prepareRelease.contains("-f event_type=stable-release"))
        #expect(!prepareRelease.contains("VERSION=\"${{ github.event.client_payload"))
        #expect(prepareRelease.contains("persist-credentials: false"))
        #expect(!prepareRelease.contains("token: ${{ secrets.RELEASE_PUSH_TOKEN }}"))
        #expect(prepareRelease.contains("GIT_ASKPASS=\"$ASKPASS\" GIT_TERMINAL_PROMPT=0 git push"))
        #expect(deployWebsite.contains("if: github.ref == 'refs/heads/main'"))
        #expect(deployWebsite.contains("ref: main"))
    }

    @Test("CI tool installers are immutable and remote-daemon fixtures are inert")
    func ciToolInstallersAreImmutableAndFixturesAreInert() throws {
        let root = repositoryRoot()
        let installerURL = root.appendingPathComponent("scripts/install-pinned-xcodegen.sh")
        let fixtureScriptURL = root.appendingPathComponent("scripts/prepare-ci-cocxycore-fixture.sh")
        let installer = try String(contentsOf: installerURL, encoding: .utf8)
        let fixtureScript = try String(contentsOf: fixtureScriptURL, encoding: .utf8)

        #expect(FileManager.default.isExecutableFile(atPath: installerURL.path))
        #expect(FileManager.default.isExecutableFile(atPath: fixtureScriptURL.path))
        #expect(installer.contains("XCODEGEN_VERSION=\"2.45.3\""))
        #expect(installer.contains("0c90f4d28ca57335f9fa78cf5bf6dabfe20a232036dabe36de2eef79cb7c0878"))
        #expect(installer.contains("--proto '=https'"))
        #expect(installer.contains("shasum -a 256 -c -"))
        #expect(!installer.contains("brew install"))
        #expect(fixtureScript.contains("COCXY_CI_REMOTE_DAEMON_FIXTURE"))
        #expect(fixtureScript.contains("x86_64-linux-musl"))
        #expect(fixtureScript.contains("aarch64-linux-musl"))
        #expect(fixtureScript.contains("xcrun clang -arch arm64"))

        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun"),
              let path = ProcessInfo.processInfo.environment["PATH"],
              path.split(separator: ":").contains(where: {
                  FileManager.default.isExecutableFile(atPath: String($0) + "/zig")
              }) else {
            return
        }

        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-ci-core-fixture-\(UUID().uuidString)", isDirectory: true)
        let fixtureRoot = temporaryRoot.appendingPathComponent("cocxycore", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let prepare = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [fixtureScriptURL.path, fixtureRoot.path]
        )
        #expect(prepare.terminationStatus == 0, "CI fixture preparation failed")

        let buildScript = fixtureRoot.appendingPathComponent("scripts/build.sh")
        let withoutOptIn = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [buildScript.path, "build"]
        )
        #expect(withoutOptIn.terminationStatus == 77)

        let build = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [buildScript.path, "build"],
            environment: ["COCXY_CI_REMOTE_DAEMON_FIXTURE": "1"]
        )
        #expect(build.terminationStatus == 0, "CI fixture compilation failed")

        let binaries = fixtureRoot.appendingPathComponent("zig-out/bin", isDirectory: true)
        let macOSMagic = try Data(
            contentsOf: binaries.appendingPathComponent("cocxyd-remote-macos-arm64")
        ).prefix(4)
        let linuxMagic = try Data(
            contentsOf: binaries.appendingPathComponent("cocxyd-remote-linux-x86_64")
        ).prefix(4)
        #expect(macOSMagic == Data([0xCF, 0xFA, 0xED, 0xFE]))
        #expect(linuxMagic == Data([0x7F, 0x45, 0x4C, 0x46]))
    }

    @Test("SwiftPM release inputs are tracked exact and fail closed")
    func swiftPMReleaseInputsAreTrackedExactAndFailClosed() throws {
        let root = repositoryRoot()
        let manifest = try String(
            contentsOf: root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        let lockURL = root.appendingPathComponent("Package.resolved")
        let lock = try JSONSerialization.jsonObject(with: Data(contentsOf: lockURL)) as? [String: Any]
        let pins = lock?["pins"] as? [[String: Any]]
        let sparkle = pins?.first { $0["identity"] as? String == "sparkle" }
        let state = sparkle?["state"] as? [String: Any]
        let gitignore = try String(
            contentsOf: root.appendingPathComponent(".gitignore"),
            encoding: .utf8
        )
        let verifierURL = root.appendingPathComponent("scripts/verify-swiftpm-resolution.sh")
        let verifier = try String(contentsOf: verifierURL, encoding: .utf8)
        let buildScript = try String(
            contentsOf: root.appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )
        let bundleVerifier = try String(
            contentsOf: root.appendingPathComponent("scripts/verify-app-bundle.sh"),
            encoding: .utf8
        )
        let ci = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/ci.yml"),
            encoding: .utf8
        )
        let automatedScripts = [
            "scripts/run-tests.sh",
            "scripts/run-swift-testing-serial.sh",
            "scripts/run-performance-benchmarks.sh",
            "scripts/run-cocxycore-benchmarks.sh",
            "scripts/run-security-audit.sh",
        ]
        let releaseWorkflows = ["release.yml", "preview.yml", "nightly.yml"]

        #expect(manifest.contains(#".package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.4")"#))
        #expect(!manifest.contains(#"Sparkle", from:"#))
        #expect(lock?["version"] as? Int == 3)
        #expect(pins?.filter { $0["identity"] as? String == "sparkle" }.count == 1)
        #expect(sparkle?["kind"] as? String == "remoteSourceControl")
        #expect(sparkle?["location"] as? String == "https://github.com/sparkle-project/Sparkle")
        #expect(state?["version"] as? String == "2.9.4")
        #expect(state?["revision"] as? String == "b6496a74a087257ef5e6da1c5b29a447a60f5bd7")
        #expect(!gitignore.components(separatedBy: .newlines).contains("Package.resolved"))

        #expect(FileManager.default.isExecutableFile(atPath: verifierURL.path))
        #expect(verifier.contains("cb6fdbdc8884f15d62a616e79face92b08322410fd2d425edc6596ccbf4ba3b0"))
        #expect(verifier.contains("bfb52400c3da18bb4c251ac4818c2c2e1e31c2e649a45b31c11109b6e57b34ad"))
        #expect(verifier.contains("ls-files --error-unmatch Package.resolved"))
        #expect(verifier.contains("lipo \"${SPARKLE_TOOL}\" -verify_arch x86_64 arm64"))
        #expect(buildScript.contains("SWIFT_FLAGS=\"--disable-automatic-resolution -c release\""))
        #expect(buildScript.contains("SWIFT_FLAGS=\"--disable-automatic-resolution\""))
        #expect(buildScript.contains("verify-swiftpm-resolution.sh\" --lock-only"))
        #expect(buildScript.contains("verify-swiftpm-resolution.sh\" --verify-artifacts"))
        #expect(buildScript.contains(".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"))
        #expect(!buildScript.contains("find \"${PROJECT_ROOT}/.build\" -name \"Sparkle.framework\""))
        #expect(bundleVerifier.contains("CFBundleShortVersionString\" \"2.9.4\" \"Reviewed Sparkle version"))
        #expect(bundleVerifier.contains("check_codesign_valid \"$SPARKLE_FRAMEWORK\" \"Sparkle.framework signature\""))
        #expect(ci.contains("swift build --disable-automatic-resolution -c debug"))
        #expect(ci.contains("swift build --disable-automatic-resolution -c release"))

        for path in automatedScripts {
            let contents = try String(
                contentsOf: root.appendingPathComponent(path),
                encoding: .utf8
            )
            #expect(contents.contains("--disable-automatic-resolution"), "Unlocked SwiftPM automation: \(path)")
        }
        for workflowName in releaseWorkflows {
            let workflow = try String(
                contentsOf: root.appendingPathComponent(".github/workflows/\(workflowName)"),
                encoding: .utf8
            )
            #expect(workflow.contains("verify-swiftpm-resolution.sh --print-sign-update"))
            #expect(!workflow.contains("find .build -name \"sign_update\""))
        }

        let lockVerification = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [verifierURL.path, "--lock-only"]
        )
        #expect(lockVerification.terminationStatus == 0)
        let artifactVerification = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [verifierURL.path, "--verify-artifacts"]
        )
        #expect(artifactVerification.terminationStatus == 0)
    }

    @Test("performance workflow enforces benchmark regression baselines")
    func performanceWorkflowEnforcesBenchmarkRegressionBaselines() throws {
        let root = repositoryRoot()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/performance.yml"),
            encoding: .utf8
        )
        let scriptURL = root.appendingPathComponent("scripts/check-performance-regression.py")
        let memoryScriptURL = root.appendingPathComponent("scripts/bench-memory-baseline.sh")
        let memoryScript = try String(contentsOf: memoryScriptURL, encoding: .utf8)
        let baselinesURL = root.appendingPathComponent("scripts/performance-baselines.json")
        let baselinePayload = try JSONSerialization.jsonObject(
            with: Data(contentsOf: baselinesURL),
            options: []
        ) as? [String: Any]
        let ciBaselinesURL = root.appendingPathComponent("scripts/performance-baselines.macos15-ci.json")
        let ciBaselinePayload = try JSONSerialization.jsonObject(
            with: Data(contentsOf: ciBaselinesURL),
            options: []
        ) as? [String: Any]
        let ciMetrics = ciBaselinePayload?["metrics"] as? [[String: Any]]
        let ciMetric: (String) -> [String: Any]? = { metricName in
            ciMetrics?.first { $0["name"] as? String == metricName }
        }

        #expect(FileManager.default.isExecutableFile(atPath: scriptURL.path))
        #expect(workflow.contains("tee build/performance/cold-start.json"))
        #expect(workflow.contains("tee build/performance/memory-baseline.json"))
        #expect(workflow.contains("tee build/performance/benchmark-suite.log"))
        #expect(workflow.contains("scripts/check-performance-regression.py"))
        #expect(workflow.contains("COCXY_COLD_START_BUDGET_MS: \"800\""))
        #expect(workflow.contains("COCXY_COLD_START_INTERNAL_BUDGET_MS: \"125\""))
        #expect(workflow.contains("COCXY_PERFORMANCE_BASELINE: scripts/performance-baselines.macos15-ci.json"))
        #expect(workflow.contains("COCXY_SYNTAX_INCREMENTAL_PARSE_BUDGET_MS: \"20\""))
        #expect(workflow.contains("COCXYCORE_OUTPUT_THROUGHPUT_BUDGET_MBPS: \"0.8\""))
        #expect(workflow.contains("timeout-minutes: 75"))
        #expect(workflow.contains("timeout-minutes: 60"))
        #expect(workflow.contains("--baseline \"$COCXY_PERFORMANCE_BASELINE\""))
        #expect(workflow.contains("Cleanup CocxyTerminal processes"))
        #expect(workflow.contains("pkill -x CocxyTerminal || true"))
        #expect(workflow.contains("--enforce"))
        #expect(baselinePayload?["default_tolerance_ratio"] as? Double == 0.1)
        #expect((baselinePayload?["metrics"] as? [[String: Any]])?.isEmpty == false)
        #expect(ciBaselinePayload?["default_tolerance_ratio"] as? Double == 0.1)
        #expect(ciMetrics?.contains {
            $0["name"] as? String == "app_readiness_median_ms"
                && ($0["baseline"] as? NSNumber)?.doubleValue == 800
        } == true)
        #expect(ciMetrics?.contains {
            $0["name"] as? String == "internal_critical_path_median_ms"
                && ($0["baseline"] as? NSNumber)?.doubleValue == 100
        } == true)
        #expect((ciMetric("syntax_cold_parse_ms")?["baseline"] as? NSNumber)?.doubleValue == 16.0)
        #expect((ciMetric("syntax_cold_parse_ms")?["absolute_tolerance"] as? NSNumber)?.doubleValue == 4.0)
        #expect((ciMetric("editor_scroll_frame_ms")?["baseline"] as? NSNumber)?.doubleValue == 11.0)
        #expect((ciMetric("editor_insert_frame_ms")?["baseline"] as? NSNumber)?.doubleValue == 15.0)
        #expect((ciMetric("editor_insert_frame_ms")?["absolute_tolerance"] as? NSNumber)?.doubleValue == 3.0)
        #expect((ciMetric("editor_delete_frame_ms")?["baseline"] as? NSNumber)?.doubleValue == 13.0)
        #expect((ciMetric("editor_delete_frame_ms")?["absolute_tolerance"] as? NSNumber)?.doubleValue == 3.0)
        #expect((ciMetric("syntax_viewport_capture_ms")?["baseline"] as? NSNumber)?.doubleValue == 7.7)
        #expect((ciMetric("syntax_viewport_capture_ms")?["absolute_tolerance"] as? NSNumber)?.doubleValue == 2.3)
        #expect((ciMetric("syntax_token_mapping_ms")?["baseline"] as? NSNumber)?.doubleValue == 0.85)
        #expect((ciMetric("syntax_token_mapping_ms")?["absolute_tolerance"] as? NSNumber)?.doubleValue == 0.35)
        #expect((ciMetric("syntax_viewport_highlight_ms")?["baseline"] as? NSNumber)?.doubleValue == 25.0)
        #expect((ciMetric("syntax_viewport_highlight_ms")?["absolute_tolerance"] as? NSNumber)?.doubleValue == 5.0)
        #expect((ciMetric("syntax_incremental_parse_ms")?["baseline"] as? NSNumber)?.doubleValue == 16.0)
        #expect((ciMetric("syntax_incremental_parse_ms")?["absolute_tolerance"] as? NSNumber)?.doubleValue == 4.0)
        #expect((ciMetric("cocxycore_surface_creation_ms")?["baseline"] as? NSNumber)?.doubleValue == 215.0)
        #expect((ciMetric("cocxycore_surface_creation_ms")?["absolute_tolerance"] as? NSNumber)?.doubleValue == 35.0)
        #expect((ciMetric("cocxycore_echo_latency_ms")?["baseline"] as? NSNumber)?.doubleValue == 10.0)
        #expect((ciMetric("cocxycore_output_throughput_mbps")?["baseline"] as? NSNumber)?.doubleValue == 1.0)
        #expect((ciMetric("cocxycore_output_throughput_mbps")?["absolute_tolerance"] as? NSNumber)?.doubleValue == 0.2)
        #expect((ciMetric("cocxycore_frame_average_ms")?["baseline"] as? NSNumber)?.doubleValue == 2.6)
        #expect((ciMetric("cocxycore_frame_average_ms")?["absolute_tolerance"] as? NSNumber)?.doubleValue == 0.6)
        #expect((ciMetric("cocxycore_frame_p99_ms")?["baseline"] as? NSNumber)?.doubleValue == 6.5)
        #expect((ciMetric("cocxycore_frame_p99_ms")?["absolute_tolerance"] as? NSNumber)?.doubleValue == 1.5)
        #expect((ciMetric("cocxycore_idle_rss_delta_mb")?["baseline"] as? NSNumber)?.doubleValue == 3.0)
        #expect(FileManager.default.isExecutableFile(atPath: memoryScriptURL.path))
        #expect(memoryScript.contains("BENCHMARK_ENV=\"COCXY_MEMORY_BASELINE_BENCHMARK=1\""))
        #expect(memoryScript.contains("/usr/bin/open -n --env \"$BENCHMARK_ENV\" \"$APP_PATH\""))
        #expect(memoryScript.contains("find_benchmark_pid"))
        #expect(memoryScript.contains("trap cleanup EXIT"))
        #expect(memoryScript.contains("Cocxy Terminal is already running outside this benchmark."))
        #expect(memoryScript.contains("Close it cleanly before running memory-baseline measurements."))
        #expect(memoryScript.contains("COCXY_BENCH_FORCE_KILL"))
        #expect(!memoryScript.contains("pkill -x CocxyTerminal"))
    }

    @Test("prepare release script has a non-mutating dry run preflight")
    func prepareReleaseScriptHasDryRunPreflight() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/prepare-release.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/prepare-release.yml"),
            encoding: .utf8
        )

        #expect(FileManager.default.isExecutableFile(atPath: scriptURL.path))
        #expect(script.contains("[--dry-run] <version>"))
        #expect(script.contains("ROOT_DIR="))
        #expect(script.contains("GH_BIN="))
        #expect(script.contains("version_greater_than()"))
        #expect(script.contains("CFBundleShortVersionString"))
        #expect(script.contains("must not be older than current Info.plist version"))
        #expect(script.contains("/opt/homebrew/bin/gh /usr/local/bin/gh"))
        #expect(script.contains("cd \"$ROOT_DIR\""))
        #expect(script.contains("git ls-remote --tags origin"))
        #expect(script.contains("already exists on origin"))
        #expect(script.contains("\"$GH_BIN\" auth status"))
        #expect(script.contains("\"$GH_BIN\" api --method POST"))
        #expect(script.contains("event_type=prepare-stable-release"))
        #expect(script.contains(".github/workflows/prepare-release.yml"))
        #expect(script.contains("DRY_RUN=1"))
        #expect(script.contains("No GitHub workflow was triggered."))
        #expect(workflow.contains("git config user.name \"Said Arturo Lopez\""))
        #expect(workflow.contains("git config user.email \"dev@cocxy.dev\""))
        #expect(workflow.contains("git push origin HEAD:main"))
        #expect(workflow.contains("Target version ${VERSION} is older than current Info.plist version ${CURRENT}."))
        #expect(workflow.contains("github.event.client_payload.version"))
        #expect(!workflow.contains("git config user.name \"said lopez\""))

        let dryRunRange = try #require(script.range(of: "if [ \"$DRY_RUN\" -eq 1 ]; then"))
        let dispatchRange = try #require(script.range(of: "\"$GH_BIN\" api --method POST"))
        #expect(dryRunRange.lowerBound < dispatchRange.lowerBound)
    }

    @Test("release workflow uses the shared app bundle builder")
    func releaseWorkflowUsesSharedAppBundleBuilder() throws {
        let root = repositoryRoot()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        #expect(workflow.contains("./scripts/build-app.sh release --version \"$VERSION\""))
        #expect(workflow.contains("mv build/CocxyTerminal.app \"build/Cocxy Terminal.app\""))
        #expect(workflow.contains("./scripts/verify-app-bundle.sh \"$APP_DIR\""))
        #expect(!workflow.contains("cp \".build/arm64-apple-macosx/release/CocxyTerminal\" \"$MACOS_DIR/Cocxy Terminal\""))
        #expect(!workflow.contains("[ -d Resources/Markdown ] && cp -R Resources/Markdown \"$RESOURCES_DIR/\" || true"))
    }

    @Test("release workflow fails if Homebrew cask update does not publish")
    func releaseWorkflowFailsIfHomebrewCaskUpdateDoesNotPublish() throws {
        let root = repositoryRoot()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        let homebrewStart = try #require(workflow.range(of: "- name: Update Homebrew Cask"))
        let homebrewBlock = String(workflow[homebrewStart.lowerBound..<workflow.endIndex])
        #expect(homebrewBlock.contains("git config user.name \"Said Arturo Lopez\""))
        #expect(homebrewBlock.contains("git config user.email \"dev@cocxy.dev\""))
        #expect(homebrewBlock.contains("git diff --cached --quiet"))
        #expect(homebrewBlock.contains("Homebrew cask did not change"))
        #expect(homebrewBlock.contains("git commit -m \"Update cocxy to ${VERSION}\""))
        #expect(homebrewBlock.contains("git push"))
        #expect(!homebrewBlock.contains("git commit -m \"Update cocxy to ${VERSION}\" || true"))
        #expect(!homebrewBlock.contains("git push || true"))
    }

    @Test("release workflow fails if changelog publish does not land")
    func releaseWorkflowFailsIfChangelogPublishDoesNotLand() throws {
        let root = repositoryRoot()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        let changelogStart = try #require(workflow.range(of: "- name: Update CHANGELOG on main"))
        let deployStart = try #require(workflow.range(of: "- name: Deploy website"))
        let changelogBlock = String(workflow[changelogStart.lowerBound..<deployStart.lowerBound])
        #expect(changelogBlock.contains("git config user.name \"Said Arturo Lopez\""))
        #expect(changelogBlock.contains("git config user.email \"dev@cocxy.dev\""))
        #expect(changelogBlock.contains("git commit -m \"docs: update CHANGELOG for v${VERSION}\""))
        #expect(changelogBlock.contains("git push origin HEAD:main"))
        #expect(!changelogBlock.contains("said lopez"))
        #expect(!changelogBlock.contains("git push origin HEAD:main ||"))
        #expect(!changelogBlock.contains("Push to main failed"))
    }

    @Test("release workflow fails if existing website assets do not deploy")
    func releaseWorkflowFailsIfExistingWebsiteAssetsDoNotDeploy() throws {
        let root = repositoryRoot()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )
        let runtimeScriptURL = root.appendingPathComponent("web/scripts/restart-production-runtime.sh")
        let runtimeScript = try String(contentsOf: runtimeScriptURL, encoding: .utf8)

        let deployStart = try #require(workflow.range(of: "- name: Deploy website"))
        let homebrewStart = try #require(workflow.range(of: "- name: Update Homebrew Cask"))
        let deployBlock = String(workflow[deployStart.lowerBound..<homebrewStart.lowerBound])
        #expect(deployBlock.contains(#"case "$DEPLOY_PATH" in"#))
        #expect(deployBlock.contains(#"*) DEPLOY_PATH="${DEPLOY_PATH}/" ;;"#))
        #expect(deployBlock.contains("mkdir -p ${DEPLOY_PATH} ${DEPLOY_PATH}css ${DEPLOY_PATH}js ${DEPLOY_PATH}images ${DEPLOY_PATH}es"))
        #expect(deployBlock.contains("if [ -d web/public/js ]; then"))
        #expect(deployBlock.contains("web/public/css/* ${DEPLOY_TARGET}:${DEPLOY_PATH}css/"))
        #expect(deployBlock.contains("web/public/js/* ${DEPLOY_TARGET}:${DEPLOY_PATH}js/"))
        #expect(deployBlock.contains("node web/scripts/generate-releases-page.mjs"))
        #expect(deployBlock.contains("build/releases.html ${DEPLOY_TARGET}:${DEPLOY_PATH}releases.html"))
        #expect(deployBlock.contains("build/es/releases.html ${DEPLOY_TARGET}:${DEPLOY_PATH}es/releases.html"))
        #expect(deployBlock.contains("web/server.js web/package.json web/package-lock.json web/ecosystem.config.js"))
        #expect(deployBlock.contains("web/scripts/restart-production-runtime.sh"))
        #expect(deployBlock.contains("npm ci --omit=dev --ignore-scripts --no-audit --no-fund"))
        #expect(deployBlock.contains("main.js?v=${ASSET_VERSION}"))
        #expect(deployBlock.contains("theme-switcher.js?v=${ASSET_VERSION}"))
        #expect(deployBlock.contains("cocxy-preview.png?v=${ASSET_VERSION}"))
        #expect(deployBlock.contains(#"export PATH=\"\$HOME/.npm-global/bin:\$HOME/.npm/bin:\$HOME/.local/bin:\$HOME/.nvm/current/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:\$PATH\""#))
        #expect(deployBlock.contains(#"if [ -s \"\$HOME/.nvm/nvm.sh\" ]; then . \"\$HOME/.nvm/nvm.sh\""#))
        #expect(deployBlock.contains("chmod +x restart-production-runtime.sh"))
        #expect(deployBlock.contains("./restart-production-runtime.sh"))
        #expect(FileManager.default.isExecutableFile(atPath: runtimeScriptURL.path))
        #expect(runtimeScript.contains("./node_modules/.bin/pm2"))
        #expect(runtimeScript.contains(#""$PM2_BIN" reload "$APP_NAME" --update-env"#))
        #expect(runtimeScript.contains(#""$PM2_BIN" start ecosystem.config.js --only "$APP_NAME""#))
        #expect(runtimeScript.contains("matching_node_server_pids"))
        #expect(runtimeScript.contains("port_listener_pids"))
        #expect(runtimeScript.contains("matching_port_pids"))
        #expect(runtimeScript.contains(#"[ "$cwd" = "$APP_DIR" ]"#))
        #expect(runtimeScript.contains("no listener PID was available; leaving it in place."))
        #expect(runtimeScript.contains(#"nohup env NODE_ENV=production PORT="$PORT" "$NODE_BIN" server.js"#))
        #expect(runtimeScript.contains(#""http://127.0.0.1:${PORT}/health""#))
        #expect(!deployBlock.contains("web/public/js/* ${DEPLOY_TARGET}:${DEPLOY_PATH}js/ || true"))
    }

    @Test("manual website deploy workflow validates static site and restarts server runtime")
    func manualWebsiteDeployWorkflowValidatesStaticSiteAndRestartsServerRuntime() throws {
        let root = repositoryRoot()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/deploy-website.yml"),
            encoding: .utf8
        )
        let runtimeScript = try String(
            contentsOf: root.appendingPathComponent("web/scripts/restart-production-runtime.sh"),
            encoding: .utf8
        )
        let serverScript = try String(
            contentsOf: root.appendingPathComponent("web/server.js"),
            encoding: .utf8
        )

        #expect(workflow.contains("workflow_dispatch:"))
        #expect(workflow.contains("environment: production"))
        #expect(workflow.contains("npm run smoke"))
        #expect(workflow.contains("npm audit --audit-level=high"))
        #expect(workflow.contains("npm audit signatures"))
        #expect(workflow.contains("npm run smoke:visual"))
        #expect(workflow.contains("npm run audit:quality:full"))
        #expect(workflow.contains("node scripts/generate-releases-page.mjs"))
        #expect(workflow.contains("tar -czf /tmp/${BACKUP_NAME} -C ${DEPLOY_PATH} ."))
        #expect(workflow.contains("web/public/css/* ${DEPLOY_TARGET}:${DEPLOY_PATH}css/"))
        #expect(workflow.contains("web/public/js/* ${DEPLOY_TARGET}:${DEPLOY_PATH}js/"))
        #expect(workflow.contains("build/releases.html ${DEPLOY_TARGET}:${DEPLOY_PATH}releases.html"))
        #expect(workflow.contains("build/es/releases.html ${DEPLOY_TARGET}:${DEPLOY_PATH}es/releases.html"))
        #expect(workflow.contains("web/server.js web/package.json web/package-lock.json web/ecosystem.config.js"))
        #expect(workflow.contains("web/scripts/restart-production-runtime.sh"))
        #expect(workflow.contains("npm ci --omit=dev --ignore-scripts --no-audit --no-fund"))
        #expect(workflow.contains("main.js?v=${ASSET_VERSION}"))
        #expect(workflow.contains("theme-switcher.js?v=${ASSET_VERSION}"))
        #expect(workflow.contains("cocxy-preview.png?v=${ASSET_VERSION}"))
        #expect(workflow.contains(#"export PATH=\"\$HOME/.npm-global/bin:\$HOME/.npm/bin:\$HOME/.local/bin:\$HOME/.nvm/current/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:\$PATH\""#))
        #expect(workflow.contains(#"if [ -s \"\$HOME/.nvm/nvm.sh\" ]; then . \"\$HOME/.nvm/nvm.sh\""#))
        #expect(workflow.contains("chmod +x restart-production-runtime.sh"))
        #expect(workflow.contains("./restart-production-runtime.sh"))
        #expect(runtimeScript.contains("node not found in deploy environment and pm2 is unavailable"))
        #expect(runtimeScript.contains("cocxy-web failed to stay running after fallback start"))
        #expect(runtimeScript.contains("cocxy-web did not pass local health check"))
        #expect(runtimeScript.contains("port_listener_pids | tr"))
        #expect(serverScript.contains("PUBLIC_ROOT"))
        #expect(serverScript.contains("isPublicRequestPath"))
        #expect(serverScript.contains(#"dotfiles: "ignore""#))
        #expect(serverScript.contains("no-cache, no-transform, max-age=0, must-revalidate"))
        #expect(workflow.contains("https://cocxy.dev/getting-started.html"))
        #expect(workflow.contains(#"test "$REDIRECT_STATUS" = "301""#))
        #expect(workflow.contains(#"SMOKE_DIR="$(mktemp -d)""#))
        #expect(workflow.contains(#"curl -fsSL https://cocxy.dev/ -o "$SMOKE_DIR/home.html""#))
        #expect(workflow.contains(#"grep -qi "cache-control: .*no-transform" "$SMOKE_DIR/home.headers""#))
        #expect(workflow.contains(#"grep -q "style.css?v=${ASSET_VERSION}" "$SMOKE_DIR/home.html""#))
        #expect(workflow.contains(#"grep -q "main.js?v=${ASSET_VERSION}" "$SMOKE_DIR/home.html""#))
        #expect(workflow.contains(#"grep -q "theme-switcher.js?v=${ASSET_VERSION}" "$SMOKE_DIR/home.html""#))
        #expect(!workflow.contains("curl -fsSL https://cocxy.dev/ | grep -q"))
        #expect(!workflow.contains("|| true"))
    }

    @Test("preview workflow runs website quality gates without publishing from pull requests")
    func previewWorkflowRunsWebsiteQualityGatesWithoutPublishingFromPullRequests() throws {
        let root = repositoryRoot()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/preview.yml"),
            encoding: .utf8
        )

        #expect(workflow.contains("pull_request:"))
        #expect(workflow.contains("- 'web/**'"))
        #expect(workflow.contains("website-quality:"))
        #expect(workflow.contains("name: Website Quality"))
        #expect(workflow.contains("timeout-minutes: 45"))
        #expect(workflow.contains("permissions:\n      contents: read"))
        #expect(workflow.contains("working-directory: web"))
        #expect(workflow.contains("npm ci --ignore-scripts --no-audit --no-fund"))
        #expect(workflow.contains("npm run smoke"))
        #expect(workflow.contains("npm audit --audit-level=high"))
        #expect(workflow.contains("npm audit signatures"))
        #expect(workflow.contains("npm run smoke:visual"))
        #expect(workflow.contains("npm run audit:quality:full"))
        #expect(workflow.contains("request-preview:"))
        #expect(workflow.contains("event_type=preview-release"))
        #expect(workflow.contains("build-preview:"))
        #expect(workflow.contains("if: github.event_name == 'repository_dispatch' && github.ref == 'refs/heads/main'"))
        #expect(workflow.contains("contents: write"))
    }

    @Test("web quality audit keeps strict Lighthouse gates when CI runner hits Lantern zero-score")
    func webQualityAuditKeepsStrictLighthouseGatesWhenCIRunnerHitsLanternZeroScore() throws {
        let root = repositoryRoot()
        let auditScript = try String(
            contentsOf: root.appendingPathComponent("web/scripts/quality-audit.mjs"),
            encoding: .utf8
        )

        #expect(auditScript.contains("shouldRerunLighthouseWithDevtools"))
        #expect(auditScript.contains("throttlingMethod: method"))
        #expect(auditScript.contains("lighthouseDevtoolsFallback"))
        #expect(auditScript.contains("lighthouseProvidedFallback"))
        #expect(auditScript.contains("COCXY_WEB_LIGHTHOUSE_PROVIDED_FALLBACK"))
        #expect(auditScript.contains("lighthouseDesktopFallback"))
        #expect(auditScript.contains("COCXY_WEB_LIGHTHOUSE_DESKTOP_FALLBACK"))
        #expect(auditScript.contains("lighthouseBorderlineRetryMargin"))
        #expect(auditScript.contains("rerunning in isolated Chrome"))
        #expect(auditScript.contains("provided throttling in isolated Chrome"))
        #expect(auditScript.contains("runIsolatedLighthouse(url, 'provided')"))
        #expect(auditScript.contains("desktop provided in isolated Chrome"))
        #expect(auditScript.contains("runIsolatedLighthouse(url, 'provided', 'desktop')"))
        #expect(auditScript.contains("formFactor: lighthouseResult.formFactor"))
        #expect(auditScript.contains("fallbackFrom: fallbackFrom ? primaryMethod : null"))
        #expect(auditScript.contains("performance: 0"))
        #expect(auditScript.contains("'best-practices': 0"))
        #expect(auditScript.contains("Lighthouse ${category} on ${url} scored ${score}, below ${threshold}"))
        #expect(!auditScript.contains("if (process.env.CI"))
        #expect(!auditScript.contains("|| true"))
    }

    @Test("release readiness script documents external blockers")
    func releaseReadinessScriptDocumentsExternalBlockers() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/check-release-readiness.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(FileManager.default.isExecutableFile(atPath: scriptURL.path))
        #expect(script.contains("set -euo pipefail"))
        #expect(script.contains("--enforce"))
        #expect(script.contains("--version"))
        #expect(script.contains("--require-public-release"))
        #expect(script.contains("--require-critical-coverage"))
        #expect(script.contains("--critical-coverage"))
        #expect(script.contains("RELEASE_PUSH_TOKEN"))
        #expect(script.contains("DEVELOPER_ID_P12"))
        #expect(script.contains("DEVELOPER_ID_PASSWORD"))
        #expect(script.contains("SIGNING_IDENTITY"))
        #expect(script.contains("APPLE_ID"))
        #expect(script.contains("APPLE_TEAM_ID"))
        #expect(script.contains("APPLE_APP_PASSWORD"))
        #expect(script.contains("SPARKLE_PRIVATE_KEY"))
        #expect(script.contains("HOMEBREW_TAP_TOKEN"))
        #expect(script.contains("LIGHTSAIL_SSH_KEY"))
        #expect(script.contains("DEPLOY_HOST"))
        #expect(script.contains("POSTGRES_URL"))
        #expect(script.contains("AWS_ACCESS_KEY_ID"))
        #expect(script.contains("git status --porcelain --untracked-files=no"))
        #expect(script.contains("git config user.email"))
        #expect(script.contains("origin/main..HEAD"))
        #expect(script.contains("private_trace_pattern"))
        #expect(script.contains("fetch_public_payload"))
        #expect(script.contains("http ${appcast_status}"))
        #expect(script.contains("http ${homepage_status}"))
        #expect(script.contains("http ${releases_status}"))
        #expect(script.contains("http ${spanish_homepage_status}"))
        #expect(script.contains("http ${spanish_releases_status}"))
        #expect(script.contains("CocxyTerminal-${VERSION}.dmg"))
        #expect(script.contains("build/appcast.xml"))
        #expect(script.contains("gh release view \"v${VERSION}\""))
        #expect(script.contains("latest_release_tag"))
        #expect(script.contains("https://cocxy.dev/appcast.xml"))
        #expect(script.contains("appcast_version"))
        #expect(script.contains("sparkle:shortVersionString=\\\"${VERSION}\\\""))
        #expect(script.contains("brew info --cask salp2403/tap/cocxy"))
        #expect(script.contains("brew_version"))
        #expect(script.contains("https://cocxy.dev/"))
        #expect(script.contains("homepage_version"))
        #expect(script.contains("https://cocxy.dev/releases.html"))
        #expect(script.contains("releases_version"))
        #expect(script.contains("https://cocxy.dev/es/"))
        #expect(script.contains("spanish_homepage_version"))
        #expect(script.contains("https://cocxy.dev/es/releases.html"))
        #expect(script.contains("spanish_releases_version"))
        #expect(script.contains("scripts/check-critical-coverage.py"))
        #expect(script.contains("critical coverage artifacts missing"))
        #expect(script.contains("critical coverage gate passed"))
        #expect(!script.contains(#"echo "${!name}""#))
    }

    @Test("release readiness report mode does not fail while blockers remain")
    func releaseReadinessReportModeDoesNotFailWhileBlockersRemain() throws {
        let root = repositoryRoot()
        let missingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-release-readiness-\(UUID().uuidString)", isDirectory: true)
        let result = try runProcess(
            root.appendingPathComponent("scripts/check-release-readiness.sh"),
            arguments: [
                "--version", "0.1.93",
                "--app", missingRoot.appendingPathComponent("Missing.app").path,
                "--dmg", missingRoot.appendingPathComponent("Missing.dmg").path,
                "--appcast", missingRoot.appendingPathComponent("missing-appcast.xml").path,
            ]
        )

        #expect(result.terminationStatus == 0)
        #expect(result.stdout.contains("Cocxy release readiness report"))
        #expect(result.stdout.contains("app bundle missing"))
        #expect(result.stdout.contains("Release readiness has"))
    }

    @Test("release readiness enforce mode fails closed while blockers remain")
    func releaseReadinessEnforceModeFailsClosedWhileBlockersRemain() throws {
        let root = repositoryRoot()
        let missingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-release-readiness-\(UUID().uuidString)", isDirectory: true)
        let result = try runProcess(
            root.appendingPathComponent("scripts/check-release-readiness.sh"),
            arguments: [
                "--enforce",
                "--version", "0.1.93",
                "--app", missingRoot.appendingPathComponent("Missing.app").path,
                "--dmg", missingRoot.appendingPathComponent("Missing.dmg").path,
                "--appcast", missingRoot.appendingPathComponent("missing-appcast.xml").path,
            ]
        )

        #expect(result.terminationStatus == 1)
        #expect(result.stdout.contains("Release readiness has"))
        #expect(result.stdout.contains("appcast missing"))
    }

    @Test("release workflow fails if required nested signing fails")
    func releaseWorkflowFailsIfRequiredNestedSigningFails() throws {
        let root = repositoryRoot()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )

        let signingStart = try #require(workflow.range(of: "- name: Code sign with Developer ID"))
        let dmgStart = try #require(workflow.range(of: "- name: Create DMG", range: signingStart.upperBound..<workflow.endIndex))
        let signingBlock = String(workflow[signingStart.lowerBound..<dmgStart.lowerBound])
        #expect(signingBlock.contains("\"$APP_DIR/Contents/Resources/cocxy\""))
        #expect(signingBlock.contains("\"$APP_DIR/Contents/Resources/cocxyd\""))
        #expect(signingBlock.contains("\"$APP_DIR/Contents/Library/LaunchServices/cocxyd.app\""))
        #expect(!signingBlock.contains("\"$APP_DIR/Contents/Resources/cocxy\" || true"))
        #expect(!signingBlock.contains("\"$APP_DIR/Contents/Resources/cocxyd\" || true"))
        #expect(!signingBlock.contains("\"$APP_DIR/Contents/Library/LaunchServices/cocxyd.app\" || true"))
    }

    @Test("nightly workflow uses shared app bundle builder")
    func nightlyWorkflowUsesSharedAppBundleBuilder() throws {
        let root = repositoryRoot()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/nightly.yml"),
            encoding: .utf8
        )

        #expect(workflow.contains("./scripts/build-app.sh release --version \"$VERSION\" --channel nightly"))
        #expect(workflow.contains("mv build/CocxyTerminalNightly.app \"$APP_DIR\""))
        #expect(workflow.contains("codesign --force --sign - --entitlements Resources/CocxyTerminal.entitlements \"$APP_DIR\""))
        #expect(workflow.contains("./scripts/verify-app-bundle.sh \"$APP_DIR\""))
        #expect(workflow.contains("https://cocxy.dev/appcast-nightly.xml"))
        #expect(!workflow.contains("cp \".build/arm64-apple-macosx/release/CocxyTerminal\" \"$MACOS_DIR/Cocxy Terminal Nightly\""))
        #expect(!workflow.contains("[ -d Resources/Markdown ] && cp -R Resources/Markdown \"$RESOURCES_DIR/\" || true"))
    }

    @Test("critical coverage checker reports and enforces configured modules")
    func criticalCoverageCheckerReportsAndEnforcesConfiguredModules() throws {
        let root = repositoryRoot()
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-critical-coverage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let configURL = fixtureRoot.appendingPathComponent("critical-coverage.json")
        let coverageURL = fixtureRoot.appendingPathComponent("coverage.json")
        try """
        {
          "threshold": 90,
          "modules": [
            {
              "name": "sample-critical",
              "include": ["Sources/Critical/*.swift"]
            }
          ]
        }
        """.write(to: configURL, atomically: true, encoding: .utf8)
        try """
        {
          "data": [
            {
              "files": [
                {
                  "filename": "\(root.path)/Sources/Critical/Auth.swift",
                  "summary": { "lines": { "count": 10, "covered": 7, "percent": 70.0 } }
                },
                {
                  "filename": "\(root.path)/Sources/Critical/Safe.swift",
                  "summary": { "lines": { "count": 10, "covered": 10, "percent": 100.0 } }
                }
              ]
            }
          ]
        }
        """.write(to: coverageURL, atomically: true, encoding: .utf8)

        let scriptURL = root.appendingPathComponent("scripts/check-critical-coverage.py")
        #expect(FileManager.default.isExecutableFile(atPath: scriptURL.path))

        let reportOnly = try runProcess(scriptURL, arguments: [
            "--config", configURL.path,
            "--coverage", coverageURL.path,
        ])
        #expect(reportOnly.terminationStatus == 0)
        #expect(reportOnly.stdout.contains("sample-critical"))
        #expect(reportOnly.stdout.contains("17/20"))
        #expect(reportOnly.stdout.contains("FAIL"))

        let enforced = try runProcess(scriptURL, arguments: [
            "--config", configURL.path,
            "--coverage", coverageURL.path,
            "--enforce",
        ])
        #expect(enforced.terminationStatus == 1)
        #expect(enforced.stdout.contains("Enforce mode"))
    }

    @Test("critical coverage config resolves every include pattern")
    func criticalCoverageConfigResolvesEveryIncludePattern() throws {
        let root = repositoryRoot()
        let configURL = root.appendingPathComponent("scripts/critical-coverage.json")
        let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: Any]
        let modules = try #require(payload?["modules"] as? [[String: Any]])
        let sourceFiles = try Self.files(
            under: root.appendingPathComponent("Sources", isDirectory: true),
            fileExtension: "swift"
        )
        .map { Self.relativePath($0, root: root) }

        for module in modules {
            let name = try #require(module["name"] as? String)
            let includes = try #require(module["include"] as? [String])
            for pattern in includes {
                #expect(
                    sourceFiles.contains { Self.matchesGlob($0, pattern: pattern) },
                    "\(name) include pattern should match a source file: \(pattern)"
                )
            }
        }
    }

    @Test("cold start enforce fails when the internal critical path is over budget")
    func coldStartEnforceFailsOnInternalCriticalPathRegression() throws {
        let root = repositoryRoot()
        let script = try String(
            contentsOf: root.appendingPathComponent("scripts/bench-cold-start.sh"),
            encoding: .utf8
        )

        #expect(script.contains("BENCHMARK_ENV=\"COCXY_COLD_START_BENCHMARK=1\""))
        #expect(script.contains("COCXY_COLD_START_BUDGET_MS"))
        #expect(script.contains("COCXY_COLD_START_INTERNAL_BUDGET_MS"))
        #expect(script.contains("--internal-critical-path-budget-ms"))
        #expect(script.contains("benchmark_pids"))
        #expect(script.contains("trap cleanup_benchmark_app EXIT"))
        #expect(script.contains("/usr/bin/open -n --env \"$BENCHMARK_ENV\" \"$APP_PATH\""))
        #expect(script.contains("Cocxy Terminal is already running outside this benchmark."))
        #expect(script.contains("COCXY_BENCH_FORCE_KILL"))
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

    @Test("remote browser local SSH smoke script verifies browser over forwarded port without CI flakiness")
    func remoteBrowserLocalSSHSmokeScriptIsManualAndBrowserBacked() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/smoke-remote-browser-local-ssh.sh")
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
        #expect(script.contains("-N -L"))
        #expect(script.contains("browser navigate"))
        #expect(script.contains("browser eval"))
        #expect(script.contains("browser screenshot --output"))
        #expect(script.contains("remote-browser-ok"))
        #expect(script.contains("asset-js-ok"))
        #expect(script.contains("favicon.svg"))
        #expect(script.contains("GET /asset.svg "))
        #expect(script.contains("GET /favicon.svg "))
        #expect(script.contains("status=skipped"))
        #expect(!ci.contains("smoke-remote-browser-local-ssh.sh"))
        #expect(!nightly.contains("smoke-remote-browser-local-ssh.sh"))
        #expect(!release.contains("smoke-remote-browser-local-ssh.sh"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)
    }

    @Test("remote browser Docker SSH smoke script is reproducible and manual only")
    func remoteBrowserDockerSSHSmokeScriptIsManualAndSkippable() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/smoke-remote-browser-docker-ssh.sh")
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
        #expect(script.contains("docker build"))
        #expect(script.contains("COCXY_REMOTE_BROWSER_DOCKER_BASE_IMAGE"))
        #expect(script.contains("COCXY_REMOTE_BROWSER_DOCKER_INSTALL_PACKAGES"))
        #expect(script.contains("--build-arg \"BASE_IMAGE=${BASE_IMAGE}\""))
        #expect(script.contains("docker run -d"))
        #expect(script.contains("status=skipped"))
        #expect(script.contains("artifactRoot=${ARTIFACT_ROOT}"))
        #expect(script.contains("docker daemon is not available"))
        #expect(script.contains("remote fixture was reachable without SSH forwarding"))
        #expect(script.contains("-N -L"))
        #expect(script.contains("browser navigate"))
        #expect(script.contains("browser eval"))
        #expect(script.contains("browser screenshot --output"))
        #expect(script.contains("remote-browser-ok"))
        #expect(script.contains("asset-js-ok"))
        #expect(script.contains("favicon.svg"))
        #expect(script.contains("passwd -d cocxy"))
        #expect(script.contains("AllowTcpForwarding=yes"))
        #expect(script.contains("PermitOpen=any"))
        #expect(!ci.contains("smoke-remote-browser-docker-ssh.sh"))
        #expect(!nightly.contains("smoke-remote-browser-docker-ssh.sh"))
        #expect(!release.contains("smoke-remote-browser-docker-ssh.sh"))

        let manifest = try runProcess(scriptURL, arguments: ["--matrix-manifest"])
        #expect(manifest.terminationStatus == 0)
        #expect(manifest.stdout.contains("scenario\tstatus\tproof"))

        let manifestLines = manifest.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
        #expect(manifestLines.count >= 14)

        for scenario in [
            "pre-forward-unreachable",
            "ssh-forward-reachable",
            "browser-navigate",
            "js-asset-load",
            "image-asset-load",
            "favicon-load",
            "screenshot",
            "hmac-invalid-token",
            "hmac-expired-token",
            "hmac-replay-token",
            "drag-drop-upload",
            "proxy-fallback",
            "dev-server-auto-discovery"
        ] {
            #expect(manifest.stdout.contains("\(scenario)\t"))
        }
        for implementedSecurityScenario in [
            "hmac-invalid-token",
            "hmac-expired-token",
            "hmac-replay-token"
        ] {
            #expect(manifest.stdout.contains("\(implementedSecurityScenario)\timplemented\t"))
        }
        #expect(manifest.stdout.contains("proxy-fallback\timplemented\t"))
        #expect(manifest.stdout.contains("dev-server-auto-discovery\timplemented\t"))
        #expect(manifest.stdout.contains("drag-drop-upload\timplemented\t"))
        #expect(script.contains("hmac.compare_digest"))
        #expect(script.contains("hmac-invalid-token.txt"))
        #expect(script.contains("hmac-expired-token.txt"))
        #expect(script.contains("hmac-replay-token.txt"))
        #expect(script.contains("drag-drop-upload.txt"))
        #expect(script.contains("browser upload"))
        #expect(script.contains("dev-server-auto-discovery.txt"))
        #expect(script.contains("ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null"))
        #expect(script.contains("proxy-fallback.txt"))
        #expect(script.contains("--proxy \"http://127.0.0.1:${BROKEN_PROXY_PORT}\""))
        #expect(script.contains("summary.txt"))
        #expect(script.contains("tee \"$ARTIFACT_ROOT/summary.txt\""))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)
    }

    @Test("Agent Workspace OS completion audit gate reports current closure state")
    func agentWorkspaceOSCompletionAuditGateReportsCurrentClosureState() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/audit-agent-workspace-os-completion.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        #expect(FileManager.default.isExecutableFile(atPath: scriptURL.path))
        #expect(script.contains("status=not-complete"))
        #expect(script.contains("plan-current-status-note=complete"))
        #expect(script.contains("source plan missing current complete status note"))
        #expect(script.contains("completion-audit-required-sections=present"))
        #expect(script.contains("FINAL_AUDIT_REPORT="))
        #expect(script.contains("2026-05-17-agent-workspace-os-completion-audit-final.md"))
        #expect(script.contains("completion-final-report=present"))
        #expect(script.contains("completion-final-report-status=not-complete"))
        #expect(script.contains("completion-final-report-status-consistency=matches-blockers"))
        #expect(script.contains("completion-final-report-required-sections=present"))
        #expect(script.contains("## Phase Status Matrix"))
        #expect(script.contains("check=cells-cloud-gcp-compute-api="))
        #expect(script.contains("latest_cells_cloud_provider_preflight()"))
        #expect(script.contains("record_cells_cloud_aws_latest_recheck"))
        #expect(script.contains("record_cells_cloud_latest_smoke_failure"))
        #expect(script.contains("cells-cloud-${provider}-latest-smoke="))
        #expect(script.contains("cells-cloud-${provider}-latest-smoke-status="))
        #expect(script.contains("cells-cloud-${provider}-latest-smoke-reason="))
        #expect(script.contains("cells-cloud-${provider}-latest-smoke-output="))
        #expect(script.contains("cells-cloud-aws-latest-recheck="))
        #expect(script.contains("cells-cloud-aws-latest-recheck-status="))
        #expect(script.contains("cells-cloud-aws-latest-recheck-missing-prerequisites="))
        #expect(script.contains("cells-cloud-aws-latest-recheck-latest-smoke-artifact="))
        #expect(script.contains("cells-cloud-aws-latest-recheck-latest-smoke-status="))
        #expect(script.contains("cells-cloud-aws-latest-recheck-latest-smoke-reason="))
        #expect(script.contains("cells-cloud-aws-latest-recheck-latest-smoke-output="))
        #expect(script.contains("cells-cloud-aws-latest-recheck-diagnostics="))
        #expect(script.contains("cells-cloud-aws-latest-recheck-instance-profile-check="))
        #expect(script.contains("cells-cloud-aws-latest-recheck-run-instances-dry-run="))
        #expect(script.contains("cells-cloud-aws-latest-recheck-run-instances-without-profile-dry-run="))
        #expect(script.contains("cells-cloud-aws-latest-recheck-ssm-runtime-policy-simulation="))
        #expect(script.contains("cells-cloud-aws-ssm-runtime-policy-simulation="))
        #expect(script.contains("cells-aws-setup-verify-latest="))
        #expect(script.contains("cells-aws-setup-verify-status="))
        #expect(script.contains("cells-aws-setup-verify-blockers="))
        #expect(script.contains("cells-aws-setup-verify-checks="))
        #expect(script.contains("cells-aws-setup-verify-remediation="))
        #expect(script.contains("record_cells_aws_readonly_diagnostics_summary()"))
        #expect(script.contains("cells-aws-readonly-diagnostics-latest="))
        #expect(script.contains("cells-aws-readonly-diagnostics-image-state="))
        #expect(script.contains("cells-aws-readonly-diagnostics-associations="))
        #expect(script.contains("cells-aws-readonly-diagnostics-simulate-principal-policy="))
        #expect(script.contains("record_cells_aws_direct_dryrun_summary()"))
        #expect(script.contains("cells-aws-direct-dryrun-latest="))
        #expect(script.contains("cells-aws-direct-dryrun-with-profile="))
        #expect(script.contains("cells-aws-direct-dryrun-without-profile="))
        #expect(script.contains("record_cells_aws_profile_diagnostics_summary()"))
        #expect(script.contains("cells-aws-profile-diagnostics-latest="))
        #expect(script.contains("cells-aws-profile-diagnostics-configured-profile-count="))
        #expect(script.contains("cells-aws-profile-diagnostics-list-instance-profiles="))
        #expect(script.contains("CELLS_AWS_READINESS_SEQUENCE="))
        #expect(script.contains("cells-aws-readiness-sequence=present"))
        #expect(script.contains("record_cells_aws_readiness_sequence()"))
        #expect(script.contains("latest_cells_aws_readiness_sequence_summary()"))
        #expect(script.contains("cells-aws-readiness-sequence-latest="))
        #expect(script.contains("cells-aws-readiness-sequence-status="))
        #expect(script.contains("cells-aws-readiness-sequence-result="))
        #expect(script.contains("cells-aws-readiness-sequence-aws-smoke="))
        #expect(script.contains("cells-aws-readiness-sequence-steps="))
        #expect(script.contains("cells-aws-readiness-sequence-self-audit="))
        #expect(script.contains("record_aws_owner_handoff()"))
        #expect(script.contains("latest_aws_setup_dry_run_summary()"))
        #expect(script.contains("cells-aws-setup-dryrun-latest="))
        #expect(script.contains("cells-aws-setup-principal-policy-passrole"))
        #expect(script.contains("cells-aws-setup-generated-verify-script="))
        #expect(script.contains("cells-aws-setup-generated-verify-script-dryrun-operation"))
        #expect(script.contains("cells-aws-setup-generated-verify-script-profile-arn-dry-run"))
        #expect(script.contains("cells-aws-setup-generated-verify-script-runner"))
        #expect(script.contains("cells-aws-owner-handoff="))
        #expect(script.contains("cells-aws-owner-handoff-image-export"))
        #expect(script.contains("cells-aws-owner-handoff-propagation-guardrail"))
        #expect(script.contains("cells-aws-owner-handoff-dryrun-not-runtime"))
        #expect(script.contains("cells-aws-owner-handoff-ssm-runtime-required"))
        #expect(script.contains("cells-aws-owner-handoff-secret-scan=clean"))
        #expect(script.contains("cells-aws-owner-handoff-guardrails=present"))
        #expect(script.contains("| AWS owner handoff is present, secret-clean, and guarded |"))
        #expect(script.contains("## Definition Of Done"))
        #expect(script.contains("result=cells-cloud-aws-ok"))
        #expect(script.contains("no longer reports AWS"))
        #expect(script.contains("check=cells-aws-setup-dryrun-latest="))
        #expect(script.contains("check=cells-aws-setup-principal-policy="))
        #expect(script.contains("check=cells-aws-setup-principal-policy-passrole="))
        #expect(script.contains("check=cells-aws-setup-generated-verify-script="))
        #expect(script.contains("check=cells-aws-setup-generated-verify-script-dryrun-operation="))
        #expect(script.contains("check=cells-aws-setup-generated-verify-script-profile-arn-dry-run="))
        #expect(script.contains("check=cells-aws-setup-generated-verify-script-runner="))
        #expect(script.contains("check=cells-aws-owner-handoff="))
        #expect(script.contains("check=cells-aws-owner-handoff-image-export="))
        #expect(script.contains("check=cells-aws-owner-handoff-propagation-guardrail="))
        #expect(script.contains("check=cells-aws-owner-handoff-dryrun-not-runtime="))
        #expect(script.contains("check=cells-aws-owner-handoff-ssm-runtime-required="))
        #expect(script.contains("check=cells-aws-owner-handoff-secret-scan="))
        #expect(script.contains("check=cells-aws-owner-handoff-guardrails="))
        #expect(script.contains("AWS owner handoff missing setup, verifier, preflight, smoke, readiness sequence, aggregate, definition-of-done, no-publish, or SSM-runtime guardrails"))
        #expect(script.contains("GCP/AWS cloud diagnostics/latest recheck/setup verifier/handoff checks"))
        #expect(script.contains("check=agent-workspace-product-ux-manual-acceptance="))
        #expect(script.contains("record_agent_workspace_plan_phase_statuses()"))
        #expect(script.contains("agent-workspace-plan-phase-0="))
        #expect(script.contains("agent-workspace-plan-phase-1="))
        #expect(script.contains("agent-workspace-plan-phase-2="))
        #expect(script.contains("agent-workspace-plan-phase-3="))
        #expect(script.contains("agent-workspace-plan-phase-4="))
        #expect(script.contains("agent-workspace-plan-phase-5="))
        #expect(script.contains("agent-workspace-plan-phase-6="))
        #expect(script.contains("agent-workspace-plan-phase-7="))
        #expect(script.contains("check=agent-workspace-plan-phase-0="))
        #expect(script.contains("check=agent-workspace-plan-phase-7="))
        #expect(script.contains("final_report_puerta_has_required_fields()"))
        #expect(script.contains("completion-final-report-puerta-${puerta_index}=initial-action-artifact-sha-verdict"))
        #expect(script.contains("missing Initial state, Action taken, Final artifact path with SHA-256, or Verdict"))
        #expect(script.contains("COMMAND_INSTRUCTION_DOC="))
        #expect(script.contains("${HOME}/claude-terminal/docs/commands/instruccion.md"))
        #expect(script.contains("command-instruction-doc=present"))
        #expect(script.contains("command-instruction-doc-path="))
        #expect(script.contains("command-instruction-doc-guards=present"))
        #expect(script.contains("no auto-acceptance of fabricated evidence"))
        #expect(script.contains("Do NOT auto-accept any human acceptance fields"))
        #expect(script.contains("Do NOT submit notarization to Apple"))
        #expect(script.contains("If any cloud smoke fails"))
        #expect(script.contains("Literal fresh audit output:"))
        #expect(script.contains("Prompt-To-Artifact Checklist"))
        #expect(script.contains("Completion Unlock Checklist"))
        #expect(script.contains("North strategic MCP support"))
        #expect(script.contains("North strategic Notebooks"))
        #expect(script.contains("North strategic Vault reuse and Code Review handoff"))
        #expect(script.contains("Docker limitation stated honestly"))
        #expect(script.contains("E2E matrix gate rejects partial verification"))
        #expect(script.contains("Docker live smoke refresh"))
        #expect(script.contains("docker-daemon=available"))
        #expect(script.contains("docker-daemon=unavailable"))
        #expect(script.contains("record_docker_runtime_diagnostics"))
        #expect(script.contains("colima status"))
        #expect(script.contains("limactl list"))
        #expect(script.contains("docker-colima=installed-not-running"))
        #expect(script.contains("docker-lima=rosetta-incompatible"))
        #expect(script.contains("Current Docker daemon unavailable"))
        #expect(script.contains("Remote Browser Docker SSH and Cells Docker live smokes cannot be refreshed"))
        #expect(script.contains("Cells cloud account E2E blocked"))
        #expect(script.contains("smoke-agent-workspace-e2e-matrices.sh"))
        #expect(script.contains("smoke-agent-workspace-a11y.sh"))
        #expect(script.contains("agent-workspace-e2e-matrices=9"))
        #expect(script.contains("E2E matrix audit reports"))
        #expect(script.contains("VoiceOver/WCAG acceptance artifact"))
        #expect(script.contains("voiceoverAcceptance=source-and-test"))
        #expect(script.contains("swiftTests=passed"))
        #expect(script.contains("attachUnsupported"))
        #expect(script.contains("cells-cloud-attach=e2b-fly-command-backed"))
        #expect(script.contains("E2B/Fly command-backed attach commands"))
        #expect(script.contains("smoke-remote-browser-docker-ssh.sh"))
        #expect(script.contains("smoke-cells-docker.sh"))
        #expect(script.contains("smoke-cells-local-ssh.sh"))
        #expect(script.contains("smoke-cells-cloud-account.sh"))
        #expect(script.contains("smoke-cells-operator.sh"))
        #expect(script.contains("preflight-cells-operator.sh"))
        #expect(script.contains("preflight-agent-workspace-release.sh"))
        #expect(script.contains("preflight-agent-workspace-product-ux.sh"))
        #expect(script.contains("preflight-agent-teams-provider-coverage.sh"))
        #expect(script.contains("smoke-agent-teams-graph-performance.sh"))
        #expect(script.contains("preflight-agent-teams-graph-performance.sh"))
        #expect(script.contains("latest_artifact_with_fields"))
        #expect(script.contains("latest_artifact()"))
        #expect(script.contains("artifact_field()"))
        #expect(script.contains("Sources/Domain/MCP/BrowserMCPTool.swift"))
        #expect(script.contains("spec\\(\"browser_"))
        #expect(script.contains("count_notebook_cli_commands"))
        #expect(script.contains("mcp-agent-integration=browser-and-configured"))
        #expect(script.contains("notebook-quicklook-contract=present"))
        #expect(script.contains("vault-visual-foundation=search-detector-sidebar"))
        #expect(script.contains("code-review-agent-team-handoff=present"))
        #expect(script.contains("MCP support incomplete"))
        #expect(script.contains("Notebook support incomplete"))
        #expect(script.contains("Vault base incomplete"))
        #expect(script.contains("Code Review integration incomplete"))
        #expect(script.contains("dev.cocxy.notebook"))
        #expect(script.contains("QuickLook Cocxy notebook content type"))
        #expect(script.contains("VaultBuiltInAgents.swift"))
        #expect(script.contains("AgentTeamReviewBeforeShipRequest"))
        #expect(script.contains("latest_cells_cloud_all_preflight()"))
        #expect(script.contains("record_cells_cloud_preflight_blockers()"))
        #expect(script.contains("Cells cloud preflight blocked:"))
        #expect(script.contains("missingPrerequisites="))
        #expect(script.contains("cells-cloud-preflight-latest"))
        #expect(script.contains("cells-cloud-preflight-scope=all"))
        #expect(script.contains("cells-cloud-preflight-provider-count=5"))
        #expect(script.contains("cells-cloud-preflight-blocked"))
        #expect(script.contains("cells-cloud-preflight-complete"))
        #expect(script.contains("cells-cloud-preflight-next"))
        #expect(script.contains("record_cells_cloud_diagnostics()"))
        #expect(script.contains("cells-cloud-gcp-diagnostics="))
        #expect(script.contains("cells-cloud-gcp-compute-api="))
        #expect(script.contains("latest_cells_cloud_summary()"))
        #expect(script.contains("verify_cells_cloud_evidence"))
        #expect(script.contains("local hash_field=\"${path_field}Sha256\""))
        #expect(script.contains("createOutput"))
        #expect(script.contains("destroyOutput"))
        #expect(script.contains("latest_product_ux_summary()"))
        #expect(script.contains("latest_product_ux_any_summary()"))
        #expect(script.contains("record_product_ux_smoke_blocker()"))
        #expect(script.contains("record_product_ux_acceptance_state()"))
        #expect(script.contains("agent-workspace-product-ux-manual-acceptance="))
        #expect(script.contains("Agent Workspace OS product UX latest smoke blocked:"))
        #expect(script.contains("latest_agent_workspace_ui_smoke_summary()"))
        #expect(script.contains("verify_agent_workspace_ui_smoke_summary()"))
        #expect(script.contains("verify_summary_hash_for_basename()"))
        #expect(script.contains("agent-workspace-ui-smoke-latest"))
        #expect(script.contains("commandPalette=cells,vault,browser ok"))
        #expect(script.contains("browserDevTools=opened consoleCount="))
        #expect(script.contains("remotePorts=connected forwardedLocalPort="))
        #expect(script.contains("agentTeams=created team with Planner,Reviewer"))
        #expect(script.contains("codeReview=visible empty diff state"))
        #expect(script.contains("28-final4-command-palette-cells.png"))
        #expect(script.contains("16c-final-browser-devtools-console-visible.png"))
        #expect(script.contains("Requested app-open UI smoke has no archived summary-final.txt"))
        #expect(script.contains("verify_product_ux_evidence"))
        #expect(script.contains("verify_referenced_file_with_hash"))
        #expect(script.contains("verify_release_preflight_summary"))
        #expect(script.contains("record_release_preflight_blockers()"))
        #expect(script.contains("Agent Workspace OS release preflight blocked:"))
        #expect(script.contains("verify_agent_teams_provider_preflight_summary"))
        #expect(script.contains("expected[\"claude-code\"]"))
        #expect(script.contains("expected[\"kiro\"]"))
        #expect(script.contains("$3 == \"-\""))
        #expect(script.contains("dmg-codesign-verification"))
        #expect(script.contains("appcast-sparkle-signature"))
        #expect(script.contains("local-release-tag"))
        #expect(script.contains("acceptanceSha256"))
        #expect(script.contains("a11ySummarySha256"))
        #expect(script.contains("visualSummarySha256"))
        #expect(script.contains("bundleSummarySha256"))
        #expect(script.contains("agent-teams-provider-coverage-latest"))
        #expect(script.contains("agent-teams-provider-coverage-available"))
        #expect(script.contains("agent-teams-provider-coverage-passed"))
        #expect(script.contains("agent-teams-provider-coverage-next"))
        #expect(script.contains("agent-workspace-release-preflight-latest"))
        #expect(script.contains("agent-workspace-release-preflight-target"))
        #expect(script.contains("agent-workspace-release-preflight-blocked"))
        #expect(script.contains("agent-workspace-release-preflight-next"))
        #expect(script.contains("agent-workspace-product-ux-preflight-latest"))
        #expect(script.contains("agent-workspace-product-ux-preflight-status"))
        #expect(script.contains("agent-workspace-product-ux-preflight-next"))
        #expect(script.contains("LC_ALL=C sort -r"))
        #expect(script.contains("head -1"))
        #expect(script.contains("if ! grep -q '^status=ok$' \"$file\""))
        #expect(script.contains("hmac=ok"))
        #expect(script.contains("proxyFallback=ok"))
        #expect(script.contains("dragDropUpload=ok"))
        #expect(script.contains("discovery=ok"))
        #expect(script.contains("result=cells-docker-ok"))
        #expect(script.contains("cells-ssh-artifact"))
        #expect(script.contains("provider=self-hosted"))
        #expect(script.contains("result=cells-self-hosted-ok"))
        #expect(script.contains("build/cells-operator"))
        #expect(script.contains("2026-05-16-cells-operator-scope-decision.md"))
        #expect(script.contains("result=cells-operator-ok"))
        #expect(script.contains("cells-operator-smoke"))
        #expect(script.contains("cells-operator-preflight"))
        #expect(script.contains("Cells Operator control plane"))
        #expect(script.contains("agent-workspace-release-preflight"))
        #expect(script.contains("targetVersion=1.18.0"))
        #expect(script.contains("blocked=0"))
        #expect(script.contains("v1.18.0 release target"))
        #expect(script.contains("agent-workspace-product-ux-preflight"))
        #expect(script.contains("agent-workspace-product-ux-smoke"))
        #expect(script.contains("agent-workspace-product-ux-artifact"))
        #expect(script.contains("voiceOverManual=ok"))
        #expect(script.contains("manualAcceptance=ok"))
        #expect(script.contains("automatedA11y=ok"))
        #expect(script.contains("visualGoldens=ok"))
        #expect(script.contains("bundleLocalCLI=ok"))
        #expect(script.contains("reduceMotion=ok"))
        #expect(script.contains("reviewer=.+"))
        #expect(script.contains("release-candidate summary.txt"))
        #expect(script.contains("agent-teams-provider-coverage-preflight"))
        #expect(script.contains("latestProviderProcessInstalled=12"))
        #expect(script.contains("latestProviderProcessPassed=12"))
        #expect(script.contains("latestProviderProcessEvidence=ok"))
        #expect(script.contains("agent-teams-graph-performance-smoke"))
        #expect(script.contains("agent-teams-graph-performance-preflight"))
        #expect(script.contains("result=agent-teams-graph-performance-ok"))
        #expect(script.contains("nodeCount=12"))
        #expect(script.contains("frameBudgetMs=16"))
        #expect(script.contains("maxFrameMs=ok"))
        #expect(script.contains("updates=ok"))
        #expect(script.contains("cells-cloud-account-smoke"))
        #expect(script.contains("result=cells-cloud-${provider}-ok"))
        #expect(script.contains("provider_tool=\"gcloud\""))
        #expect(script.contains("cloud-tool-${provider_tool}=present"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)

        let result = try runProcess(scriptURL, arguments: [])
        func auditCheck(_ name: String) -> String? {
            let prefix = "check=\(name)="
            return result.stdout
                .split(separator: "\n")
                .first { $0.hasPrefix(prefix) }
                .map { String($0.dropFirst(prefix.count)) }
        }

        let isComplete = result.stdout
            .split(separator: "\n")
            .contains("status=complete")
        #expect(result.terminationStatus == (isComplete ? 0 : 1))
        #expect(isComplete || result.stdout.contains("status=not-complete"))

        let privateCompletionEvidenceMissing = [
            "blocker=source plan missing:",
            "blocker=completion audit missing:",
            "blocker=completion final report missing:",
            "blocker=command instruction doc missing:",
        ].contains { result.stdout.contains($0) }
        if privateCompletionEvidenceMissing {
            #expect(result.terminationStatus == 1)
            #expect(result.stdout.contains("status=not-complete"))
            #expect(result.stdout.contains("check=browser-mcp-tools="))
            #expect(result.stdout.contains("check=agent-workspace-e2e-matrices=9"))
            #expect(
                result.stdout.contains("blocker=source plan missing:")
                    || result.stdout.contains("blocker=completion audit missing:")
                    || result.stdout.contains("blocker=completion final report missing:")
                    || result.stdout.contains("blocker=command instruction doc missing:")
            )
            return
        }

        #expect(result.stdout.contains("check=plan-current-status-note=complete"))
        #expect(result.stdout.contains("check=browser-mcp-tools="))
        #expect(result.stdout.contains("check=completion-final-report=present"))
        #expect(result.stdout.contains("check=completion-final-report-status="))
        #expect(result.stdout.contains("check=completion-final-report-status-consistency=matches-blockers"))
        #expect(result.stdout.contains("check=completion-final-report-required-sections=present"))
        #expect(result.stdout.contains("check=completion-final-report-puerta-1=initial-action-artifact-sha-verdict"))
        #expect(result.stdout.contains("check=completion-final-report-puerta-2=initial-action-artifact-sha-verdict"))
        #expect(result.stdout.contains("check=completion-final-report-puerta-3=initial-action-artifact-sha-verdict"))
        #expect(result.stdout.contains("check=completion-final-report-puerta-4=initial-action-artifact-sha-verdict"))
        #expect(result.stdout.contains("check=completion-final-report-puerta-5=initial-action-artifact-sha-verdict"))
        #expect(result.stdout.contains("check=command-instruction-doc=present"))
        #expect(result.stdout.contains("check=command-instruction-doc-path="))
        #expect(result.stdout.contains("check=command-instruction-doc-guards=present"))
        #expect(result.stdout.contains("check=mcp-domain-files="))
        #expect(result.stdout.contains("check=mcp-unit-test-files="))
        #expect(result.stdout.contains("check=mcp-agent-integration=browser-and-configured"))
        #expect(result.stdout.contains("check=notebook-cli-commands="))
        #expect(result.stdout.contains("check=notebook-domain-files="))
        #expect(result.stdout.contains("check=notebook-unit-test-files="))
        #expect(result.stdout.contains("check=notebook-quicklook-contract=present"))
        #expect(result.stdout.contains("check=vault-builtin-agents="))
        #expect(result.stdout.contains("check=vault-domain-files="))
        #expect(result.stdout.contains("check=vault-ui-files="))
        #expect(result.stdout.contains("check=vault-unit-test-files="))
        #expect(result.stdout.contains("check=vault-visual-foundation=search-detector-sidebar"))
        #expect(result.stdout.contains("check=code-review-domain-files="))
        #expect(result.stdout.contains("check=code-review-ui-files="))
        #expect(result.stdout.contains("check=code-review-unit-test-files="))
        #expect(result.stdout.contains("check=code-review-agent-team-handoff=present"))
        #expect(result.stdout.contains("check=completion-audit-required-sections=present"))
        #expect(result.stdout.contains("check=remote-browser-docker-manifest-implemented=13"))
        #expect(result.stdout.contains("check=cells-cloud-attach=e2b-fly-command-backed"))
        #expect(result.stdout.contains("check=cells-cloud-preflight-latest="))
        #expect(result.stdout.contains("check=cells-cloud-preflight-status="))
        #expect(result.stdout.contains("check=cells-cloud-preflight-blocked="))
        #expect(result.stdout.contains("check=cells-cloud-preflight-ready="))
        #expect(result.stdout.contains("check=cells-cloud-preflight-complete="))
        #expect(result.stdout.contains("check=cells-cloud-gcp-diagnostics="))
        #expect(result.stdout.contains("check=cells-cloud-gcp-compute-api="))
        #expect(result.stdout.contains("check=cells-aws-readiness-sequence=present"))
        #expect(result.stdout.contains("check=cells-aws-readiness-sequence-latest="))
        #expect(result.stdout.contains("check=cells-aws-readiness-sequence-status="))
        #expect(result.stdout.contains("check=cells-aws-readiness-sequence-result="))
        #expect(result.stdout.contains("check=cells-aws-readiness-sequence-aws-smoke="))
        #expect(result.stdout.contains("check=cells-aws-readiness-sequence-steps="))
        if result.stdout.contains("check=docker-daemon=unavailable") ||
            result.stdout.contains("check=docker-cli=missing") {
            #expect(result.stdout.contains("Remote Browser Docker SSH and Cells Docker live smokes cannot be refreshed"))
        }
        #expect(result.stdout.contains("check=agent-teams-provider-coverage-latest="))
        #expect(result.stdout.contains("check=agent-teams-provider-coverage-status="))
        #expect(result.stdout.contains("check=agent-teams-provider-coverage-available="))
        #expect(result.stdout.contains("check=agent-teams-provider-coverage-installed="))
        #expect(result.stdout.contains("check=agent-teams-provider-coverage-passed="))
        #expect(result.stdout.contains("check=agent-teams-provider-coverage-evidence="))
        #expect(result.stdout.contains("check=agent-workspace-release-preflight-latest="))
        #expect(result.stdout.contains("check=agent-workspace-release-preflight-status="))
        #expect(result.stdout.contains("check=agent-workspace-release-preflight-target="))
        #expect(result.stdout.contains("check=agent-workspace-release-preflight-blocked="))
        #expect(result.stdout.contains("check=agent-workspace-product-ux-preflight-latest="))
        #expect(result.stdout.contains("check=agent-workspace-product-ux-preflight-status="))
        #expect(result.stdout.contains("check=agent-workspace-product-ux-manual-acceptance="))
        if result.stdout.contains("check=agent-workspace-ui-smoke-latest=") {
            #expect(result.stdout.contains("check=agent-workspace-ui-smoke-command-palette=cells-vault-browser"))
            #expect(result.stdout.contains("check=agent-workspace-ui-smoke-dashboard=agent-status-pills"))
            #expect(result.stdout.contains("check=agent-workspace-ui-smoke-browser-devtools=console-visible"))
            #expect(result.stdout.contains("check=agent-workspace-ui-smoke-remote-ports=localhost-suggestion"))
            #expect(result.stdout.contains("check=agent-workspace-ui-smoke-agent-teams=two-members"))
            #expect(result.stdout.contains("check=agent-workspace-ui-smoke-code-review=empty-diff-visible"))
            #expect(result.stdout.contains("check=agent-workspace-ui-smoke-evidence=hashes-ok"))
            #expect(!result.stdout.contains("blocker=Requested app-open UI smoke has no archived summary-final.txt"))
        } else {
            #expect(result.stdout.contains("blocker=Requested app-open UI smoke has no archived summary-final.txt"))
        }
        for requiredCheck in [
            "cells-cloud-preflight-latest",
            "cells-cloud-preflight-scope",
            "cells-cloud-preflight-provider-count",
            "cells-cloud-preflight-status",
            "cells-cloud-preflight-blocked",
            "cells-cloud-preflight-ready",
            "cells-cloud-preflight-complete",
            "cells-cloud-preflight-next",
            "cells-cloud-gcp-diagnostics",
            "cells-cloud-gcp-compute-api",
            "cells-aws-readiness-sequence",
            "cells-aws-readiness-sequence-latest",
            "cells-aws-readiness-sequence-status",
            "cells-aws-readiness-sequence-result",
            "cells-aws-readiness-sequence-aws-smoke",
            "cells-aws-readiness-sequence-steps",
            "completion-final-report",
            "completion-final-report-status",
            "completion-final-report-status-consistency",
            "completion-final-report-required-sections",
            "completion-final-report-puerta-1",
            "completion-final-report-puerta-2",
            "completion-final-report-puerta-3",
            "completion-final-report-puerta-4",
            "completion-final-report-puerta-5",
            "command-instruction-doc",
            "command-instruction-doc-path",
            "command-instruction-doc-guards",
            "agent-workspace-product-ux-manual-acceptance",
            "mcp-domain-files",
            "mcp-unit-test-files",
            "mcp-agent-integration",
            "notebook-cli-commands",
            "notebook-domain-files",
            "notebook-unit-test-files",
            "notebook-quicklook-contract",
            "vault-builtin-agents",
            "vault-domain-files",
            "vault-ui-files",
            "vault-unit-test-files",
            "vault-visual-foundation",
            "code-review-domain-files",
            "code-review-ui-files",
            "code-review-unit-test-files",
            "code-review-agent-team-handoff",
            "agent-teams-provider-coverage-latest",
            "agent-teams-provider-coverage-status",
            "agent-teams-provider-coverage-available",
            "agent-teams-provider-coverage-installed",
            "agent-teams-provider-coverage-passed",
            "agent-teams-provider-coverage-evidence",
            "agent-teams-provider-coverage-next",
            "agent-workspace-release-preflight-latest",
            "agent-workspace-release-preflight-status",
            "agent-workspace-release-preflight-target",
            "agent-workspace-release-preflight-blocked",
            "agent-workspace-release-preflight-next",
            "agent-workspace-product-ux-preflight-latest",
            "agent-workspace-product-ux-preflight-status",
            "agent-workspace-product-ux-preflight-next",
            "agent-workspace-ui-smoke-latest",
            "agent-workspace-ui-smoke-command-palette",
            "agent-workspace-ui-smoke-dashboard",
            "agent-workspace-ui-smoke-browser-devtools",
            "agent-workspace-ui-smoke-remote-ports",
            "agent-workspace-ui-smoke-agent-teams",
            "agent-workspace-ui-smoke-code-review",
            "agent-workspace-ui-smoke-evidence",
        ] {
            let value = try #require(auditCheck(requiredCheck))
            #expect(!value.isEmpty)
        }
        #expect(auditCheck("cells-cloud-preflight-scope") == "all")
        #expect(auditCheck("cells-cloud-preflight-provider-count") == "5")
        for statusCheck in [
            "cells-cloud-preflight-status",
            "agent-teams-provider-coverage-status",
            "agent-teams-provider-coverage-evidence",
            "agent-workspace-release-preflight-status",
            "agent-workspace-product-ux-preflight-status",
        ] {
            let value = try #require(auditCheck(statusCheck))
            #expect(["missing", "blocked", "ready", "complete", "ok"].contains(value))
        }
        for numericCheck in [
            "cells-cloud-preflight-blocked",
            "cells-cloud-preflight-ready",
            "cells-cloud-preflight-complete",
            "agent-teams-provider-coverage-available",
            "agent-teams-provider-coverage-installed",
            "agent-teams-provider-coverage-passed",
            "agent-workspace-release-preflight-blocked",
            "mcp-domain-files",
            "mcp-unit-test-files",
            "notebook-cli-commands",
            "notebook-domain-files",
            "notebook-unit-test-files",
            "vault-builtin-agents",
            "vault-domain-files",
            "vault-ui-files",
            "vault-unit-test-files",
            "code-review-domain-files",
            "code-review-ui-files",
            "code-review-unit-test-files",
        ] {
            let value = try #require(auditCheck(numericCheck))
            #expect(Int(value) != nil)
        }
        #expect(auditCheck("agent-workspace-release-preflight-target") == "1.18.0")
        if auditCheck("cells-cloud-preflight-status") == "complete" {
            #expect(!result.stdout.contains("Cells cloud account E2E has no archived"))
        } else {
            #expect(result.stdout.contains("Cells cloud account E2E has no archived"))
        }
        #expect(result.stdout.contains("check=agent-workspace-e2e-matrices=9"))
        if result.stdout.contains("check=remote-browser-docker-artifact=") {
            #expect(result.stdout.contains("check=cells-docker-artifact="))
            #expect(!result.stdout.contains("Remote Browser Docker SSH E2E latest artifact is not current-green"))
            #expect(!result.stdout.contains("Cells Docker E2E latest artifact is not current-green"))
        } else {
            #expect(result.stdout.contains("blocker=Docker E2E blocked") || result.stdout.contains("Remote Browser Docker SSH E2E latest artifact is not current-green"))
            #expect(result.stdout.contains("Cells Docker E2E latest artifact is not current-green"))
        }
        if result.stdout.contains("check=cells-ssh-artifact=") {
            #expect(!result.stdout.contains("blocker=Cells SSH E2E has no archived summary.txt"))
        } else {
            #expect(result.stdout.contains("blocker=Cells SSH E2E has no archived summary.txt"))
        }
        if result.stdout.contains("check=cells-self-hosted-ssh-artifact=") {
            #expect(!result.stdout.contains("blocker=Cells self-hosted SSH E2E has no archived summary.txt"))
        } else {
            #expect(result.stdout.contains("blocker=Cells self-hosted SSH E2E has no archived summary.txt"))
        }
        #expect(
            result.stdout.contains("check=cells-operator-artifact=")
                || result.stdout.contains("check=cells-operator-scope=out-of-scope-for-v1.18.0")
                || result.stdout.contains("blocker=Cells Operator control plane has no archived summary.txt")
        )
        if result.stdout.contains("check=agent-workspace-e2e-status=complete") {
            #expect(!result.stdout.contains("blocker=Verification moat incomplete: E2E matrix audit reports"))
        } else {
            #expect(result.stdout.contains("blocker=Verification moat incomplete: E2E matrix audit reports"))
        }
        if result.stdout.contains("check=agent-teams-provider-coverage=") {
            #expect(!result.stdout.contains("blocker=Agent Teams provider process coverage has no archived preflight.txt"))
        } else {
            #expect(result.stdout.contains("blocker=Agent Teams provider process coverage has no archived preflight.txt"))
            #expect(result.stdout.contains("detailed provider availability summary"))
        }
        if result.stdout.contains("check=agent-teams-graph-performance=") {
            #expect(!result.stdout.contains("blocker=Agent Teams graph performance has no archived summary.txt"))
        } else {
            #expect(result.stdout.contains("blocker=Agent Teams graph performance has no archived summary.txt"))
        }
        if result.stdout.contains("check=agent-workspace-release-preflight=build/") {
            #expect(!result.stdout.contains("blocker=Agent Workspace OS v1.18.0 release target has no archived preflight.txt"))
        } else {
            #expect(result.stdout.contains("blocker=Agent Workspace OS v1.18.0 release target has no archived preflight.txt"))
            #expect(result.stdout.contains("detailed release evidence summary"))
        }
        if result.stdout.contains("check=agent-workspace-product-ux-artifact=") {
            #expect(!result.stdout.contains("blocker=Agent Workspace OS product UX latest smoke blocked:"))
        } else {
            #expect(result.stdout.contains("blocker=Agent Workspace OS product UX latest smoke blocked:"))
            #expect(result.stdout.contains("reason="))
            #expect(result.stdout.contains("acceptanceFile="))
        }
        if result.stdout.contains("check=voiceover-artifact=") {
            #expect(!result.stdout.contains("blocker=Product v1.18 UX incomplete: no VoiceOver/WCAG acceptance artifact"))
        } else {
            #expect(result.stdout.contains("blocker=Product v1.18 UX incomplete: no VoiceOver/WCAG acceptance artifact"))
        }
    }

    @Test("completion audit helper refuses stale green artifacts when newest artifact is blocked")
    func completionAuditHelperRefusesStaleGreenArtifacts() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/audit-agent-workspace-os-completion.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        let helperStart = try #require(script.range(of: "latest_artifact_with_fields() {"))
        let helperEndMarker = try #require(
            script.range(
                of: "\n}\n\nrequire_executable",
                range: helperStart.upperBound..<script.endIndex
            )
        )
        let helperSource = String(script[helperStart.lowerBound..<helperEndMarker.lowerBound]) + "\n}\n"

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-completion-artifact-helper-\(UUID().uuidString)", isDirectory: true)
        let oldArtifact = fixtureRoot.appendingPathComponent("20260101-000000", isDirectory: true)
        let newArtifact = fixtureRoot.appendingPathComponent("20260102-000000", isDirectory: true)
        try FileManager.default.createDirectory(at: oldArtifact, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newArtifact, withIntermediateDirectories: true)

        try """
        status=ok
        required=ok
        """.write(to: oldArtifact.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
        try """
        status=blocked
        required=ok
        """.write(to: newArtifact.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)

        let probeURL = fixtureRoot.appendingPathComponent("probe.sh")
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        \(helperSource)
        latest_artifact_with_fields "$1" 'summary.txt' 'required=ok'
        """.write(to: probeURL, atomically: true, encoding: .utf8)

        let blocked = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: [probeURL.path, fixtureRoot.path])
        #expect(blocked.terminationStatus == 1)
        #expect(blocked.stdout.isEmpty)

        try """
        status=blocked
        required=ok
        """.write(to: newArtifact.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)

        let blockedWithRequiredFields = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path]
        )
        #expect(blockedWithRequiredFields.terminationStatus == 1)
        #expect(blockedWithRequiredFields.stdout.isEmpty)

        try """
        status=ok
        required=ok
        """.write(to: newArtifact.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)

        let passing = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: [probeURL.path, fixtureRoot.path])
        #expect(passing.terminationStatus == 0)
        #expect(passing.stdout.contains("20260102-000000/summary.txt"))
        #expect(!passing.stdout.contains("20260101-000000/summary.txt"))
    }

    @Test("completion audit cloud preflight helper ignores newer partial provider preflights")
    func completionAuditCloudPreflightHelperRequiresAllProviderScope() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/audit-agent-workspace-os-completion.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        let helperStart = try #require(script.range(of: "latest_cells_cloud_all_preflight() {"))
        let helperEndMarker = try #require(
            script.range(
                of: "\n}\n\nrequire_executable",
                range: helperStart.upperBound..<script.endIndex
            )
        )
        let helperSource = String(script[helperStart.lowerBound..<helperEndMarker.lowerBound]) + "\n}\n"

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-cells-cloud-all-preflight-\(UUID().uuidString)", isDirectory: true)
        let preflightRoot = fixtureRoot
            .appendingPathComponent("build/cells-cloud-preflight", isDirectory: true)
        let olderAll = preflightRoot.appendingPathComponent("20260101-000000", isDirectory: true)
        let newerPartial = preflightRoot.appendingPathComponent("20260102-000000", isDirectory: true)
        try writeCellsCloudPreflightFixture(root: olderAll, providerCount: 5)
        try writeCellsCloudPreflightFixture(root: newerPartial, providerCount: 1)

        let probeURL = fixtureRoot.appendingPathComponent("probe-cloud-all.sh")
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        ROOT_DIR="$1"
        \(helperSource)
        latest_cells_cloud_all_preflight
        """.write(to: probeURL, atomically: true, encoding: .utf8)

        let partialIgnored = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path]
        )
        #expect(partialIgnored.terminationStatus == 0)
        #expect(partialIgnored.stdout.contains("20260101-000000/preflight.txt"))
        #expect(!partialIgnored.stdout.contains("20260102-000000/preflight.txt"))

        let newestAll = preflightRoot.appendingPathComponent("20260103-000000", isDirectory: true)
        try writeCellsCloudPreflightFixture(root: newestAll, providerCount: 5)
        let newestAllSelected = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path]
        )
        #expect(newestAllSelected.terminationStatus == 0)
        #expect(newestAllSelected.stdout.contains("20260103-000000/preflight.txt"))
        #expect(!newestAllSelected.stdout.contains("20260101-000000/preflight.txt"))
        #expect(!newestAllSelected.stdout.contains("20260102-000000/preflight.txt"))
    }

    @Test("completion audit records AWS preflight diagnostics when AWS is blocked")
    func completionAuditRecordsAWSPreflightDiagnostics() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/audit-agent-workspace-os-completion.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        let helperStart = try #require(script.range(of: "artifact_field() {"))
        let helperEndMarker = try #require(
            script.range(
                of: "\nrecord_agent_workspace_plan_phase_statuses() {",
                range: helperStart.upperBound..<script.endIndex
            )
        )
        let helperSource = String(script[helperStart.lowerBound..<helperEndMarker.lowerBound])

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-cells-cloud-aws-audit-diagnostics-\(UUID().uuidString)", isDirectory: true)
        let preflightRoot = fixtureRoot
            .appendingPathComponent("build/cells-cloud-preflight/20260101-000000", isDirectory: true)
        try FileManager.default.createDirectory(at: preflightRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let diagnostics = preflightRoot.appendingPathComponent("aws-diagnostics.txt")
        let requiredPolicy = preflightRoot.appendingPathComponent("aws-required-policy.json")
        let diagnosticPolicy = preflightRoot.appendingPathComponent("aws-diagnostic-policy.json")
        let setupPolicy = preflightRoot.appendingPathComponent("aws-setup-principal-policy.json")
        let requiredSetup = preflightRoot.appendingPathComponent("aws-required-setup.md")

        try """
        status=blocked
        artifactRoot=\(preflightRoot.path)
        summary=\(preflightRoot.appendingPathComponent("summary.tsv").path)
        blocked=1
        ready=0
        complete=4
        awsDiagnostics=build/cells-cloud-preflight/20260101-000000/aws-diagnostics.txt
        next=scripts/smoke-cells-cloud-account.sh <provider> with COCXY_CELLS_CLOUD_E2E=1 against disposable resources
        """.write(to: preflightRoot.appendingPathComponent("preflight.txt"), atomically: true, encoding: .utf8)
        try """
        provider\tstatus\ttool\ttoolStatus\tmissingPrerequisites\tokArtifact
        aws\tblocked\taws\tpresent\tAWS_INVALID_INSTANCE_PROFILE,AWS_IAM_GET_INSTANCE_PROFILE_DENIED\t-
        """.write(to: preflightRoot.appendingPathComponent("summary.tsv"), atomically: true, encoding: .utf8)

        try """
        region=us-east-1
        image=ami-fixture
        vmSize=t3.micro
        instanceProfile=CocxyCellsSSMProfile
        instanceProfileCheck=AWS_IAM_GET_INSTANCE_PROFILE_DENIED
        identity=arn:aws:iam::123456789012:user/cocxy
        profile=fixture-profile
        profileSource=COCXY_AWS_PROFILE
        configuredProfileCount=2
        callerIdentityType=user
        iamGetUser=access-denied
        iamListAttachedUserPolicies=access-denied
        iamListUserPolicies=access-denied
        iamListGroupsForUser=access-denied
        setupRole=CocxyCellsSSMRole
        iamGetSetupRole=access-denied
        iamListRoles=access-denied
        iamListInstanceProfiles=access-denied
        ssmRuntimePolicySimulation=access-denied
        runInstancesDryRun=AWS_INVALID_INSTANCE_PROFILE,AWS_IAM_GET_INSTANCE_PROFILE_DENIED
        runInstancesProfileArnDryRun=AWS_INVALID_INSTANCE_PROFILE
        runInstancesWithoutProfileDryRun=authorized
        requiredPolicy=build/cells-cloud-preflight/20260101-000000/aws-required-policy.json
        diagnosticPolicy=build/cells-cloud-preflight/20260101-000000/aws-diagnostic-policy.json
        setupPrincipalPolicy=build/cells-cloud-preflight/20260101-000000/aws-setup-principal-policy.json
        requiredSetup=build/cells-cloud-preflight/20260101-000000/aws-required-setup.md
        permissionProbeImage=ami-probe
        permissionProbeStatus=not-run
        """.write(to: diagnostics, atomically: true, encoding: .utf8)
        try "{}\n".write(to: requiredPolicy, atomically: true, encoding: .utf8)
        try """
        {"Statement":[{"Action":["iam:SimulatePrincipalPolicy"]}]}
        """.write(to: diagnosticPolicy, atomically: true, encoding: .utf8)
        try """
        {"Statement":[{"Action":["iam:AddRoleToInstanceProfile","iam:PassRole"]}]}
        """.write(to: setupPolicy, atomically: true, encoding: .utf8)
        try "# setup\n".write(to: requiredSetup, atomically: true, encoding: .utf8)

        let probeURL = fixtureRoot.appendingPathComponent("probe-aws-audit-diagnostics.sh")
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        ROOT_DIR="$1"
        CHECKS=()
        BLOCKERS=()
        record_check() { CHECKS+=("$1"); }
        blocker() { BLOCKERS+=("$1"); }
        \(helperSource)
        record_cells_cloud_aws_diagnostics "$2"
        record_cells_cloud_aws_latest_recheck
        printf '%s\\n' "${CHECKS[@]}"
        for item in "${BLOCKERS[@]}"; do
          printf 'blocker=%s\\n' "$item"
        done
        """.write(to: probeURL, atomically: true, encoding: .utf8)

        let result = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path, preflightRoot.appendingPathComponent("preflight.txt").path]
        )

        #expect(result.terminationStatus == 0)
        #expect(result.stdout.contains("cells-cloud-aws-diagnostics=build/cells-cloud-preflight/20260101-000000/aws-diagnostics.txt"))
        #expect(result.stdout.contains("cells-cloud-aws-identity=present"))
        #expect(!result.stdout.contains("arn:aws:iam::123456789012:user/cocxy"))
        #expect(result.stdout.contains("cells-cloud-aws-profile=fixture-profile"))
        #expect(result.stdout.contains("cells-cloud-aws-profile-source=COCXY_AWS_PROFILE"))
        #expect(result.stdout.contains("cells-cloud-aws-configured-profile-count=2"))
        #expect(result.stdout.contains("cells-cloud-aws-caller-identity-type=user"))
        #expect(result.stdout.contains("cells-cloud-aws-iam-get-user=access-denied"))
        #expect(result.stdout.contains("cells-cloud-aws-iam-list-attached-user-policies=access-denied"))
        #expect(result.stdout.contains("cells-cloud-aws-iam-list-user-policies=access-denied"))
        #expect(result.stdout.contains("cells-cloud-aws-iam-list-groups-for-user=access-denied"))
        #expect(result.stdout.contains("cells-cloud-aws-setup-role=CocxyCellsSSMRole"))
        #expect(result.stdout.contains("cells-cloud-aws-iam-get-setup-role=access-denied"))
        #expect(result.stdout.contains("cells-cloud-aws-iam-list-roles=access-denied"))
        #expect(result.stdout.contains("cells-cloud-aws-iam-list-instance-profiles=access-denied"))
        #expect(result.stdout.contains("cells-cloud-aws-ssm-runtime-policy-simulation=access-denied"))
        #expect(result.stdout.contains("cells-cloud-aws-instance-profile=CocxyCellsSSMProfile"))
        #expect(result.stdout.contains("cells-cloud-aws-instance-profile-check=AWS_IAM_GET_INSTANCE_PROFILE_DENIED"))
        #expect(result.stdout.contains("cells-cloud-aws-run-instances-dry-run=AWS_INVALID_INSTANCE_PROFILE,AWS_IAM_GET_INSTANCE_PROFILE_DENIED"))
        #expect(result.stdout.contains("cells-cloud-aws-run-instances-profile-arn-dry-run=AWS_INVALID_INSTANCE_PROFILE"))
        #expect(result.stdout.contains("cells-cloud-aws-run-instances-without-profile-dry-run=authorized"))
        #expect(result.stdout.contains("cells-cloud-aws-permission-probe-image=configured"))
        #expect(result.stdout.contains("cells-cloud-aws-permission-probe-status=not-run"))
        #expect(result.stdout.contains("cells-cloud-aws-required-policy=build/cells-cloud-preflight/20260101-000000/aws-required-policy.json"))
        #expect(result.stdout.contains("cells-cloud-aws-diagnostic-policy=build/cells-cloud-preflight/20260101-000000/aws-diagnostic-policy.json"))
        #expect(result.stdout.contains("cells-cloud-aws-diagnostic-policy-simulate-principal-policy=present"))
        #expect(result.stdout.contains("cells-cloud-aws-setup-principal-policy=build/cells-cloud-preflight/20260101-000000/aws-setup-principal-policy.json"))
        #expect(result.stdout.contains("cells-cloud-aws-setup-principal-policy-passrole=present"))
        #expect(result.stdout.contains("cells-cloud-aws-required-setup=build/cells-cloud-preflight/20260101-000000/aws-required-setup.md"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck=build/cells-cloud-preflight/20260101-000000/preflight.txt"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-status=blocked"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-missing-prerequisites=AWS_INVALID_INSTANCE_PROFILE,AWS_IAM_GET_INSTANCE_PROFILE_DENIED"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-latest-smoke-artifact=unknown"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-latest-smoke-status=unknown"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-latest-smoke-reason=unknown"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-latest-smoke-output=unknown"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-diagnostics=build/cells-cloud-preflight/20260101-000000/aws-diagnostics.txt"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-profile=fixture-profile"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-instance-profile=CocxyCellsSSMProfile"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-instance-profile-check=AWS_IAM_GET_INSTANCE_PROFILE_DENIED"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-run-instances-dry-run=AWS_INVALID_INSTANCE_PROFILE,AWS_IAM_GET_INSTANCE_PROFILE_DENIED"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-run-instances-profile-arn-dry-run=AWS_INVALID_INSTANCE_PROFILE"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-run-instances-without-profile-dry-run=authorized"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-ssm-runtime-policy-simulation=access-denied"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-required-policy=build/cells-cloud-preflight/20260101-000000/aws-required-policy.json"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-diagnostic-policy=build/cells-cloud-preflight/20260101-000000/aws-diagnostic-policy.json"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-diagnostic-policy-simulate-principal-policy=present"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-setup-principal-policy=build/cells-cloud-preflight/20260101-000000/aws-setup-principal-policy.json"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-setup-principal-policy-passrole=present"))
        #expect(result.stdout.contains("cells-cloud-aws-latest-recheck-required-setup=build/cells-cloud-preflight/20260101-000000/aws-required-setup.md"))
        #expect(result.stdout.contains("blocker=Latest AWS cloud preflight blocked: missingPrerequisites=AWS_INVALID_INSTANCE_PROFILE,AWS_IAM_GET_INSTANCE_PROFILE_DENIED"))
    }

    @Test("completion audit records AWS setup verifier profile ARN dry-run status")
    func completionAuditRecordsAWSSetupVerifierProfileArnDryRunStatus() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/audit-agent-workspace-os-completion.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        let helperStart = try #require(script.range(of: "artifact_field() {"))
        let helperEndMarker = try #require(
            script.range(
                of: "\nrecord_agent_workspace_plan_phase_statuses() {",
                range: helperStart.upperBound..<script.endIndex
            )
        )
        let helperSource = String(script[helperStart.lowerBound..<helperEndMarker.lowerBound])

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-aws-setup-verifier-audit-\(UUID().uuidString)", isDirectory: true)
        let verifyRoot = fixtureRoot
            .appendingPathComponent("build/cells-aws-setup-verify/20260101-000000", isDirectory: true)
        try FileManager.default.createDirectory(at: verifyRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try """
        status=blocked
        artifactRoot=\(verifyRoot.path)
        checks=build/cells-aws-setup-verify/20260101-000000/checks.tsv
        remediation=build/cells-aws-setup-verify/20260101-000000/remediation.md
        blockers=run-instances-with-profile-arn-dry-run:invalid-instance-profile
        """.write(to: verifyRoot.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
        try """
        check\tstatus\tdetail\toutput\terror
        run-instances-with-profile-dry-run\tinvalid-instance-profile\tami-fixture\tout\terr
        run-instances-with-profile-arn-dry-run\tinvalid-instance-profile\tami-fixture\tout\terr
        run-instances-without-profile-dry-run\tauthorized\tami-fixture\tout\terr
        """.write(to: verifyRoot.appendingPathComponent("checks.tsv"), atomically: true, encoding: .utf8)
        try "# remediation\n".write(to: verifyRoot.appendingPathComponent("remediation.md"), atomically: true, encoding: .utf8)

        let probeURL = fixtureRoot.appendingPathComponent("probe-aws-setup-verifier-audit.sh")
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        ROOT_DIR="$1"
        CHECKS=()
        BLOCKERS=()
        record_check() { CHECKS+=("$1"); }
        blocker() { BLOCKERS+=("$1"); }
        \(helperSource)
        record_aws_setup_verify_summary
        printf '%s\\n' "${CHECKS[@]}"
        for item in "${BLOCKERS[@]}"; do
          printf 'blocker=%s\\n' "$item"
        done
        """.write(to: probeURL, atomically: true, encoding: .utf8)

        let result = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path]
        )

        #expect(result.terminationStatus == 0)
        #expect(result.stdout.contains("cells-aws-setup-verify-profile-dry-run=invalid-instance-profile"))
        #expect(result.stdout.contains("cells-aws-setup-verify-profile-arn-dry-run=invalid-instance-profile"))
        #expect(result.stdout.contains("cells-aws-setup-verify-without-profile-dry-run=authorized"))
        #expect(result.stdout.contains("blocker=AWS setup verifier blocked: blockers=run-instances-with-profile-arn-dry-run:invalid-instance-profile"))
    }

    @Test("completion audit records AWS read-only diagnostic and direct dry-run isolation artifacts")
    func completionAuditRecordsAWSReadOnlyDiagnosticAndDirectDryRunArtifacts() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/audit-agent-workspace-os-completion.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        let helperStart = try #require(script.range(of: "artifact_field() {"))
        let helperEndMarker = try #require(
            script.range(
                of: "\nrecord_agent_workspace_plan_phase_statuses() {",
                range: helperStart.upperBound..<script.endIndex
            )
        )
        let helperSource = String(script[helperStart.lowerBound..<helperEndMarker.lowerBound])

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-aws-readonly-direct-dryrun-audit-\(UUID().uuidString)", isDirectory: true)
        let readonlyRoot = fixtureRoot
            .appendingPathComponent("build/cells-aws-readonly-diagnostics/20260101-000000", isDirectory: true)
        let directRoot = fixtureRoot
            .appendingPathComponent("build/cells-aws-direct-dryrun/20260101-000000", isDirectory: true)
        let profileRoot = fixtureRoot
            .appendingPathComponent("build/cells-aws-profile-diagnostics/20260101-000000", isDirectory: true)
        try FileManager.default.createDirectory(at: readonlyRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: directRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profileRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try """
        status=diagnostic
        artifactRoot=\(readonlyRoot.path)
        callerIdentityExit=0
        associationsExit=0
        simulatePrincipalPolicyExit=254
        describeImageExit=0
        callerIdentity=build/cells-aws-readonly-diagnostics/20260101-000000/caller-identity.out
        ec2InstanceProfileAssociations=build/cells-aws-readonly-diagnostics/20260101-000000/ec2-instance-profile-associations.out
        simulatePrincipalPolicy=build/cells-aws-readonly-diagnostics/20260101-000000/simulate-principal-policy.err
        describeImage=build/cells-aws-readonly-diagnostics/20260101-000000/describe-image.out
        """.write(to: readonlyRoot.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
        try #"{"Arn":"arn:aws:iam::123456789012:user/cocxy"}"#.write(
            to: readonlyRoot.appendingPathComponent("caller-identity.out"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"IamInstanceProfileAssociations": []}"#.write(
            to: readonlyRoot.appendingPathComponent("ec2-instance-profile-associations.out"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"Images":[{"State": "available"}]}"#.write(
            to: readonlyRoot.appendingPathComponent("describe-image.out"),
            atomically: true,
            encoding: .utf8
        )
        try "AccessDenied: iam:SimulatePrincipalPolicy denied\n".write(
            to: readonlyRoot.appendingPathComponent("simulate-principal-policy.err"),
            atomically: true,
            encoding: .utf8
        )

        try """
        status=blocked
        artifactRoot=\(directRoot.path)
        withProfileExit=254
        withoutProfileExit=254
        withProfileError=build/cells-aws-direct-dryrun/20260101-000000/with-profile.err
        withoutProfileError=build/cells-aws-direct-dryrun/20260101-000000/without-profile.err
        env=build/cells-aws-direct-dryrun/20260101-000000/env.txt
        """.write(to: directRoot.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
        try """
        region=us-east-1
        image=ami-fixture
        profile=CocxyCellsSSMProfile
        subnet=
        sg=
        key=
        vm=t3.micro
        """.write(to: directRoot.appendingPathComponent("env.txt"), atomically: true, encoding: .utf8)
        try "Invalid IAM Instance Profile name\n".write(
            to: directRoot.appendingPathComponent("with-profile.err"),
            atomically: true,
            encoding: .utf8
        )
        try "DryRunOperation: Request would have succeeded\n".write(
            to: directRoot.appendingPathComponent("without-profile.err"),
            atomically: true,
            encoding: .utf8
        )

        try """
        status=blocked
        artifactRoot=\(profileRoot.path)
        profileList=build/cells-aws-profile-diagnostics/20260101-000000/profiles.out
        identity=build/cells-aws-profile-diagnostics/20260101-000000/identity.out
        listInstanceProfiles=build/cells-aws-profile-diagnostics/20260101-000000/list-instance-profiles.err
        configuredProfile=default
        awsProfile=
        """.write(to: profileRoot.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
        try "default\n".write(
            to: profileRoot.appendingPathComponent("profiles.out"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"Arn":"arn:aws:iam::123456789012:user/cocxy"}"#.write(
            to: profileRoot.appendingPathComponent("identity.out"),
            atomically: true,
            encoding: .utf8
        )
        try "AccessDenied: iam:ListInstanceProfiles denied\n".write(
            to: profileRoot.appendingPathComponent("list-instance-profiles.err"),
            atomically: true,
            encoding: .utf8
        )

        let probeURL = fixtureRoot.appendingPathComponent("probe-aws-readonly-direct-dryrun-audit.sh")
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        ROOT_DIR="$1"
        CHECKS=()
        BLOCKERS=()
        record_check() { CHECKS+=("$1"); }
        blocker() { BLOCKERS+=("$1"); }
        \(helperSource)
        record_cells_aws_readonly_diagnostics_summary
        record_cells_aws_direct_dryrun_summary
        record_cells_aws_profile_diagnostics_summary
        printf '%s\\n' "${CHECKS[@]}"
        """.write(to: probeURL, atomically: true, encoding: .utf8)

        let result = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path]
        )

        #expect(result.terminationStatus == 0)
        #expect(result.stdout.contains("cells-aws-readonly-diagnostics-latest=build/cells-aws-readonly-diagnostics/20260101-000000/summary.txt"))
        #expect(result.stdout.contains("cells-aws-readonly-diagnostics-describe-image-exit=0"))
        #expect(result.stdout.contains("cells-aws-readonly-diagnostics-image-state=available"))
        #expect(result.stdout.contains("cells-aws-readonly-diagnostics-associations-exit=0"))
        #expect(result.stdout.contains("cells-aws-readonly-diagnostics-associations=empty"))
        #expect(result.stdout.contains("cells-aws-readonly-diagnostics-simulate-principal-policy-exit=254"))
        #expect(result.stdout.contains("cells-aws-readonly-diagnostics-simulate-principal-policy=access-denied"))
        #expect(result.stdout.contains("cells-aws-direct-dryrun-latest=build/cells-aws-direct-dryrun/20260101-000000/summary.txt"))
        #expect(result.stdout.contains("cells-aws-direct-dryrun-subnet=missing"))
        #expect(result.stdout.contains("cells-aws-direct-dryrun-security-group=missing"))
        #expect(result.stdout.contains("cells-aws-direct-dryrun-key=missing"))
        #expect(result.stdout.contains("cells-aws-direct-dryrun-with-profile=invalid-instance-profile"))
        #expect(result.stdout.contains("cells-aws-direct-dryrun-without-profile=authorized"))
        #expect(result.stdout.contains("cells-aws-profile-diagnostics-latest=build/cells-aws-profile-diagnostics/20260101-000000/summary.txt"))
        #expect(result.stdout.contains("cells-aws-profile-diagnostics-configured-profile=default"))
        #expect(result.stdout.contains("cells-aws-profile-diagnostics-aws-profile=missing"))
        #expect(result.stdout.contains("cells-aws-profile-diagnostics-configured-profile-count=1"))
        #expect(result.stdout.contains("cells-aws-profile-diagnostics-active-identity=user"))
        #expect(result.stdout.contains("cells-aws-profile-diagnostics-list-instance-profiles=access-denied"))
    }

    @Test("completion audit records persistent AWS shell environment readiness")
    func completionAuditRecordsPersistentAWSShellEnvironmentReadiness() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/audit-agent-workspace-os-completion.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        let helperStart = try #require(script.range(of: "artifact_field() {"))
        let helperEndMarker = try #require(
            script.range(
                of: "\nrecord_agent_workspace_plan_phase_statuses() {",
                range: helperStart.upperBound..<script.endIndex
            )
        )
        let helperSource = String(script[helperStart.lowerBound..<helperEndMarker.lowerBound])

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-cells-cloud-aws-persistent-env-\(UUID().uuidString)", isDirectory: true)
        let preflightRoot = fixtureRoot
            .appendingPathComponent("build/cells-cloud-preflight/20260101-000000", isDirectory: true)
        let binRoot = fixtureRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: preflightRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: binRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        try """
        status=blocked
        artifactRoot=\(preflightRoot.path)
        summary=\(preflightRoot.appendingPathComponent("summary.tsv").path)
        blocked=1
        ready=0
        complete=4
        awsDiagnostics=build/cells-cloud-preflight/20260101-000000/aws-diagnostics.txt
        next=scripts/smoke-cells-cloud-account.sh <provider> with COCXY_CELLS_CLOUD_E2E=1 against disposable resources
        """.write(to: preflightRoot.appendingPathComponent("preflight.txt"), atomically: true, encoding: .utf8)
        try """
        region=us-east-1
        image=ami-good
        instanceProfile=CocxyCellsSSMProfile
        """.write(to: preflightRoot.appendingPathComponent("aws-diagnostics.txt"), atomically: true, encoding: .utf8)

        let fakeZsh = binRoot.appendingPathComponent("zsh")
        try """
        #!/bin/sh
        printf 'region=us-east-1\\n'
        printf 'image=ami-stale\\n'
        printf 'instanceProfile=\\n'
        printf 'permissionProbeImage=\\n'
        """.write(to: fakeZsh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeZsh.path)

        let probeURL = fixtureRoot.appendingPathComponent("probe-aws-persistent-env.sh")
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        ROOT_DIR="$1"
        PATH="$2:/usr/bin:/bin"
        CHECKS=()
        record_check() { CHECKS+=("$1"); }
        blocker() { CHECKS+=("blocker=$1"); }
        \(helperSource)
        record_cells_cloud_aws_persistent_env_state "$3"
        printf '%s\\n' "${CHECKS[@]}"
        """.write(to: probeURL, atomically: true, encoding: .utf8)

        let result = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [
                probeURL.path,
                fixtureRoot.path,
                binRoot.path,
                preflightRoot.appendingPathComponent("preflight.txt").path,
            ]
        )

        #expect(result.terminationStatus == 0)
        #expect(result.stdout.contains("cells-cloud-aws-persistent-env=zsh"))
        #expect(result.stdout.contains("cells-cloud-aws-persistent-region=us-east-1"))
        #expect(result.stdout.contains("cells-cloud-aws-persistent-image=ami-stale"))
        #expect(result.stdout.contains("cells-cloud-aws-persistent-instance-profile=missing"))
        #expect(result.stdout.contains("cells-cloud-aws-persistent-permission-probe-image=missing"))
        #expect(result.stdout.contains("cells-cloud-aws-persistent-image-matches-preflight=no"))
        #expect(result.stdout.contains("AWS persistent shell environment missing COCXY_AWS_INSTANCE_PROFILE"))
        #expect(result.stdout.contains("AWS persistent shell COCXY_AWS_IMAGE does not match latest AWS preflight image"))
    }

    @Test("completion audit Cells cloud helper rejects fabricated summaries without output hashes")
    func completionAuditCellsCloudHelperRejectsFabricatedEvidence() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/audit-agent-workspace-os-completion.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        let helperStart = try #require(script.range(of: "artifact_field() {"))
        let helperEndMarker = try #require(
            script.range(
                of: "\nlatest_cells_cloud_all_preflight() {",
                range: helperStart.upperBound..<script.endIndex
            )
        )
        let helperSource = String(script[helperStart.lowerBound..<helperEndMarker.lowerBound])

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-cells-cloud-completion-helper-\(UUID().uuidString)", isDirectory: true)
        let cloudRoot = fixtureRoot.appendingPathComponent("build/cells-cloud-gcp", isDirectory: true)
        let fabricated = cloudRoot.appendingPathComponent("20260101-000000", isDirectory: true)
        try FileManager.default.createDirectory(at: fabricated, withIntermediateDirectories: true)
        try """
        status=ok
        provider=gcp
        create=ok
        status-check=ok
        exec=ok
        logs=ok
        attach=ok
        list=ok
        destroy=ok
        result=cells-cloud-gcp-ok
        """.write(to: fabricated.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)

        let probeURL = fixtureRoot.appendingPathComponent("probe-cells-cloud.sh")
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        ROOT_DIR="$1"
        \(helperSource)
        latest_cells_cloud_summary gcp
        """.write(to: probeURL, atomically: true, encoding: .utf8)

        let rejected = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path]
        )
        #expect(rejected.terminationStatus == 1)
        #expect(rejected.stdout.isEmpty)

        let valid = cloudRoot.appendingPathComponent("20260102-000000", isDirectory: true)
        try writeCellsCloudSummary(root: valid, status: "ok")
        try writeCellsCloudSummary(
            root: cloudRoot.appendingPathComponent("20260103-000000", isDirectory: true),
            status: "blocked"
        )
        let accepted = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path]
        )
        #expect(accepted.terminationStatus == 0)
        #expect(accepted.stdout.contains("20260102-000000/summary.txt"))
        #expect(!accepted.stdout.contains("20260101-000000/summary.txt"))
    }

    @Test("completion audit Product UX helper rejects fabricated summaries without hashed evidence")
    func completionAuditProductUXHelperRejectsFabricatedEvidence() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/audit-agent-workspace-os-completion.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        let helperStart = try #require(script.range(of: "artifact_field() {"))
        let helperEndMarker = try #require(
            script.range(
                of: "\nverify_cells_cloud_evidence() {",
                range: helperStart.upperBound..<script.endIndex
            )
        )
        let helperSource = String(script[helperStart.lowerBound..<helperEndMarker.lowerBound])

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-product-ux-completion-helper-\(UUID().uuidString)", isDirectory: true)
        let productUXRoot = fixtureRoot
            .appendingPathComponent("build/agent-workspace-product-ux", isDirectory: true)
        let fabricated = productUXRoot.appendingPathComponent("20260101-000000", isDirectory: true)
        try writeProductUXSummary(root: fabricated, status: "ok")

        let probeURL = fixtureRoot.appendingPathComponent("probe-product-ux.sh")
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        ROOT_DIR="$1"
        \(helperSource)
        latest_product_ux_summary
        """.write(to: probeURL, atomically: true, encoding: .utf8)

        let rejected = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path]
        )
        #expect(rejected.terminationStatus == 1)
        #expect(rejected.stdout.isEmpty)

        let valid = productUXRoot.appendingPathComponent("20260102-000000", isDirectory: true)
        try writeProductUXSummaryWithEvidence(root: valid)
        let accepted = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path]
        )
        #expect(accepted.terminationStatus == 0)
        #expect(accepted.stdout.contains("20260102-000000/summary.txt"))
        #expect(!accepted.stdout.contains("20260101-000000/summary.txt"))
    }

    @Test("completion audit app-open UI helper rejects fabricated summaries without hashed screenshots")
    func completionAuditAppOpenUISmokeHelperRejectsFabricatedEvidence() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/audit-agent-workspace-os-completion.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        let helperStart = try #require(script.range(of: "resolve_artifact_path() {"))
        let helperEndMarker = try #require(
            script.range(
                of: "\nverify_cells_cloud_evidence() {",
                range: helperStart.upperBound..<script.endIndex
            )
        )
        let helperSource = String(script[helperStart.lowerBound..<helperEndMarker.lowerBound])

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-ui-smoke-completion-helper-\(UUID().uuidString)", isDirectory: true)
        let uiSmokeRoot = fixtureRoot
            .appendingPathComponent("build/agent-workspace-ui-smoke", isDirectory: true)
        let olderValid = uiSmokeRoot.appendingPathComponent("20260101-000000", isDirectory: true)
        let newerFabricated = uiSmokeRoot.appendingPathComponent("20260102-000000", isDirectory: true)
        try writeAgentWorkspaceUISmokeSummaryWithEvidence(root: olderValid)
        try writeAgentWorkspaceUISmokeSummary(root: newerFabricated)

        let probeURL = fixtureRoot.appendingPathComponent("probe-ui-smoke.sh")
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        ROOT_DIR="$1"
        \(helperSource)
        latest_agent_workspace_ui_smoke_summary
        """.write(to: probeURL, atomically: true, encoding: .utf8)

        let rejected = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path]
        )
        #expect(rejected.terminationStatus == 1)
        #expect(rejected.stdout.isEmpty)

        try writeAgentWorkspaceUISmokeSummaryWithEvidence(root: newerFabricated)
        let accepted = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path]
        )
        #expect(accepted.terminationStatus == 0)
        #expect(accepted.stdout.contains("20260102-000000/summary-final.txt"))
        #expect(!accepted.stdout.contains("20260101-000000/summary-final.txt"))
    }

    @Test("completion audit final report puerta helper requires action artifact hash and verdict")
    func completionAuditFinalReportPuertaHelperRequiresRequiredFields() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/audit-agent-workspace-os-completion.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        let helperStart = try #require(script.range(of: "final_report_puerta_has_required_fields() {"))
        let helperEndMarker = try #require(
            script.range(
                of: "\n\nif [ -f \"$PLAN\" ]; then",
                range: helperStart.upperBound..<script.endIndex
            )
        )
        let helperSource = String(script[helperStart.lowerBound..<helperEndMarker.lowerBound])

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-final-report-helper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        let report = fixtureRoot.appendingPathComponent("final.md")

        let incompleteReport = """
        # Final Report

        ## Puerta 1 - Docker Live Smokes

        Initial state:
        - fixture

        Action taken:
        - fixture

        Final artifacts:
        - build/example/summary.txt

        ## Puerta 2 - Agent Teams Provider And Runtime
        """
        try incompleteReport.write(to: report, atomically: true, encoding: .utf8)

        let probeURL = fixtureRoot.appendingPathComponent("probe-final-report.sh")
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        FINAL_AUDIT_REPORT="$1"
        \(helperSource)
        final_report_puerta_has_required_fields '## Puerta 1 - Docker Live Smokes'
        """.write(to: probeURL, atomically: true, encoding: .utf8)

        let rejected = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, report.path]
        )
        #expect(rejected.terminationStatus == 1)

        let completeReport = """
        # Final Report

        ## Puerta 1 - Docker Live Smokes

        Initial state:
        - fixture

        Action taken:
        - fixture

        Final artifacts:
        - build/example/summary.txt
          SHA-256: `0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef`

        Verdict:
        - pass

        ## Puerta 2 - Agent Teams Provider And Runtime
        """
        try completeReport.write(to: report, atomically: true, encoding: .utf8)

        let accepted = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, report.path]
        )
        #expect(accepted.terminationStatus == 0)
    }

    @Test("completion audit release helper rejects fabricated preflights without detailed evidence")
    func completionAuditReleaseHelperRejectsFabricatedPreflight() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/audit-agent-workspace-os-completion.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        #expect(script.contains("cells-cloud-account-readiness"))

        let helperStart = try #require(script.range(of: "latest_artifact_with_fields() {"))
        let helperEndMarker = try #require(
            script.range(
                of: "\nverify_product_ux_evidence() {",
                range: helperStart.upperBound..<script.endIndex
            )
        )
        let helperSource = String(script[helperStart.lowerBound..<helperEndMarker.lowerBound])

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-release-completion-helper-\(UUID().uuidString)", isDirectory: true)
        let preflightRoot = fixtureRoot
            .appendingPathComponent("build/agent-workspace-release-preflight", isDirectory: true)
        let fabricated = preflightRoot.appendingPathComponent("20260101-000000", isDirectory: true)
        try FileManager.default.createDirectory(at: fabricated, withIntermediateDirectories: true)
        try """
        status=ok
        targetVersion=1.18.0
        artifactRoot=\(fabricated.path)
        summary=\(fabricated.appendingPathComponent("summary.tsv").path)
        blocked=0
        next=fixture
        """.write(to: fabricated.appendingPathComponent("preflight.txt"), atomically: true, encoding: .utf8)

        let probeURL = fixtureRoot.appendingPathComponent("probe-release.sh")
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        ROOT_DIR="$1"
        \(helperSource)
        candidate="$(latest_artifact_with_fields "${ROOT_DIR}/build/agent-workspace-release-preflight" 'preflight.txt' 'targetVersion=1.18.0' 'blocked=0' || true)"
        if [ -n "$candidate" ] && verify_release_preflight_summary "$candidate"; then
          printf '%s\\n' "$candidate"
        fi
        """.write(to: probeURL, atomically: true, encoding: .utf8)

        let rejected = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path]
        )
        #expect(rejected.terminationStatus == 0)
        #expect(rejected.stdout.isEmpty)

        let oldComplete = preflightRoot.appendingPathComponent("20260102-000000", isDirectory: true)
        try writeReleasePreflightFixture(root: oldComplete, includeCellsCloudReadiness: false)
        let missingCloudReadiness = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path]
        )
        #expect(missingCloudReadiness.terminationStatus == 0)
        #expect(missingCloudReadiness.stdout.isEmpty)

        let valid = preflightRoot.appendingPathComponent("20260103-000000", isDirectory: true)
        try writeReleasePreflightFixture(root: valid)
        let accepted = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path]
        )
        #expect(accepted.terminationStatus == 0)
        #expect(accepted.stdout.contains("20260103-000000/preflight.txt"))
        #expect(!accepted.stdout.contains("20260102-000000/preflight.txt"))
        #expect(!accepted.stdout.contains("20260101-000000/preflight.txt"))
    }

    @Test("completion audit Agent Teams helper rejects fabricated provider coverage preflights")
    func completionAuditAgentTeamsProviderHelperRejectsFabricatedPreflight() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/audit-agent-workspace-os-completion.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)

        let helperStart = try #require(script.range(of: "latest_artifact_with_fields() {"))
        let helperEndMarker = try #require(
            script.range(
                of: "\nverify_product_ux_evidence() {",
                range: helperStart.upperBound..<script.endIndex
            )
        )
        let helperSource = String(script[helperStart.lowerBound..<helperEndMarker.lowerBound])

        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-agent-teams-provider-completion-helper-\(UUID().uuidString)", isDirectory: true)
        let preflightRoot = fixtureRoot
            .appendingPathComponent("build/agent-teams-provider-coverage-preflight", isDirectory: true)
        let fabricated = preflightRoot.appendingPathComponent("20260101-000000", isDirectory: true)
        try FileManager.default.createDirectory(at: fabricated, withIntermediateDirectories: true)
        try """
        status=ok
        artifactRoot=\(fabricated.path)
        summary=\(fabricated.appendingPathComponent("summary.tsv").path)
        providerCount=12
        availableProviderBinaries=12
        latestProviderProcessSummary=build/agent-teams-provider-process/fixture/summary.txt
        latestProviderProcessStatus=ok
        latestProviderProcessInstalled=12
        latestProviderProcessPassed=12
        latestProviderProcessEvidence=ok
        next=fixture
        """.write(to: fabricated.appendingPathComponent("preflight.txt"), atomically: true, encoding: .utf8)

        let probeURL = fixtureRoot.appendingPathComponent("probe-agent-teams-provider.sh")
        try """
        #!/usr/bin/env bash
        set -euo pipefail
        ROOT_DIR="$1"
        \(helperSource)
        candidate="$(latest_artifact_with_fields "${ROOT_DIR}/build/agent-teams-provider-coverage-preflight" 'preflight.txt' 'providerCount=12' 'latestProviderProcessStatus=ok' 'latestProviderProcessInstalled=12' 'latestProviderProcessPassed=12' 'latestProviderProcessEvidence=ok' || true)"
        if [ -n "$candidate" ] && verify_agent_teams_provider_preflight_summary "$candidate"; then
          printf '%s\\n' "$candidate"
        fi
        """.write(to: probeURL, atomically: true, encoding: .utf8)

        let rejected = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path]
        )
        #expect(rejected.terminationStatus == 0)
        #expect(rejected.stdout.isEmpty)

        let wrongProviders = preflightRoot.appendingPathComponent("20260101-010000", isDirectory: true)
        try FileManager.default.createDirectory(at: wrongProviders, withIntermediateDirectories: true)
        let wrongSummary = wrongProviders.appendingPathComponent("summary.tsv")
        let wrongRows = ["provider\tstatus\tbinary"]
            + (1...12).map { "fabricated-provider-\($0)\tavailable\t/usr/bin/true" }
        try (wrongRows.joined(separator: "\n") + "\n")
            .write(to: wrongSummary, atomically: true, encoding: .utf8)
        try """
        status=ok
        artifactRoot=\(wrongProviders.path)
        summary=\(wrongSummary.path)
        providerCount=12
        availableProviderBinaries=12
        latestProviderProcessSummary=build/agent-teams-provider-process/fixture/summary.txt
        latestProviderProcessStatus=ok
        latestProviderProcessInstalled=12
        latestProviderProcessPassed=12
        latestProviderProcessEvidence=ok
        next=fixture
        """.write(to: wrongProviders.appendingPathComponent("preflight.txt"), atomically: true, encoding: .utf8)

        let rejectedWrongProviders = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path]
        )
        #expect(rejectedWrongProviders.terminationStatus == 0)
        #expect(rejectedWrongProviders.stdout.isEmpty)

        let valid = preflightRoot.appendingPathComponent("20260102-000000", isDirectory: true)
        try writeAgentTeamsProviderCoveragePreflightFixture(root: valid)
        let accepted = try runProcess(
            URL(fileURLWithPath: "/bin/bash"),
            arguments: [probeURL.path, fixtureRoot.path]
        )
        #expect(accepted.terminationStatus == 0)
        #expect(accepted.stdout.contains("20260102-000000/preflight.txt"))
        #expect(!accepted.stdout.contains("20260101-000000/preflight.txt"))
        #expect(!accepted.stdout.contains("20260101-010000/preflight.txt"))
    }

    @Test("Agent Workspace preflights distinguish stale green gates from archived cloud account evidence")
    func agentWorkspacePreflightsDistinguishStaleGreenGatesFromArchivedCloudEvidence() throws {
        let root = repositoryRoot()
        let fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-preflight-stale-artifacts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)

        let productUXRoot = fixtureRoot.appendingPathComponent("product-ux", isDirectory: true)
        try writeProductUXSummary(
            root: productUXRoot.appendingPathComponent("20260101-000000", isDirectory: true),
            status: "ok"
        )
        try writeProductUXSummary(
            root: productUXRoot.appendingPathComponent("20260102-000000", isDirectory: true),
            status: "blocked"
        )

        let productUXPreflight = try runProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "COCXY_AGENT_WORKSPACE_PRODUCT_UX_ARTIFACT_ROOT=\(productUXRoot.path)",
                "COCXY_AGENT_WORKSPACE_PRODUCT_UX_PREFLIGHT_ARTIFACTS=\(fixtureRoot.appendingPathComponent("product-ux-preflight").path)",
                root.appendingPathComponent("scripts/preflight-agent-workspace-product-ux.sh").path,
            ]
        )
        #expect(productUXPreflight.terminationStatus == 1)
        #expect(productUXPreflight.stdout.contains("product-ux-walkthrough\tblocked\t-"))
        #expect(!productUXPreflight.stdout.contains("20260101-000000/summary.txt"))

        let providerProcessRoot = fixtureRoot.appendingPathComponent("provider-process", isDirectory: true)
        try writeProviderProcessSummary(
            root: providerProcessRoot.appendingPathComponent("20260101-000000", isDirectory: true),
            status: "ok",
            installed: 12,
            passed: 12
        )
        try writeProviderProcessSummary(
            root: providerProcessRoot.appendingPathComponent("20260102-000000", isDirectory: true),
            status: "blocked",
            installed: 2,
            passed: 2
        )

        let providerCoveragePreflight = try runProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "COCXY_AGENT_TEAMS_PROVIDER_PROCESS_ARTIFACT_ROOT=\(providerProcessRoot.path)",
                "COCXY_AGENT_TEAMS_PROVIDER_PREFLIGHT_ARTIFACTS=\(fixtureRoot.appendingPathComponent("provider-coverage-preflight").path)",
                root.appendingPathComponent("scripts/preflight-agent-teams-provider-coverage.sh").path,
            ]
        )
        #expect(providerCoveragePreflight.terminationStatus == 1)
        #expect(providerCoveragePreflight.stdout.contains("status=blocked"))
        #expect(providerCoveragePreflight.stdout.contains("latestProviderProcessSummary="))
        #expect(providerCoveragePreflight.stdout.contains("20260102-000000/summary.txt"))
        #expect(providerCoveragePreflight.stdout.contains("latestProviderProcessStatus=blocked"))
        #expect(!providerCoveragePreflight.stdout.contains("20260101-000000/summary.txt"))

        let cellsCloudRoot = fixtureRoot.appendingPathComponent("cells-cloud", isDirectory: true)
        try writeCellsCloudSummary(
            root: cellsCloudRoot.appendingPathComponent("cells-cloud-gcp/20260101-000000", isDirectory: true),
            status: "ok"
        )
        try writeCellsCloudSummary(
            root: cellsCloudRoot.appendingPathComponent("cells-cloud-gcp/20260102-000000", isDirectory: true),
            status: "blocked"
        )

        let cellsCloudPreflight = try runProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "COCXY_CELLS_CLOUD_ARTIFACT_ROOT=\(cellsCloudRoot.path)",
                "COCXY_CELLS_CLOUD_PREFLIGHT_ARTIFACTS=\(fixtureRoot.appendingPathComponent("cells-cloud-preflight").path)",
                root.appendingPathComponent("scripts/preflight-cells-cloud-account.sh").path,
                "gcp",
            ]
        )
        #expect(cellsCloudPreflight.terminationStatus == 0)
        #expect(cellsCloudPreflight.stdout.contains("status=complete"))
        #expect(cellsCloudPreflight.stdout.contains("gcp\tcomplete\tgcloud"))
        #expect(cellsCloudPreflight.stdout.contains("20260101-000000/summary.txt"))
        #expect(cellsCloudPreflight.stdout.contains("20260102-000000/summary.txt\tblocked"))

        try writeCellsCloudSummary(
            root: cellsCloudRoot.appendingPathComponent("cells-cloud-gcp/20260102-000000", isDirectory: true),
            status: "ok"
        )
        let completedCellsCloudPreflight = try runProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "COCXY_CELLS_CLOUD_ARTIFACT_ROOT=\(cellsCloudRoot.path)",
                "COCXY_CELLS_CLOUD_PREFLIGHT_ARTIFACTS=\(fixtureRoot.appendingPathComponent("cells-cloud-preflight-complete").path)",
                root.appendingPathComponent("scripts/preflight-cells-cloud-account.sh").path,
                "gcp",
            ]
        )
        #expect(completedCellsCloudPreflight.terminationStatus == 0)
        #expect(completedCellsCloudPreflight.stdout.contains("status=complete"))
        #expect(completedCellsCloudPreflight.stdout.contains("gcp\tcomplete\tgcloud"))
        #expect(completedCellsCloudPreflight.stdout.contains("20260102-000000/summary.txt"))
        #expect(!completedCellsCloudPreflight.stdout.contains("20260101-000000/summary.txt"))
    }

    @Test("Agent Teams provider coverage preflight is read-only and distinguishes adapters from real process coverage")
    func agentTeamsProviderCoveragePreflightIsReadOnlyAndProcessBacked() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/preflight-agent-teams-provider-coverage.sh")
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
        #expect(script.contains("Read-only preflight"))
        #expect(script.contains("does not launch providers"))
        #expect(script.contains("REQUIRED_PROVIDER_COUNT=12"))
        #expect(script.contains("claude-code|Claude Code"))
        #expect(script.contains("codex|Codex CLI"))
        #expect(script.contains("qoder|Qoder"))
        #expect(script.contains("kiro|Kiro"))
        #expect(script.contains("build/agent-teams-provider-process"))
        #expect(script.contains("result=agent-teams-provider-process-ok"))
        #expect(script.contains("latestProviderProcessInstalled"))
        #expect(script.contains("latestProviderProcessPassed"))
        #expect(script.contains("latestProviderProcessEvidence"))
        #expect(script.contains("verify_provider_evidence_manifest"))
        #expect(script.contains("EXPECTED_PROVIDER_IDS"))
        #expect(script.contains("is_expected_provider_id"))
        #expect(script.contains("providerID\\thookAgent\\tbinary"))
        #expect(script.contains("providerEvidenceSha256"))
        #expect(!ci.contains("preflight-agent-teams-provider-coverage.sh"))
        #expect(!nightly.contains("preflight-agent-teams-provider-coverage.sh"))
        #expect(!release.contains("preflight-agent-teams-provider-coverage.sh"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)

        let fixtureRoot = try temporaryArtifactRoot(named: "provider-coverage-preflight")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let result = try runProcess(
            scriptURL,
            arguments: [],
            environment: [
                "COCXY_AGENT_TEAMS_PROVIDER_PREFLIGHT_ARTIFACTS": fixtureRoot
                    .appendingPathComponent("preflight")
                    .path,
                "COCXY_AGENT_TEAMS_PROVIDER_PROCESS_ARTIFACT_ROOT": fixtureRoot
                    .appendingPathComponent("provider-process")
                    .path,
            ]
        )
        #expect(result.terminationStatus == 0 || result.terminationStatus == 1)
        #expect(result.stdout.contains("providerCount=12"))
        #expect(result.stdout.contains("summary="))
        #expect(result.stdout.contains("provider\tstatus\tbinary"))
        #expect(result.stdout.contains("latestProviderProcessSummary="))
        #expect(result.stdout.contains("latestProviderProcessEvidence="))
    }

    @Test("Agent Teams provider coverage preflight rejects fabricated OK summaries without process evidence")
    func agentTeamsProviderCoveragePreflightRejectsFabricatedOKSummary() throws {
        let root = repositoryRoot()
        let fixtureRoot = try temporaryArtifactRoot(named: "provider-coverage-fabricated-summary")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let processRoot = fixtureRoot.appendingPathComponent("provider-process/20260101-000000", isDirectory: true)
        try FileManager.default.createDirectory(at: processRoot, withIntermediateDirectories: true)
        try """
        status=ok
        result=agent-teams-provider-process-ok
        installedProviders=12
        passedProviders=12
        """.write(to: processRoot.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)

        let result = try runProcess(
            URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "COCXY_AGENT_TEAMS_PROVIDER_PROCESS_ARTIFACT_ROOT=\(fixtureRoot.appendingPathComponent("provider-process").path)",
                "COCXY_AGENT_TEAMS_PROVIDER_PREFLIGHT_ARTIFACTS=\(fixtureRoot.appendingPathComponent("preflight").path)",
                root.appendingPathComponent("scripts/preflight-agent-teams-provider-coverage.sh").path,
            ]
        )

        #expect(result.terminationStatus == 1)
        #expect(result.stdout.contains("status=blocked"))
        #expect(result.stdout.contains("latestProviderProcessStatus=ok"))
        #expect(result.stdout.contains("latestProviderProcessInstalled=12"))
        #expect(result.stdout.contains("latestProviderProcessPassed=12"))
        #expect(result.stdout.contains("latestProviderProcessEvidence=blocked"))
    }

    @Test("Agent Teams graph performance preflight is read-only and blocks without a 16ms visual update artifact")
    func agentTeamsGraphPerformancePreflightIsReadOnlyAndFrameBudgetBacked() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/preflight-agent-teams-graph-performance.sh")
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
        #expect(script.contains("Read-only preflight"))
        #expect(script.contains("does not open the app"))
        #expect(script.contains("render SwiftUI"))
        #expect(script.contains("Team graph visual < 16ms render per update"))
        #expect(script.contains("build/agent-teams-graph-performance"))
        #expect(script.contains("result=agent-teams-graph-performance-ok"))
        #expect(script.contains("nodeCount=12"))
        #expect(script.contains("frameBudgetMs=16"))
        #expect(script.contains("maxFrameMs=ok"))
        #expect(script.contains("updates=ok"))
        #expect(!ci.contains("preflight-agent-teams-graph-performance.sh"))
        #expect(!nightly.contains("preflight-agent-teams-graph-performance.sh"))
        #expect(!release.contains("preflight-agent-teams-graph-performance.sh"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)

        let fixtureRoot = try temporaryArtifactRoot(named: "graph-performance-preflight")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let result = try runProcess(
            scriptURL,
            arguments: [],
            environment: [
                "COCXY_AGENT_TEAMS_GRAPH_PREFLIGHT_ARTIFACTS": fixtureRoot
                    .appendingPathComponent("preflight")
                    .path,
                "COCXY_AGENT_TEAMS_GRAPH_PERFORMANCE_ARTIFACT_ROOT": fixtureRoot
                    .appendingPathComponent("graph-performance")
                    .path,
            ]
        )
        #expect(result.terminationStatus == 0 || result.terminationStatus == 1)
        #expect(result.stdout.contains("summary="))
        #expect(result.stdout.contains("graphArtifactRoot="))
        #expect(result.stdout.contains("latestGraphPerformanceSummary="))
        #expect(result.stdout.contains("requirement\tstatus\tevidence\tdetail"))
        #expect(
            result.stdout.contains("status=ok")
                || result.stdout.contains("status=blocked")
        )
    }

    @Test("Agent Teams graph performance smoke archives a real 16ms visual update benchmark")
    func agentTeamsGraphPerformanceSmokeArchivesVisualBenchmark() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/smoke-agent-teams-graph-performance.sh")
        let benchmarkURL = root.appendingPathComponent("Tests/Unit/AgentTeamsTests/AgentTeamGraphPerformanceBenchmarks.swift")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let benchmark = try String(contentsOf: benchmarkURL, encoding: .utf8)

        #expect(FileManager.default.isExecutableFile(atPath: scriptURL.path))
        #expect(script.contains("COCXY_RUN_AGENT_TEAMS_GRAPH_BENCHMARKS=1"))
        #expect(script.contains("COCXY_AGENT_TEAMS_GRAPH_PERF_ARTIFACT_ROOT"))
        #expect(script.contains("swift test --filter AgentTeamGraphPerformanceBenchmarks"))
        #expect(script.contains("result=agent-teams-graph-performance-ok"))
        #expect(script.contains("nodeCount=12"))
        #expect(script.contains("frameBudgetMs=16"))
        #expect(script.contains("maxFrameMs=ok"))
        #expect(script.contains("updates=ok"))
        #expect(script.contains("summary.txt"))
        #expect(benchmark.contains("@Suite("))
        #expect(benchmark.contains("Agent Teams graph performance benchmarks"))
        #expect(benchmark.contains("NSHostingView"))
        #expect(benchmark.contains("TeamGraphView"))
        #expect(benchmark.contains("displayIfNeeded"))
        #expect(benchmark.contains("COCXY_AGENT_TEAMS_GRAPH_PERF_ARTIFACT_ROOT"))
        #expect(benchmark.contains("nodeCount=12"))
        #expect(benchmark.contains("frameBudgetMs=16"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)
    }

    @Test("Agent Workspace product UX preflight is read-only and requires release-candidate walkthrough evidence")
    func agentWorkspaceProductUXPreflightRequiresReleaseCandidateEvidence() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/preflight-agent-workspace-product-ux.sh")
        let smokeURL = root.appendingPathComponent("scripts/smoke-agent-workspace-product-ux.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let smoke = try String(contentsOf: smokeURL, encoding: .utf8)
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
        #expect(FileManager.default.isExecutableFile(atPath: smokeURL.path))
        #expect(script.contains("Read-only preflight"))
        #expect(script.contains("does not open the app"))
        #expect(script.contains("build/agent-workspace-product-ux"))
        #expect(script.contains("result=agent-workspace-product-ux-ok"))
        #expect(script.contains("surfaces=6"))
        #expect(script.contains("commandPalette=ok"))
        #expect(script.contains("dashboard=ok"))
        #expect(script.contains("browserDevTools=ok"))
        #expect(script.contains("remotePorts=ok"))
        #expect(script.contains("teams=ok"))
        #expect(script.contains("codeReview=ok"))
        #expect(script.contains("voiceOverManual=ok"))
        #expect(script.contains("manualAcceptance=ok"))
        #expect(script.contains("automatedA11y=ok"))
        #expect(script.contains("visualGoldens=ok"))
        #expect(script.contains("bundleLocalCLI=ok"))
        #expect(script.contains("reviewer=<human reviewer>"))
        #expect(script.contains("grep -Eq '^reviewer=.+$'"))
        #expect(script.contains("verify_referenced_file"))
        #expect(script.contains("acceptanceSha256"))
        #expect(script.contains("a11ySummarySha256"))
        #expect(script.contains("visualSummarySha256"))
        #expect(script.contains("bundleSummarySha256"))
        #expect(script.contains("keyboard=ok"))
        #expect(script.contains("reduceMotion=ok"))
        #expect(script.contains("contrast=ok"))
        #expect(smoke.contains("COCXY_AGENT_WORKSPACE_PRODUCT_UX_ACCEPTANCE_FILE"))
        #expect(smoke.contains("--write-template"))
        #expect(smoke.contains("Pending release-candidate walkthrough"))
        #expect(smoke.contains("Status: Accepted for v1.18.0 release candidate."))
        #expect(smoke.contains("Reviewer:"))
        #expect(smoke.contains("result=agent-workspace-product-ux-ok"))
        #expect(smoke.contains("manualAcceptance=ok"))
        #expect(smoke.contains("automatedA11y=ok"))
        #expect(smoke.contains("visualGoldens=ok"))
        #expect(smoke.contains("bundleLocalCLI=ok"))
        #expect(smoke.contains("acceptanceSha256="))
        #expect(smoke.contains("a11ySummarySha256="))
        #expect(smoke.contains("visualSummarySha256="))
        #expect(smoke.contains("bundleSummarySha256="))
        #expect(!ci.contains("preflight-agent-workspace-product-ux.sh"))
        #expect(!nightly.contains("preflight-agent-workspace-product-ux.sh"))
        #expect(!release.contains("preflight-agent-workspace-product-ux.sh"))
        #expect(!ci.contains("smoke-agent-workspace-product-ux.sh"))
        #expect(!nightly.contains("smoke-agent-workspace-product-ux.sh"))
        #expect(!release.contains("smoke-agent-workspace-product-ux.sh"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)
        let smokeSyntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", smokeURL.path])
        #expect(smokeSyntax.terminationStatus == 0)

        let fixtureRoot = try temporaryArtifactRoot(named: "product-ux-preflight")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let result = try runProcess(
            scriptURL,
            arguments: [],
            environment: [
                "COCXY_AGENT_WORKSPACE_PRODUCT_UX_PREFLIGHT_ARTIFACTS": fixtureRoot
                    .appendingPathComponent("preflight")
                    .path,
                "COCXY_AGENT_WORKSPACE_PRODUCT_UX_ARTIFACT_ROOT": fixtureRoot
                    .appendingPathComponent("product-ux")
                    .path,
            ]
        )
        #expect(result.terminationStatus == 0 || result.terminationStatus == 1)
        #expect(result.stdout.contains("summary="))
        #expect(result.stdout.contains("requirement\tstatus\tevidence\tdetail"))
        #expect(
            result.stdout.contains("status=ok")
                || result.stdout.contains("status=blocked")
        )

        let templatePath = fixtureRoot
            .appendingPathComponent("manual-acceptance", isDirectory: true)
            .appendingPathComponent("acceptance.txt")
        let templateResult = try runProcess(
            smokeURL,
            arguments: ["--write-template", templatePath.path]
        )
        #expect(templateResult.terminationStatus == 0)
        let template = try String(contentsOf: templatePath, encoding: .utf8)
        #expect(template.contains("Status: Pending release-candidate walkthrough."))
        #expect(template.contains("Reviewer:"))
        #expect(template.contains("Command Palette (Cmd+Shift+P)"))
        #expect(template.contains("Agent Teams"))
        #expect(!template.contains("\nStatus: Accepted for v1.18.0 release candidate."))

        let blockedTemplateSmoke = try runProcess(
            smokeURL,
            arguments: [],
            environment: [
                "COCXY_AGENT_WORKSPACE_PRODUCT_UX_ACCEPTANCE_FILE": templatePath.path,
                "COCXY_AGENT_WORKSPACE_PRODUCT_UX_ARTIFACTS": fixtureRoot
                    .appendingPathComponent("template-smoke")
                    .path,
            ]
        )
        #expect(blockedTemplateSmoke.terminationStatus == 1)
        #expect(blockedTemplateSmoke.stdout.contains("reason=acceptance-file-missing-status"))
    }

    @Test("Agent Workspace product UX preflight rejects fabricated OK summaries without evidence hashes")
    func agentWorkspaceProductUXPreflightRejectsFabricatedOKSummary() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/preflight-agent-workspace-product-ux.sh")
        let fixtureRoot = try temporaryArtifactRoot(named: "product-ux-fabricated-summary")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let productUXRoot = fixtureRoot.appendingPathComponent("product-ux", isDirectory: true)
        try writeProductUXSummary(
            root: productUXRoot.appendingPathComponent("20260101-000000", isDirectory: true),
            status: "ok"
        )

        let result = try runProcess(
            scriptURL,
            arguments: [],
            environment: [
                "COCXY_AGENT_WORKSPACE_PRODUCT_UX_ARTIFACT_ROOT": productUXRoot.path,
                "COCXY_AGENT_WORKSPACE_PRODUCT_UX_PREFLIGHT_ARTIFACTS": fixtureRoot
                    .appendingPathComponent("preflight")
                    .path,
            ]
        )
        #expect(result.terminationStatus == 1)
        #expect(result.stdout.contains("status=blocked"))
        #expect(result.stdout.contains("product-ux-walkthrough\tblocked\t-"))
        #expect(!result.stdout.contains("20260101-000000/summary.txt"))
    }

    @Test("Agent Workspace release preflight is read-only and verifies local v1.18 release-target evidence")
    func agentWorkspaceReleasePreflightIsReadOnlyAndVersionTargeted() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/preflight-agent-workspace-release.sh")
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
        #expect(script.contains("Read-only preflight"))
        #expect(script.contains("never bumps versions"))
        #expect(script.contains("COCXY_AGENT_WORKSPACE_RELEASE_VERSION"))
        #expect(script.contains("1.18.0"))
        #expect(script.contains("Resources/Info.plist"))
        #expect(script.contains("fallbackVersion"))
        #expect(script.contains("build/CocxyTerminal.app"))
        #expect(script.contains("build/CocxyTerminal-${TARGET_VERSION}.dmg"))
        #expect(script.contains("COCXY_CELLS_CLOUD_PREFLIGHT_ROOT"))
        #expect(script.contains("latest_cells_cloud_all_preflight"))
        #expect(script.contains("cells-cloud-account-readiness"))
        #expect(script.contains("build/cells-cloud-preflight"))
        #expect(script.contains("provider-count=5"))
        #expect(script.contains("complete=5"))
        #expect(script.contains("blocked=0"))
        #expect(script.contains("scripts/verify-app-bundle.sh"))
        #expect(script.contains("codesign --verify --deep --strict"))
        #expect(script.contains("hdiutil imageinfo"))
        #expect(script.contains("codesign --verify --strict"))
        #expect(script.contains("sparkle:shortVersionString"))
        #expect(script.contains("appcast-dmg-reference"))
        #expect(script.contains("sparkle:edSignature"))
        #expect(script.contains("appcast-enclosure-length"))
        #expect(script.contains("CHANGELOG.md"))
        #expect(script.contains("refs/tags/v${TARGET_VERSION}"))
        #expect(script.contains("blocked=\\${blocked_count}") || script.contains("blocked=${blocked_count}"))
        #expect(!ci.contains("preflight-agent-workspace-release.sh"))
        #expect(!nightly.contains("preflight-agent-workspace-release.sh"))
        #expect(!release.contains("preflight-agent-workspace-release.sh"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)

        let fixtureRoot = try temporaryArtifactRoot(named: "release-preflight")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let result = try runProcess(
            scriptURL,
            arguments: [],
            environment: [
                "COCXY_AGENT_WORKSPACE_RELEASE_PREFLIGHT_ARTIFACTS": fixtureRoot
                    .appendingPathComponent("preflight")
                    .path,
                "COCXY_AGENT_WORKSPACE_RELEASE_APP": fixtureRoot
                    .appendingPathComponent("CocxyTerminal.app")
                    .path,
                "COCXY_AGENT_WORKSPACE_RELEASE_DMG": fixtureRoot
                    .appendingPathComponent("CocxyTerminal-1.18.0.dmg")
                    .path,
                "COCXY_AGENT_WORKSPACE_RELEASE_APPCAST": fixtureRoot
                    .appendingPathComponent("appcast.xml")
                    .path,
                "COCXY_CELLS_CLOUD_PREFLIGHT_ROOT": fixtureRoot
                    .appendingPathComponent("cells-cloud-preflight-root", isDirectory: true)
                    .path,
            ]
        )
        #expect(result.terminationStatus == 0 || result.terminationStatus == 1)
        #expect(result.stdout.contains("targetVersion=1.18.0"))
        #expect(result.stdout.contains("summary="))
        #expect(result.stdout.contains("requirement\tstatus\tevidence\tdetail"))
        #expect(result.stdout.contains("resources-info-version"))
        #expect(result.stdout.contains("cli-fallback-version"))
        #expect(result.stdout.contains("bundle-cli-version"))
        #expect(result.stdout.contains("bundle-contents-verification"))
        #expect(result.stdout.contains("bundle-codesign-verification"))
        #expect(result.stdout.contains("cells-cloud-account-readiness"))
        #expect(result.stdout.contains("cells-cloud-account-readiness\tblocked\t-"))
        #expect(result.stdout.contains("expected provider-count=5 complete=5 blocked=0 before v1.18.0 release target"))
        #expect(result.stdout.contains("dmg-image-verification"))
        #expect(result.stdout.contains("dmg-codesign-verification"))
        #expect(result.stdout.contains("appcast-dmg-reference"))
        #expect(result.stdout.contains("appcast-sparkle-signature"))
        #expect(result.stdout.contains("appcast-enclosure-length"))
    }

    @Test("Agent Workspace release preflight uses newest all-provider cloud preflight")
    func agentWorkspaceReleasePreflightUsesNewestAllProviderCloudPreflight() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/preflight-agent-workspace-release.sh")
        let fixtureRoot = try temporaryArtifactRoot(named: "release-preflight-cloud-selection")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let preflightRoot = fixtureRoot.appendingPathComponent("cells-cloud-preflight", isDirectory: true)
        let olderAll = preflightRoot.appendingPathComponent("20260101-000000", isDirectory: true)
        let newerAll = preflightRoot.appendingPathComponent("20260102-000000", isDirectory: true)
        try writeCellsCloudPreflightFixture(root: olderAll, providerCount: 5)
        try writeCellsCloudPreflightFixture(root: newerAll, providerCount: 5)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: olderAll.appendingPathComponent("preflight.txt").path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2_000)],
            ofItemAtPath: newerAll.appendingPathComponent("preflight.txt").path
        )

        let result = try runProcess(
            scriptURL,
            arguments: [],
            environment: [
                "COCXY_AGENT_WORKSPACE_RELEASE_PREFLIGHT_ARTIFACTS": fixtureRoot
                    .appendingPathComponent("preflight")
                    .path,
                "COCXY_AGENT_WORKSPACE_RELEASE_APP": fixtureRoot
                    .appendingPathComponent("CocxyTerminal.app")
                    .path,
                "COCXY_AGENT_WORKSPACE_RELEASE_DMG": fixtureRoot
                    .appendingPathComponent("CocxyTerminal-1.18.0.dmg")
                    .path,
                "COCXY_AGENT_WORKSPACE_RELEASE_APPCAST": fixtureRoot
                    .appendingPathComponent("appcast.xml")
                    .path,
                "COCXY_CELLS_CLOUD_PREFLIGHT_ROOT": preflightRoot.path,
            ]
        )

        #expect(result.terminationStatus == 1)
        #expect(result.stdout.contains("cells-cloud-account-readiness\tblocked\t\(newerAll.appendingPathComponent("preflight.txt").path)"))
        #expect(!result.stdout.contains("cells-cloud-account-readiness\tblocked\t\(olderAll.appendingPathComponent("preflight.txt").path)"))
    }

    @Test("Cells Operator preflight is read-only and blocks without evidence or explicit scope decision")
    func cellsOperatorPreflightIsReadOnlyAndBlocksWithoutEvidenceOrScopeDecision() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/preflight-cells-operator.sh")
        let smokeURL = root.appendingPathComponent("scripts/smoke-cells-operator.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let smoke = try String(contentsOf: smokeURL, encoding: .utf8)
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
        #expect(FileManager.default.isExecutableFile(atPath: smokeURL.path))
        #expect(script.contains("Read-only preflight"))
        #expect(script.contains("never creates cloud resources"))
        #expect(script.contains("build/cells-operator"))
        #expect(script.contains("2026-05-16-cells-operator-scope-decision.md"))
        #expect(script.contains("result=cells-operator-ok"))
        #expect(script.contains("operator-e2e-artifact"))
        #expect(script.contains("operator-scope-decision"))
        #expect(script.contains("status=\\${overall_status}") || script.contains("status=${overall_status}"))
        #expect(smoke.contains("CellOperatorSwiftTestingTests"))
        #expect(smoke.contains("result=cells-operator-ok"))
        #expect(smoke.contains("providerCount=2"))
        #expect(smoke.contains("lifecycle=ok"))
        #expect(smoke.contains("ownershipRecovery=ok"))
        #expect(smoke.contains("unsafeRequestGuards=ok"))
        #expect(smoke.contains("cloudResources=none"))
        #expect(smoke.contains("userConfigWrites=none"))
        #expect(!ci.contains("preflight-cells-operator.sh"))
        #expect(!nightly.contains("preflight-cells-operator.sh"))
        #expect(!release.contains("preflight-cells-operator.sh"))
        #expect(!ci.contains("smoke-cells-operator.sh"))
        #expect(!nightly.contains("smoke-cells-operator.sh"))
        #expect(!release.contains("smoke-cells-operator.sh"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)
        let smokeSyntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", smokeURL.path])
        #expect(smokeSyntax.terminationStatus == 0)

        let fixtureRoot = try temporaryArtifactRoot(named: "cells-operator-preflight")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let result = try runProcess(
            scriptURL,
            arguments: [],
            environment: [
                "COCXY_CELLS_OPERATOR_PREFLIGHT_ARTIFACTS": fixtureRoot
                    .appendingPathComponent("preflight")
                    .path,
            ]
        )
        #expect(result.terminationStatus == 0 || result.terminationStatus == 1)
        #expect(result.stdout.contains("summary="))
        #expect(result.stdout.contains("requirement\tstatus\tevidence\tdetail"))
        #expect(
            result.stdout.contains("status=complete")
                || result.stdout.contains("status=out-of-scope")
                || result.stdout.contains("status=blocked")
        )
    }

    @Test("Agent Workspace OS accessibility smoke creates VoiceOver and WCAG acceptance evidence")
    func agentWorkspaceAccessibilitySmokeCreatesAcceptanceArtifact() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/smoke-agent-workspace-a11y.sh")
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
        #expect(script.contains("voiceover-ok.txt"))
        #expect(script.contains("result=agent-workspace-a11y-ok"))
        #expect(script.contains("voiceoverAcceptance=source-and-test"))
        #expect(script.contains("wcagAA=ok"))
        #expect(script.contains("surfaces=6"))
        #expect(script.contains("commandPalette.accessibilityLabel"))
        #expect(script.contains("agentDashboard.accessibility"))
        #expect(script.contains("browser.devTools.accessibility"))
        #expect(script.contains("remoteWorkspace.browserSuggestions.open.accessibility"))
        #expect(script.contains("agentTeams.panel.title"))
        #expect(script.contains("codeReview.panel.accessibility"))
        #expect(script.contains("DesignTokensSwiftTestingTests"))
        #expect(script.contains("AccessibilityLabelTests"))
        #expect(script.contains("GlassSurfaceCoverageSwiftTestingTests"))
        #expect(script.contains("contrast_ratio"))
        #expect(script.contains("localization-files"))
        #expect(script.contains("COCXY_A11Y_SKIP_SWIFT_TESTS"))
        #expect(!ci.contains("smoke-agent-workspace-a11y.sh"))
        #expect(!nightly.contains("smoke-agent-workspace-a11y.sh"))
        #expect(!release.contains("smoke-agent-workspace-a11y.sh"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)
    }

    @Test("Cells cloud account smoke is manual, provider scoped, and requires explicit cost consent")
    func cellsCloudAccountSmokeScriptIsManualAndCostGuarded() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/smoke-cells-cloud-account.sh")
        let preflightURL = root.appendingPathComponent("scripts/preflight-cells-cloud-account.sh")
        let setupURL = root.appendingPathComponent("scripts/setup-cells-aws-account.sh")
        let verifyURL = root.appendingPathComponent("scripts/verify-cells-aws-setup.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let preflight = try String(contentsOf: preflightURL, encoding: .utf8)
        let setup = try String(contentsOf: setupURL, encoding: .utf8)
        let verify = try String(contentsOf: verifyURL, encoding: .utf8)
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
        #expect(FileManager.default.isExecutableFile(atPath: preflightURL.path))
        #expect(FileManager.default.isExecutableFile(atPath: setupURL.path))
        #expect(FileManager.default.isExecutableFile(atPath: verifyURL.path))
        #expect(script.contains("COCXY_CELLS_CLOUD_E2E=1"))
        #expect(script.contains("billable user-owned cloud resources"))
        #expect(script.contains("build/cells-cloud-${PROVIDER}"))
        #expect(script.contains("cell create --provider"))
        #expect(script.contains("cell status \"$CELL_ID\" --provider \"$PROVIDER\""))
        #expect(script.contains("wait_for_cell_running()"))
        #expect(script.contains("COCXY_CELLS_CLOUD_STATUS_ATTEMPTS"))
        #expect(script.contains("COCXY_CELLS_CLOUD_STATUS_RETRY_DELAY_SECONDS"))
        #expect(script.contains("cell-status-wait.log"))
        #expect(script.contains("cell-status-attempt-${attempt}.out"))
        #expect(script.contains("\"creating\"|\"provisioning\"|\"pending\"|\"starting\""))
        #expect(script.contains("cell exec \"$CELL_ID\" --provider \"$PROVIDER\""))
        #expect(script.contains("run_cell_exec_with_retries()"))
        #expect(script.contains("default_exec_attempts()"))
        #expect(script.contains("aws) echo 12"))
        #expect(script.contains("COCXY_CELLS_CLOUD_EXEC_ATTEMPTS"))
        #expect(script.contains("COCXY_CELLS_CLOUD_EXEC_RETRY_DELAY_SECONDS"))
        #expect(script.contains("cell-exec-retries.log"))
        #expect(script.contains("cell-exec-attempt-${attempt}.err"))
        #expect(script.contains("cell logs \"$CELL_ID\" --provider \"$PROVIDER\""))
        #expect(script.contains("cell attach \"$CELL_ID\" --provider \"$PROVIDER\""))
        #expect(script.contains("cell list"))
        #expect(script.contains("cell destroy \"$CELL_ID\" --provider \"$PROVIDER\" --force"))
        #expect(script.contains("status=skipped"))
        #expect(script.contains("provider=${PROVIDER}"))
        #expect(script.contains("tee \"$ARTIFACT_ROOT/summary.txt\""))
        #expect(script.contains("result=cells-cloud-${PROVIDER}-ok"))
        #expect(script.contains("record_output_evidence \"createOutput\""))
        #expect(script.contains("record_output_evidence \"destroyOutput\""))
        #expect(script.contains("Sha256="))
        #expect(script.contains("COCXY_E2B_TEMPLATE"))
        #expect(script.contains("COCXY_FLY_APP"))
        #expect(script.contains("COCXY_AWS_IMAGE"))
        #expect(script.contains("COCXY_GCP_PROJECT"))
        #expect(script.contains("COCXY_AZURE_RESOURCE_GROUP"))
        #expect(preflight.contains("read-only"))
        #expect(preflight.contains("never creates cloud resources"))
        #expect(preflight.contains("required_env_names"))
        #expect(preflight.contains("join_missing_prerequisites"))
        #expect(preflight.contains("gcloud services list"))
        #expect(preflight.contains("GCP_COMPUTE_API_NOT_ENABLED"))
        #expect(preflight.contains("write_gcp_diagnostics()"))
        #expect(preflight.contains("gcpDiagnostics="))
        #expect(preflight.contains("activeAccount="))
        #expect(preflight.contains("computeApiEnabled="))
        #expect(preflight.contains("aws ec2 run-instances"))
        #expect(preflight.contains("--dry-run"))
        #expect(preflight.contains("AWS_INVALID_AMI"))
        #expect(preflight.contains("COCXY_AWS_PERMISSION_PROBE_IMAGE"))
        #expect(preflight.contains("aws-run-instances-permission-probe.err"))
        #expect(preflight.contains("aws-run-instances-without-profile-dry-run.err"))
        #expect(preflight.contains("runInstancesWithoutProfileDryRun="))
        #expect(preflight.contains("COCXY_AWS_INSTANCE_PROFILE"))
        #expect(preflight.contains("AWS_INVALID_INSTANCE_PROFILE"))
        #expect(preflight.contains("AWS_IAM_GET_INSTANCE_PROFILE_DENIED"))
        #expect(preflight.contains("AWS_INSTANCE_PROFILE_NOT_FOUND"))
        #expect(preflight.contains("AWS_INSTANCE_PROFILE_HAS_NO_ROLE"))
        #expect(preflight.contains("aws-get-instance-profile.err"))
        #expect(preflight.contains("aws-required-policy.json"))
        #expect(preflight.contains("aws-diagnostic-policy.json"))
        #expect(preflight.contains("aws-setup-principal-policy.json"))
        #expect(preflight.contains("aws-required-setup.md"))
        #expect(preflight.contains("Setup Principal Policy"))
        #expect(preflight.contains("scripts/setup-cells-aws-account.sh"))
        #expect(preflight.contains("scripts/verify-cells-aws-setup.sh"))
        #expect(preflight.contains("setup-principal-policy.json"))
        #expect(preflight.contains("setupPrincipalPolicy="))
        #expect(preflight.contains("COCXY_AWS_SETUP_APPLY=1"))
        #expect(preflight.contains("AmazonSSMManagedInstanceCore"))
        #expect(preflight.contains("iam:PassRole"))
        #expect(preflight.contains("iam:GetInstanceProfile"))
        #expect(preflight.contains("iam:GetRole"))
        #expect(preflight.contains("iam:ListAttachedRolePolicies"))
        #expect(preflight.contains("iam:SimulatePrincipalPolicy"))
        #expect(preflight.contains("Optional Diagnostic Policy"))
        #expect(preflight.contains("Diagnostic Read Access"))
        #expect(preflight.contains("Prefer that generated policy over a broad wildcard copy."))
        #expect(preflight.contains("iam:ListAttachedUserPolicies"))
        #expect(preflight.contains("DryRunOperation` from `ec2:RunInstances` proves only the launch/profile path"))
        #expect(preflight.contains("caller's SSM runtime permissions for exec/logs/attach"))
        #expect(preflight.contains("AWS_SSM_GETPARAMETERS_DENIED"))
        #expect(preflight.contains("write_aws_diagnostics()"))
        #expect(preflight.contains("awsDiagnostics="))
        #expect(preflight.contains("aws configure list-profiles"))
        #expect(preflight.contains("configuredProfileCount="))
        #expect(preflight.contains("profileSource="))
        #expect(preflight.contains("callerIdentityType="))
        #expect(preflight.contains("iamGetUser="))
        #expect(preflight.contains("iamListAttachedUserPolicies="))
        #expect(preflight.contains("iamGetSetupRole="))
        #expect(preflight.contains("iamListRoles="))
        #expect(preflight.contains("iamListInstanceProfiles="))
        #expect(preflight.contains("az vm create"))
        #expect(preflight.contains("--validate"))
        #expect(preflight.contains("AZURE_SKU_NOT_AVAILABLE"))
        #expect(preflight.contains("AZURE_INVALID_ADMIN_USERNAME"))
        #expect(preflight.contains("write_azure_diagnostics()"))
        #expect(preflight.contains("azureDiagnostics="))
        #expect(preflight.contains("COCXY_E2B_TEMPLATE"))
        #expect(preflight.contains("COCXY_FLY_APP"))
        #expect(preflight.contains("COCXY_AWS_REGION"))
        #expect(preflight.contains("COCXY_AWS_PROFILE"))
        #expect(preflight.contains("COCXY_GCP_ZONE"))
        #expect(preflight.contains("COCXY_AZURE_RESOURCE_GROUP"))
        #expect(preflight.contains("latest_ok_summary"))
        #expect(preflight.contains("latest_any_summary"))
        #expect(preflight.contains("latestSmokeArtifact"))
        #expect(preflight.contains("latestSmokeStatus"))
        #expect(preflight.contains("latestSmokeReason"))
        #expect(preflight.contains("latestSmokeOutput"))
        #expect(preflight.contains("verify_cloud_evidence"))
        #expect(preflight.contains("local hash_field=\"${path_field}Sha256\""))
        #expect(preflight.contains("createOutput"))
        #expect(preflight.contains("destroyOutput"))
        #expect(preflight.contains("status=blocked"))
        #expect(preflight.contains("status=ready"))
        #expect(preflight.contains("status=\"complete\""))
        #expect(preflight.contains("total_count"))
        #expect(preflight.contains("[ \"$complete_count\" -eq \"$total_count\" ]"))
        #expect(setup.contains("COCXY_AWS_SETUP_APPLY=1"))
        #expect(setup.contains("status=dry-run"))
        #expect(setup.contains("setup-principal-policy.json"))
        #expect(setup.contains("AWS_OWNER_APPLY_README.md"))
        #expect(setup.contains("OWNER_HANDOFF_README="))
        #expect(setup.contains("write_owner_handoff_readme()"))
        #expect(setup.contains("ownerHandoff="))
        #expect(setup.contains("scripts/run-cells-aws-readiness-sequence.sh"))
        #expect(setup.contains("verify-aws-setup.sh"))
        #expect(setup.contains("verifyScript="))
        #expect(setup.contains("write_verify_script()"))
        #expect(setup.contains("list-attached-role-policies"))
        #expect(setup.contains("COCXY_AWS_IMAGE:?set COCXY_AWS_IMAGE"))
        #expect(setup.contains("scripts/verify-cells-aws-setup.sh"))
        #expect(setup.contains("AmazonSSMManagedInstanceCore"))
        #expect(setup.contains("ensure_role()"))
        #expect(setup.contains("update-assume-role-policy"))
        #expect(setup.contains("iam create-instance-profile"))
        #expect(setup.contains("iam add-role-to-instance-profile"))
        #expect(setup.contains("instance-profile-has-different-role"))
        #expect(setup.contains("already contains role"))
        #expect(setup.contains("COCXY_AWS_SETUP_PROPAGATION_TIMEOUT_SECONDS"))
        #expect(setup.contains("wait_for_instance_profile_role_attachment()"))
        #expect(setup.contains("wait_for_ec2_instance_profile_dry_run()"))
        #expect(setup.contains("profileRolePropagation="))
        #expect(setup.contains("profileDryRunPropagation="))
        #expect(setup.contains("iam list-policy-versions"))
        #expect(setup.contains("iam delete-policy-version"))
        #expect(setup.contains("iam create-policy-version"))
        #expect(setup.contains("caller-policy-version-limit"))
        #expect(setup.contains("iam attach-user-policy"))
        #expect(setup.contains("COCXY_AWS_INSTANCE_PROFILE"))
        #expect(!ci.contains("smoke-cells-cloud-account.sh"))
        #expect(!nightly.contains("smoke-cells-cloud-account.sh"))
        #expect(!release.contains("smoke-cells-cloud-account.sh"))
        #expect(!ci.contains("preflight-cells-cloud-account.sh"))
        #expect(!nightly.contains("preflight-cells-cloud-account.sh"))
        #expect(!release.contains("preflight-cells-cloud-account.sh"))
        #expect(!ci.contains("verify-cells-aws-setup.sh"))
        #expect(!nightly.contains("verify-cells-aws-setup.sh"))
        #expect(!release.contains("verify-cells-aws-setup.sh"))
        #expect(verify.contains("Read-only verifier for AWS Cocxy Cells setup"))
        #expect(verify.contains("does not create, modify, or delete AWS resources"))
        #expect(verify.contains("COCXY_AWS_VERIFY_ARTIFACTS"))
        #expect(verify.contains("checks.tsv"))
        #expect(verify.contains("remediation.md"))
        #expect(verify.contains("write_remediation()"))
        #expect(verify.contains("iam get-role"))
        #expect(verify.contains("iam list-attached-role-policies"))
        #expect(verify.contains("AmazonSSMManagedInstanceCore"))
        #expect(verify.contains("iam get-instance-profile"))
        #expect(verify.contains("InstanceProfile.Roles[].RoleName"))
        #expect(verify.contains("ec2 run-instances"))
        #expect(verify.contains("--dry-run"))
        #expect(verify.contains("run-instances-with-profile-arn-dry-run"))
        #expect(verify.contains("arn:aws:iam::"))
        #expect(verify.contains("aws-setup-ok"))
        #expect(verify.contains("Remediation Sequence"))
        #expect(!verify.contains("create-role"))
        #expect(!verify.contains("create-instance-profile"))
        #expect(!verify.contains("terminate-instances"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)
        let preflightSyntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", preflightURL.path])
        #expect(preflightSyntax.terminationStatus == 0)
        let setupSyntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", setupURL.path])
        #expect(setupSyntax.terminationStatus == 0)
        let verifySyntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", verifyURL.path])
        #expect(verifySyntax.terminationStatus == 0)

        let setupFixtureRoot = try temporaryArtifactRoot(named: "cells-aws-setup")
        defer { try? FileManager.default.removeItem(at: setupFixtureRoot) }
        let setupBinRoot = setupFixtureRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: setupBinRoot, withIntermediateDirectories: true)
        let awsFixture = setupBinRoot.appendingPathComponent("aws")
        try """
        #!/bin/sh
        printf '%s\\n' "$*" >> "\(setupFixtureRoot.appendingPathComponent("verify-aws-calls.log").path)"
        if [ "$1" = "sts" ] && [ "$2" = "get-caller-identity" ]; then
          printf '{"Account":"123456789012","Arn":"arn:aws:iam::123456789012:user/cocxy"}\\n'
          exit 0
        fi
        if [ "$1" = "iam" ] && [ "$2" = "get-role" ]; then
          printf '{"Role":{"RoleName":"CocxyCellsSSMRole"}}\\n'
          exit 0
        fi
        if [ "$1" = "iam" ] && [ "$2" = "list-attached-role-policies" ]; then
          printf '{"AttachedPolicies":[{"PolicyName":"AmazonSSMManagedInstanceCore","PolicyArn":"arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"}]}\\n'
          exit 0
        fi
        if [ "$1" = "iam" ] && [ "$2" = "get-instance-profile" ]; then
          case "$*" in
            *'--query InstanceProfile.Roles[].RoleName --output text'*)
              printf 'CocxyCellsSSMRole\\n'
              ;;
            *)
              printf '{"InstanceProfile":{"InstanceProfileName":"CocxyCellsSSMProfile","Roles":[{"RoleName":"CocxyCellsSSMRole"}]}}\\n'
              ;;
          esac
          exit 0
        fi
        if [ "$1" = "ec2" ] && [ "$2" = "run-instances" ]; then
          if [ "${COCXY_AWS_SIMULATE_PROFILE_PROPAGATION:-0}" = "1" ]; then
            count_file="${COCXY_AWS_FAKE_CALLS}.ec2-count"
            count="$(cat "$count_file" 2>/dev/null || printf '0')"
            count="$((count + 1))"
            printf '%s\\n' "$count" > "$count_file"
            if [ "$count" -le 2 ]; then
              printf 'An error occurred (InvalidParameterValue) when calling the RunInstances operation: Invalid IAM Instance Profile\\n' >&2
              exit 254
            fi
          fi
          printf 'An error occurred (DryRunOperation) when calling the RunInstances operation: Request would have succeeded, but DryRun flag is set.\\n' >&2
          exit 254
        fi
        printf 'unexpected aws call: %s\\n' "$*" >&2
        exit 99
        """.write(to: awsFixture, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: awsFixture.path)

        let setupArtifacts = setupFixtureRoot.appendingPathComponent("aws-setup", isDirectory: true)
        let setupDryRun = try runProcess(
            setupURL,
            arguments: [],
            environment: [
                "PATH": "\(setupBinRoot.path):/usr/bin:/bin",
                "COCXY_AWS_SETUP_ARTIFACTS": setupArtifacts.path,
                "COCXY_AWS_SETUP_ROLE": "CocxyCellsSSMRole",
                "COCXY_AWS_SETUP_INSTANCE_PROFILE": "CocxyCellsSSMProfile",
                "COCXY_AWS_INSTANCE_PROFILE": "CocxyCellsSSMProfile",
            ]
        )
        #expect(setupDryRun.terminationStatus == 0)
        #expect(setupDryRun.stdout.contains("status=dry-run"))
        #expect(setupDryRun.stdout.contains("callerPolicyArn=arn:aws:iam::123456789012:policy/CocxyCellsCallerPolicy"))
        #expect(setupDryRun.stdout.contains("setupPrincipalPolicy="))
        #expect(setupDryRun.stdout.contains("verifyScript="))
        #expect(setupDryRun.stdout.contains("ownerHandoff="))
        #expect(setupDryRun.stdout.contains("attachUser=cocxy"))
        let verifyArtifacts = setupFixtureRoot.appendingPathComponent("aws-verify", isDirectory: true)
        let verifyDryRun = try runProcess(
            verifyURL,
            arguments: [],
            environment: [
                "PATH": "\(setupBinRoot.path):/usr/bin:/bin",
                "COCXY_AWS_VERIFY_ARTIFACTS": verifyArtifacts.path,
                "COCXY_AWS_IMAGE": "ami-fixture",
                "COCXY_AWS_SETUP_ROLE": "CocxyCellsSSMRole",
                "COCXY_AWS_SETUP_INSTANCE_PROFILE": "CocxyCellsSSMProfile",
                "COCXY_AWS_INSTANCE_PROFILE": "CocxyCellsSSMProfile",
            ]
        )
        #expect(verifyDryRun.terminationStatus == 0)
        #expect(verifyDryRun.stdout.contains("status=ok"))
        #expect(verifyDryRun.stdout.contains("result=aws-setup-ok"))
        #expect(verifyDryRun.stdout.contains("roleName=CocxyCellsSSMRole"))
        #expect(verifyDryRun.stdout.contains("instanceProfile=CocxyCellsSSMProfile"))
        let verifySummary = try String(
            contentsOf: verifyArtifacts.appendingPathComponent("summary.txt"),
            encoding: .utf8
        )
        let verifyChecks = try String(
            contentsOf: verifyArtifacts.appendingPathComponent("checks.tsv"),
            encoding: .utf8
        )
        let verifyRemediation = try String(
            contentsOf: verifyArtifacts.appendingPathComponent("remediation.md"),
            encoding: .utf8
        )
        #expect(verifySummary.contains("status=ok"))
        #expect(verifySummary.contains("remediation="))
        #expect(verifyChecks.contains("caller-identity\tok\tcurrent principal"))
        #expect(verifyChecks.contains("role\tok\tCocxyCellsSSMRole"))
        #expect(verifyChecks.contains("role-ssm-policy\tok\tCocxyCellsSSMRole"))
        #expect(verifyChecks.contains("instance-profile\tok\tCocxyCellsSSMProfile"))
        #expect(verifyChecks.contains("instance-profile-roles\tok\tCocxyCellsSSMRole"))
        #expect(verifyChecks.contains("run-instances-with-profile-dry-run\tauthorized\tami-fixture"))
        #expect(verifyChecks.contains("run-instances-with-profile-arn-dry-run\tauthorized\tami-fixture"))
        #expect(verifyChecks.contains("run-instances-without-profile-dry-run\tauthorized\tami-fixture"))
        #expect(verifyRemediation.contains("Expected Green Checks"))
        #expect(verifyRemediation.contains("run-instances-with-profile-arn-dry-run"))
        #expect(verifyRemediation.contains("Remediation Sequence"))
        #expect(verifyRemediation.contains("scripts/setup-cells-aws-account.sh"))
        #expect(verifyRemediation.contains("CocxyCellsSSMRole"))
        #expect(verifyRemediation.contains("CocxyCellsSSMProfile"))
        let setupCommands = try String(
            contentsOf: setupArtifacts.appendingPathComponent("commands.sh"),
            encoding: .utf8
        )
        #expect(setupCommands.contains("iam create-role"))
        #expect(setupCommands.contains("iam create-instance-profile"))
        #expect(setupCommands.contains("iam add-role-to-instance-profile"))
        #expect(setupCommands.contains("iam create-policy"))
        #expect(setupCommands.contains("iam attach-user-policy"))
        let setupTrust = try String(
            contentsOf: setupArtifacts.appendingPathComponent("ec2-trust-policy.json"),
            encoding: .utf8
        )
        let setupCallerPolicy = try String(
            contentsOf: setupArtifacts.appendingPathComponent("caller-policy.json"),
            encoding: .utf8
        )
        let setupPrincipalPolicy = try String(
            contentsOf: setupArtifacts.appendingPathComponent("setup-principal-policy.json"),
            encoding: .utf8
        )
        let setupDiagnosticPolicy = try String(
            contentsOf: setupArtifacts.appendingPathComponent("diagnostic-policy.json"),
            encoding: .utf8
        )
        let setupVerifyScriptURL = setupArtifacts.appendingPathComponent("verify-aws-setup.sh")
        let setupVerifyScript = try String(contentsOf: setupVerifyScriptURL, encoding: .utf8)
        let ownerHandoffURL = setupArtifacts.appendingPathComponent("AWS_OWNER_APPLY_README.md")
        let ownerHandoff = try String(contentsOf: ownerHandoffURL, encoding: .utf8)
        #expect(setupTrust.contains("ec2.amazonaws.com"))
        #expect(setupCallerPolicy.contains("ec2:RunInstances"))
        #expect(setupCallerPolicy.contains("iam:PassRole"))
        #expect(setupCallerPolicy.contains("iam:GetInstanceProfile"))
        #expect(setupCallerPolicy.contains("iam:GetRole"))
        #expect(setupCallerPolicy.contains("iam:ListAttachedRolePolicies"))
        #expect(setupCallerPolicy.contains("arn:aws:iam::123456789012:role/CocxyCellsSSMRole"))
        #expect(setupCallerPolicy.contains("arn:aws:iam::123456789012:instance-profile/CocxyCellsSSMProfile"))
        #expect(setupPrincipalPolicy.contains("sts:GetCallerIdentity"))
        #expect(setupPrincipalPolicy.contains("iam:CreateRole"))
        #expect(setupPrincipalPolicy.contains("iam:PassRole"))
        #expect(setupPrincipalPolicy.contains("arn:aws:iam::123456789012:role/CocxyCellsSSMRole"))
        #expect(setupPrincipalPolicy.contains("iam:GetInstanceProfile"))
        #expect(setupPrincipalPolicy.contains("iam:ListAttachedRolePolicies"))
        #expect(setupPrincipalPolicy.contains("iam:ListInstanceProfiles"))
        #expect(setupPrincipalPolicy.contains("iam:ListRoles"))
        #expect(setupPrincipalPolicy.contains("iam:CreatePolicyVersion"))
        #expect(setupPrincipalPolicy.contains("iam:AttachUserPolicy"))
        #expect(setupDiagnosticPolicy.contains("iam:SimulatePrincipalPolicy"))
        #expect(setupDiagnosticPolicy.contains("iam:ListAttachedUserPolicies"))
        #expect(FileManager.default.isExecutableFile(atPath: setupVerifyScriptURL.path))
        #expect(setupVerifyScript.contains("Read-only AWS setup verification"))
        #expect(setupVerifyScript.contains("COCXY_AWS_IMAGE:?set COCXY_AWS_IMAGE"))
        #expect(setupVerifyScript.contains("aws)"))
        #expect(setupVerifyScript.contains("iam get-role --role-name CocxyCellsSSMRole"))
        #expect(setupVerifyScript.contains("iam list-attached-role-policies --role-name CocxyCellsSSMRole"))
        #expect(setupVerifyScript.contains("iam get-instance-profile --instance-profile-name \"$COCXY_AWS_INSTANCE_PROFILE\""))
        #expect(setupVerifyScript.contains("ec2 run-instances"))
        #expect(setupVerifyScript.contains("--dry-run"))
        #expect(setupVerifyScript.contains("--iam-instance-profile \"Name=$COCXY_AWS_INSTANCE_PROFILE\""))
        #expect(setupVerifyScript.contains("run_ec2_dry_run()"))
        #expect(setupVerifyScript.contains("DryRunOperation"))
        #expect(setupVerifyScript.contains("run-instances-with-profile-arn-dry-run"))
        #expect(setupVerifyScript.contains("--iam-instance-profile \"Arn=$profile_arn\""))
        #expect(ownerHandoff.contains("Do not run this from CI."))
        #expect(ownerHandoff.contains("Do not treat the dry-run bundle as AWS lifecycle success."))
        #expect(ownerHandoff.contains("Do not treat a `DryRunOperation` RunInstances result as exec/logs/attach"))
        #expect(ownerHandoff.contains("must include `iam:PassRole`"))
        #expect(ownerHandoff.contains("export COCXY_AWS_IMAGE=<valid-ami-for-region>"))
        #expect(ownerHandoff.contains("dry-run accepts"))
        #expect(ownerHandoff.contains("caller-policy.json` must include the runtime SSM actions"))
        #expect(ownerHandoff.contains("ssm:SendCommand"))
        #expect(ownerHandoff.contains("ssm:GetCommandInvocation"))
        #expect(ownerHandoff.contains("ssm:ListCommandInvocations"))
        #expect(ownerHandoff.contains("ssm:StartSession"))
        #expect(ownerHandoff.contains("Applying only"))
        #expect(ownerHandoff.contains("iam:PassRole` is insufficient"))
        #expect(ownerHandoff.contains("A green EC2 dry-run only proves `ec2:RunInstances`"))
        #expect(ownerHandoff.contains("AWS is not complete until SSM runtime is proven"))
        #expect(ownerHandoff.contains("COCXY_AWS_SETUP_ROLE` must match the actual role inside"))
        #expect(ownerHandoff.contains("export COCXY_AWS_SETUP_ROLE=CocxyCellsSSMRole"))
        #expect(ownerHandoff.contains("role and instance profile with the same name"))
        #expect(ownerHandoff.contains("less diagnostic-policy.json"))
        #expect(ownerHandoff.contains("diagnostic-policy.json` is optional and read-only"))
        #expect(ownerHandoff.contains("iam:SimulatePrincipalPolicy"))
        #expect(ownerHandoff.contains("ssmRuntimePolicySimulation=allowed"))
        #expect(ownerHandoff.contains("ssmRuntimePolicySimulation=access-denied"))
        #expect(ownerHandoff.contains("COCXY_AWS_SETUP_APPLY=1 scripts/setup-cells-aws-account.sh"))
        #expect(ownerHandoff.contains("scripts/verify-cells-aws-setup.sh"))
        #expect(ownerHandoff.contains("scripts/preflight-cells-cloud-account.sh aws"))
        #expect(ownerHandoff.contains("scripts/smoke-cells-cloud-account.sh aws"))
        #expect(ownerHandoff.contains("scripts/preflight-cells-cloud-account.sh all"))
        #expect(ownerHandoff.contains("scripts/run-cells-aws-readiness-sequence.sh"))
        #expect(ownerHandoff.contains("complete=5"))
        #expect(ownerHandoff.contains("## Definition Of Done"))
        #expect(ownerHandoff.contains("result=cells-cloud-aws-ok"))
        #expect(ownerHandoff.contains("no longer reports AWS"))
        #expect(!ownerHandoff.contains("123456789012"))
        #expect(!ownerHandoff.contains("arn:aws:iam::"))
        let setupVerifySyntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", setupVerifyScriptURL.path])
        #expect(setupVerifySyntax.terminationStatus == 0)
        let generatedVerify = try runProcess(
            setupVerifyScriptURL,
            arguments: [],
            environment: [
                "PATH": "\(setupBinRoot.path):/usr/bin:/bin",
                "COCXY_AWS_IMAGE": "ami-fixture",
                "COCXY_AWS_SETUP_ROLE": "CocxyCellsSSMRole",
                "COCXY_AWS_SETUP_INSTANCE_PROFILE": "CocxyCellsSSMProfile",
                "COCXY_AWS_INSTANCE_PROFILE": "CocxyCellsSSMProfile",
            ]
        )
        #expect(generatedVerify.terminationStatus == 0)
        #expect(generatedVerify.stdout.contains("run-instances-with-profile-dry-run=authorized"))
        #expect(generatedVerify.stdout.contains("run-instances-with-profile-arn-dry-run=authorized"))
        #expect(try iamPolicyActions(from: setupCallerPolicy) == [
            "ec2:CreateTags",
            "ec2:DescribeImages",
            "ec2:DescribeInstances",
            "ec2:DescribeRegions",
            "ec2:RunInstances",
            "ec2:TerminateInstances",
            "iam:GetInstanceProfile",
            "iam:GetRole",
            "iam:ListAttachedRolePolicies",
            "iam:PassRole",
            "ssm:GetCommandInvocation",
            "ssm:ListCommandInvocations",
            "ssm:SendCommand",
            "ssm:StartSession",
        ])
        #expect(try iamPolicyActions(from: setupPrincipalPolicy) == [
            "iam:AddRoleToInstanceProfile",
            "iam:AttachRolePolicy",
            "iam:AttachUserPolicy",
            "iam:CreateInstanceProfile",
            "iam:CreatePolicy",
            "iam:CreatePolicyVersion",
            "iam:CreateRole",
            "iam:DeletePolicyVersion",
            "iam:GetInstanceProfile",
            "iam:GetPolicy",
            "iam:GetRole",
            "iam:ListAttachedRolePolicies",
            "iam:ListInstanceProfiles",
            "iam:ListPolicyVersions",
            "iam:ListRoles",
            "iam:PassRole",
            "iam:UpdateAssumeRolePolicy",
            "sts:GetCallerIdentity",
        ])
        #expect(try iamPolicyActions(from: setupDiagnosticPolicy) == [
            "iam:GetUser",
            "iam:ListAttachedUserPolicies",
            "iam:ListGroupsForUser",
            "iam:ListUserPolicies",
            "iam:SimulatePrincipalPolicy",
        ])

        let applyFixtureRoot = try temporaryArtifactRoot(named: "cells-aws-setup-apply")
        defer { try? FileManager.default.removeItem(at: applyFixtureRoot) }
        let applyBinRoot = applyFixtureRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: applyBinRoot, withIntermediateDirectories: true)
        let applyCallLog = applyFixtureRoot.appendingPathComponent("aws-calls.log")
        let applyAwsFixture = applyBinRoot.appendingPathComponent("aws")
        try """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$COCXY_AWS_FAKE_CALLS"
        if [ "$1" = "sts" ] && [ "$2" = "get-caller-identity" ]; then
          printf '{"Account":"123456789012","Arn":"arn:aws:iam::123456789012:user/cocxy"}\\n'
          exit 0
        fi
        if [ "$1" = "iam" ]; then
          case "$2" in
            get-role|update-assume-role-policy|attach-role-policy|get-policy|delete-policy-version|create-policy-version|attach-user-policy)
              exit 0
              ;;
            get-instance-profile)
              printf 'CocxyCellsSSMRole\\n'
              exit 0
              ;;
            list-policy-versions)
              case "$*" in
                *"length(Versions)"*) printf '5\\n' ;;
                *) printf 'v1\\n' ;;
              esac
              exit 0
              ;;
          esac
        fi
        if [ "$1" = "ec2" ] && [ "$2" = "run-instances" ]; then
          if [ "${COCXY_AWS_SIMULATE_PROFILE_PROPAGATION:-0}" = "1" ]; then
            count_file="${COCXY_AWS_FAKE_CALLS}.ec2-count"
            count="$(cat "$count_file" 2>/dev/null || printf '0')"
            count="$((count + 1))"
            printf '%s\\n' "$count" > "$count_file"
            if [ "$count" -le 2 ]; then
              printf 'An error occurred (InvalidParameterValue) when calling the RunInstances operation: Invalid IAM Instance Profile\\n' >&2
              exit 254
            fi
          fi
          printf 'An error occurred (DryRunOperation) when calling the RunInstances operation: Request would have succeeded, but DryRun flag is set.\\n' >&2
          exit 254
        fi
        printf 'unexpected aws call: %s\\n' "$*" >&2
        exit 99
        """.write(to: applyAwsFixture, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: applyAwsFixture.path)

        let applyArtifacts = applyFixtureRoot.appendingPathComponent("aws-setup", isDirectory: true)
        let setupApply = try runProcess(
            setupURL,
            arguments: [],
            environment: [
                "PATH": "\(applyBinRoot.path):/usr/bin:/bin",
                "COCXY_AWS_FAKE_CALLS": applyCallLog.path,
                "COCXY_AWS_SETUP_APPLY": "1",
                "COCXY_AWS_SETUP_ARTIFACTS": applyArtifacts.path,
                "COCXY_AWS_IMAGE": "ami-fixture",
                "COCXY_AWS_SETUP_ROLE": "CocxyCellsSSMRole",
                "COCXY_AWS_SETUP_INSTANCE_PROFILE": "CocxyCellsSSMProfile",
                "COCXY_AWS_INSTANCE_PROFILE": "CocxyCellsSSMProfile",
                "COCXY_AWS_SIMULATE_PROFILE_PROPAGATION": "1",
                "COCXY_AWS_SETUP_PROPAGATION_INTERVAL_SECONDS": "1",
                "COCXY_AWS_SETUP_PROPAGATION_TIMEOUT_SECONDS": "5",
            ]
        )
        #expect(setupApply.terminationStatus == 0)
        #expect(setupApply.stdout.contains("status=applied"))
        #expect(setupApply.stdout.contains("profileRolePropagation=ok"))
        #expect(setupApply.stdout.contains("profileDryRunPropagation=authorized"))
        let applyCommands = try String(
            contentsOf: applyArtifacts.appendingPathComponent("commands.sh"),
            encoding: .utf8
        )
        #expect(applyCommands.contains("iam update-assume-role-policy"))
        #expect(applyCommands.contains("iam delete-policy-version"))
        #expect(applyCommands.contains("iam create-policy-version"))
        #expect(applyCommands.contains("iam attach-user-policy"))
        #expect(!applyCommands.contains("iam create-role"))
        #expect(!applyCommands.contains("iam create-instance-profile"))
        #expect(!applyCommands.contains("iam add-role-to-instance-profile"))
        let applyCalls = try String(contentsOf: applyCallLog, encoding: .utf8)
        #expect(applyCalls.contains("iam get-role"))
        #expect(applyCalls.contains("iam get-instance-profile"))
        #expect(applyCalls.contains("iam list-policy-versions"))
        #expect(applyCalls.contains("iam create-policy-version"))
        #expect(applyCalls.contains("ec2 run-instances"))
        #expect(applyCalls.split(separator: "\n").filter { $0.contains("ec2 run-instances") }.count >= 4)
        #expect(awsActions(fromCallLog: applyCalls).isSubset(of: try iamPolicyActions(from: setupPrincipalPolicy)))

        let deniedApplyFixtureRoot = try temporaryArtifactRoot(named: "cells-aws-setup-apply-denied")
        defer { try? FileManager.default.removeItem(at: deniedApplyFixtureRoot) }
        let deniedApplyBinRoot = deniedApplyFixtureRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: deniedApplyBinRoot, withIntermediateDirectories: true)
        let deniedApplyCallLog = deniedApplyFixtureRoot.appendingPathComponent("aws-calls.log")
        let deniedApplyAwsFixture = deniedApplyBinRoot.appendingPathComponent("aws")
        try """
        #!/bin/sh
        printf '%s\\n' "$*" >> "$COCXY_AWS_FAKE_CALLS"
        if [ "$1" = "sts" ] && [ "$2" = "get-caller-identity" ]; then
          printf '{"Account":"123456789012","Arn":"arn:aws:iam::123456789012:user/cocxy"}\\n'
          exit 0
        fi
        if [ "$1" = "iam" ]; then
          case "$2" in
            get-role)
              printf 'An error occurred (NoSuchEntity) when calling the GetRole operation: role cannot be found\\n' >&2
              exit 254
              ;;
            get-instance-profile)
              printf 'An error occurred (AccessDenied) when calling the GetInstanceProfile operation: not authorized\\n' >&2
              exit 254
              ;;
          esac
        fi
        printf 'unexpected aws call: %s\\n' "$*" >&2
        exit 99
        """.write(to: deniedApplyAwsFixture, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deniedApplyAwsFixture.path)

        let deniedApplyArtifacts = deniedApplyFixtureRoot.appendingPathComponent("aws-setup", isDirectory: true)
        let setupApplyDenied = try runProcess(
            setupURL,
            arguments: [],
            environment: [
                "PATH": "\(deniedApplyBinRoot.path):/usr/bin:/bin",
                "COCXY_AWS_FAKE_CALLS": deniedApplyCallLog.path,
                "COCXY_AWS_SETUP_APPLY": "1",
                "COCXY_AWS_SETUP_ARTIFACTS": deniedApplyArtifacts.path,
                "COCXY_AWS_SETUP_ROLE": "CocxyCellsSSMRole",
                "COCXY_AWS_SETUP_INSTANCE_PROFILE": "CocxyCellsSSMProfile",
                "COCXY_AWS_INSTANCE_PROFILE": "CocxyCellsSSMProfile",
            ]
        )
        #expect(setupApplyDenied.terminationStatus == 1)
        #expect(setupApplyDenied.stdout.contains("status=blocked"))
        #expect(setupApplyDenied.stdout.contains("reason=apply-preflight-get-instance-profile-failed"))
        let deniedApplyCalls = try String(contentsOf: deniedApplyCallLog, encoding: .utf8)
        #expect(deniedApplyCalls.contains("iam get-role"))
        #expect(deniedApplyCalls.contains("iam get-instance-profile"))
        #expect(!deniedApplyCalls.contains("iam create-role"))
        #expect(!deniedApplyCalls.contains("iam create-instance-profile"))
        #expect(!deniedApplyCalls.contains("iam add-role-to-instance-profile"))

        let fixtureRoot = try temporaryArtifactRoot(named: "cells-cloud-account")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let skipped = try runProcess(
            scriptURL,
            arguments: ["gcp"],
            environment: [
                "COCXY_CELLS_CLOUD_E2E": "",
                "COCXY_CELLS_CLOUD_ARTIFACTS": fixtureRoot
                    .appendingPathComponent("smoke-gcp")
                    .path,
            ]
        )
        #expect(skipped.terminationStatus == 2)
        #expect(skipped.stdout.contains("status=skipped"))
        #expect(skipped.stdout.contains("provider=gcp"))
        #expect(skipped.stdout.contains("COCXY_CELLS_CLOUD_E2E=1"))
        let artifactRootLine = try #require(
            skipped.stdout
                .split(separator: "\n")
                .first { $0.hasPrefix("artifactRoot=") }
        )
        let artifactRoot = URL(
            fileURLWithPath: String(artifactRootLine.dropFirst("artifactRoot=".count))
        )
        let summary = try String(
            contentsOf: artifactRoot.appendingPathComponent("summary.txt"),
            encoding: .utf8
        )
        #expect(summary.contains("status=skipped"))
        #expect(summary.contains("provider=gcp"))
        #expect(summary.contains("reason=set COCXY_CELLS_CLOUD_E2E=1"))

        let preflightResult = try runProcess(
            preflightURL,
            arguments: ["gcp"],
            environment: [
                "COCXY_CELLS_CLOUD_PREFLIGHT_ARTIFACTS": fixtureRoot
                    .appendingPathComponent("preflight-gcp")
                    .path,
                "COCXY_CELLS_CLOUD_ARTIFACT_ROOT": fixtureRoot
                    .appendingPathComponent("cloud-artifacts")
                    .path,
                "COCXY_GCP_IMAGE": "",
                "COCXY_GCP_PROJECT": "",
                "COCXY_GCP_ZONE": "",
            ]
        )
        #expect(preflightResult.terminationStatus == 0 || preflightResult.terminationStatus == 1)
        #expect(preflightResult.stdout.contains("provider\tstatus\ttool\ttoolStatus\tmissingPrerequisites\tokArtifact"))
        #expect(preflightResult.stdout.contains("gcp\t"))
        #expect(preflightResult.stdout.contains("gcloud"))
        #expect(preflightResult.stdout.contains("COCXY_GCP_IMAGE"))
    }

    @Test("Cells AWS setup verifier treats IAM inspection denial as ready when EC2 dry-runs are authorized")
    func cellsAWSSetupVerifierTreatsIAMInspectionDeniedAsReadyWhenDryRunsAreAuthorized() throws {
        let root = repositoryRoot()
        let verifyURL = root.appendingPathComponent("scripts/verify-cells-aws-setup.sh")
        let fixtureRoot = try temporaryArtifactRoot(named: "cells-aws-setup-verify-ready")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let binRoot = fixtureRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binRoot, withIntermediateDirectories: true)
        let aws = binRoot.appendingPathComponent("aws")
        try """
        #!/bin/sh
        if [ "$1" = "sts" ] && [ "$2" = "get-caller-identity" ]; then
          printf '{"Account":"123456789012","Arn":"arn:aws:iam::123456789012:user/cocxy"}\\n'
          exit 0
        fi
        if [ "$1" = "iam" ]; then
          case "$2" in
            get-role|list-attached-role-policies|get-instance-profile)
              printf 'An error occurred (AccessDenied) when calling the %s operation: User is not authorized\\n' "$2" >&2
              exit 254
              ;;
          esac
        fi
        if [ "$1" = "ec2" ] && [ "$2" = "run-instances" ]; then
          printf 'An error occurred (DryRunOperation) when calling the RunInstances operation: Request would have succeeded, but DryRun flag is set.\\n' >&2
          exit 254
        fi
        printf 'unexpected aws call: %s\\n' "$*" >&2
        exit 99
        """.write(to: aws, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: aws.path)

        let verifyArtifacts = fixtureRoot.appendingPathComponent("verify", isDirectory: true)
        let result = try runProcess(
            verifyURL,
            arguments: [],
            environment: [
                "PATH": "\(binRoot.path):/usr/bin:/bin",
                "COCXY_AWS_VERIFY_ARTIFACTS": verifyArtifacts.path,
                "COCXY_AWS_IMAGE": "ami-fixture",
                "COCXY_AWS_INSTANCE_PROFILE": "cocxy-cells-ec2-role",
            ]
        )

        #expect(result.terminationStatus == 0)
        #expect(result.stdout.contains("status=ready"))
        #expect(result.stdout.contains("result=aws-setup-ready"))
        #expect(result.stdout.contains("blockers=-"))
        #expect(result.stdout.contains("warnings=role:access-denied,role-ssm-policy:access-denied,instance-profile:access-denied,instance-profile-roles:access-denied"))

        let checks = try String(
            contentsOf: verifyArtifacts.appendingPathComponent("checks.tsv"),
            encoding: .utf8
        )
        #expect(checks.contains("role\taccess-denied\tCocxyCellsSSMRole"))
        #expect(checks.contains("role-ssm-policy\taccess-denied\tCocxyCellsSSMRole"))
        #expect(checks.contains("instance-profile\taccess-denied\tcocxy-cells-ec2-role"))
        #expect(checks.contains("instance-profile-roles\taccess-denied\tcocxy-cells-ec2-role"))
        #expect(checks.contains("run-instances-with-profile-dry-run\tauthorized\tami-fixture"))
        #expect(checks.contains("run-instances-with-profile-arn-dry-run\tauthorized\tami-fixture"))
        #expect(checks.contains("run-instances-without-profile-dry-run\tauthorized\tami-fixture"))
    }

    @Test("Cells AWS readiness sequence is manual, ordered, and cost guarded")
    func cellsAWSReadinessSequenceIsManualOrderedAndCostGuarded() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/run-cells-aws-readiness-sequence.sh")
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
        #expect(script.contains("Manual AWS Cells readiness sequence"))
        #expect(script.contains("refuses to run from CI"))
        #expect(script.contains("COCXY_CELLS_CLOUD_E2E=1"))
        #expect(script.contains("billable user-owned AWS resources"))
        #expect(script.contains("build/cells-aws-readiness-sequence"))
        #expect(script.contains("summary.txt"))
        #expect(script.contains("step-results.tsv"))
        #expect(script.contains("COCXY_AWS_SETUP_APPLY"))
        #expect(!script.contains("COCXY_AWS_SETUP_APPLY=1"))
        #expect(script.contains("COCXY_AWS_VERIFY_ARTIFACTS"))
        #expect(script.contains("COCXY_CELLS_CLOUD_PREFLIGHT_ARTIFACTS"))
        #expect(script.contains("COCXY_CELLS_CLOUD_ARTIFACTS"))
        #expect(script.contains("scripts/verify-cells-aws-setup.sh"))
        #expect(script.contains("scripts/preflight-cells-cloud-account.sh aws"))
        #expect(script.contains("scripts/smoke-cells-cloud-account.sh aws"))
        #expect(script.contains("scripts/preflight-cells-cloud-account.sh all"))
        #expect(script.contains("scripts/audit-agent-workspace-os-completion.sh"))
        #expect(script.contains("awsSmoke=skipped-cost-guard"))
        #expect(script.contains("result=cells-aws-readiness-sequence-ok"))
        #expect(script.contains("audit-agent-workspace-os-completion.out"))

        let verifyRange = try #require(script.range(of: "scripts/verify-cells-aws-setup.sh"))
        let awsPreflightRange = try #require(script.range(of: "scripts/preflight-cells-cloud-account.sh aws"))
        let smokeRange = try #require(script.range(of: "scripts/smoke-cells-cloud-account.sh aws"))
        let allPreflightRange = try #require(script.range(of: "scripts/preflight-cells-cloud-account.sh all"))
        let auditRange = try #require(script.range(of: "scripts/audit-agent-workspace-os-completion.sh"))
        #expect(verifyRange.lowerBound < awsPreflightRange.lowerBound)
        #expect(awsPreflightRange.lowerBound < smokeRange.lowerBound)
        #expect(smokeRange.lowerBound < allPreflightRange.lowerBound)
        #expect(allPreflightRange.lowerBound < auditRange.lowerBound)

        #expect(!ci.contains("run-cells-aws-readiness-sequence.sh"))
        #expect(!nightly.contains("run-cells-aws-readiness-sequence.sh"))
        #expect(!release.contains("run-cells-aws-readiness-sequence.sh"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)
    }

    @Test("Cells AWS readiness sequence stops before smoke when verifier fails")
    func cellsAWSReadinessSequenceStopsBeforeSmokeWhenVerifierFails() throws {
        let root = repositoryRoot()
        let fixtureRoot = try temporaryArtifactRoot(named: "cells-aws-readiness-sequence")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let scriptsRoot = fixtureRoot.appendingPathComponent("scripts", isDirectory: true)
        try FileManager.default.createDirectory(at: scriptsRoot, withIntermediateDirectories: true)

        let sourceScript = root.appendingPathComponent("scripts/run-cells-aws-readiness-sequence.sh")
        let fixtureScript = scriptsRoot.appendingPathComponent("run-cells-aws-readiness-sequence.sh")
        try String(contentsOf: sourceScript, encoding: .utf8)
            .write(to: fixtureScript, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixtureScript.path)

        let callLog = fixtureRoot.appendingPathComponent("calls.log")
        func writeExecutableScript(_ name: String, _ body: String) throws {
            let url = scriptsRoot.appendingPathComponent(name)
            try body.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        try writeExecutableScript("verify-cells-aws-setup.sh", """
        #!/bin/sh
        printf 'verify\\n' >> "\(callLog.path)"
        printf 'status=blocked\\n'
        exit 1
        """)
        try writeExecutableScript("preflight-cells-cloud-account.sh", """
        #!/bin/sh
        printf 'preflight %s\\n' "$*" >> "\(callLog.path)"
        exit 0
        """)
        try writeExecutableScript("smoke-cells-cloud-account.sh", """
        #!/bin/sh
        printf 'smoke %s\\n' "$*" >> "\(callLog.path)"
        exit 0
        """)
        try writeExecutableScript("audit-agent-workspace-os-completion.sh", """
        #!/bin/sh
        printf 'audit\\n' >> "\(callLog.path)"
        exit 0
        """)

        let artifactRoot = fixtureRoot.appendingPathComponent("artifacts", isDirectory: true)
        let result = try runProcess(
            fixtureScript,
            arguments: [],
            environment: [
                "CI": "",
                "COCXY_AWS_SETUP_APPLY": "",
                "COCXY_CELLS_AWS_READINESS_ARTIFACTS": artifactRoot.path,
            ]
        )

        #expect(result.terminationStatus == 1)
        #expect(result.stdout.contains("status=blocked"))
        #expect(result.stdout.contains("scripts/verify-cells-aws-setup.sh failed"))

        let calls = try String(contentsOf: callLog, encoding: .utf8)
        #expect(calls.contains("verify"))
        #expect(!calls.contains("preflight"))
        #expect(!calls.contains("smoke"))
        #expect(!calls.contains("audit"))

        let steps = try String(contentsOf: artifactRoot.appendingPathComponent("step-results.tsv"), encoding: .utf8)
        #expect(steps.contains("verify-aws-setup\tfailed\t1"))
    }

    @Test("Cells cloud preflight blocks GCP when Compute Engine API is not enabled")
    func cellsCloudPreflightBlocksGCPWhenComputeAPIIsNotEnabled() throws {
        let root = repositoryRoot()
        let preflightURL = root.appendingPathComponent("scripts/preflight-cells-cloud-account.sh")
        let fixtureRoot = try temporaryArtifactRoot(named: "cells-cloud-gcp-service-preflight")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let binRoot = fixtureRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binRoot, withIntermediateDirectories: true)
        let gcloud = binRoot.appendingPathComponent("gcloud")
        try """
        #!/bin/sh
        if [ "$1" = "auth" ] && [ "$2" = "list" ]; then
          printf 'fixture@example.com\\n'
          exit 0
        fi
        if [ "$1" = "services" ] && [ "$2" = "list" ]; then
          exit 0
        fi
        exit 0
        """.write(to: gcloud, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gcloud.path)

        let result = try runProcess(
            preflightURL,
            arguments: ["gcp"],
            environment: [
                "PATH": "\(binRoot.path):/usr/bin:/bin",
                "COCXY_CELLS_CLOUD_ARTIFACT_ROOT": fixtureRoot
                    .appendingPathComponent("cloud-artifacts")
                    .path,
                "COCXY_CELLS_CLOUD_PREFLIGHT_ARTIFACTS": fixtureRoot
                    .appendingPathComponent("preflight")
                    .path,
                "COCXY_GCP_IMAGE": "projects/debian-cloud/global/images/family/debian-12",
                "COCXY_GCP_PROJECT": "fixture-project",
                "COCXY_GCP_ZONE": "us-central1-a",
            ]
        )

        #expect(result.terminationStatus == 1)
        #expect(result.stdout.contains("status=blocked"))
        #expect(result.stdout.contains("blocked=1"))
        #expect(result.stdout.contains("ready=0"))
        #expect(result.stdout.contains("gcp\tblocked\tgcloud\tpresent\tGCP_COMPUTE_API_NOT_ENABLED\t-"))

        let preflight = fixtureRoot.appendingPathComponent("preflight/preflight.txt")
        let preflightContents = try String(contentsOf: preflight, encoding: .utf8)
        #expect(preflightContents.contains("gcpDiagnostics="))
        let diagnostics = fixtureRoot.appendingPathComponent("preflight/gcp-diagnostics.txt")
        let diagnosticsContents = try String(contentsOf: diagnostics, encoding: .utf8)
        #expect(diagnosticsContents.contains("project=fixture-project"))
        #expect(diagnosticsContents.contains("activeAccount=fixture@example.com"))
        #expect(diagnosticsContents.contains("computeApiEnabled=no"))
    }

    @Test("Cells cloud preflight reports AWS instance profile IAM access denial explicitly")
    func cellsCloudPreflightReportsAWSInstanceProfileAccessDenied() throws {
        let root = repositoryRoot()
        let preflightURL = root.appendingPathComponent("scripts/preflight-cells-cloud-account.sh")
        let fixtureRoot = try temporaryArtifactRoot(named: "cells-cloud-aws-profile-access-preflight")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let latestSmokeRoot = fixtureRoot
            .appendingPathComponent("cloud-artifacts/cells-cloud-aws/20260101-000000", isDirectory: true)
        try FileManager.default.createDirectory(at: latestSmokeRoot, withIntermediateDirectories: true)
        let latestSmokeError = latestSmokeRoot.appendingPathComponent("cell-exec.err")
        try "AccessDeniedException: ssm:SendCommand denied\n"
            .write(to: latestSmokeError, atomically: true, encoding: .utf8)
        try """
        status=failed
        provider=aws
        reason=cell exec failed
        output=\(latestSmokeError.path)
        """.write(to: latestSmokeRoot.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)

        let binRoot = fixtureRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binRoot, withIntermediateDirectories: true)
        let aws = binRoot.appendingPathComponent("aws")
        try """
        #!/bin/sh
        if [ "$1" = "configure" ] && [ "$2" = "list-profiles" ]; then
          printf 'fixture-profile\\nother-profile\\n'
          exit 0
        fi
        if [ "$1" = "sts" ] && [ "$2" = "get-caller-identity" ]; then
          case " $* " in
            *" --profile fixture-profile "*) printf 'arn:aws:iam::123456789012:user/cocxy-profile\\n' ;;
            *) printf 'arn:aws:iam::123456789012:user/default\\n' ;;
          esac
          exit 0
        fi
        if [ "$1" = "iam" ] && [ "$2" = "get-instance-profile" ]; then
          printf 'An error occurred (AccessDenied) when calling the GetInstanceProfile operation: User is not authorized to perform: iam:GetInstanceProfile\\n' >&2
          exit 254
        fi
        if [ "$1" = "iam" ]; then
          case "$2" in
            simulate-principal-policy)
              printf 'An error occurred (AccessDenied) when calling the SimulatePrincipalPolicy operation: User is not authorized\\n' >&2
              exit 254
              ;;
            get-user|list-attached-user-policies|list-user-policies|list-groups-for-user|get-role|list-roles|list-instance-profiles)
              printf 'An error occurred (AccessDenied) when calling the %s operation: User is not authorized\\n' "$2" >&2
              exit 254
              ;;
          esac
        fi
        if [ "$1" = "ec2" ] && [ "$2" = "run-instances" ]; then
          case " $* " in
            *" --iam-instance-profile "*) printf 'An error occurred (InvalidParameterValue) when calling the RunInstances operation: Invalid IAM Instance Profile name\\n' >&2 ;;
            *) printf 'An error occurred (DryRunOperation) when calling the RunInstances operation: Request would have succeeded, but DryRun flag is set.\\n' >&2 ;;
          esac
          exit 255
        fi
        printf 'unexpected aws call: %s\\n' "$*" >&2
        exit 99
        """.write(to: aws, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: aws.path)

        let result = try runProcess(
            preflightURL,
            arguments: ["aws"],
            environment: [
                "PATH": "\(binRoot.path):/usr/bin:/bin",
                "COCXY_CELLS_CLOUD_ARTIFACT_ROOT": fixtureRoot
                    .appendingPathComponent("cloud-artifacts")
                    .path,
                "COCXY_CELLS_CLOUD_PREFLIGHT_ARTIFACTS": fixtureRoot
                    .appendingPathComponent("preflight")
                    .path,
                "COCXY_AWS_REGION": "us-east-1",
                "COCXY_AWS_IMAGE": "ami-fixture",
                "COCXY_AWS_INSTANCE_PROFILE": "CocxyCellsSSMProfile",
                "COCXY_AWS_PROFILE": "fixture-profile",
                "COCXY_AWS_PERMISSION_PROBE_IMAGE": "ami-probe",
            ]
        )

        #expect(result.terminationStatus == 1)
        #expect(result.stdout.contains("status=blocked"))
        #expect(result.stdout.contains("aws\tblocked\taws\tpresent\tAWS_INVALID_INSTANCE_PROFILE,AWS_IAM_GET_INSTANCE_PROFILE_DENIED\t-"))
        #expect(result.stdout.contains("\(latestSmokeRoot.appendingPathComponent("summary.txt").path)\tfailed\tcell exec failed\t\(latestSmokeError.path)"))
        let diagnostics = fixtureRoot.appendingPathComponent("preflight/aws-diagnostics.txt")
        let diagnosticsContents = try String(contentsOf: diagnostics, encoding: .utf8)
        #expect(diagnosticsContents.contains("instanceProfile=CocxyCellsSSMProfile"))
        #expect(diagnosticsContents.contains("instanceProfileCheck=AWS_IAM_GET_INSTANCE_PROFILE_DENIED"))
        #expect(diagnosticsContents.contains("identity=arn:aws:iam::123456789012:user/cocxy-profile"))
        #expect(!diagnosticsContents.contains("identity=arn:aws:iam::123456789012:user/default"))
        #expect(diagnosticsContents.contains("profile=fixture-profile"))
        #expect(diagnosticsContents.contains("profileSource=COCXY_AWS_PROFILE"))
        #expect(diagnosticsContents.contains("configuredProfileCount=2"))
        #expect(diagnosticsContents.contains("callerIdentityType=user"))
        #expect(diagnosticsContents.contains("iamGetUser=access-denied"))
        #expect(diagnosticsContents.contains("iamListAttachedUserPolicies=access-denied"))
        #expect(diagnosticsContents.contains("iamListUserPolicies=access-denied"))
        #expect(diagnosticsContents.contains("iamListGroupsForUser=access-denied"))
        #expect(diagnosticsContents.contains("setupRole=CocxyCellsSSMRole"))
        #expect(diagnosticsContents.contains("iamGetSetupRole=access-denied"))
        #expect(diagnosticsContents.contains("iamListRoles=access-denied"))
        #expect(diagnosticsContents.contains("iamListInstanceProfiles=access-denied"))
        #expect(diagnosticsContents.contains("ssmRuntimePolicySimulation=access-denied"))
        #expect(diagnosticsContents.contains("ssmRuntimePolicySimulationOutput="))
        #expect(diagnosticsContents.contains("ssmRuntimePolicySimulationError="))
        #expect(diagnosticsContents.contains("runInstancesDryRun=AWS_INVALID_INSTANCE_PROFILE,AWS_IAM_GET_INSTANCE_PROFILE_DENIED"))
        #expect(diagnosticsContents.contains("runInstancesProfileArnDryRun=AWS_INVALID_INSTANCE_PROFILE"))
        #expect(diagnosticsContents.contains("runInstancesProfileArnDryRunOutput="))
        #expect(diagnosticsContents.contains("runInstancesProfileArnDryRunError="))
        #expect(diagnosticsContents.contains("runInstancesWithoutProfileDryRun=authorized"))
        #expect(diagnosticsContents.contains("permissionProbeImage=ami-probe"))
        #expect(diagnosticsContents.contains("permissionProbeStatus=not-run"))
        #expect(!diagnosticsContents.contains("permissionProbeOutput="))
        #expect(!diagnosticsContents.contains("permissionProbeError="))
        #expect(diagnosticsContents.contains("instanceProfileLookupError="))
        #expect(diagnosticsContents.contains("setupPrincipalPolicy="))
        #expect(diagnosticsContents.contains("diagnosticPolicy="))
        let requiredSetup = try String(
            contentsOf: fixtureRoot
                .appendingPathComponent("preflight/aws-required-setup.md"),
            encoding: .utf8
        )
        #expect(requiredSetup.contains("export COCXY_AWS_SETUP_ROLE=<role-inside-instance-profile>"))
        #expect(requiredSetup.contains("COCXY_AWS_SETUP_ROLE` to the actual role inside"))
        #expect(requiredSetup.contains("same value for both `COCXY_AWS_SETUP_ROLE` and `COCXY_AWS_INSTANCE_PROFILE`"))
        #expect(requiredSetup.contains("aws iam get-role --role-name \"$COCXY_AWS_SETUP_ROLE\""))
        let requiredPolicy = try String(
            contentsOf: fixtureRoot
                .appendingPathComponent("preflight/aws-required-policy.json"),
            encoding: .utf8
        )
        let diagnosticPolicy = try String(
            contentsOf: fixtureRoot
                .appendingPathComponent("preflight/aws-diagnostic-policy.json"),
            encoding: .utf8
        )
        #expect(requiredPolicy.contains("arn:aws:iam::123456789012:role/CocxyCellsSSMRole"))
        #expect(requiredPolicy.contains("arn:aws:iam::123456789012:instance-profile/CocxyCellsSSMProfile"))
        #expect(requiredPolicy.contains("iam:GetRole"))
        #expect(requiredPolicy.contains("iam:ListAttachedRolePolicies"))
        #expect(diagnosticPolicy.contains("iam:SimulatePrincipalPolicy"))
        #expect(diagnosticPolicy.contains("iam:ListAttachedUserPolicies"))
        #expect(
            FileManager.default.fileExists(
                atPath: fixtureRoot
                    .appendingPathComponent("preflight/aws-run-instances-profile-arn-dry-run.err")
                    .path
            )
        )
        let setupPrincipalPolicy = try String(
            contentsOf: fixtureRoot
                .appendingPathComponent("preflight/aws-setup-principal-policy.json"),
            encoding: .utf8
        )
        #expect(setupPrincipalPolicy.contains("arn:aws:iam::123456789012:role/CocxyCellsSSMRole"))
        #expect(try iamPolicyActions(from: setupPrincipalPolicy) == [
            "iam:AddRoleToInstanceProfile",
            "iam:AttachRolePolicy",
            "iam:AttachUserPolicy",
            "iam:CreateInstanceProfile",
            "iam:CreatePolicy",
            "iam:CreatePolicyVersion",
            "iam:CreateRole",
            "iam:DeletePolicyVersion",
            "iam:GetInstanceProfile",
            "iam:GetPolicy",
            "iam:GetRole",
            "iam:ListAttachedRolePolicies",
            "iam:ListInstanceProfiles",
            "iam:ListPolicyVersions",
            "iam:ListRoles",
            "iam:PassRole",
            "iam:UpdateAssumeRolePolicy",
            "sts:GetCallerIdentity",
        ])
    }

    @Test("Cells cloud preflight marks AWS permission probe artifacts only when the probe runs")
    func cellsCloudPreflightMarksAWSPermissionProbeArtifactsWhenProbeRuns() throws {
        let root = repositoryRoot()
        let preflightURL = root.appendingPathComponent("scripts/preflight-cells-cloud-account.sh")
        let fixtureRoot = try temporaryArtifactRoot(named: "cells-cloud-aws-permission-probe-preflight")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let binRoot = fixtureRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: binRoot, withIntermediateDirectories: true)
        let aws = binRoot.appendingPathComponent("aws")
        try """
        #!/bin/sh
        if [ "$1" = "sts" ] && [ "$2" = "get-caller-identity" ]; then
          printf 'arn:aws:iam::123456789012:user/cocxy\\n'
          exit 0
        fi
        if [ "$1" = "iam" ] && [ "$2" = "get-instance-profile" ]; then
          printf 'CocxyCellsSSMRole\\n'
          exit 0
        fi
        if [ "$1" = "iam" ] && [ "$2" = "simulate-principal-policy" ]; then
          printf '{"EvaluationResults":[{"EvalActionName":"ssm:SendCommand","EvalDecision":"allowed"},{"EvalActionName":"ssm:GetCommandInvocation","EvalDecision":"allowed"},{"EvalActionName":"ssm:ListCommandInvocations","EvalDecision":"allowed"},{"EvalActionName":"ssm:StartSession","EvalDecision":"allowed"}]}\\n'
          exit 0
        fi
        if [ "$1" = "ec2" ] && [ "$2" = "run-instances" ]; then
          case " $* " in
            *" --image-id ami-bad "*) printf 'An error occurred (InvalidAMIID.NotFound) when calling the RunInstances operation: ami does not exist\\n' >&2 ;;
            *" --image-id ami-probe "*) printf 'An error occurred (UnauthorizedOperation) when calling the RunInstances operation: not authorized\\n' >&2 ;;
            *) printf 'unexpected run-instances image: %s\\n' "$*" >&2 ;;
          esac
          exit 255
        fi
        printf 'unexpected aws call: %s\\n' "$*" >&2
        exit 99
        """.write(to: aws, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: aws.path)

        let result = try runProcess(
            preflightURL,
            arguments: ["aws"],
            environment: [
                "PATH": "\(binRoot.path):/usr/bin:/bin",
                "COCXY_CELLS_CLOUD_ARTIFACT_ROOT": fixtureRoot
                    .appendingPathComponent("cloud-artifacts")
                    .path,
                "COCXY_CELLS_CLOUD_PREFLIGHT_ARTIFACTS": fixtureRoot
                    .appendingPathComponent("preflight")
                    .path,
                "COCXY_AWS_REGION": "us-east-1",
                "COCXY_AWS_IMAGE": "ami-bad",
                "COCXY_AWS_INSTANCE_PROFILE": "CocxyCellsSSMProfile",
                "COCXY_AWS_PERMISSION_PROBE_IMAGE": "ami-probe",
            ]
        )

        #expect(result.terminationStatus == 1)
        #expect(result.stdout.contains("aws\tblocked\taws\tpresent\tAWS_INVALID_AMI,AWS_RUNINSTANCES_UNAUTHORIZED\t-"))
        let diagnostics = fixtureRoot.appendingPathComponent("preflight/aws-diagnostics.txt")
        let diagnosticsContents = try String(contentsOf: diagnostics, encoding: .utf8)
        #expect(diagnosticsContents.contains("runInstancesDryRun=AWS_INVALID_AMI,AWS_RUNINSTANCES_UNAUTHORIZED"))
        #expect(diagnosticsContents.contains("runInstancesWithoutProfileDryRun=AWS_INVALID_AMI"))
        #expect(diagnosticsContents.contains("ssmRuntimePolicySimulation=allowed"))
        #expect(diagnosticsContents.contains("permissionProbeImage=ami-probe"))
        #expect(diagnosticsContents.contains("permissionProbeStatus=ran"))
        #expect(diagnosticsContents.contains("permissionProbeOutput="))
        #expect(diagnosticsContents.contains("permissionProbeError="))
        #expect(
            FileManager.default.fileExists(
                atPath: fixtureRoot
                    .appendingPathComponent("preflight/aws-run-instances-permission-probe.err")
                    .path
            )
        )
    }

    @Test("Cells cloud preflight rejects fabricated OK summaries without output evidence hashes")
    func cellsCloudPreflightRejectsFabricatedOKSummary() throws {
        let root = repositoryRoot()
        let preflightURL = root.appendingPathComponent("scripts/preflight-cells-cloud-account.sh")
        let fixtureRoot = try temporaryArtifactRoot(named: "cells-cloud-fabricated-summary")
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }

        let cellsCloudRoot = fixtureRoot.appendingPathComponent("cells-cloud", isDirectory: true)
        let summaryRoot = cellsCloudRoot
            .appendingPathComponent("cells-cloud-gcp/20260101-000000", isDirectory: true)
        try FileManager.default.createDirectory(at: summaryRoot, withIntermediateDirectories: true)
        try """
        status=ok
        provider=gcp
        create=ok
        status-check=ok
        exec=ok
        logs=ok
        attach=ok
        list=ok
        destroy=ok
        result=cells-cloud-gcp-ok
        """.write(to: summaryRoot.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)

        let result = try runProcess(
            preflightURL,
            arguments: ["gcp"],
            environment: [
                "COCXY_CELLS_CLOUD_ARTIFACT_ROOT": cellsCloudRoot.path,
                "COCXY_CELLS_CLOUD_PREFLIGHT_ARTIFACTS": fixtureRoot
                    .appendingPathComponent("preflight")
                    .path,
                "COCXY_GCP_IMAGE": "",
                "COCXY_GCP_PROJECT": "",
                "COCXY_GCP_ZONE": "",
            ]
        )
        #expect(result.terminationStatus == 1)
        #expect(result.stdout.contains("gcp\tblocked\tgcloud"))
        #expect(!result.stdout.contains("20260101-000000/summary.txt"))
    }

    @Test("Cells Docker smoke script is manual, skippable, and covers the full lifecycle")
    func cellsDockerSmokeScriptIsManualSkippableAndLifecycleBacked() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/smoke-cells-docker.sh")
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
        #expect(script.contains("status=skipped"))
        #expect(script.contains("artifactRoot=${ARTIFACT_ROOT}"))
        #expect(script.contains("docker info"))
        #expect(script.contains("COCXY_CELLS_DOCKER_IMAGE"))
        #expect(script.contains("cell create --provider docker --image \"$CELL_IMAGE\""))
        #expect(script.contains("cell exec"))
        #expect(script.contains("cell status"))
        #expect(script.contains("cell logs"))
        #expect(script.contains("cell list"))
        #expect(script.contains("cell destroy"))
        #expect(script.contains("cells-docker-ok"))
        #expect(script.contains("summary.txt"))
        #expect(script.contains("tee \"$ARTIFACT_ROOT/summary.txt\""))
        #expect(!ci.contains("smoke-cells-docker.sh"))
        #expect(!nightly.contains("smoke-cells-docker.sh"))
        #expect(!release.contains("smoke-cells-docker.sh"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)
    }

    @Test("Cells local SSH smoke script is manual, skippable, and covers the full lifecycle")
    func cellsLocalSSHSmokeScriptIsManualSkippableAndLifecycleBacked() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/smoke-cells-local-ssh.sh")
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
        #expect(script.contains("write_summary \"skipped\""))
        #expect(script.contains("COCXY_CELLS_SSH_PROVIDER"))
        #expect(script.contains("self-hosted"))
        #expect(script.contains("cells-self-hosted-ok"))
        #expect(script.contains("summary.txt"))
        #expect(script.contains("tee \"$ARTIFACT_ROOT/summary.txt\""))
        #expect(script.contains("/usr/sbin/sshd"))
        #expect(script.contains("cell create --provider \"$PROVIDER\""))
        #expect(script.contains("provider=${PROVIDER}"))
        #expect(script.contains("--host 127.0.0.1"))
        #expect(script.contains("cell exec"))
        #expect(script.contains("cell status"))
        #expect(script.contains("cell list"))
        #expect(script.contains("cell destroy"))
        #expect(script.contains("cells-ssh-ok"))
        #expect(!ci.contains("smoke-cells-local-ssh.sh"))
        #expect(!nightly.contains("smoke-cells-local-ssh.sh"))
        #expect(!release.contains("smoke-cells-local-ssh.sh"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)
    }

    @Test("Cells attach bundle smoke script exercises one-shot WebSocket PTY without CI flakiness")
    func cellsAttachBundleSmokeScriptIsManualAndWebSocketBacked() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/smoke-cells-attach-bundle.sh")
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
        #expect(script.contains("build/CocxyTerminal.app"))
        #expect(script.contains("cell create --provider ssh"))
        #expect(script.contains("cell attach"))
        #expect(script.contains("Authorization"))
        #expect(script.contains("auth_fail"))
        #expect(script.contains("auth_ok"))
        #expect(script.contains("capture-pane"))
        #expect(script.contains("replayRejected=true"))
        #expect(script.contains("Status: stopped"))
        #expect(script.contains("cells-attach-websocket-ok"))
        #expect(!ci.contains("smoke-cells-attach-bundle.sh"))
        #expect(!nightly.contains("smoke-cells-attach-bundle.sh"))
        #expect(!release.contains("smoke-cells-attach-bundle.sh"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)
    }

    @Test("Bundle-local CLI smoke script launches the shipped app and persists status evidence")
    func bundleLocalCLISmokeScriptPersistsStatusEvidence() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/smoke-bundle-local-cli.sh")
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
        #expect(script.contains("build/CocxyTerminal.app"))
        #expect(script.contains("Contents/Resources/cocxy"))
        #expect(script.contains("summary.txt"))
        #expect(script.contains("result=bundle-local-cli-ok"))
        #expect(script.contains("statusCheck=ok"))
        #expect(!ci.contains("smoke-bundle-local-cli.sh"))
        #expect(!nightly.contains("smoke-bundle-local-cli.sh"))
        #expect(!release.contains("smoke-bundle-local-cli.sh"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)
    }

    @Test("Agent Teams provider process smoke uses isolated hook fixtures")
    func agentTeamsProviderProcessSmokeUsesIsolatedHookFixtures() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/smoke-agent-teams-provider-process.sh")
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
        #expect(script.contains("COCXY_HOOKS_HOME"))
        #expect(script.contains("PROVIDER_TIMEOUT=\"${COCXY_AGENT_TEAMS_PROVIDER_TIMEOUT:-45}\""))
        #expect(script.contains("setup-hooks --agent"))
        #expect(script.contains("--dry-run"))
        #expect(script.contains("--check"))
        #expect(script.contains("--remove"))
        #expect(script.contains("provider-process-preflight-ok"))
        #expect(script.contains("provider-process-preflight-failed"))
        #expect(script.contains("env[\"PATH\"] = str(pathlib.Path(binary).parent) + \":\" +"))
        #expect(script.contains("COCXY_AGENT_TEAMS_STRICT_PROVIDER_SMOKE"))
        #expect(script.contains("hook-preflight-ok"))
        #expect(script.contains("hook-handler-exit-ok"))
        #expect(script.contains("status=skipped"))
        #expect(script.contains("status=degraded"))
        #expect(script.contains("summary.txt"))
        #expect(script.contains("tee \"${ARTIFACT_ROOT}/summary.txt\""))
        #expect(script.contains("provider-evidence.tsv"))
        #expect(script.contains("providerID\\thookAgent\\tbinary"))
        #expect(script.contains("claude-code|claude|Claude Code"))
        #expect(script.contains("setup-hooks --agent \"${hook_target}\""))
        #expect(script.contains("COCXY_HOOK_AGENT=\"${hook_target}\""))
        #expect(script.contains("evidence_pair"))
        #expect(script.contains("providerEvidenceSha256"))
        #expect(script.contains("result=agent-teams-provider-process-ok"))
        #expect(!ci.contains("smoke-agent-teams-provider-process.sh"))
        #expect(!nightly.contains("smoke-agent-teams-provider-process.sh"))
        #expect(!release.contains("smoke-agent-teams-provider-process.sh"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)
    }

    @Test("Visual screenshot golden smoke validates approved browser action screenshots")
    func visualScreenshotGoldenSmokeValidatesApprovedBrowserActionScreenshots() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/smoke-visual-screenshot-golden.sh")
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let matrixScript = try String(
            contentsOf: root.appendingPathComponent("scripts/smoke-agent-workspace-e2e-matrices.sh"),
            encoding: .utf8
        )
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
        #expect(script.contains("approved-goldens.tsv"))
        #expect(script.contains("requiredScreenshots="))
        #expect(script.contains("result=visual-screenshot-golden-ok"))
        #expect(script.contains("screenshotStatus") && script.contains("captured"))
        #expect(script.contains("sha256"))
        #expect(matrixScript.contains("smoke-visual-screenshot-golden.sh"))
        #expect(matrixScript.contains("approved-golden-screenshots"))
        #expect(!ci.contains("smoke-visual-screenshot-golden.sh"))
        #expect(!nightly.contains("smoke-visual-screenshot-golden.sh"))
        #expect(!release.contains("smoke-visual-screenshot-golden.sh"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)
    }

    @Test("CocxyCore moat smoke is manual parametrized and outside CI")
    func cocxyCoreMoatSmokeIsManualParametrizedAndOutsideCI() throws {
        let root = repositoryRoot()
        let scriptURL = root.appendingPathComponent("scripts/smoke-cocxycore-moat.sh")
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
        #expect(script.contains("COCXYCORE_MOAT_FUZZ_CASES"))
        #expect(script.contains("COCXYCORE_MOAT_SEARCH_ROWS"))
        #expect(script.contains("COCXYCORE_MOAT_SEARCH_MAX_MICROS"))
        #expect(script.contains("swift test --filter CocxyCoreMoatSmokeSwiftTestingTests"))
        #expect(script.contains("result=cocxycore-moat-smoke-ok"))
        #expect(script.contains("build/cocxycore-moat"))
        #expect(script.contains("summary.txt"))
        #expect(script.contains("swiftTestOutputSha256"))
        #expect(script.contains("swiftTestErrorSha256"))
        #expect(!ci.contains("smoke-cocxycore-moat.sh"))
        #expect(!nightly.contains("smoke-cocxycore-moat.sh"))
        #expect(!release.contains("smoke-cocxycore-moat.sh"))

        let syntax = try runProcess(URL(fileURLWithPath: "/bin/bash"), arguments: ["-n", scriptURL.path])
        #expect(syntax.terminationStatus == 0)
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
        let releasesGenerator = try String(
            contentsOf: root.appendingPathComponent("web/scripts/generate-releases-page.mjs"),
            encoding: .utf8
        )

        #expect(workflow.contains("web/public/es/*.html ${DEPLOY_TARGET}:${DEPLOY_PATH}es/"))
        #expect(releasesGenerator.contains(#"<link rel="alternate" hreflang="es" href="${site}/es/releases.html">"#))
        #expect(releasesGenerator.contains(#"languageHref: '/es/releases.html'"#))
        #expect(releasesGenerator.contains(#"languageHref: '/releases.html'"#))
        #expect(workflow.contains("web/public/*.html ${DEPLOY_TARGET}:${DEPLOY_PATH}"))
        #expect(workflow.contains("${DEPLOY_PATH}es/features"))
        #expect(workflow.contains("${DEPLOY_PATH}es/docs"))
        #expect(workflow.contains("web/public/es/features/*.html ${DEPLOY_TARGET}:${DEPLOY_PATH}es/features/"))
        #expect(workflow.contains("web/public/es/docs/*.html ${DEPLOY_TARGET}:${DEPLOY_PATH}es/docs/"))
        #expect(workflow.contains("node web/scripts/generate-releases-page.mjs"))
        #expect(workflow.contains("build/es/releases.html ${DEPLOY_TARGET}:${DEPLOY_PATH}es/releases.html"))
        #expect(workflow.contains("web/public/videos/* ${DEPLOY_TARGET}:${DEPLOY_PATH}videos/"))
        #expect(workflow.contains(#"find ${DEPLOY_PATH} -type f -name '*.html' -print0"#))
        #expect(workflow.contains(#"\"softwareVersion\": \"${VERSION}\"|g'"#))
        #expect(workflow.contains(#"CocxyTerminal-${VERSION}.dmg|g'"#))

        let rewriteStart = try #require(workflow.range(of: "# Update version-specific values"))
        let cleanupStart = try #require(
            workflow.range(of: "rm /tmp/deploy_key", range: rewriteStart.upperBound..<workflow.endIndex)
        )
        let versionRewriteBlock = String(workflow[rewriteStart.lowerBound..<cleanupStart.lowerBound])
        #expect(versionRewriteBlock.contains("set -e;"))
        #expect(!versionRewriteBlock.contains("|| true"))
    }

    @Test("release website deploy keeps channel docs wired")
    func releaseWebsiteDeployKeepsChannelDocsWired() throws {
        let root = repositoryRoot()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )
        let english = try String(
            contentsOf: root.appendingPathComponent("web/public/channels.html"),
            encoding: .utf8
        )
        let spanish = try String(
            contentsOf: root.appendingPathComponent("web/public/es/channels.html"),
            encoding: .utf8
        )

        #expect(workflow.contains("web/public/*.html ${DEPLOY_TARGET}:${DEPLOY_PATH}"))
        #expect(workflow.contains(#"style.css?v=${ASSET_VERSION}|g'"#))
        #expect(workflow.contains(#"main.js?v=${ASSET_VERSION}|g"#))
        #expect(workflow.contains(#"theme-switcher.js?v=${ASSET_VERSION}|g"#))
        #expect(english.contains(#"<link rel="alternate" hreflang="es" href="https://cocxy.dev/es/channels.html">"#))
        #expect(spanish.contains(#"<link rel="alternate" hreflang="en" href="https://cocxy.dev/channels.html">"#))
        #expect(english.contains("brew install --cask cocxy-preview"))
        #expect(english.contains("brew install --cask cocxy-nightly"))
        #expect(spanish.contains("brew install --cask cocxy-pr&#101;view"))
        #expect(spanish.contains("brew install --cask cocxy-nightly"))
        #expect(english.contains("appcast-preview.xml"))
        #expect(english.contains("appcast-nightly.xml"))
    }

    @Test("preview and nightly workflows publish signed appcasts and channel casks")
    func previewAndNightlyWorkflowsPublishSignedAppcastsAndChannelCasks() throws {
        let root = repositoryRoot()
        let preview = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/preview.yml"),
            encoding: .utf8
        )
        let nightly = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/nightly.yml"),
            encoding: .utf8
        )

        #expect(preview.contains("ERROR: sign_update not found. Cannot generate Sparkle signature."))
        #expect(preview.contains("ERROR: Failed to generate Sparkle EdDSA signature."))
        #expect(preview.contains("- name: Update Homebrew preview Cask"))
        #expect(preview.contains("Casks/cocxy-preview.rb"))
        #expect(preview.contains(#"cask "cocxy-preview" do"#))
        #expect(preview.contains(#"app "Cocxy Terminal Preview.app""#))
        #expect(preview.contains("git commit -m \"Update cocxy-preview to ${VERSION}\""))
        #expect(preview.contains("git push"))
        #expect(preview.contains("rm /tmp/deploy_key"))

        #expect(nightly.contains("ERROR: sign_update not found. Cannot generate Sparkle signature."))
        #expect(nightly.contains("ERROR: Failed to generate Sparkle EdDSA signature."))
        #expect(nightly.contains("- name: Update Homebrew nightly Cask"))
        #expect(nightly.contains("Casks/cocxy-nightly.rb"))
        #expect(nightly.contains(#"cask "cocxy-nightly" do"#))
        #expect(nightly.contains(#"app "Cocxy Terminal Nightly.app""#))
        #expect(nightly.contains("git commit -m \"Update cocxy-nightly to ${VERSION}\""))
        #expect(nightly.contains("git push"))
    }

    @Test("local installer derives default app destination from bundle display name")
    func localInstallerDerivesDefaultDestinationFromBundleDisplayName() throws {
        let root = repositoryRoot()
        let script = try String(
            contentsOf: root.appendingPathComponent("scripts/install-local-app.sh"),
            encoding: .utf8
        )

        #expect(script.contains("BUNDLE_DISPLAY_NAME="))
        #expect(script.contains("CFBundleDisplayName"))
        #expect(script.contains("DEST_APP=\"${2:-/Applications/${BUNDLE_DISPLAY_NAME}.app}\""))
        #expect(!script.contains("DEST_APP=\"${2:-/Applications/Cocxy Terminal.app}\""))
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
            #expect(homepage.contains(#"<div class="hero-version""#))
            #expect(homepage.contains(#"<span class="version-badge">v0.0.0</span>"#))
            #expect(homepage.contains(#""@type": "SoftwareApplication""#))
            #expect(homepage.contains(#""softwareVersion": "0.0.0""#))
        }
        #expect(englishHome.contains(">Zero telemetry</span>"))
        #expect(spanishHome.contains(">Cero telemetría</span>"))
        #expect(spanishHome.contains("<b>ESPACIOS</b>"))
        #expect(spanishHome.contains("> inactivo · 1</span>"))
        #expect(!spanishHome.contains("<b>WORKSPACES</b>"))

        for releasePage in [englishReleases, spanishReleases] {
            #expect(releasePage.contains(#""@type": "BreadcrumbList""#))
            #expect(releasePage.contains(#""@type": "CollectionPage""#))
            #expect(releasePage.contains(#""@type": "ItemList""#))
            #expect(releasePage.contains(#""softwareVersion": "0.0.0""#))
            #expect(releasePage.contains(#"href="/appcast.xml""#))
            #expect(releasePage.contains("https://github.com/salp2403/cocxy-terminal/releases/latest"))
        }
        #expect(spanishReleases.contains("CocxyTerminal-0.0.0.dmg"))

        #expect(workflow.contains("release_items = []"))
        #expect(workflow.contains(#""@type": "CollectionPage""#))
        #expect(workflow.contains(#""@type": "ItemList""#))
        #expect(workflow.contains(#""softwareVersion": version"#))
        #expect(workflow.contains(#"<link rel="alternate" type="application/rss+xml" title="Cocxy Terminal Appcast" href="/appcast.xml">"#))
        #expect(workflow.contains(#"find ${DEPLOY_PATH} -type f -name '*.html' -print0"#))
        #expect(workflow.contains(#"style.css?v=${ASSET_VERSION}|g'"#))
        #expect(workflow.contains(#"main.js?v=${ASSET_VERSION}|g"#))
        #expect(workflow.contains(#"theme-switcher.js?v=${ASSET_VERSION}|g"#))
        #expect(workflow.contains(#"\"softwareVersion\": \"${VERSION}\"|g'"#))
        #expect(workflow.contains(#"CocxyTerminal-${VERSION}.dmg|g'"#))
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

    @Test("public marketing copy confines named agent brands to compatibility surfaces")
    func publicMarketingCopyConfinesNamedAgentBrandsToCompatibilitySurfaces() throws {
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
        let comparisonPattern = try NSRegularExpression(
            pattern: #"\b(cocxy\s+vs\.?|vs\.?\s+cocxy|versus|better than|faster than|beats|mejor que|más rápido que|supera a)\b"#,
            options: [.caseInsensitive]
        )
        let compatibilitySurfaces: Set<String> = [
            "web/public/index.html",
            "web/public/es/index.html",
            "web/public/agents.html",
            "web/public/es/agents.html",
            "web/public/features/agents.html",
            "web/public/es/features/agents.html",
        ]

        for file in files {
            let relativePath = Self.relativePath(file, root: root)
            let contents = try String(contentsOf: file, encoding: .utf8)
            let range = NSRange(location: 0, length: (contents as NSString).length)
            #expect(
                comparisonPattern.firstMatch(in: contents, range: range) == nil,
                "\(relativePath) should describe Cocxy without competitor comparisons"
            )
            guard !compatibilitySurfaces.contains(relativePath) else { continue }
            #expect(
                pattern.firstMatch(in: contents, range: range) == nil,
                "\(relativePath) should reserve named agent brands for compatibility surfaces"
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
        #expect(english.contains("brew update &amp;&amp; brew upgrade --cask cocxy"))
        #expect(spanish.contains("Migrar desde versiones v0.x"))
        #expect(spanish.contains("~/.config/cocxy/"))
    }

    @Test("public getting started docs include local backup restore guidance in both locales")
    func publicGettingStartedDocsIncludeLocalBackupRestoreGuidanceInBothLocales() throws {
        let root = repositoryRoot()
        let english = try String(
            contentsOf: root.appendingPathComponent("web/public/getting-started.html"),
            encoding: .utf8
        )
        let spanish = try String(
            contentsOf: root.appendingPathComponent("web/public/es/getting-started.html"),
            encoding: .utf8
        )

        #expect(english.contains(#"<h2 id="local-backups">Local Backups</h2>"#))
        #expect(english.contains(##"<a href="#local-backups" class="sidebar-link">Local Backups</a>"##))
        #expect(english.contains("Preferences &gt; Backups"))
        #expect(english.contains("Restore only the selected artifact"))
        #expect(spanish.contains("Copias locales"))
        #expect(spanish.contains("Preferencias &gt; Backups"))
        #expect(spanish.contains("Restaura solo el artefacto seleccionado"))
    }

    @Test("public getting started docs document local input classification in both locales")
    func publicGettingStartedDocsDocumentLocalInputClassificationInBothLocales() throws {
        let root = repositoryRoot()
        let english = try String(
            contentsOf: root.appendingPathComponent("web/public/getting-started.html"),
            encoding: .utf8
        )
        let spanish = try String(
            contentsOf: root.appendingPathComponent("web/public/es/getting-started.html"),
            encoding: .utf8
        )

        #expect(english.contains(#"<h2 id="input-classifier">Input Classifier</h2>"#))
        #expect(english.contains(##"<a href="#input-classifier" class="sidebar-link">Input Classifier</a>"##))
        #expect(english.contains("[input-classifier]"))
        #expect(english.contains("dangerous-command-warning = true"))
        #expect(english.contains("auto-route-natural-language = false"))
        #expect(english.contains("foundation-models-fallback = true"))
        #expect(english.contains("cocxy classify"))
        #expect(english.contains("dangerous-command"))
        #expect(english.contains("natural-language"))

        #expect(spanish.contains(#"id="input-classifier""#))
        #expect(spanish.contains("clasificador de entrada"))
        #expect(spanish.contains("[input-classifier]"))
        #expect(spanish.contains("dangerous-command-warning = true"))
        #expect(spanish.contains("auto-route-natural-language = false"))
        #expect(spanish.contains("foundation-models-fallback = true"))
        #expect(spanish.contains("cocxy classify"))
        #expect(spanish.contains("dangerous-command"))
        #expect(spanish.contains("natural-language"))
    }

    @Test("public getting started docs document local command signatures in both locales")
    func publicGettingStartedDocsDocumentLocalCommandSignaturesInBothLocales() throws {
        let root = repositoryRoot()
        let english = try String(
            contentsOf: root.appendingPathComponent("web/public/getting-started.html"),
            encoding: .utf8
        )
        let spanish = try String(
            contentsOf: root.appendingPathComponent("web/public/es/getting-started.html"),
            encoding: .utf8
        )

        #expect(english.contains(#"<h2 id="command-signatures">Command Signatures</h2>"#))
        #expect(english.contains(##"<a href="#command-signatures" class="sidebar-link">Command Signatures</a>"##))
        #expect(english.contains("[security]"))
        #expect(english.contains("require-signed-templates = false"))
        #expect(english.contains("require-signed-macros = false"))
        #expect(english.contains("require-signed-plugins = false"))
        #expect(english.contains("warn-on-unsigned = true"))
        #expect(english.contains("trust-on-first-use = false"))
        #expect(english.contains("cocxy keys generate --author"))
        #expect(english.contains("cocxy sign template"))
        #expect(english.contains("cocxy verify template"))
        #expect(english.contains("verified"))
        #expect(english.contains("unsigned"))
        #expect(english.contains("invalid signature"))

        #expect(spanish.contains(#"id="command-signatures""#))
        #expect(spanish.contains("firmas de comandos"))
        #expect(spanish.contains("[security]"))
        #expect(spanish.contains("require-signed-templates = false"))
        #expect(spanish.contains("require-signed-macros = false"))
        #expect(spanish.contains("require-signed-plugins = false"))
        #expect(spanish.contains("warn-on-unsigned = true"))
        #expect(spanish.contains("trust-on-first-use = false"))
        #expect(spanish.contains("cocxy keys generate --author"))
        #expect(spanish.contains("cocxy sign template"))
        #expect(spanish.contains("cocxy verify template"))
        #expect(spanish.contains("verificada"))
        #expect(spanish.contains("sin firma"))
        #expect(spanish.contains("firma inv&aacute;lida"))
    }

    @Test("public getting started docs document granular sandbox controls in both locales")
    func publicGettingStartedDocsDocumentGranularSandboxControlsInBothLocales() throws {
        let root = repositoryRoot()
        let english = try String(
            contentsOf: root.appendingPathComponent("web/public/getting-started.html"),
            encoding: .utf8
        )
        let spanish = try String(
            contentsOf: root.appendingPathComponent("web/public/es/getting-started.html"),
            encoding: .utf8
        )

        #expect(english.contains(#"<h2 id="sandbox-controls">Sandbox Controls</h2>"#))
        #expect(english.contains(##"<a href="#sandbox-controls" class="sidebar-link">Sandbox Controls</a>"##))
        #expect(english.contains("[security.sandbox]"))
        #expect(english.contains("plugins-strict = true"))
        #expect(english.contains("agents-isolated = true"))
        #expect(english.contains("mcp-isolated = true"))
        #expect(english.contains("audit-log-enabled = true"))
        #expect(english.contains("warn-on-grant = true"))
        #expect(english.contains("cocxy sandbox list-grants"))
        #expect(english.contains("cocxy sandbox revoke"))
        #expect(english.contains("Sandbox Inspector"))
        #expect(english.contains("Agent command tools run with workspace-scoped read/write access"))

        #expect(spanish.contains(#"id="sandbox-controls""#))
        #expect(spanish.lowercased().contains("controles de sandbox"))
        #expect(spanish.contains("[security.sandbox]"))
        #expect(spanish.contains("plugins-strict = true"))
        #expect(spanish.contains("agents-isolated = true"))
        #expect(spanish.contains("mcp-isolated = true"))
        #expect(spanish.contains("audit-log-enabled = true"))
        #expect(spanish.contains("warn-on-grant = true"))
        #expect(spanish.contains("cocxy sandbox list-grants"))
        #expect(spanish.contains("cocxy sandbox revoke"))
        #expect(spanish.contains("Inspector de sandbox"))
    }

    @Test("public getting started docs document command corrections in both locales")
    func publicGettingStartedDocsDocumentCommandCorrectionsInBothLocales() throws {
        let root = repositoryRoot()
        let english = try String(
            contentsOf: root.appendingPathComponent("web/public/getting-started.html"),
            encoding: .utf8
        )
        let spanish = try String(
            contentsOf: root.appendingPathComponent("web/public/es/getting-started.html"),
            encoding: .utf8
        )

        #expect(english.contains(#"<h2 id="command-corrections">Command Corrections</h2>"#))
        #expect(english.contains(##"<a href="#command-corrections" class="sidebar-link">Command Corrections</a>"##))
        #expect(english.contains("[command-corrections]"))
        #expect(english.contains("edit-distance-threshold = 2"))
        #expect(english.contains("foundation-models-enabled = true"))
        #expect(english.contains("agent-fallback = false"))
        #expect(english.contains("auto-show-on-failure = true"))
        #expect(english.contains("show-confidence-badge = true"))
        #expect(english.contains("cocxy correct"))
        #expect(english.contains("gti status"))
        #expect(english.contains("pyhton -m venv ."))
        #expect(english.contains("Tab"))
        #expect(english.contains("Esc"))

        #expect(spanish.contains(#"id="command-corrections""#))
        #expect(spanish.contains("correcciones de comandos"))
        #expect(spanish.contains("[command-corrections]"))
        #expect(spanish.contains("edit-distance-threshold = 2"))
        #expect(spanish.contains("foundation-models-enabled = true"))
        #expect(spanish.contains("agent-fallback = false"))
        #expect(spanish.contains("auto-show-on-failure = true"))
        #expect(spanish.contains("show-confidence-badge = true"))
        #expect(spanish.contains("cocxy correct"))
        #expect(spanish.contains("gti status"))
        #expect(spanish.contains("pyhton -m venv ."))
        #expect(spanish.contains("Tab"))
        #expect(spanish.contains("Esc"))
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
            "local-backups",
            "input-classifier",
            "command-signatures",
            "sandbox-controls",
            "command-corrections",
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

    @Test("Spanish public docs keep metadata and structured data accent-safe")
    func spanishPublicDocsKeepMetadataAndStructuredDataAccentSafe() throws {
        let root = repositoryRoot()
        let webRoot = root.appendingPathComponent("web/public/es", isDirectory: true)
        let files = try Self.files(under: webRoot, fileExtension: "html")
        let forbiddenFragments = [
            "agentes de codigo",
            "revision de codigo",
            "cero telemetria",
            "documentacion",
            "deteccion de agentes",
            "configuracion por proyecto",
            "analiticas",
            "automatico",
            "accion o configuracion explicita",
            "tambien puedes",
            "como instalo",
            "que es cocxy",
            "guia en espanol",
            "comentarios en linea",
        ]

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8).lowercased()
            for fragment in forbiddenFragments {
                #expect(
                    !contents.contains(fragment),
                    "\(Self.relativePath(file, root: root)) contains accentless Spanish public metadata: \(fragment)"
                )
            }
        }
    }

    @Test("Spanish public docs keep primary navigation inside the Spanish site")
    func spanishPublicDocsKeepPrimaryNavigationInsideSpanishSite() throws {
        let root = repositoryRoot()
        let paths = [
            "web/public/es/index.html",
            "web/public/es/features.html",
            "web/public/es/releases.html",
            "web/public/es/getting-started.html",
            "web/public/es/faq.html",
            "web/public/es/press.html",
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
            #expect(!contents.contains(#"<a href="/getting-started.html">Gu&iacute;a</a>"#))
            #expect(!contents.contains(#"<a href="/faq.html">FAQ</a>"#))
            #expect(!contents.contains(#"<a href="/#download">Descargar</a>"#))
        }
    }

    @Test("public press kit keeps launch copy media assets and demo outline wired")
    func publicPressKitKeepsLaunchCopyMediaAssetsAndDemoOutlineWired() throws {
        let root = repositoryRoot()
        let english = try String(
            contentsOf: root.appendingPathComponent("web/public/press.html"),
            encoding: .utf8
        )
        let spanish = try String(
            contentsOf: root.appendingPathComponent("web/public/es/press.html"),
            encoding: .utf8
        )

        #expect(english.contains("Launch note draft"))
        #expect(english.contains("Demo outline"))
        #expect(english.contains("/images/icon.png"))
        #expect(english.contains("/images/og-image.png"))
        #expect(english.contains("/images/cocxy-preview.png"))
        #expect(english.contains("/videos/cocxy-demo.mp4"))
        #expect(english.contains(#"<video controls preload="metadata" poster="/images/og-image.avif""#))
        #expect(english.contains("No telemetry pipeline"))
        #expect(english.contains(#""@type": "Article""#))
        #expect(english.contains(#"<link rel="alternate" hreflang="es" href="https://cocxy.dev/es/press.html">"#))

        #expect(spanish.contains("Borrador de nota de lanzamiento"))
        #expect(spanish.contains("Guion de demo"))
        #expect(spanish.contains("Recursos visuales"))
        #expect(spanish.contains("/videos/cocxy-demo.mp4"))
        #expect(spanish.contains("Video demo"))
        #expect(spanish.contains("Sin sistema de telemetr&iacute;a"))
        #expect(spanish.contains(#""@type": "Article""#))
        #expect(spanish.contains(#"<link rel="alternate" hreflang="en" href="https://cocxy.dev/press.html">"#))

        let video = root.appendingPathComponent("web/public/videos/cocxy-demo.mp4")
        let attributes = try FileManager.default.attributesOfItem(atPath: video.path)
        let byteCount = try #require(attributes[.size] as? NSNumber).intValue
        #expect(byteCount > 100_000)
        #expect(byteCount < 8_000_000)
    }

    @Test("public preview render uses real captures and smoke evidence without private terms")
    func publicPreviewRenderUsesRealCapturesAndSmokeEvidenceWithoutPrivateTerms() throws {
        let root = repositoryRoot()
        let script = try String(
            contentsOf: root.appendingPathComponent("web/scripts/render-public-preview.mjs"),
            encoding: .utf8
        )

        #expect(script.contains("getting-started-dashboard.png"))
        #expect(script.contains("getting-started-browser.png"))
        #expect(script.contains("getting-started-preferences.png"))
        #expect(script.contains("cocxy-preview-source.png"))
        #expect(script.contains("Cocxy Terminal real smoke capture"))
        #expect(script.contains("Resources', 'Info.plist"))
        #expect(script.contains("CFBundleShortVersionString"))
        #expect(script.contains("build/web-quality-audit/report.json"))
        #expect(script.contains("build/web-visual-smoke/report.json"))
        #expect(script.contains("Smoke test evidence"))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("web/assets/cocxy-preview-source.png").path))

        for restrictedTerm in [
            "Ga" + "lf",
            "Mac" + "Book",
            "/Use" + "rs/",
            "clau" + "de-code",
            "cm" + "ux",
            "wa" + "rp",
        ] {
            #expect(!script.contains(restrictedTerm))
        }
    }

    @Test("public visual smoke covers both home locales and supported responsive widths")
    func publicVisualSmokeCoversBothHomeLocalesAndSupportedResponsiveWidths() throws {
        let root = repositoryRoot()
        let script = try String(
            contentsOf: root.appendingPathComponent("web/scripts/visual-smoke.mjs"),
            encoding: .utf8
        )

        #expect(script.contains("{ name: 'desktop', width: 1440, height: 1000 }"))
        #expect(script.contains("{ name: 'tablet', width: 768, height: 1024 }"))
        #expect(script.contains("{ name: 'mobile', width: 390, height: 844 }"))
        #expect(script.contains("{ name: 'narrow', width: 320, height: 700 }"))
        #expect(script.contains("for (const url of ['/', '/es/'"))
        #expect(script.contains("url === '/' || url === '/es/'"))
        #expect(script.contains("metrics.overflowX > 1"))
    }

    @Test("public website locale alternates are reciprocal for every public page")
    func publicWebsiteLocaleAlternatesAreReciprocalForEveryPublicPage() throws {
        let root = repositoryRoot().appendingPathComponent("web/public", isDirectory: true)

        for pair in Self.publicWebsiteLocalePairs {
            let english = try String(
                contentsOf: root.appendingPathComponent(pair.englishPath),
                encoding: .utf8
            )
            let spanish = try String(
                contentsOf: root.appendingPathComponent(pair.spanishPath),
                encoding: .utf8
            )

            #expect(
                english.contains(#"<link rel="canonical" href="\#(pair.englishURL)">"#),
                "\(pair.englishPath) should canonicalize to the English route"
            )
            #expect(
                english.contains(#"<link rel="alternate" hreflang="en" href="\#(pair.englishURL)">"#),
                "\(pair.englishPath) should expose its English alternate"
            )
            #expect(
                english.contains(#"<link rel="alternate" hreflang="es" href="\#(pair.spanishURL)">"#),
                "\(pair.englishPath) should expose its Spanish alternate"
            )
            #expect(
                english.contains(#"<link rel="alternate" hreflang="x-default" href="\#(pair.englishURL)">"#),
                "\(pair.englishPath) should keep x-default on English"
            )
            #expect(
                english.contains(#"href="\#(pair.spanishHref)" hreflang="es" lang="es""#),
                "\(pair.englishPath) should link to the matching Spanish page"
            )

            #expect(
                spanish.contains(#"<link rel="canonical" href="\#(pair.spanishURL)">"#),
                "\(pair.spanishPath) should canonicalize to the Spanish route"
            )
            #expect(
                spanish.contains(#"<link rel="alternate" hreflang="en" href="\#(pair.englishURL)">"#),
                "\(pair.spanishPath) should expose its English alternate"
            )
            #expect(
                spanish.contains(#"<link rel="alternate" hreflang="es" href="\#(pair.spanishURL)">"#),
                "\(pair.spanishPath) should expose its Spanish alternate"
            )
            #expect(
                spanish.contains(#"<link rel="alternate" hreflang="x-default" href="\#(pair.englishURL)">"#),
                "\(pair.spanishPath) should keep x-default on English"
            )
            #expect(
                spanish.contains(#"href="\#(pair.englishHref)" hreflang="en" lang="en""#),
                "\(pair.spanishPath) should link to the matching English page"
            )
        }
    }

    @Test("public sitemap lists reciprocal localized routes")
    func publicSitemapListsReciprocalLocalizedRoutes() throws {
        let root = repositoryRoot()
        let sitemap = try String(
            contentsOf: root.appendingPathComponent("web/public/sitemap.xml"),
            encoding: .utf8
        )

        for pair in Self.publicWebsiteLocalePairs {
            for url in [pair.englishURL, pair.spanishURL] {
                let block = try #require(
                    Self.sitemapURLBlock(for: url, in: sitemap),
                    "sitemap.xml should include \(url)"
                )
                #expect(block.contains(#"<xhtml:link rel="alternate" hreflang="en" href="\#(pair.englishURL)"/>"#))
                #expect(block.contains(#"<xhtml:link rel="alternate" hreflang="es" href="\#(pair.spanishURL)"/>"#))
                #expect(block.contains(#"<xhtml:link rel="alternate" hreflang="x-default" href="\#(pair.englishURL)"/>"#))
            }
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

    @Test("public crawl policy avoids named third-party crawler brands")
    func publicCrawlPolicyAvoidsNamedThirdPartyCrawlerBrands() throws {
        let root = repositoryRoot()
        let files = [
            root.appendingPathComponent("web/public/robots.txt"),
            root.appendingPathComponent("web/public/manifest.webmanifest"),
            root.appendingPathComponent("web/public/sitemap.xml"),
        ]
        let forbiddenFragments = [
            "GPTBot",
            "ChatGPT-User",
            "Google-Extended",
            "ClaudeBot",
            "anthropic-ai",
            "PerplexityBot",
            "CCBot",
        ]

        for file in files {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for fragment in forbiddenFragments {
                #expect(
                    !contents.localizedCaseInsensitiveContains(fragment),
                    "\(Self.relativePath(file, root: root)) should keep crawler policy generic: \(fragment)"
                )
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

    private struct PublicWebsiteLocalePair {
        let englishPath: String
        let spanishPath: String
        let englishURL: String
        let spanishURL: String
        let englishHref: String
        let spanishHref: String
    }

    private static let publicWebsiteLocalePairs = [
        PublicWebsiteLocalePair(
            englishPath: "index.html",
            spanishPath: "es/index.html",
            englishURL: "https://cocxy.dev/",
            spanishURL: "https://cocxy.dev/es/",
            englishHref: "/",
            spanishHref: "/es/"
        ),
        PublicWebsiteLocalePair(
            englishPath: "features.html",
            spanishPath: "es/features.html",
            englishURL: "https://cocxy.dev/features.html",
            spanishURL: "https://cocxy.dev/es/features.html",
            englishHref: "/features.html",
            spanishHref: "/es/features.html"
        ),
        PublicWebsiteLocalePair(
            englishPath: "releases.html",
            spanishPath: "es/releases.html",
            englishURL: "https://cocxy.dev/releases.html",
            spanishURL: "https://cocxy.dev/es/releases.html",
            englishHref: "/releases.html",
            spanishHref: "/es/releases.html"
        ),
        PublicWebsiteLocalePair(
            englishPath: "channels.html",
            spanishPath: "es/channels.html",
            englishURL: "https://cocxy.dev/channels.html",
            spanishURL: "https://cocxy.dev/es/channels.html",
            englishHref: "/channels.html",
            spanishHref: "/es/channels.html"
        ),
        PublicWebsiteLocalePair(
            englishPath: "docs/first-run.html",
            spanishPath: "es/docs/first-run.html",
            englishURL: "https://cocxy.dev/docs/first-run.html",
            spanishURL: "https://cocxy.dev/es/docs/first-run.html",
            englishHref: "/docs/first-run.html",
            spanishHref: "/es/docs/first-run.html"
        ),
        PublicWebsiteLocalePair(
            englishPath: "faq.html",
            spanishPath: "es/faq.html",
            englishURL: "https://cocxy.dev/faq.html",
            spanishURL: "https://cocxy.dev/es/faq.html",
            englishHref: "/faq.html",
            spanishHref: "/es/faq.html"
        ),
        PublicWebsiteLocalePair(
            englishPath: "press.html",
            spanishPath: "es/press.html",
            englishURL: "https://cocxy.dev/press.html",
            spanishURL: "https://cocxy.dev/es/press.html",
            englishHref: "/press.html",
            spanishHref: "/es/press.html"
        ),
    ]

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

    private static func matchesGlob(_ path: String, pattern: String) -> Bool {
        var regex = "^"
        for scalar in pattern.unicodeScalars {
            switch scalar {
            case "*":
                regex += "[^/]*"
            case "?":
                regex += "[^/]"
            default:
                regex += NSRegularExpression.escapedPattern(for: String(scalar))
            }
        }
        regex += "$"
        return path.range(of: regex, options: .regularExpression) != nil
    }

    private static func sitemapURLBlock(for loc: String, in contents: String) -> String? {
        guard let locRange = contents.range(of: "<loc>\(loc)</loc>"),
              let blockStart = contents[..<locRange.lowerBound].range(
                of: "<url>",
                options: .backwards
              ),
              let blockEnd = contents[locRange.upperBound...].range(of: "</url>")
        else {
            return nil
        }

        return String(contents[blockStart.lowerBound..<blockEnd.upperBound])
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

    private func writeProductUXSummary(root: URL, status: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let okFields = """
        status=ok
        result=agent-workspace-product-ux-ok
        surfaces=6
        commandPalette=ok
        dashboard=ok
        browserDevTools=ok
        remotePorts=ok
        teams=ok
        codeReview=ok
        voiceOverManual=ok
        keyboard=ok
        reduceMotion=ok
        contrast=ok
        manualAcceptance=ok
        automatedA11y=ok
        visualGoldens=ok
        bundleLocalCLI=ok
        reviewer=Fixture Reviewer
        """
        let blockedFields = """
        status=blocked
        result=agent-workspace-product-ux-blocked
        surfaces=6
        commandPalette=blocked
        """
        try (status == "ok" ? okFields : blockedFields)
            .write(to: root.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
    }

    private func writeProductUXSummaryWithEvidence(root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let evidence = [
            ("acceptanceFile", "acceptanceSha256", "acceptance.md", "Status: Accepted for v1.18.0 release candidate.\nReviewer: Fixture Reviewer\n"),
            ("a11ySummary", "a11ySummarySha256", "a11y-summary.txt", "status=ok\nresult=agent-workspace-a11y-ok\n"),
            ("visualSummary", "visualSummarySha256", "visual-summary.txt", "status=ok\nresult=visual-screenshot-golden-ok\n"),
            ("bundleSummary", "bundleSummarySha256", "bundle-summary.txt", "status=ok\nresult=bundle-local-cli-ok\n"),
        ]

        var fields = [
            "status=ok",
            "result=agent-workspace-product-ux-ok",
            "surfaces=6",
            "commandPalette=ok",
            "dashboard=ok",
            "browserDevTools=ok",
            "remotePorts=ok",
            "teams=ok",
            "codeReview=ok",
            "voiceOverManual=ok",
            "keyboard=ok",
            "reduceMotion=ok",
            "contrast=ok",
            "manualAcceptance=ok",
            "automatedA11y=ok",
            "visualGoldens=ok",
            "bundleLocalCLI=ok",
            "reviewer=Fixture Reviewer",
        ]

        for (pathField, hashField, filename, contents) in evidence {
            let file = root.appendingPathComponent(filename)
            try contents.write(to: file, atomically: true, encoding: .utf8)
            fields.append("\(pathField)=\(file.path)")
            fields.append("\(hashField)=\(Self.sha256Hex(contents))")
        }

        try (fields.joined(separator: "\n") + "\n")
            .write(to: root.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
    }

    private func writeAgentWorkspaceUISmokeSummary(root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        status=ok
        artifactRoot=\(root.path)
        bundle=build/CocxyTerminal.app
        commandPalette=cells,vault,browser ok
        dashboard=session_count=1 active_count=1 subagent_count=2 active_subagent_count=2
        browserDevTools=opened consoleCount=1 message=fixture-console
        remotePorts=connected forwardedLocalPort=52152 suggestion=localhost:3000
        agentTeams=created team with Planner,Reviewer
        codeReview=visible empty diff state
        cleanup=ok
        evidenceHashes=
        """.write(to: root.appendingPathComponent("summary-final.txt"), atomically: true, encoding: .utf8)
    }

    private func writeAgentWorkspaceUISmokeSummaryWithEvidence(root: URL) throws {
        try writeAgentWorkspaceUISmokeSummary(root: root)

        let evidence = [
            ("28-final4-command-palette-cells.png", "cells screenshot\n"),
            ("29-final4-command-palette-vault.png", "vault screenshot\n"),
            ("30-final4-command-palette-browser.png", "browser screenshot\n"),
            ("26-final3-dashboard-agent-team.png", "dashboard screenshot\n"),
            ("16c-final-browser-devtools-console-visible.png", "devtools screenshot\n"),
            ("17-final-remote-sidebar-suggestions.png", "remote screenshot\n"),
            ("18-final-code-review-panel.png", "review screenshot\n"),
            ("31-cleanup-final-summary.txt", "cleanup ok\n"),
        ]

        var hashLines: [String] = []
        for (filename, contents) in evidence {
            let file = root.appendingPathComponent(filename)
            try contents.write(to: file, atomically: true, encoding: .utf8)
            hashLines.append("\(Self.sha256Hex(contents))  \(file.path)")
        }

        let summary = root.appendingPathComponent("summary-final.txt")
        var summaryContents = try String(contentsOf: summary, encoding: .utf8)
        if !summaryContents.hasSuffix("\n") {
            summaryContents += "\n"
        }
        summaryContents += hashLines.joined(separator: "\n") + "\n"
        try summaryContents.write(to: summary, atomically: true, encoding: .utf8)
    }

    private func writeReleasePreflightFixture(
        root: URL,
        includeCellsCloudReadiness: Bool = true
    ) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let summary = root.appendingPathComponent("summary.tsv")
        var requirements = [
            "resources-info-version",
            "cli-fallback-version",
            "bundle-info-version",
            "bundle-contents-verification",
            "bundle-codesign-verification",
            "bundle-cli-version",
            "dmg-artifact",
            "dmg-image-verification",
            "dmg-codesign-verification",
            "appcast-version",
            "appcast-dmg-reference",
            "appcast-sparkle-signature",
            "appcast-enclosure-length",
            "changelog-version",
            "local-release-tag",
        ]
        if includeCellsCloudReadiness {
            requirements.append("cells-cloud-account-readiness")
        }
        let rows = ["requirement\tstatus\tevidence\tdetail"]
            + requirements.map { "\($0)\tok\tfixture\tok" }
        try (rows.joined(separator: "\n") + "\n")
            .write(to: summary, atomically: true, encoding: .utf8)

        try """
        status=ok
        targetVersion=1.18.0
        artifactRoot=\(root.path)
        summary=\(summary.path)
        blocked=0
        next=fixture
        """.write(to: root.appendingPathComponent("preflight.txt"), atomically: true, encoding: .utf8)
    }

    private func writeAgentTeamsProviderCoveragePreflightFixture(root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let summary = root.appendingPathComponent("summary.tsv")
        let processSummary = root.appendingPathComponent("provider-process-summary.txt")
        let processManifest = root.appendingPathComponent("provider-evidence.tsv")
        let providers = [
            "claude-code",
            "codex",
            "opencode",
            "pi",
            "cursor",
            "gemini",
            "rovo-dev",
            "copilot",
            "codebuddy",
            "factory",
            "qoder",
            "kiro",
        ]
        let rows = ["provider\tstatus\tbinary"]
            + providers.map { "\($0)\tavailable\t/usr/bin/true" }
        try (rows.joined(separator: "\n") + "\n")
            .write(to: summary, atomically: true, encoding: .utf8)

        var manifestRows = [
            "providerID\thookAgent\tbinary\tprocessOutput\tprocessOutputSha256\tdryRunOutput\tdryRunOutputSha256\tinstallOutput\tinstallOutputSha256\tcheckOutput\tcheckOutputSha256\thookHandlerOutput\thookHandlerOutputSha256\tremoveOutput\tremoveOutputSha256",
        ]
        for provider in providers {
            let hookAgent = provider == "claude-code" ? "claude" : provider
            let outputs = [
                ("process", "process ok \(provider)\n"),
                ("dry-run", "would install \(provider)\n"),
                ("install", "installed \(provider)\n"),
                ("check", "hooks OK \(provider)\n"),
                ("hook-handler", "handled \(provider)\n"),
                ("remove", "removed \(provider)\n"),
            ]
            var cells = [provider, hookAgent, "/usr/bin/true"]
            for (suffix, contents) in outputs {
                let file = root.appendingPathComponent("\(provider)-\(suffix).out")
                try contents.write(to: file, atomically: true, encoding: .utf8)
                cells.append(file.path)
                cells.append(Self.sha256Hex(contents))
            }
            manifestRows.append(cells.joined(separator: "\t"))
        }
        let manifestContents = manifestRows.joined(separator: "\n") + "\n"
        try manifestContents.write(to: processManifest, atomically: true, encoding: .utf8)
        try """
        status=ok
        result=agent-teams-provider-process-ok
        installedProviders=12
        passedProviders=12
        providerEvidence=\(processManifest.path)
        providerEvidenceSha256=\(Self.sha256Hex(manifestContents))
        """.write(to: processSummary, atomically: true, encoding: .utf8)

        try """
        status=ok
        artifactRoot=\(root.path)
        summary=\(summary.path)
        providerCount=12
        availableProviderBinaries=12
        latestProviderProcessSummary=\(processSummary.path)
        latestProviderProcessStatus=ok
        latestProviderProcessInstalled=12
        latestProviderProcessPassed=12
        latestProviderProcessEvidence=ok
        next=fixture
        """.write(to: root.appendingPathComponent("preflight.txt"), atomically: true, encoding: .utf8)
    }

    private func writeProviderProcessSummary(root: URL, status: String, installed: Int, passed: Int) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var fields = [
            "status=\(status)",
            "result=agent-teams-provider-process-ok",
            "installedProviders=\(installed)",
            "passedProviders=\(passed)",
        ]

        if status == "ok" {
            let manifest = root.appendingPathComponent("provider-evidence.tsv")
            let providerIDs = [
                "claude-code",
                "codex",
                "opencode",
                "pi",
                "cursor",
                "gemini",
                "rovo-dev",
                "copilot",
                "codebuddy",
                "factory",
                "qoder",
                "kiro",
            ]
            var rows = [
                "providerID\thookAgent\tbinary\tprocessOutput\tprocessOutputSha256\tdryRunOutput\tdryRunOutputSha256\tinstallOutput\tinstallOutputSha256\tcheckOutput\tcheckOutputSha256\thookHandlerOutput\thookHandlerOutputSha256\tremoveOutput\tremoveOutputSha256",
            ]

            if passed > 0 {
                for index in 0..<passed {
                    let provider = providerIDs[index % providerIDs.count]
                    let hookAgent = provider == "claude-code" ? "claude" : provider
                    let outputs = [
                        ("process", "process ok \(provider)\n"),
                        ("dry-run", "would install \(provider)\n"),
                        ("install", "installed \(provider)\n"),
                        ("check", "hooks OK \(provider)\n"),
                        ("hook-handler", "handled \(provider)\n"),
                        ("remove", "removed \(provider)\n"),
                    ]
                    var cells = [provider, hookAgent, "/usr/bin/true"]

                    for (suffix, contents) in outputs {
                        let file = root.appendingPathComponent("\(provider)-\(suffix).out")
                        try contents.write(to: file, atomically: true, encoding: .utf8)
                        cells.append(file.path)
                        cells.append(Self.sha256Hex(contents))
                    }

                    rows.append(cells.joined(separator: "\t"))
                }
            }

            let manifestContents = rows.joined(separator: "\n") + "\n"
            try manifestContents.write(to: manifest, atomically: true, encoding: .utf8)
            fields.append("providerEvidence=\(manifest.path)")
            fields.append("providerEvidenceSha256=\(Self.sha256Hex(manifestContents))")
        }

        try (fields.joined(separator: "\n") + "\n")
            .write(to: root.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
    }

    private func writeCellsCloudSummary(root: URL, status: String) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let okFields: String
        if status == "ok" {
            okFields = try cellsCloudOKSummary(root: root)
        } else {
            okFields = ""
        }
        let blockedFields = """
        status=blocked
        provider=gcp
        result=cells-cloud-gcp-blocked
        """
        try (status == "ok" ? okFields : blockedFields)
            .write(to: root.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
    }

    private func cellsCloudOKSummary(root: URL) throws -> String {
        let outputs = [
            "createOutput": "Cell created: fixture-cell\n",
            "statusOutput": "{ \"status\" : \"running\" }\n",
            "execOutput": "cells-cloud-gcp-ok\n",
            "logsOutput": "fixture logs\n",
            "attachOutput": "{ \"status\" : \"attach-ready\", \"pty-command\" : \"fixture\" }\n",
            "listOutput": "fixture-cell\n",
            "destroyOutput": "destroyed fixture-cell\n",
        ]

        var fields = [
            "status=ok",
            "provider=gcp",
            "create=ok",
            "status-check=ok",
            "exec=ok",
            "logs=ok",
            "attach=ok",
            "list=ok",
            "destroy=ok",
        ]

        for (field, contents) in outputs.sorted(by: { $0.key < $1.key }) {
            let file = root.appendingPathComponent("\(field).out")
            try contents.write(to: file, atomically: true, encoding: .utf8)
            fields.append("\(field)=\(file.path)")
            fields.append("\(field)Sha256=\(Self.sha256Hex(contents))")
        }

        fields.append("result=cells-cloud-gcp-ok")
        return fields.joined(separator: "\n") + "\n"
    }

    private static func sha256Hex(_ contents: String) -> String {
        SHA256.hash(data: Data(contents.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func writeCellsCloudPreflightFixture(root: URL, providerCount: Int) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try """
        status=blocked
        artifactRoot=\(root.path)
        summary=\(root.appendingPathComponent("summary.tsv").path)
        blocked=\(providerCount)
        ready=0
        complete=0
        next=scripts/smoke-cells-cloud-account.sh <provider> with COCXY_CELLS_CLOUD_E2E=1 against disposable resources
        """.write(to: root.appendingPathComponent("preflight.txt"), atomically: true, encoding: .utf8)

        var rows = ["provider\tstatus\ttool\ttoolStatus\tmissingPrerequisites\tokArtifact"]
        let providers = ["e2b", "fly", "aws", "gcp", "azure"]
        for provider in providers.prefix(providerCount) {
            rows.append("\(provider)\tblocked\t\(provider)\tmissing\tCOCXY_FIXTURE\t-")
        }
        try (rows.joined(separator: "\n") + "\n")
            .write(to: root.appendingPathComponent("summary.tsv"), atomically: true, encoding: .utf8)
    }

    private func temporaryArtifactRoot(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func iamPolicyActions(from policy: String) throws -> Set<String> {
        let payload = try JSONSerialization.jsonObject(
            with: Data(policy.utf8),
            options: []
        ) as? [String: Any]
        let statements = payload?["Statement"] as? [[String: Any]] ?? []
        var actions = Set<String>()

        for statement in statements {
            if let action = statement["Action"] as? String {
                actions.insert(action)
            } else if let actionList = statement["Action"] as? [String] {
                actions.formUnion(actionList)
            }
        }

        return actions
    }

    private func awsActions(fromCallLog callLog: String) -> Set<String> {
        Set(
            callLog
                .split(separator: "\n")
                .compactMap { line in
                    var parts = line.split(separator: " ").map(String.init)
                    while parts.first == "--profile", parts.count >= 3 {
                        parts.removeFirst(2)
                    }
                    guard parts.count >= 2 else { return nil }
                    let service = parts[0]
                    let operation = parts[1]
                    guard service == "iam" || service == "sts" else { return nil }
                    let action = operation
                        .split(separator: "-")
                        .map { word -> String in
                            let text = String(word)
                            return text.prefix(1).uppercased() + String(text.dropFirst())
                        }
                        .joined()
                    return "\(service):\(action)"
                }
        )
    }

    private func runProcess(_ executableURL: URL, arguments: [String]) throws -> ProcessResult {
        try runProcess(executableURL, arguments: arguments, environment: [:])
    }

    private func runProcess(
        _ executableURL: URL,
        arguments: [String],
        environment: [String: String]
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in
                override
            }
        }

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
