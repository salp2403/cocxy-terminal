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
        #expect(script.contains("api\\.openai\\.com|api\\.anthro[p]ic\\.com|generativelanguage\\.googleapis\\.com"))
        #expect(ci.contains("./scripts/run-privacy-audit.sh --app build/CocxyTerminal.app"))
        #expect(nightly.contains("./scripts/run-privacy-audit.sh --app \"$APP_DIR\""))
        #expect(release.contains("./scripts/run-privacy-audit.sh --app \"$APP_DIR\""))

        let result = try runProcess(scriptURL, arguments: [])
        #expect(result.terminationStatus == 0)
        #expect(result.stdout.contains("Privacy audit passed"))
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
