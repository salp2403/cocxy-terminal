// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonDeployerTests.swift - Tests for daemon deployment and platform detection.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Mock Deploy Executor

@MainActor
final class MockDeployExecutor: DaemonDeployExecuting {
    var commands: [String] = []
    var uploads: [(local: String, remote: String)] = []
    var responses: [String: String] = [:]
    var shouldThrow = false

    func executeRemote(_ command: String, profileID: UUID) async throws -> String {
        if shouldThrow { throw DaemonProtocolError.connectionLost }
        commands.append(command)
        return responses[command] ?? ""
    }

    func uploadFile(localPath: String, remotePath: String, profileID: UUID) async throws {
        if shouldThrow { throw DaemonProtocolError.connectionLost }
        uploads.append((local: localPath, remote: remotePath))
    }
}

@Suite("DaemonDeployer")
struct DaemonDeployerTests {

    // MARK: - Platform Detection

    @Test("Parse Linux x86_64 platform")
    func parseLinux() {
        let platform = RemotePlatform.parse("Linux\nx86_64\n")
        #expect(platform?.os == "Linux")
        #expect(platform?.arch == "x86_64")
    }

    @Test("Parse macOS arm64 platform")
    func parseMacOS() {
        let platform = RemotePlatform.parse("Darwin\narm64\n")
        #expect(platform?.os == "Darwin")
        #expect(platform?.arch == "arm64")
    }

    @Test("Parse single-line platform")
    func parseSingleLine() {
        let platform = RemotePlatform.parse("Linux x86_64")
        #expect(platform?.os == "Linux")
        #expect(platform?.arch == "x86_64")
    }

    @Test("Invalid platform returns nil")
    func parseInvalid() {
        let platform = RemotePlatform.parse("")
        #expect(platform == nil)
    }

    // MARK: - Deploy

    @Test("Deploy uploads script and sets executable")
    @MainActor func deploy() async throws {
        let executor = MockDeployExecutor()
        let deployer = DaemonDeployer(executor: executor)

        try await deployer.deploy(profileID: UUID())

        #expect(executor.commands.contains("mkdir -p ~/.cocxy"))
        #expect(executor.uploads.count == 1)
        #expect(executor.commands.contains { $0.contains("chmod +x") })
    }

    // MARK: - Start

    @Test("Start returns daemon port")
    @MainActor func start() async throws {
        let executor = MockDeployExecutor()
        executor.responses["sh ~/.cocxy/cocxyd.sh start"] = "COCXYD_PORT=54321\nDaemon started (PID 12345)"
        let deployer = DaemonDeployer(executor: executor)

        let port = try await deployer.start(profileID: UUID())
        #expect(port == 54321)
    }

    // MARK: - Version

    @Test("Remote version parsed correctly")
    @MainActor func remoteVersion() async throws {
        let executor = MockDeployExecutor()
        let versionCmd = "grep '^COCXYD_VERSION=' ~/.cocxy/cocxyd.sh 2>/dev/null | cut -d'\"' -f2"
        executor.responses[versionCmd] = "1.0.0\n"
        let deployer = DaemonDeployer(executor: executor)

        let version = try await deployer.remoteVersion(profileID: UUID())
        #expect(version == "1.0.0")
    }

    // MARK: - Is Running

    @Test("isRunning detects active daemon")
    @MainActor func isRunningTrue() async throws {
        let executor = MockDeployExecutor()
        executor.responses["sh ~/.cocxy/cocxyd.sh ping"] = "{\"ok\":true,\"data\":{\"pong\":true}}"
        let deployer = DaemonDeployer(executor: executor)

        let running = try await deployer.isRunning(profileID: UUID())
        #expect(running)
    }

    @Test("isRunning detects stopped daemon")
    @MainActor func isRunningFalse() async throws {
        let executor = MockDeployExecutor()
        executor.responses["sh ~/.cocxy/cocxyd.sh ping"] = "{\"ok\":false,\"error\":\"not running\"}"
        let deployer = DaemonDeployer(executor: executor)

        let running = try await deployer.isRunning(profileID: UUID())
        #expect(!running)
    }
}
