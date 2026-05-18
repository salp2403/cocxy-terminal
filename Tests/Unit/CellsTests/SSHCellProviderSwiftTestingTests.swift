// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SSHCellProviderSwiftTestingTests.swift - SSH-backed Cells provider contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("SSH cell provider")
struct SSHCellProviderSwiftTestingTests {
    @Test("create connects a ControlMaster profile and returns a running SSH cell")
    func createConnectsProfileAndReturnsRunningCell() async throws {
        let cellID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let now = Date(timeIntervalSince1970: 1_800_000_100)
        let multiplexer = RecordingSSHCellMultiplexer()
        let provider = SSHCellProvider(
            multiplexer: multiplexer,
            executor: RecordingSSHCellProcessExecutor(),
            clock: { now },
            idGenerator: { cellID }
        )

        let cell = try await provider.create(CellCreateRequest(
            name: "Lab SSH",
            metadata: [
                "host": "example.test",
                "user": "deploy",
                "port": "2222",
                "identity": "~/.ssh/id_ed25519",
                "known-hosts": "/tmp/cocxy-known-hosts",
                "strict-host-key-checking": "no",
            ]
        ))

        #expect(cell.id == cellID)
        #expect(cell.name == "Lab SSH")
        #expect(cell.provider == .ssh)
        #expect(cell.status == .running)
        #expect(cell.createdAt == now)
        #expect(cell.metadata["host"] == "example.test")
        #expect(cell.metadata["user"] == "deploy")
        #expect(cell.metadata["port"] == "2222")
        #expect(cell.metadata["identity"] == "~/.ssh/id_ed25519")
        #expect(cell.metadata["known-hosts"] == "/tmp/cocxy-known-hosts")
        #expect(cell.metadata["strict-host-key-checking"] == "no")
        #expect(cell.metadata["batch-mode"] == "true")
        #expect(multiplexer.connectedProfiles.count == 1)
        #expect(multiplexer.connectedProfiles[0].id == cellID)
        #expect(multiplexer.connectedProfiles[0].host == "example.test")
        #expect(multiplexer.connectedProfiles[0].user == "deploy")
        #expect(multiplexer.connectedProfiles[0].port == 2222)
        #expect(multiplexer.connectedProfiles[0].identityFile == "~/.ssh/id_ed25519")
        #expect(multiplexer.connectedProfiles[0].knownHostsFile == "/tmp/cocxy-known-hosts")
        #expect(multiplexer.connectedProfiles[0].strictHostKeyChecking == "no")
        #expect(multiplexer.connectedProfiles[0].batchMode == true)
        #expect(multiplexer.connectedProfiles[0].autoReconnect == false)
    }

    @Test("self-hosted kind reuses the SSH transport without rewriting provider identity")
    func selfHostedKindReusesSSHTransport() async throws {
        let cellID = UUID(uuidString: "12121212-3434-5656-7878-909090909090")!
        let multiplexer = RecordingSSHCellMultiplexer()
        let provider = SSHCellProvider(
            kind: .selfHosted,
            multiplexer: multiplexer,
            executor: RecordingSSHCellProcessExecutor(),
            idGenerator: { cellID }
        )

        let cell = try await provider.create(CellCreateRequest(
            name: "Self Hosted",
            metadata: ["host": "metal.example.test", "user": "ops"]
        ))
        let attach = try await provider.attachCommand(cellID: cellID)

        #expect(provider.kind == .selfHosted)
        #expect(cell.provider == .selfHosted)
        #expect(multiplexer.connectedProfiles[0].host == "metal.example.test")
        #expect(attach.argv.last == "ops@metal.example.test")
    }

    @Test("exec shell-quotes argv before sending one remote command")
    func execShellQuotesArgvBeforeRemoteCommand() async throws {
        let cellID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let multiplexer = RecordingSSHCellMultiplexer(
            remoteResult: ProcessResult(exitCode: 0, stdout: "ok\n", stderr: "")
        )
        let provider = SSHCellProvider(
            multiplexer: multiplexer,
            executor: RecordingSSHCellProcessExecutor(),
            idGenerator: { cellID }
        )
        _ = try await provider.create(CellCreateRequest(
            name: "Quoted",
            metadata: ["host": "example.test"]
        ))

        let output = try await provider.exec(
            cellID: cellID,
            command: ["printf", "hello world", "it's ok"]
        )

        #expect(output == "ok\n")
        #expect(multiplexer.remoteCommands == ["printf 'hello world' 'it'\\''s ok'"])
    }

    @Test("status maps dead ControlMaster to stopped without dropping the cell")
    func statusMapsDeadControlMasterToStopped() async throws {
        let cellID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let multiplexer = RecordingSSHCellMultiplexer(isAlive: false)
        let provider = SSHCellProvider(
            multiplexer: multiplexer,
            executor: RecordingSSHCellProcessExecutor(),
            idGenerator: { cellID }
        )
        _ = try await provider.create(CellCreateRequest(
            name: "Dead",
            metadata: ["host": "example.test"]
        ))

        let status = try await provider.status(cellID: cellID)
        let cells = try await provider.list()

        #expect(status == .stopped)
        #expect(cells.count == 1)
        #expect(cells[0].status == .stopped)
    }

    @Test("attach command uses the stored SSH profile as an executable argv")
    func attachCommandUsesStoredProfile() async throws {
        let cellID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let provider = SSHCellProvider(
            multiplexer: RecordingSSHCellMultiplexer(),
            executor: RecordingSSHCellProcessExecutor(),
            idGenerator: { cellID }
        )
        _ = try await provider.create(CellCreateRequest(
            name: "Attach SSH",
            metadata: [
                "host": "example.test",
                "user": "deploy",
                "port": "2222",
                "identity": "/tmp/key with spaces",
                "known-hosts": "/tmp/known hosts",
                "strict-host-key-checking": "accept-new",
                "batch-mode": "false",
            ]
        ))

        let command = try await provider.attachCommand(cellID: cellID)

        #expect(command.argv == [
            "ssh",
            "-p", "2222",
            "-i", "/tmp/key with spaces",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "UserKnownHostsFile=/tmp/known hosts",
            "-o", "BatchMode=no",
            "-o", "ServerAliveInterval=60",
            "-tt",
            "deploy@example.test",
        ])
        #expect(command.shellCommand.contains("'/tmp/key with spaces'"))
        #expect(command.shellCommand.contains("'UserKnownHostsFile=/tmp/known hosts'"))
        #expect(command.displayName == "deploy@example.test:2222")
    }

    @Test("destroy disconnects ControlMaster and removes only the requested cell")
    func destroyDisconnectsAndRemovesRequestedCell() async throws {
        let cellID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let multiplexer = RecordingSSHCellMultiplexer()
        let provider = SSHCellProvider(
            multiplexer: multiplexer,
            executor: RecordingSSHCellProcessExecutor(),
            idGenerator: { cellID }
        )
        _ = try await provider.create(CellCreateRequest(
            name: "Destroy",
            metadata: ["host": "example.test"]
        ))

        try await provider.destroy(cellID: cellID, force: true)

        #expect(multiplexer.disconnectedProfiles.map(\.id) == [cellID])
        #expect(try await provider.list() == [])
    }
}

private final class RecordingSSHCellMultiplexer: SSHMultiplexing, @unchecked Sendable {
    private struct State: Sendable {
        var alive: Bool
        var connectedProfiles: [RemoteConnectionProfile] = []
        var disconnectedProfiles: [RemoteConnectionProfile] = []
        var remoteCommands: [String] = []
    }

    private let state: LockedBox<State>
    private let remoteResult: ProcessResult
    var connectedProfiles: [RemoteConnectionProfile] {
        state.withValue { $0.connectedProfiles }
    }
    var disconnectedProfiles: [RemoteConnectionProfile] {
        state.withValue { $0.disconnectedProfiles }
    }
    var remoteCommands: [String] {
        state.withValue { $0.remoteCommands }
    }

    init(
        isAlive: Bool = true,
        remoteResult: ProcessResult = ProcessResult(exitCode: 0, stdout: "", stderr: "")
    ) {
        state = LockedBox(State(alive: isAlive))
        self.remoteResult = remoteResult
    }

    func controlPath(for profile: RemoteConnectionProfile) -> String {
        profile.controlPath
    }

    func connect(profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws {
        state.withValue { $0.connectedProfiles.append(profile) }
    }

    func newSession(profile: RemoteConnectionProfile) -> String {
        "ssh \(profile.displayTitle)"
    }

    func isAlive(profile: RemoteConnectionProfile, executor: any ProcessExecutor) async throws -> Bool {
        state.withValue { $0.alive }
    }

    func disconnect(profile: RemoteConnectionProfile, executor: any ProcessExecutor) throws {
        state.withValue { $0.disconnectedProfiles.append(profile) }
    }

    func forwardPort(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {}

    func cancelForward(
        _ forward: RemoteConnectionProfile.PortForward,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) throws {}

    func executeRemoteCommand(
        _ command: String,
        on profile: RemoteConnectionProfile,
        executor: any ProcessExecutor
    ) async throws -> ProcessResult {
        state.withValue { $0.remoteCommands.append(command) }
        return remoteResult
    }
}

private struct RecordingSSHCellProcessExecutor: ProcessExecutor {
    func execute(command: String, arguments: [String]) throws -> ProcessResult {
        ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }

    func executeAsync(command: String, arguments: [String]) async throws -> ProcessResult {
        ProcessResult(exitCode: 0, stdout: "", stderr: "")
    }
}
