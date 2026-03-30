// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonScriptTests.swift - Integration tests for cocxyd.sh daemon script.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("DaemonScript")
struct DaemonScriptTests {

    /// Path to the cocxyd.sh script in the project.
    private var scriptPath: String {
        // #filePath = .../Tests/Unit/RemoteWorkspaceTests/DaemonScriptTests.swift
        // Project root is 4 levels up.
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { url = url.deletingLastPathComponent() }
        return url.appendingPathComponent("Resources/cocxyd.sh").path
    }

    private func runScript(args: [String]) throws -> (stdout: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [scriptPath] + args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // Set XDG_RUNTIME_DIR to temp for isolation.
        var env = ProcessInfo.processInfo.environment
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxyd-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        env["XDG_RUNTIME_DIR"] = tempDir.path
        process.environment = env

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        // Cleanup.
        try? FileManager.default.removeItem(at: tempDir)

        return (stdout: output, exitCode: process.terminationStatus)
    }

    @Test("Script prints help with no arguments")
    func helpOutput() throws {
        let result = try runScript(args: ["help"])
        #expect(result.stdout.contains("cocxyd.sh"))
        #expect(result.stdout.contains("Usage"))
        #expect(result.exitCode == 0)
    }

    @Test("Status reports not running when daemon is off")
    func statusNotRunning() throws {
        let result = try runScript(args: ["status"])
        #expect(result.stdout.contains("\"ok\":false"))
        #expect(result.stdout.contains("not running"))
    }

    @Test("Ping reports not running when daemon is off")
    func pingNotRunning() throws {
        let result = try runScript(args: ["ping"])
        #expect(result.stdout.contains("\"ok\":false"))
        #expect(result.stdout.contains("not running"))
    }

    @Test("Stop is safe when daemon not running")
    func stopWhenNotRunning() throws {
        let result = try runScript(args: ["stop"])
        #expect(result.stdout.contains("not running"))
        #expect(result.exitCode == 0)
    }

    @Test("Script is valid POSIX shell")
    func posixValid() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-n", scriptPath]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
    }
}
