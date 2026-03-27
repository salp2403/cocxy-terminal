// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SSHMultiplexerTests.swift - Tests for SSH ControlMaster multiplexer.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Mock Process Executor

final class MockProcessExecutor: ProcessExecutor, @unchecked Sendable {
    var executedCommands: [(command: String, arguments: [String])] = []
    var stubbedResult: ProcessResult = ProcessResult(exitCode: 0, stdout: "", stderr: "")
    var stubbedAsyncResult: ProcessResult?
    var shouldThrow: Bool = false

    func execute(command: String, arguments: [String]) throws -> ProcessResult {
        executedCommands.append((command, arguments))
        if shouldThrow {
            throw SSHMultiplexerError.connectionFailed("mock error")
        }
        return stubbedResult
    }

    func executeAsync(command: String, arguments: [String]) async throws -> ProcessResult {
        executedCommands.append((command, arguments))
        if shouldThrow {
            throw SSHMultiplexerError.connectionFailed("mock error")
        }
        return stubbedAsyncResult ?? stubbedResult
    }
}

// MARK: - SSH Multiplexer Tests

@Suite("SSHMultiplexer")
struct SSHMultiplexerTests {

    private let multiplexer = SSHMultiplexer()

    // MARK: - Control Path Generation

    @Test func controlPathWithUserAndPort() {
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "root", port: 2222
        )
        let home = NSHomeDirectory()

        let path = multiplexer.controlPath(for: profile)

        #expect(path == "\(home)/.config/cocxy/sockets/root@server.com:2222")
    }

    @Test func controlPathWithoutUser() {
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        let home = NSHomeDirectory()

        let path = multiplexer.controlPath(for: profile)

        #expect(path == "\(home)/.config/cocxy/sockets/server.com:22")
    }

    @Test func controlPathUsesDefaultPort() {
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "admin"
        )
        let home = NSHomeDirectory()

        let path = multiplexer.controlPath(for: profile)

        #expect(path == "\(home)/.config/cocxy/sockets/admin@server.com:22")
    }

    // MARK: - Connect

    @Test func connectExecutesControlMasterCommand() throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "root", port: 22
        )

        try multiplexer.connect(profile: profile, executor: executor)

        #expect(executor.executedCommands.count == 1)
        let call = executor.executedCommands[0]
        #expect(call.command == "/usr/bin/ssh")
        #expect(call.arguments.contains("-o"))
        #expect(call.arguments.contains("ControlMaster=auto"))
        #expect(call.arguments.contains("ControlPersist=yes"))
        #expect(call.arguments.contains("root@server.com"))
    }

    @Test func connectIncludesControlPath() throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "deploy", port: 2222
        )
        let home = NSHomeDirectory()

        try multiplexer.connect(profile: profile, executor: executor)

        let call = executor.executedCommands[0]
        let controlPathFlag = "ControlPath=\(home)/.config/cocxy/sockets/deploy@server.com:2222"
        #expect(call.arguments.contains(controlPathFlag))
    }

    @Test func connectIncludesPortFlag() throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", port: 2222
        )

        try multiplexer.connect(profile: profile, executor: executor)

        let call = executor.executedCommands[0]
        #expect(call.arguments.contains("-p"))
        #expect(call.arguments.contains("2222"))
    }

    @Test func connectThrowsOnFailure() {
        let executor = MockProcessExecutor()
        executor.stubbedResult = ProcessResult(
            exitCode: 255, stdout: "", stderr: "Connection refused"
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "unreachable.com")

        #expect(throws: SSHMultiplexerError.self) {
            try multiplexer.connect(profile: profile, executor: executor)
        }
    }

    // MARK: - New Session

    @Test func newSessionReturnsCommandWithControlPath() {
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "deploy", port: 22
        )

        let command = multiplexer.newSession(profile: profile)

        #expect(command.contains("-o ControlPath="))
        #expect(command.contains("deploy@server.com"))
    }

    @Test func newSessionUsesExistingControlMaster() {
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "root"
        )

        let command = multiplexer.newSession(profile: profile)

        #expect(command.hasPrefix("ssh "))
        #expect(command.contains("-o ControlMaster=no"))
        #expect(command.contains("root@server.com"))
    }

    // MARK: - Is Alive

    @Test func isAliveReturnsTrueWhenConnectionActive() async throws {
        let executor = MockProcessExecutor()
        executor.stubbedAsyncResult = ProcessResult(
            exitCode: 0,
            stdout: "Master running (pid=12345)",
            stderr: ""
        )
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "root"
        )

        let alive = try await multiplexer.isAlive(profile: profile, executor: executor)

        #expect(alive == true)

        let call = executor.executedCommands[0]
        #expect(call.arguments.contains("-O"))
        #expect(call.arguments.contains("check"))
    }

    @Test func isAliveReturnsFalseWhenConnectionDead() async throws {
        let executor = MockProcessExecutor()
        executor.stubbedAsyncResult = ProcessResult(
            exitCode: 255, stdout: "", stderr: "No such process"
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")

        let alive = try await multiplexer.isAlive(profile: profile, executor: executor)

        #expect(alive == false)
    }

    // MARK: - Disconnect

    @Test func disconnectSendsExitCommand() throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "root"
        )

        try multiplexer.disconnect(profile: profile, executor: executor)

        let call = executor.executedCommands[0]
        #expect(call.arguments.contains("-O"))
        #expect(call.arguments.contains("exit"))
    }

    // MARK: - Port Forwarding via ControlMaster

    @Test func forwardPortSendsForwardCommand() throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "root"
        )
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 8080, remotePort: 80
        )

        try multiplexer.forwardPort(forward, on: profile, executor: executor)

        let call = executor.executedCommands[0]
        #expect(call.arguments.contains("-O"))
        #expect(call.arguments.contains("forward"))
        #expect(call.arguments.contains("-L"))
        #expect(call.arguments.contains("8080:localhost:80"))
    }

    @Test func cancelForwardSendsCancelCommand() throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "root"
        )
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 8080, remotePort: 80
        )

        try multiplexer.cancelForward(forward, on: profile, executor: executor)

        let call = executor.executedCommands[0]
        #expect(call.arguments.contains("-O"))
        #expect(call.arguments.contains("cancel"))
    }

    @Test func forwardPortWithDynamicForward() throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        let forward = RemoteConnectionProfile.PortForward.dynamic(localPort: 1080)

        try multiplexer.forwardPort(forward, on: profile, executor: executor)

        let call = executor.executedCommands[0]
        #expect(call.arguments.contains("-D"))
        #expect(call.arguments.contains("1080"))
    }
}
