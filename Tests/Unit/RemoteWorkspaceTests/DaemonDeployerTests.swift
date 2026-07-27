// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonDeployerTests.swift - Tests for daemon deployment and platform detection.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Mock Deploy Executor

@MainActor
final class MockDeployExecutor: DaemonDeployExecuting {
    var commands: [String] = []
    var commandProfileIDs: [UUID] = []
    var uploads: [(local: String, remote: String)] = []
    var uploadProfileIDs: [UUID] = []
    var responses: [String: String] = [:]
    var responseQueues: [String: [String]] = [:]
    var errors: [String: any Error] = [:]
    var shouldThrow = false

    func executeRemote(_ command: String, profileID: UUID) async throws -> String {
        if shouldThrow { throw DaemonProtocolError.connectionLost }
        commands.append(command)
        commandProfileIDs.append(profileID)
        if let error = errors[command] { throw error }
        if var queued = responseQueues[command], !queued.isEmpty {
            let next = queued.removeFirst()
            responseQueues[command] = queued
            return next
        }
        return responses[command] ?? ""
    }

    func uploadFile(localPath: String, remotePath: String, profileID: UUID) async throws {
        if shouldThrow { throw DaemonProtocolError.connectionLost }
        uploads.append((local: localPath, remote: remotePath))
        uploadProfileIDs.append(profileID)
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

    @Test("Deploy uploads the absolute bundled script and sets executable")
    @MainActor func deploy() async throws {
        let scriptURL = try makeTemporaryScript()
        defer { try? FileManager.default.removeItem(at: scriptURL.deletingLastPathComponent()) }
        let executor = MockDeployExecutor()
        let deployer = DaemonDeployer(executor: executor, bundledScriptURL: scriptURL)
        let profileID = UUID()

        try await deployer.deploy(profileID: profileID)

        #expect(executor.commands.contains(DaemonDeployer.prepareRemoteDirectoryCommand))
        #expect(executor.uploads.count == 1)
        #expect(executor.uploads.first?.local == scriptURL.standardizedFileURL.path)
        #expect(executor.uploads.first?.local.hasPrefix("/") == true)
        #expect(executor.uploads.first?.remote == DaemonDeployer.remotePath)
        #expect(executor.commands.contains(DaemonDeployer.secureRemoteScriptCommand))
        #expect(executor.commandProfileIDs == [profileID, profileID])
        #expect(executor.uploadProfileIDs == [profileID])
    }

    @Test("Deploy fails before remote mutation when bundled script is absent")
    @MainActor func deployMissingScript() async {
        let executor = MockDeployExecutor()
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("cocxyd.sh")
        let deployer = DaemonDeployer(executor: executor, bundledScriptURL: missingURL)

        do {
            try await deployer.deploy(profileID: UUID())
            Issue.record("Expected deployment to reject a missing bundled script")
        } catch {
            #expect(error as? DaemonDeployError == .bundledScriptUnavailable)
        }

        #expect(executor.commands.isEmpty)
        #expect(executor.uploads.isEmpty)
    }

    @Test("Deploy rejects a directory in place of the bundled script")
    @MainActor func deployDirectory() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxyd-directory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let executor = MockDeployExecutor()
        let deployer = DaemonDeployer(executor: executor, bundledScriptURL: directoryURL)

        do {
            try await deployer.deploy(profileID: UUID())
            Issue.record("Expected deployment to reject a directory resource")
        } catch {
            #expect(error as? DaemonDeployError == .bundledScriptUnavailable)
        }

        #expect(executor.commands.isEmpty)
        #expect(executor.uploads.isEmpty)
    }

    // MARK: - Start

    @Test("Start returns daemon port")
    @MainActor func start() async throws {
        let executor = MockDeployExecutor()
        let profileID = UUID()
        executor.responses[DaemonDeployer.startCommand(profileID: profileID)] =
            "COCXYD_PORT=54321\nDaemon started (PID 12345)"
        let deployer = DaemonDeployer(executor: executor)

        let port = try await deployer.start(profileID: profileID)
        #expect(port == 54321)
        #expect(executor.commandProfileIDs == [profileID])
    }

    @Test("Start rejects an out-of-range daemon port")
    @MainActor func startRejectsInvalidPort() async {
        let executor = MockDeployExecutor()
        let profileID = UUID()
        executor.responses[DaemonDeployer.startCommand(profileID: profileID)] =
            "COCXYD_PORT=70000"
        let deployer = DaemonDeployer(executor: executor)

        do {
            _ = try await deployer.start(profileID: profileID)
            Issue.record("Expected an invalid daemon port to be rejected")
        } catch {
            #expect(error as? DaemonProtocolError == .invalidResponse)
        }
    }

    @Test("Profile namespaces are stable, distinct, and shell-safe")
    @MainActor func profileNamespacesAreStableAndDistinct() throws {
        let first = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let second = try #require(UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"))
        let firstNamespace = DaemonDeployer.profileNamespace(first)
        let secondNamespace = DaemonDeployer.profileNamespace(second)

        #expect(firstNamespace == "11111111222233334444555555555555")
        #expect(secondNamespace == "aaaaaaaabbbbccccddddeeeeeeeeeeee")
        #expect(firstNamespace != secondNamespace)
        #expect(firstNamespace.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        #expect(DaemonDeployer.startCommand(profileID: first).hasSuffix(firstNamespace))
        #expect(DaemonDeployer.stopCommand(profileID: second).hasSuffix(secondNamespace))
    }

    @Test("Start timeout reconciles the namespaced port before failing")
    @MainActor func startTimeoutReconcilesPublishedPort() async throws {
        let executor = MockDeployExecutor()
        let profileID = UUID()
        let startCommand = DaemonDeployer.startCommand(profileID: profileID)
        let portCommand = DaemonDeployer.readRemotePortCommand(profileID: profileID)
        executor.errors[startCommand] = SSHMultiplexerError.remoteCommandTimedOut(
            "start timed out"
        )
        executor.responses[portCommand] = "43123\n"
        let deployer = DaemonDeployer(executor: executor)

        let port = try await deployer.start(profileID: profileID)

        #expect(port == 43_123)
        #expect(executor.commands == [startCommand, portCommand])
        #expect(executor.commandProfileIDs == [profileID, profileID])
    }

    @Test("Unreconciled start timeout preserves structured provenance")
    @MainActor func startTimeoutPreservesOriginalError() async {
        let executor = MockDeployExecutor()
        let profileID = UUID()
        let startCommand = DaemonDeployer.startCommand(profileID: profileID)
        executor.errors[startCommand] = SSHMultiplexerError.remoteCommandTimedOut(
            "start timed out"
        )
        executor.responses[DaemonDeployer.readRemotePortCommand(profileID: profileID)] =
            "invalid\n"
        let deployer = DaemonDeployer(executor: executor)

        do {
            _ = try await deployer.start(profileID: profileID)
            Issue.record("Expected an unreconciled start timeout")
        } catch {
            #expect(
                error as? SSHMultiplexerError
                    == .remoteCommandTimedOut("start timed out")
            )
        }
    }

    @Test("Stop timeout succeeds only after the profile reports stopped")
    @MainActor func stopTimeoutReconcilesProfileState() async throws {
        let executor = MockDeployExecutor()
        let profileID = UUID()
        let stopCommand = DaemonDeployer.stopCommand(profileID: profileID)
        let pingCommand = DaemonDeployer.pingCommand(profileID: profileID)
        executor.errors[stopCommand] = SSHMultiplexerError.remoteCommandTimedOut(
            "stop timed out"
        )
        executor.responses[pingCommand] = #"{"ok":false,"error":"not running"}"#
        let deployer = DaemonDeployer(executor: executor)

        try await deployer.stop(profileID: profileID)

        #expect(executor.commands == [stopCommand, pingCommand])
        #expect(executor.commandProfileIDs == [profileID, profileID])
    }

    @Test("Read remote port uses shell expansion and validates its range")
    @MainActor func readRemotePort() async throws {
        let executor = MockDeployExecutor()
        let profileID = UUID()
        let command = DaemonDeployer.readRemotePortCommand(profileID: profileID)
        executor.responses[command] = "43123\n"
        let deployer = DaemonDeployer(executor: executor)

        let port = try await deployer.readRemotePort(profileID: profileID)

        #expect(port == 43_123)
        #expect(executor.commands == [command])
        #expect(command.contains("${XDG_RUNTIME_DIR:-/tmp}"))
        #expect(command.contains(DaemonDeployer.profileNamespace(profileID)))
        #expect(!command.contains("\\${XDG_RUNTIME_DIR"))
    }

    @Test("Read remote port rejects non-numeric state")
    @MainActor func readRemotePortRejectsInvalidState() async {
        let executor = MockDeployExecutor()
        let profileID = UUID()
        executor.responses[DaemonDeployer.readRemotePortCommand(profileID: profileID)] =
            "not-a-port\n"
        let deployer = DaemonDeployer(executor: executor)

        do {
            _ = try await deployer.readRemotePort(profileID: profileID)
            Issue.record("Expected invalid remote port state to be rejected")
        } catch {
            #expect(error as? DaemonProtocolError == .invalidResponse)
        }
    }

    @Test("Read remote capability accepts only a lowercase 256-bit token")
    @MainActor func readRemoteCapability() async throws {
        let executor = MockDeployExecutor()
        let profileID = UUID()
        let capability = String(repeating: "0f", count: 32)
        let command = DaemonDeployer.readRemoteCapabilityCommand(profileID: profileID)
        executor.responses[command] = capability + "\n"
        let deployer = DaemonDeployer(executor: executor)

        let result = try await deployer.readRemoteCapability(profileID: profileID)

        #expect(result == capability)
        #expect(executor.commands == [command])
    }

    @Test("Read remote capability rejects malformed or uppercase tokens")
    @MainActor func readRemoteCapabilityRejectsInvalidState() async {
        let executor = MockDeployExecutor()
        let profileID = UUID()
        executor.responses[DaemonDeployer.readRemoteCapabilityCommand(profileID: profileID)] =
            String(repeating: "AF", count: 32)
        let deployer = DaemonDeployer(executor: executor)

        do {
            _ = try await deployer.readRemoteCapability(profileID: profileID)
            Issue.record("Expected malformed capability state to be rejected")
        } catch {
            #expect(error as? DaemonProtocolError == .authenticationFailed)
        }
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
        let profileID = UUID()
        executor.responses[DaemonDeployer.pingCommand(profileID: profileID)] =
            "{\"ok\":true,\"data\":{\"pong\":true}}"
        let deployer = DaemonDeployer(executor: executor)

        let running = try await deployer.isRunning(profileID: profileID)
        #expect(running)
    }

    @Test("isRunning detects stopped daemon")
    @MainActor func isRunningFalse() async throws {
        let executor = MockDeployExecutor()
        let profileID = UUID()
        executor.responses[DaemonDeployer.pingCommand(profileID: profileID)] =
            "{\"ok\":false,\"error\":\"not running\"}"
        let deployer = DaemonDeployer(executor: executor)

        let running = try await deployer.isRunning(profileID: profileID)
        #expect(!running)
    }

    private func makeTemporaryScript() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxyd-deployer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let scriptURL = directoryURL.appendingPathComponent("cocxyd.sh")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: scriptURL)
        return scriptURL
    }
}
