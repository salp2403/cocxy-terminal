// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyCLILib

@Suite("Claude hook process guard")
struct ClaudeHookCommandGuardSwiftTestingTests {
    @Test("guard skips external shells before launching the hook command")
    func guardSkipsExternalShells() throws {
        let result = try runGuard(environment: [:])

        #expect(result.exitCode == 0)
        #expect(result.stdout.isEmpty)
    }

    @Test("guard forwards Cocxy marker and legacy Cocxy shell environments")
    func guardForwardsCocxyShells() throws {
        for environment in [
            ["COCXY_CLAUDE_HOOKS": "1"],
            ["COCXY_RESOURCES_DIR": "/tmp/cocxy"],
            ["COCXY_SHELL_INTEGRATION_DIR": "/tmp/cocxy/shell-integration"],
        ] {
            let result = try runGuard(environment: environment)
            #expect(result.exitCode == 0)
            #expect(result.stdout == "forwarded")
        }
    }

    @Test("guard honors the global hook disable variable")
    func guardHonorsGlobalDisableVariable() throws {
        let result = try runGuard(environment: [
            "COCXY_CLAUDE_HOOKS": "1",
            "COCXY_HOOKS_DISABLED": "1",
        ])

        #expect(result.exitCode == 0)
        #expect(result.stdout.isEmpty)
    }

    private func runGuard(environment: [String: String]) throws -> (exitCode: Int32, stdout: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            ClaudeSettingsManager.guardedHookCommand("/usr/bin/printf forwarded"),
        ]
        process.environment = environment
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        try process.run()
        process.waitUntilExit()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return (
            process.terminationStatus,
            String(data: data, encoding: .utf8) ?? ""
        )
    }
}
