// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SSHMultiplexerTests.swift - Tests for SSH ControlMaster multiplexer.

import Darwin
import Dispatch
import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Mock Process Executor

final class MockProcessExecutor: ProcessExecutor, @unchecked Sendable {
    var executedCommands: [(command: String, arguments: [String])] = []
    var stubbedResult: ProcessResult = ProcessResult(
        exitCode: 0,
        stdout: "Master running (pid=12345)",
        stderr: ""
    )
    var stubbedAsyncResult: ProcessResult?
    var shouldThrow: Bool = false
    var shouldThrowOnExecute = false
    var shouldThrowOnStart = false
    var managedChildProcessID: Int32 = 12_345
    var managedProcessIsRunning: Bool?
    private(set) var startedProcesses: [MockManagedProcess] = []

    func execute(command: String, arguments: [String]) throws -> ProcessResult {
        executedCommands.append((command, arguments))
        if shouldThrow || shouldThrowOnExecute {
            throw SSHMultiplexerError.connectionFailed("mock error")
        }
        return stubbedResult
    }

    func executeAsync(command: String, arguments: [String]) async throws -> ProcessResult {
        executedCommands.append((command, arguments))
        if shouldThrow || shouldThrowOnExecute {
            throw SSHMultiplexerError.connectionFailed("mock error")
        }
        return stubbedAsyncResult ?? stubbedResult
    }

    func start(command: String, arguments: [String]) throws -> any ManagedProcess {
        executedCommands.append((command, arguments))
        if shouldThrow || shouldThrowOnStart {
            throw SSHMultiplexerError.connectionFailed("mock error")
        }
        let process = MockManagedProcess(
            isRunning: managedProcessIsRunning ?? (stubbedResult.exitCode == 0),
            diagnosticOutput: "COCXY_SSH_CHILD_PID=\(managedChildProcessID)\n\(stubbedResult.stderr)"
        )
        startedProcesses.append(process)
        return process
    }
}

final class MockManagedProcess: ManagedProcess, @unchecked Sendable {
    let processIdentifier: Int32 = 54_321
    private(set) var isRunning: Bool
    let diagnosticOutput: String
    var closeStopsProcess = true
    var closeShouldThrow = false

    init(isRunning: Bool, diagnosticOutput: String) {
        self.isRunning = isRunning
        self.diagnosticOutput = diagnosticOutput
    }

    func closeStandardInput() throws {
        if closeShouldThrow {
            throw ProcessExecutorError.managedProcessUnsupported
        }
        if closeStopsProcess {
            isRunning = false
        }
    }

    func waitForExit(timeout: TimeInterval) -> Bool {
        _ = timeout
        return !isRunning
    }

    func terminate() {
        isRunning = false
    }

    func finish() {
        isRunning = false
    }
}

private final class MultiplexerTestProxyTransport: ProxyUpstreamTransport, @unchecked Sendable {
    let processIdentifier: Int32 = 67_890
    var isRunning = true
    let diagnosticOutput = ""

    func waitUntilReady() async throws {}

    func send(
        _ data: Data,
        completion: @escaping @Sendable (Result<Void, any Error>) -> Void
    ) {
        _ = data
        completion(.success(()))
    }

    func receive(
        maximumLength: Int,
        completion: @escaping @Sendable (Result<Data?, any Error>) -> Void
    ) {
        _ = maximumLength
        _ = completion
    }

    func closeWrite() {}

    func cancel() {
        isRunning = false
    }
}

private final class DirectTCPFactoryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCalls: [(
        controlPath: String,
        target: ProxyTarget,
        attestation: SSHControlSocketAttestation
    )] = []
    private var recordedTransports: [MultiplexerTestProxyTransport] = []

    var calls: [(
        controlPath: String,
        target: ProxyTarget,
        attestation: SSHControlSocketAttestation
    )] {
        lock.lock()
        defer { lock.unlock() }
        return recordedCalls
    }

    var transports: [MultiplexerTestProxyTransport] {
        lock.lock()
        defer { lock.unlock() }
        return recordedTransports
    }

    func make(
        controlPath: String,
        target: ProxyTarget,
        attestation: SSHControlSocketAttestation
    ) -> any ProxyUpstreamTransport {
        let transport = MultiplexerTestProxyTransport()
        lock.lock()
        recordedCalls.append((controlPath, target, attestation))
        recordedTransports.append(transport)
        lock.unlock()
        return transport
    }
}

private final class ControlSocketAttestationSequence: @unchecked Sendable {
    private let lock = NSLock()
    private let values: [SSHControlSocketAttestation]
    private var index = 0

    init(_ values: [SSHControlSocketAttestation]) {
        self.values = values
    }

    func next() throws -> SSHControlSocketAttestation {
        lock.lock()
        defer { lock.unlock() }
        guard !values.isEmpty else { throw SSHMultiplexerError.notConnected }
        let value = values[min(index, values.count - 1)]
        index += 1
        return value
    }
}

private final class ConcurrentProfileExecutor: ProcessExecutor, @unchecked Sendable {
    let releaseFirst = DispatchSemaphore(value: 0)

    private let firstPath: String
    private let secondPath: String
    private let stateLock = NSLock()
    private var firstStarted = false
    private var secondStarted = false

    var hasFirstStarted: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return firstStarted
    }

    var hasSecondStarted: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return secondStarted
    }

    init(firstPath: String, secondPath: String) {
        self.firstPath = firstPath
        self.secondPath = secondPath
    }

    func execute(command: String, arguments: [String]) throws -> ProcessResult {
        _ = command
        let path = controlPath(in: arguments)
        let processID: Int32 = path == firstPath ? 11_111 : 22_222
        return ProcessResult(
            exitCode: 0,
            stdout: "Master running (pid=\(processID))",
            stderr: ""
        )
    }

    func executeAsync(command: String, arguments: [String]) async throws -> ProcessResult {
        try execute(command: command, arguments: arguments)
    }

    func start(command: String, arguments: [String]) throws -> any ManagedProcess {
        _ = command
        let path = controlPath(in: arguments)
        let processID: Int32
        if path == firstPath {
            processID = 11_111
            stateLock.lock()
            firstStarted = true
            stateLock.unlock()
            releaseFirst.wait()
        } else {
            guard path == secondPath else {
                throw SSHMultiplexerError.connectionFailed("Unexpected control path")
            }
            processID = 22_222
            stateLock.lock()
            secondStarted = true
            stateLock.unlock()
        }
        return MockManagedProcess(
            isRunning: true,
            diagnosticOutput: "COCXY_SSH_CHILD_PID=\(processID)"
        )
    }

    private func controlPath(in arguments: [String]) -> String? {
        arguments
            .first { $0.hasPrefix("ControlPath=") }
            .map { String($0.dropFirst("ControlPath=".count)) }
    }
}

private func bindProtectedUnixSocket(at path: String) throws -> Int32 {
    let socketURL = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(
        at: socketURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    _ = Darwin.unlink(path)
    let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }

    var address = sockaddr_un()
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8CString)
    let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
    guard pathBytes.count <= pathCapacity else {
        Darwin.close(descriptor)
        throw SSHMultiplexerError.connectionFailed("Test socket path is too long")
    }
    path.withCString { source in
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { destination in
                _ = memset(destination, 0, pathCapacity)
                _ = memcpy(destination, source, pathBytes.count)
            }
        }
    }
    let bindResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
            Darwin.bind(
                descriptor,
                socketAddress,
                socklen_t(MemoryLayout<sockaddr_un>.size)
            )
        }
    }
    guard bindResult == 0,
          Darwin.chmod(path, 0o600) == 0,
          Darwin.listen(descriptor, 1) == 0 else {
        let savedError = errno
        Darwin.close(descriptor)
        _ = Darwin.unlink(path)
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(savedError))
    }
    return descriptor
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
        let path = multiplexer.controlPath(for: profile)

        #expect(path == profile.controlPath)
    }

    @Test func controlPathWithoutUser() {
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        let path = multiplexer.controlPath(for: profile)

        #expect(path == profile.controlPath)
    }

    @Test func controlPathUsesDefaultPort() {
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "admin"
        )
        let path = multiplexer.controlPath(for: profile)

        #expect(path == profile.controlPath)
    }

    // MARK: - Connect

    @Test func connectExecutesControlMasterCommand() throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "root", port: 22
        )

        try multiplexer.connect(profile: profile, executor: executor)

        #expect(executor.executedCommands.count == 2)
        let call = executor.executedCommands[0]
        #expect(call.command == "/bin/sh")
        #expect(call.arguments.contains("-o"))
        #expect(call.arguments.contains("ControlMaster=yes"))
        #expect(call.arguments.contains("ControlPersist=no"))
        #expect(!call.arguments.contains("-f"))
        #expect(call.arguments.contains("-N"))
        #expect(call.arguments.contains("root@server.com"))
    }

    @Test func connectIncludesControlPath() throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "deploy", port: 2222
        )
        try multiplexer.connect(profile: profile, executor: executor)

        let call = executor.executedCommands[0]
        let controlPathFlag = "ControlPath=\(profile.controlPath)"
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

    @Test func connectRejectsAControlSocketOwnedByAnotherProcess() {
        let executor = MockProcessExecutor()
        executor.managedChildProcessID = 98_765
        executor.managedProcessIsRunning = false
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")

        #expect(throws: SSHMultiplexerError.self) {
            try multiplexer.connect(profile: profile, executor: executor)
        }
    }

    @Test func activeLegacyControlMasterIsLeftUntouched() throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(
            name: "legacy",
            host: "legacy-\(UUID().uuidString.lowercased()).example"
        )
        let descriptor = try bindProtectedUnixSocket(at: profile.legacyControlPath)
        defer {
            Darwin.close(descriptor)
            _ = Darwin.unlink(profile.legacyControlPath)
        }

        #expect(throws: SSHMultiplexerError.self) {
            try multiplexer.connect(profile: profile, executor: executor)
        }
        #expect(FileManager.default.fileExists(atPath: profile.legacyControlPath))
        #expect(!executor.executedCommands.contains { call in
            call.arguments.contains("-O") && call.arguments.contains("exit")
        })
        #expect(executor.startedProcesses.isEmpty)
    }

    @Test func connectCleansSupervisorWhenIdentityCheckThrows() throws {
        let executor = MockProcessExecutor()
        executor.shouldThrowOnExecute = true
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")

        #expect(throws: SSHMultiplexerError.self) {
            try multiplexer.connect(profile: profile, executor: executor)
        }

        let process = try #require(executor.startedProcesses.first)
        #expect(!process.isRunning)
    }

    @Test func staleIdentityCannotTerminateReplacementSupervisor() throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        let firstIdentity = try multiplexer.connect(profile: profile, executor: executor)
        let firstProcess = try #require(executor.startedProcesses.first)

        executor.managedChildProcessID = 12_345
        executor.stubbedResult = ProcessResult(
            exitCode: 0,
            stdout: "Master running (pid=12345)",
            stderr: ""
        )
        let secondIdentity = try multiplexer.connect(profile: profile, executor: executor)
        let secondProcess = try #require(executor.startedProcesses.last)

        #expect(!firstProcess.isRunning)
        #expect(secondProcess.isRunning)
        #expect(!executor.executedCommands.contains { call in
            call.arguments.contains("-O") && call.arguments.contains("exit")
        })
        multiplexer.terminateControlMaster(firstIdentity)
        #expect(secondProcess.isRunning)
        multiplexer.terminateControlMaster(secondIdentity)
        #expect(!secondProcess.isRunning)
    }

    @Test func terminatingSupervisorRemainsTrackedUntilExactProcessExit() throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        let identity = try multiplexer.connect(profile: profile, executor: executor)
        let process = try #require(executor.startedProcesses.first)
        process.closeStopsProcess = false

        multiplexer.terminateControlMaster(identity)

        #expect(process.isRunning)
        #expect(multiplexer.isControlMasterProcessAlive(identity))
        process.finish()
        #expect(!multiplexer.isControlMasterProcessAlive(identity))
    }

    @Test func failedSupervisorPipeCloseEscalatesWithoutDroppingIdentityEarly() throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        let identity = try multiplexer.connect(profile: profile, executor: executor)
        let process = try #require(executor.startedProcesses.first)
        process.closeShouldThrow = true

        multiplexer.terminateControlMaster(identity)

        #expect(!process.isRunning)
        #expect(!multiplexer.isControlMasterProcessAlive(identity))
    }

    @Test func independentProfilesCanStartConcurrently() async throws {
        let multiplexer = SSHMultiplexer()
        let firstProfile = RemoteConnectionProfile(name: "first", host: "first.example")
        let secondProfile = RemoteConnectionProfile(name: "second", host: "second.example")
        let executor = ConcurrentProfileExecutor(
            firstPath: firstProfile.controlPath,
            secondPath: secondProfile.controlPath
        )
        let firstStart = Task.detached {
            Result {
                try multiplexer.connect(profile: firstProfile, executor: executor)
            }
        }
        for _ in 0..<100 where !executor.hasFirstStarted {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(executor.hasFirstStarted)

        let secondStart = Task.detached {
            Result {
                try multiplexer.connect(profile: secondProfile, executor: executor)
            }
        }
        for _ in 0..<100 where !executor.hasSecondStarted {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let secondWasConcurrent = executor.hasSecondStarted
        executor.releaseFirst.signal()

        _ = try await firstStart.value.get()
        _ = try await secondStart.value.get()
        #expect(secondWasConcurrent)
    }

    @Test func foreignStaleSocketIsNeverUnlinked() throws {
        let executor = MockProcessExecutor()
        executor.stubbedResult = ProcessResult(
            exitCode: 255,
            stdout: "",
            stderr: "not an OpenSSH control socket"
        )
        let profile = RemoteConnectionProfile(
            name: "foreign",
            host: "foreign-\(UUID().uuidString.lowercased()).example"
        )
        let socketURL = URL(fileURLWithPath: profile.controlPath)
        try FileManager.default.createDirectory(
            at: socketURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        #expect(descriptor >= 0)
        defer {
            if descriptor >= 0 { Darwin.close(descriptor) }
            _ = Darwin.unlink(profile.controlPath)
        }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(profile.controlPath.utf8CString)
        let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
        #expect(pathBytes.count <= pathCapacity)
        profile.controlPath.withCString { source in
            withUnsafeMutablePointer(to: &address.sun_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { destination in
                    _ = memset(destination, 0, pathCapacity)
                    _ = memcpy(destination, source, pathBytes.count)
                }
            }
        }
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(
                    descriptor,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        #expect(bindResult == 0)
        #expect(Darwin.chmod(profile.controlPath, 0o600) == 0)

        #expect(throws: SSHMultiplexerError.self) {
            try multiplexer.connect(profile: profile, executor: executor)
        }
        #expect(FileManager.default.fileExists(atPath: profile.controlPath))
    }

    @Test func systemManagedProcessStopsWhenItsControlPipeCloses() async throws {
        let process = try SystemProcessExecutor().start(
            command: "/bin/sh",
            arguments: ["-c", "cat >/dev/null"]
        )
        #expect(process.isRunning)

        try process.closeStandardInput()
        for _ in 0..<100 {
            if !process.isRunning { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        if process.isRunning { process.terminate() }
        #expect(!process.isRunning)
    }

    @Test func supervisorExitsWhenItsManagedChildDiesFirst() throws {
        let process = try SystemProcessExecutor().start(
            command: "/bin/sh",
            arguments: [
                "-c",
                SSHMultiplexer.supervisorScript,
                "cocxy-ssh-supervisor-test",
                "/bin/sh",
                "-c",
                "exit 0",
            ]
        )
        defer { process.terminate() }

        #expect(process.waitForExit(timeout: 1.0))
    }

    @Test func supervisorCleansItsChildWhenDiagnosticReaderDisappears() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-supervisor-sigpipe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sshExecutable = root.appendingPathComponent("ssh")
        try FileManager.default.copyItem(
            at: URL(fileURLWithPath: "/bin/sleep"),
            to: sshExecutable
        )

        let supervisor = Process()
        let inputPipe = Pipe()
        let diagnosticPipe = Pipe()
        supervisor.executableURL = URL(fileURLWithPath: "/bin/sh")
        supervisor.arguments = [
            "-c",
            SSHMultiplexer.supervisorScript,
            "cocxy-ssh-supervisor-sigpipe-test",
            sshExecutable.path,
            "2",
        ]
        supervisor.standardInput = inputPipe
        supervisor.standardOutput = diagnosticPipe
        supervisor.standardError = diagnosticPipe
        try diagnosticPipe.fileHandleForReading.close()
        try supervisor.run()
        defer {
            if supervisor.isRunning { supervisor.terminate() }
        }

        let deadline = ProcessInfo.processInfo.systemUptime + 1.0
        while supervisor.isRunning, ProcessInfo.processInfo.systemUptime < deadline {
            usleep(10_000)
        }

        #expect(!supervisor.isRunning)
        let childProbe = try SystemProcessExecutor().execute(
            command: "/usr/bin/pgrep",
            arguments: ["-f", sshExecutable.path]
        )
        #expect(childProbe.exitCode != 0)
    }

    @Test func supervisorInstallsTrapsBeforeSpawnAndNeverKillsCapturedPID() {
        let script = SSHMultiplexer.supervisorScript
        let trapPosition = script.range(of: "trap cleanup EXIT")?.lowerBound
        let spawnPosition = script.range(of: "\"$ssh_path\" \"$@\"")?.lowerBound

        #expect(trapPosition != nil)
        #expect(spawnPosition != nil)
        if let trapPosition, let spawnPosition {
            #expect(trapPosition < spawnPosition)
        }
        #expect(!script.contains("kill \"$ssh_pid\""))
        #expect(script.contains("/usr/bin/pkill -TERM -P \"$$\" -x ssh"))
        #expect(script.contains("wait \"$ssh_pid\""))
        #expect(script.contains("exec 3<&0"))
        #expect(script.contains("<&3 &"))
        #expect(script.contains("trap 'exit 141' PIPE"))
    }

    @Test func supervisedControlMasterLiveSmoke() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["COCXY_RUN_SUPERVISED_SSH_SMOKE"] == "1" else { return }
        let port = try #require(Int(environment["COCXY_SSH_SMOKE_PORT"] ?? ""))
        let user = try #require(environment["COCXY_SSH_SMOKE_USER"])
        let identityFile = try #require(environment["COCXY_SSH_SMOKE_IDENTITY"])
        let knownHostsFile = try #require(environment["COCXY_SSH_SMOKE_KNOWN_HOSTS"])
        let localHTTPPort = try #require(Int(environment["COCXY_SSH_SMOKE_HTTP_PORT"] ?? ""))
        let reversePort = try #require(Int(environment["COCXY_SSH_SMOKE_REVERSE_PORT"] ?? ""))
        let profile = RemoteConnectionProfile(
            name: "supervised-smoke",
            host: "127.0.0.1",
            user: user,
            port: port,
            identityFile: identityFile,
            strictHostKeyChecking: "no",
            knownHostsFile: knownHostsFile,
            batchMode: true,
            autoReconnect: false
        )
        let multiplexer = SSHMultiplexer()
        let executor = SystemProcessExecutor()
        let identity = try multiplexer.connect(profile: profile, executor: executor)
        var terminated = false
        defer {
            if !terminated {
                try? multiplexer.disconnect(profile: profile, executor: executor)
            }
        }
        #expect(multiplexer.isControlMasterProcessAlive(identity))

        let forward = RemoteConnectionProfile.PortForward.remote(
            remotePort: reversePort,
            localPort: localHTTPPort,
            localHost: "127.0.0.1"
        )
        try multiplexer.forwardPort(forward, on: profile, executor: executor)
        let result = try await multiplexer.executeRemoteCommand(
            "curl -fsS http://127.0.0.1:\(reversePort)",
            on: profile,
            executor: executor
        )
        #expect(result.exitCode == 0)
        #expect(result.stdout == "forward-ok")

        multiplexer.terminateControlMaster(identity)
        terminated = true
        for _ in 0..<100 {
            if !multiplexer.isControlMasterProcessAlive(identity) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(!multiplexer.isControlMasterProcessAlive(identity))

        let reverseProbe = try executor.execute(
            command: "/usr/bin/ssh",
            arguments: [
                "-p", "\(port)",
                "-i", identityFile,
                "-o", "StrictHostKeyChecking=no",
                "-o", "UserKnownHostsFile=\(knownHostsFile)",
                "-o", "BatchMode=yes",
                "--", "\(user)@127.0.0.1",
                "curl -fsS --connect-timeout 1 http://127.0.0.1:\(reversePort)",
            ]
        )
        #expect(reverseProbe.exitCode != 0)
    }

    // MARK: - New Session

    @Test func newSessionReturnsCommandWithControlPath() throws {
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "deploy", port: 22
        )

        let command = try multiplexer.newSession(profile: profile)

        #expect(command.contains("-o ControlPath="))
        #expect(command.contains(" -- deploy@server.com"))
        #expect(command.contains("deploy@server.com"))
    }

    @Test func newSessionUsesExistingControlMaster() throws {
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "root"
        )

        let command = try multiplexer.newSession(profile: profile)

        #expect(command.hasPrefix("ssh "))
        #expect(command.contains("-o ControlMaster=no"))
        #expect(command.contains("root@server.com"))
    }

    @Test func rejectsOptionLikeDestinationBeforeExecution() {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(
            name: "unsafe",
            host: "-oProxyCommand=/bin/true"
        )

        #expect(throws: SSHMultiplexerError.invalidDestination) {
            try multiplexer.connect(profile: profile, executor: executor)
        }
        #expect(executor.executedCommands.isEmpty)
    }

    @Test func acceptsIPv6DestinationAndPlacesItAfterOptionBoundary() throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(
            name: "ipv6",
            host: "2001:db8::10",
            user: "deploy"
        )

        try multiplexer.connect(profile: profile, executor: executor)

        #expect(executor.executedCommands[0].arguments.suffix(2) == ["--", "deploy@2001:db8::10"])
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

    @Test func controlOperationsCarryPortAndIdentity() async throws {
        let executor = MockProcessExecutor()
        executor.stubbedAsyncResult = ProcessResult(
            exitCode: 0,
            stdout: "Master running",
            stderr: ""
        )
        let profile = RemoteConnectionProfile(
            name: "lab",
            host: "127.0.0.1",
            user: "deploy",
            port: 2222,
            identityFile: "/tmp/cocxy key",
            strictHostKeyChecking: "no",
            knownHostsFile: "/tmp/cocxy-known-hosts",
            batchMode: true
        )

        _ = try multiplexer.connect(profile: profile, executor: executor)
        _ = try await multiplexer.isAlive(profile: profile, executor: executor)
        try multiplexer.disconnect(profile: profile, executor: executor)
        _ = try await multiplexer.executeRemoteCommand("printf ok", on: profile, executor: executor)

        for call in executor.executedCommands {
            #expect(call.arguments.contains("-p"))
            #expect(call.arguments.contains("2222"))
            #expect(call.arguments.contains("-i"))
            #expect(call.arguments.contains("/tmp/cocxy key"))
            #expect(call.arguments.contains("StrictHostKeyChecking=no"))
            #expect(call.arguments.contains("UserKnownHostsFile=/tmp/cocxy-known-hosts"))
            #expect(call.arguments.contains("BatchMode=yes"))
            let boundaryIndex = try #require(call.arguments.firstIndex(of: "--"))
            #expect(call.arguments[call.arguments.index(after: boundaryIndex)] == "deploy@127.0.0.1")
        }
    }

    @Test func everyOpenSSHOperationBoundsOptionsBeforeDestination() async throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(
            name: "lab",
            host: "config_alias",
            user: "deploy"
        )
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 8080,
            remotePort: 80
        )

        try multiplexer.connect(profile: profile, executor: executor)
        _ = try await multiplexer.isAlive(profile: profile, executor: executor)
        try multiplexer.disconnect(profile: profile, executor: executor)
        try multiplexer.forwardPort(forward, on: profile, executor: executor)
        try multiplexer.cancelForward(forward, on: profile, executor: executor)
        _ = try await multiplexer.executeRemoteCommand(
            "printf ok",
            on: profile,
            executor: executor
        )

        #expect(executor.executedCommands.count == 6)
        for call in executor.executedCommands {
            let boundaryIndex = try #require(call.arguments.firstIndex(of: "--"))
            let destinationIndex = call.arguments.index(after: boundaryIndex)
            #expect(call.arguments[destinationIndex] == "deploy@config_alias")
        }
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

    @Test func disconnectClosesExactSupervisorWithoutControlCommand() throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "root"
        )

        _ = try multiplexer.connect(profile: profile, executor: executor)
        let process = try #require(executor.startedProcesses.first)
        let commandCount = executor.executedCommands.count
        try multiplexer.disconnect(profile: profile, executor: executor)

        #expect(!process.isRunning)
        #expect(executor.executedCommands.count == commandCount)
        #expect(!executor.executedCommands.contains { call in
            call.arguments.contains("-O") && call.arguments.contains("exit")
        })
    }

    @Test func unownedDisconnectNeverSendsAControlCommand() {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(
            name: "unowned", host: "server.com", user: "root"
        )

        #expect(throws: SSHMultiplexerError.notConnected) {
            try multiplexer.disconnect(profile: profile, executor: executor)
        }
        #expect(executor.executedCommands.isEmpty)
    }

    @Test func deadSupervisorDisconnectNeverSendsAControlCommand() throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(
            name: "dead", host: "server.com", user: "root"
        )
        _ = try multiplexer.connect(profile: profile, executor: executor)
        let process = try #require(executor.startedProcesses.first)
        process.finish()
        let commandCount = executor.executedCommands.count

        #expect(throws: SSHMultiplexerError.notConnected) {
            try multiplexer.disconnect(profile: profile, executor: executor)
        }
        #expect(executor.executedCommands.count == commandCount)
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

    @Test func forwardPortRejectsLegacyDynamicForwardWithoutExecutingSSH() {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        let forward = RemoteConnectionProfile.PortForward.dynamic(localPort: 1080)

        #expect(throws: SSHMultiplexerError.self) {
            try multiplexer.forwardPort(forward, on: profile, executor: executor)
        }
        #expect(executor.executedCommands.isEmpty)
    }

    @Test func cancelForwardRejectsLegacyDynamicForwardWithoutExecutingSSH() {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        let forward = RemoteConnectionProfile.PortForward.dynamic(localPort: 1080)

        #expect(throws: SSHMultiplexerError.self) {
            try multiplexer.cancelForward(forward, on: profile, executor: executor)
        }
        #expect(executor.executedCommands.isEmpty)
    }

    @Test func directTCPTransportRequiresExactLiveSupervisedMaster() throws {
        let recorder = DirectTCPFactoryRecorder()
        let executor = MockProcessExecutor()
        let attestation = SSHControlSocketAttestation(
            device: 1,
            inode: 2,
            peerProcessID: executor.managedChildProcessID
        )
        let multiplexer = SSHMultiplexer(
            directTCPTransportFactory: { controlPath, target, attestation in
                recorder.make(
                    controlPath: controlPath,
                    target: target,
                    attestation: attestation
                )
            },
            controlSocketAttestationProvider: { _ in attestation }
        )
        let profile = RemoteConnectionProfile(
            name: "dev",
            host: "server.com",
            user: "operator"
        )
        let identity = try multiplexer.connect(profile: profile, executor: executor)
        defer { multiplexer.terminateControlMaster(identity) }
        let target = try ProxyTarget(host: "internal.example", port: 443)
        let wrongIdentity = SSHControlMasterIdentity(
            processID: identity.processID,
            controlPath: identity.controlPath,
            supervisorID: UUID()
        )

        #expect(throws: SSHMultiplexerError.self) {
            try multiplexer.openDirectTCPTransport(
                to: target,
                on: profile,
                expectedControlMaster: wrongIdentity
            )
        }
        #expect(recorder.calls.isEmpty)

        _ = try multiplexer.openDirectTCPTransport(
            to: target,
            on: profile,
            expectedControlMaster: identity
        )
        let call = try #require(recorder.calls.first)
        #expect(call.controlPath == profile.controlPath)
        #expect(call.target == target)
        #expect(call.attestation == attestation)

        executor.startedProcesses.first?.finish()
        #expect(throws: SSHMultiplexerError.self) {
            try multiplexer.openDirectTCPTransport(
                to: target,
                on: profile,
                expectedControlMaster: identity
            )
        }
        #expect(recorder.calls.count == 1)
    }

    @Test func directTCPTransportRejectsUnexpectedControlSocketPeer() throws {
        let recorder = DirectTCPFactoryRecorder()
        let executor = MockProcessExecutor()
        let multiplexer = SSHMultiplexer(
            directTCPTransportFactory: { controlPath, target, attestation in
                recorder.make(
                    controlPath: controlPath,
                    target: target,
                    attestation: attestation
                )
            },
            controlSocketAttestationProvider: { _ in
                SSHControlSocketAttestation(device: 1, inode: 2, peerProcessID: 99_999)
            }
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        let identity = try multiplexer.connect(profile: profile, executor: executor)
        defer { multiplexer.terminateControlMaster(identity) }

        #expect(throws: SSHMultiplexerError.notConnected) {
            try multiplexer.openDirectTCPTransport(
                to: ProxyTarget(host: "internal.example", port: 443),
                on: profile,
                expectedControlMaster: identity
            )
        }
        #expect(recorder.calls.isEmpty)
    }

    @Test func directTCPTransportCancelsWhenControlSocketChangesDuringLaunch() throws {
        let recorder = DirectTCPFactoryRecorder()
        let executor = MockProcessExecutor()
        let expected = SSHControlSocketAttestation(
            device: 1,
            inode: 2,
            peerProcessID: executor.managedChildProcessID
        )
        let replacement = SSHControlSocketAttestation(
            device: 1,
            inode: 3,
            peerProcessID: executor.managedChildProcessID
        )
        let attestations = ControlSocketAttestationSequence([expected, replacement])
        let multiplexer = SSHMultiplexer(
            directTCPTransportFactory: { controlPath, target, attestation in
                recorder.make(
                    controlPath: controlPath,
                    target: target,
                    attestation: attestation
                )
            },
            controlSocketAttestationProvider: { _ in try attestations.next() }
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        let identity = try multiplexer.connect(profile: profile, executor: executor)
        defer { multiplexer.terminateControlMaster(identity) }

        #expect(throws: SSHMultiplexerError.notConnected) {
            try multiplexer.openDirectTCPTransport(
                to: ProxyTarget(host: "internal.example", port: 443),
                on: profile,
                expectedControlMaster: identity
            )
        }
        #expect(recorder.calls.count == 1)
        #expect(recorder.transports.first?.isRunning == false)
    }

    @Test func directTCPTransportReattestsSocketAfterChannelConfirmation() async throws {
        let recorder = DirectTCPFactoryRecorder()
        let executor = MockProcessExecutor()
        let expected = SSHControlSocketAttestation(
            device: 1,
            inode: 2,
            peerProcessID: executor.managedChildProcessID
        )
        let replacement = SSHControlSocketAttestation(
            device: 1,
            inode: 3,
            peerProcessID: executor.managedChildProcessID
        )
        let attestations = ControlSocketAttestationSequence([expected, expected, replacement])
        let multiplexer = SSHMultiplexer(
            directTCPTransportFactory: { controlPath, target, attestation in
                recorder.make(
                    controlPath: controlPath,
                    target: target,
                    attestation: attestation
                )
            },
            controlSocketAttestationProvider: { _ in try attestations.next() }
        )
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")
        let identity = try multiplexer.connect(profile: profile, executor: executor)
        defer { multiplexer.terminateControlMaster(identity) }
        let transport = try multiplexer.openDirectTCPTransport(
            to: ProxyTarget(host: "internal.example", port: 443),
            on: profile,
            expectedControlMaster: identity
        )

        await #expect(throws: SSHMultiplexerError.notConnected) {
            try await transport.waitUntilReady()
        }
        #expect(recorder.transports.first?.isRunning == false)
    }
}
