// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TestHomeSandboxSwiftTestingTests.swift - The test runners keep the real home untouched.

import Foundation
import Testing

@Suite("Test home sandbox")
struct TestHomeSandboxSwiftTestingTests {
    private enum Mutation: String {
        case none
        case preference
        case config
    }

    @Test("every test runner runs inside the private home and checks the real one")
    func runnersUseTheSandbox() throws {
        let root = repositoryRoot()
        let sandbox = try String(
            contentsOf: root.appendingPathComponent("scripts/test-home-sandbox.sh"),
            encoding: .utf8
        )
        #expect(sandbox.contains(#"export CFFIXED_USER_HOME="$COCXY_TEST_HOME""#))
        #expect(sandbox.contains(#"export HOME="$COCXY_TEST_HOME""#))
        for runner in [
            "scripts/run-tests.sh",
            "scripts/run-swift-testing-serial.sh",
            "scripts/run-filtered-swift-testing.sh",
        ] {
            let script = try String(contentsOf: root.appendingPathComponent(runner), encoding: .utf8)
            #expect(script.contains("test-home-sandbox.sh"), "\(runner)")
            #expect(script.contains("cocxy_test_home_begin"), "\(runner)")
            #expect(script.contains("cocxy_test_home_end"), "\(runner)")
        }
    }

    @Test("an untouched real home passes and the private home is removed")
    func untouchedHomePasses() throws {
        let result = try runSandbox(.none, appRunning: false)

        #expect(result.status == 0, "\(result.stderr)")
        #expect(result.privateHome.isEmpty == false)
        #expect(result.privateHome.hasPrefix(result.realHome) == false)
        #expect(!FileManager.default.fileExists(atPath: result.privateHome))
    }

    @Test("a preference domain left in the real home fails the run")
    func newPreferenceFails() throws {
        let result = try runSandbox(.preference, appRunning: true)

        #expect(result.status != 0)
        #expect(result.stderr.contains("leaked.suite.plist"))
    }

    @Test("a change under the real cocxy config fails unless a Cocxy app owns it")
    func configChangeFailsWithoutApp() throws {
        let unattended = try runSandbox(.config, appRunning: false)
        #expect(unattended.status != 0)
        #expect(unattended.stderr.contains("registry.json"))

        let appOwned = try runSandbox(.config, appRunning: true)
        #expect(appOwned.status == 0, "\(appOwned.stderr)")
        #expect(appOwned.stderr.contains("warning:"))
    }

    private struct SandboxResult {
        let status: Int32
        let stderr: String
        let realHome: String
        let privateHome: String
    }

    private func runSandbox(_ mutation: Mutation, appRunning: Bool) throws -> SandboxResult {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-home-sandbox-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let realHome = fixture.appendingPathComponent("real-home", isDirectory: true)
        let preferences = realHome.appendingPathComponent("Library/Preferences", isDirectory: true)
        let config = realHome.appendingPathComponent(".config/cocxy/projects", isDirectory: true)
        try FileManager.default.createDirectory(at: preferences, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: preferences.appendingPathComponent("existing.plist"))
        try Data("[]".utf8).write(to: config.appendingPathComponent("registry.json"))
        let report = fixture.appendingPathComponent("private-home.txt")

        let script = """
        set -euo pipefail
        report="$2"; app_running="$3"; mutation="$4"
        source "$1"
        cocxy_test_home_app_running() { [[ "$app_running" == true ]]; }
        cocxy_test_home_begin
        printf '%s' "$CFFIXED_USER_HOME" > "$report"
        [[ "$HOME" == "$CFFIXED_USER_HOME" ]]
        case "$mutation" in
          preference) printf x > "$REAL/Library/Preferences/leaked.suite.plist" ;;
          config) printf '[{}]' > "$REAL/.config/cocxy/projects/registry.json" ;;
        esac
        cocxy_test_home_end
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            "-c", script, "sandbox",
            repositoryRoot().appendingPathComponent("scripts/test-home-sandbox.sh").path,
            report.path,
            appRunning ? "true" : "false",
            mutation.rawValue,
        ]
        process.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": realHome.path,
            "REAL": realHome.path,
            "TMPDIR": fixture.path,
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        let stderr = String(decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        return SandboxResult(
            status: process.terminationStatus,
            stderr: stderr,
            realHome: realHome.path,
            privateHome: (try? String(contentsOf: report, encoding: .utf8)) ?? ""
        )
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
