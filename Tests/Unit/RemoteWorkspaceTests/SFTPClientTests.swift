// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SFTPClientTests.swift - Tests for SFTP file operations wrapper.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Mock SFTP Executor

final class MockSFTPExecutor: SFTPExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var commandStorage: [(
        sftpCommand: String,
        destination: SSHConnectionDestination,
        port: Int?,
        controlPath: String
    )] = []
    var stubbedOutput = ""
    var shouldThrow = false
    var executionDelay: TimeInterval = 0
    var beforeReturning: ((String) throws -> Void)?
    var outputProvider: ((String) throws -> String)?
    var downloadPayloadProvider: ((String) throws -> Data)?

    var executedCommands: [(
        sftpCommand: String,
        destination: SSHConnectionDestination,
        port: Int?,
        controlPath: String
    )] {
        lock.lock()
        defer { lock.unlock() }
        return commandStorage
    }

    func execute(
        sftpCommand: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> String {
        lock.lock()
        commandStorage.append((
            sftpCommand,
            authorization.destination,
            authorization.port,
            authorization.controlPath
        ))
        let output = stubbedOutput
        let throwsError = shouldThrow
        let delay = executionDelay
        let callback = beforeReturning
        let provider = outputProvider
        let payloadProvider = downloadPayloadProvider
        lock.unlock()
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
        if throwsError {
            throw SFTPClientError.commandFailed("mock sftp error")
        }
        if sftpCommand.hasPrefix("get "),
           let payloadPath = Self.lastQuotedArgument(in: sftpCommand) {
            let payload = try payloadProvider?(sftpCommand)
                ?? (sftpCommand.hasPrefix("get '/etc/app/")
                    || sftpCommand.hasPrefix("get '/tmp/")
                    || sftpCommand.hasPrefix("get './config.yml'")
                    || sftpCommand.hasPrefix("get './.cocxy-review-")
                    ? Data(repeating: 0x41, count: 12)
                    : Data("downloaded".utf8))
            try payload.write(to: URL(fileURLWithPath: payloadPath))
        }
        try callback?(sftpCommand)
        return try provider?(sftpCommand) ?? output
    }

    private static func lastQuotedArgument(in command: String) -> String? {
        guard command.last == "'" else { return nil }
        let end = command.index(before: command.endIndex)
        guard let start = command[..<end].lastIndex(of: "'") else { return nil }
        return String(command[command.index(after: start)..<end])
    }
}

final class RecordingSFTPProcessRunner: SFTPProcessRunning, @unchecked Sendable {
    var invocation: SFTPProcessInvocation?
    var batchContents: String?
    var batchContentsHistory: [String] = []
    var batchPermissions: Int?
    var result = BoundedProcessResult(
        exitCode: 0,
        stdout: "fixture output",
        stderr: "",
        stdoutWasTruncated: false,
        stderrWasTruncated: false,
        timedOut: false
    )

    func run(_ invocation: SFTPProcessInvocation) throws -> BoundedProcessResult {
        self.invocation = invocation
        if let batchPath = invocation.arguments.dropFirst().first {
            batchContents = try String(contentsOfFile: batchPath, encoding: .utf8)
            batchContentsHistory.append(batchContents ?? "")
            let attributes = try FileManager.default.attributesOfItem(atPath: batchPath)
            batchPermissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        }
        return result
    }
}

private final class StructuredListingSFTPExecutor: SFTPExecutor, @unchecked Sendable {
    let output: SFTPDirectoryListingOutput

    init(canonicalNames: String, longListing: String) {
        output = SFTPDirectoryListingOutput(
            canonicalNames: canonicalNames,
            longListing: longListing
        )
    }

    func execute(
        sftpCommand: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> String {
        _ = sftpCommand
        _ = authorization
        return ""
    }

    func directoryListing(
        path: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> SFTPDirectoryListingOutput {
        _ = path
        _ = authorization
        return output
    }
}

private final class RevocationAwareSFTPProcessRunner: SFTPProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var startedStorage = false

    var started: Bool {
        lock.withLock { startedStorage }
    }

    func run(_ invocation: SFTPProcessInvocation) throws -> BoundedProcessResult {
        lock.withLock { startedStorage = true }
        for _ in 0..<1_000 {
            if invocation.cancellationRequested() {
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.002)
        }
        return BoundedProcessResult(
            exitCode: 0,
            stdout: "",
            stderr: "",
            stdoutWasTruncated: false,
            stderrWasTruncated: false,
            timedOut: false
        )
    }
}

private func firstQuotedArgument(in command: String) -> String? {
    guard let openingQuote = command.firstIndex(of: "'") else { return nil }
    let valueStart = command.index(after: openingQuote)
    guard let closingQuote = command[valueStart...].firstIndex(of: "'") else { return nil }
    return String(command[valueStart..<closingQuote])
}

private func quotedArguments(in command: String) -> [String] {
    var arguments: [String] = []
    var cursor = command.startIndex
    while let opening = command[cursor...].firstIndex(of: "'") {
        let valueStart = command.index(after: opening)
        guard let closing = command[valueStart...].firstIndex(of: "'") else { break }
        arguments.append(String(command[valueStart..<closing]))
        cursor = command.index(after: closing)
    }
    return arguments
}

private final class SFTPVerifierProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var verificationCountStorage = 0
    private var failureCallStorage: Int?

    var verificationCount: Int {
        lock.withLock { verificationCountStorage }
    }

    func fail(onCall call: Int?) {
        lock.withLock { failureCallStorage = call }
    }

    func verify() throws {
        let shouldFail = lock.withLock { () -> Bool in
            verificationCountStorage += 1
            return failureCallStorage == verificationCountStorage
        }
        if shouldFail { throw SSHMultiplexerError.notConnected }
    }
}

private final class CancellationAwareSFTPExecutor: SFTPExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var startedStorage = false
    private var cancellationObservedStorage = false

    var started: Bool { lock.withLock { startedStorage } }
    var cancellationObserved: Bool { lock.withLock { cancellationObservedStorage } }

    func execute(
        sftpCommand: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> String {
        _ = sftpCommand
        _ = authorization
        lock.withLock { startedStorage = true }
        for _ in 0..<400 {
            if Task.isCancelled {
                lock.withLock { cancellationObservedStorage = true }
                throw CancellationError()
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return ""
    }
}

private final class RecoveringUploadCancellationSFTPExecutor: SFTPExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var uploadStartedStorage = false
    private var recoveryCommandsStorage: [String] = []

    var uploadStarted: Bool { lock.withLock { uploadStartedStorage } }
    var recoveryCommands: [String] { lock.withLock { recoveryCommandsStorage } }

    func execute(
        sftpCommand: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> String {
        _ = authorization
        guard sftpCommand.hasPrefix("put ") else { return "" }
        lock.withLock { uploadStartedStorage = true }
        while !Task.isCancelled {
            Thread.sleep(forTimeInterval: 0.002)
        }
        throw CancellationError()
    }

    func executeRecovery(
        sftpCommand: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> String {
        _ = authorization
        lock.withLock { recoveryCommandsStorage.append(sftpCommand) }
        return ""
    }
}

private final class RecoveringRemovalCancellationSFTPExecutor: SFTPExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var quarantinePathStorage: String?
    private var deleteStartedStorage = false
    private var restorationAttemptedStorage = false
    private var recoveryCommandsStorage: [String] = []

    var deleteStarted: Bool { lock.withLock { deleteStartedStorage } }
    var restorationAttempted: Bool { lock.withLock { restorationAttemptedStorage } }
    var recoveryCommands: [String] { lock.withLock { recoveryCommandsStorage } }
    var quarantinePath: String? { lock.withLock { quarantinePathStorage } }

    func execute(
        sftpCommand: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> String {
        _ = authorization
        if sftpCommand.hasPrefix("rename -l '/tmp/old-file.txt' ") {
            lock.withLock {
                quarantinePathStorage = quotedArguments(in: sftpCommand).last
            }
            return ""
        }
        if sftpCommand.hasPrefix("rm '/tmp/.cocxy-review-") {
            lock.withLock { deleteStartedStorage = true }
            while !Task.isCancelled, !authorization.isRevoked {
                Thread.sleep(forTimeInterval: 0.002)
            }
            throw CancellationError()
        }
        if Task.isCancelled {
            throw CancellationError()
        }
        if sftpCommand.hasPrefix("get ") {
            try writeReviewedPayload(for: sftpCommand)
            return ""
        }
        if sftpCommand == "ls -la '/tmp'" {
            return listing()
        }
        return ""
    }

    func executeRecovery(
        sftpCommand: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> String {
        _ = authorization
        lock.withLock { recoveryCommandsStorage.append(sftpCommand) }
        if sftpCommand.hasPrefix("rename -l '/tmp/.cocxy-review-") {
            lock.withLock { restorationAttemptedStorage = true }
            throw SFTPClientError.commandFailed("restoration acknowledgement unavailable")
        }
        if sftpCommand.hasPrefix("get ") {
            try writeReviewedPayload(for: sftpCommand)
        }
        return ""
    }

    func directoryListingRecovery(
        path: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> SFTPDirectoryListingOutput {
        _ = authorization
        lock.withLock { recoveryCommandsStorage.append("recovery-list \(path)") }
        return SFTPDirectoryListingOutput(
            canonicalNames: nil,
            longListing: listing()
        )
    }

    private func listing() -> String {
        guard let quarantinePath = lock.withLock({ quarantinePathStorage }) else {
            return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 old-file.txt\n"
        }
        return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 "
            + URL(fileURLWithPath: quarantinePath).lastPathComponent + "\n"
    }

    private func writeReviewedPayload(for command: String) throws {
        guard let destination = quotedArguments(in: command).last else { return }
        try Data(repeating: 0x41, count: 12).write(
            to: URL(fileURLWithPath: destination)
        )
    }
}

private final class SFTPLifecycleMutationExecutor: SFTPExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var mutationCommandsStorage: [String] = []
    private var firstMutationReleasedStorage = false

    var mutationCommands: [String] { lock.withLock { mutationCommandsStorage } }

    func releaseFirstMutation() {
        lock.withLock { firstMutationReleasedStorage = true }
    }

    func execute(
        sftpCommand: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> String {
        _ = authorization
        guard sftpCommand.hasPrefix("mkdir ") else { return "" }
        let mutationIndex = lock.withLock { () -> Int in
            mutationCommandsStorage.append(sftpCommand)
            return mutationCommandsStorage.count
        }
        guard mutationIndex == 1 else { return "" }
        while !lock.withLock({ firstMutationReleasedStorage }) {
            Thread.sleep(forTimeInterval: 0.002)
        }
        throw SFTPClientError.commandFailed("mutation acknowledgement unavailable")
    }
}

// MARK: - SFTP Client Tests

// Serialized: several tests park a task on a synchronous transfer and poll
// for it to start, so running them concurrently competes for the same
// cooperative threads those tasks need.
@Suite("SFTPClient", .serialized)
struct SFTPClientTests {

    private func makeClient(
        executor: any SFTPExecutor = MockSFTPExecutor(),
        profile: RemoteConnectionProfile? = nil,
        verifier: @escaping @Sendable () throws -> Void = {},
        cancellationRequested: @escaping @Sendable () -> Bool = { Task.isCancelled }
    ) -> SFTPClient {
        try! SFTPClient(
            executor: executor,
            authorization: makeAuthorization(
                profile: profile ?? makeProfile(),
                verifier: verifier
            ),
            cancellationRequested: cancellationRequested
        )
    }

    private func makeProfile() -> RemoteConnectionProfile {
        RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "deploy", port: 22
        )
    }

    private func makeAuthorization(
        profile: RemoteConnectionProfile? = nil,
        verifier: @escaping @Sendable () throws -> Void = {}
    ) -> SFTPConnectionAuthorization {
        try! buildAuthorization(profile: profile ?? makeProfile(), verifier: verifier)
    }

    private func buildAuthorization(
        profile: RemoteConnectionProfile,
        verifier: @escaping @Sendable () throws -> Void = {}
    ) throws -> SFTPConnectionAuthorization {
        let identity = SSHControlMasterIdentity(
            processID: 4_242,
            controlPath: profile.controlPath,
            supervisorID: UUID()
        )
        return try SFTPConnectionAuthorization(
            profile: profile,
            connectionLeaseID: UUID(),
            controlMasterIdentity: identity,
            controlSocketAttestation: SSHControlSocketAttestation(
                device: 1,
                inode: 2,
                peerProcessID: identity.processID
            ),
            verifier: verifier
        )
    }

    private func privateTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxy-sftp-client-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return url
    }

    // MARK: - List Directory

    @Test func listDirectoryParsesStandardOutput() throws {
        let executor = MockSFTPExecutor()
        executor.stubbedOutput = """
        drwxr-xr-x    3 deploy deploy     4096 Jan 15 10:30 .config
        -rw-r--r--    1 deploy deploy     1234 Feb 20 14:22 README.md
        -rwxr-xr-x    1 deploy deploy    56789 Mar 10 09:15 deploy.sh
        drwxr-xr-x    5 deploy deploy     4096 Jan 10 08:00 src
        """

        let client = makeClient(executor: executor)
        let entries = try client.listDirectory(path: "/home/deploy")

        #expect(entries.count == 4)

        let configDir = entries.first { $0.name == ".config" }
        #expect(configDir?.isDirectory == true)
        #expect(configDir?.permissions == "drwxr-xr-x")

        let readme = entries.first { $0.name == "README.md" }
        #expect(readme?.isDirectory == false)
        #expect(readme?.size == 1234)

        let script = entries.first { $0.name == "deploy.sh" }
        #expect(script?.size == 56789)
    }

    @Test func listDirectorySkipsEmptyLines() throws {
        let executor = MockSFTPExecutor()
        executor.stubbedOutput = """

        -rw-r--r--    1 user user     100 Jan 01 00:00 file.txt

        """

        let client = makeClient(executor: executor)
        let entries = try client.listDirectory(path: "/tmp")

        #expect(entries.count == 1)
        #expect(entries.first?.name == "file.txt")
    }

    @Test func listDirectorySkipsDotEntries() throws {
        let executor = MockSFTPExecutor()
        executor.stubbedOutput = """
        drwxr-xr-x    2 user user     4096 Jan 01 00:00 .
        drwxr-xr-x    3 user user     4096 Jan 01 00:00 ..
        -rw-r--r--    1 user user      100 Jan 01 00:00 file.txt
        """

        let client = makeClient(executor: executor)
        let entries = try client.listDirectory(path: "/home")

        #expect(entries.count == 1)
        #expect(entries.first?.name == "file.txt")
    }

    @Test func listDirectoryRejectsAnAmbiguousOrUnsafeListing() throws {
        let executor = MockSFTPExecutor()
        executor.stubbedOutput = """
        -rw-r--r-- 1 user user 1 Jan 01 00:00 ../target
        -rw-r--r-- 1 user user 1 Jan 01 00:00 subdir/target
        -rw-r--r-- 1 user user 1 Jan 01 00:00 /absolute
        -rw-r--r-- 1 user user 1 Jan 01 00:00 ..\\target
        -rw-r--r-- 1 user user 1 Jan 01 00:00 safe file.txt
        """

        #expect(throws: SFTPClientError.self) {
            try makeClient(executor: executor).listDirectory(path: "/home")
        }
    }

    @Test func structuredListingPreservesLeadingSpacesExactly() throws {
        let executor = StructuredListingSFTPExecutor(
            canonicalNames: ".\n..\n report.txt\nregular.txt\n",
            longListing: """
            drwxr-xr-x 2 501 20 64 Jan 01 00:00 .
            drwxr-xr-x 3 501 20 96 Jan 01 00:00 ..
            -rw-r--r-- 1 501 20 12 Jan 01 00:00  report.txt
            -rw-r--r-- 1 501 20 7 Jan 01 00:00 regular.txt
            """
        )

        let entries = try makeClient(executor: executor).listDirectory(path: "/remote")

        #expect(entries.map(\.name) == [" report.txt", "regular.txt"])
        #expect(entries.map(\.id) == ["/remote/ report.txt", "/remote/regular.txt"])
    }

    @Test func structuredListingRejectsNameMetadataMismatch() {
        let executor = StructuredListingSFTPExecutor(
            canonicalNames: "reviewed.txt\n",
            longListing: "-rw-r--r-- 1 501 20 12 Jan 01 00:00 replaced.txt\n"
        )

        #expect(throws: SFTPClientError.self) {
            try makeClient(executor: executor).listDirectory(path: "/remote")
        }
    }

    @Test func structuredListingAcceptsOpenSSHNameOnlySymbolicLinkMetadata() throws {
        let executor = StructuredListingSFTPExecutor(
            canonicalNames: "current\n",
            longListing: "lrwxr-xr-x 1 501 20 7 Jan 01 00:00 current\n"
        )

        let entry = try #require(
            makeClient(executor: executor).listDirectory(path: "/remote").first
        )

        #expect(entry.name == "current")
        #expect(entry.id == "/remote/current")
        #expect(entry.isSymbolicLink)
        #expect(entry.linkTarget == nil)
    }

    @Test func listDirectorySendsCorrectCommand() throws {
        let executor = MockSFTPExecutor()
        executor.stubbedOutput = ""

        let client = makeClient(executor: executor)
        _ = try client.listDirectory(path: "/var/log")

        #expect(executor.executedCommands.count == 1)
        let call = executor.executedCommands[0]
        #expect(call.sftpCommand == "ls -la '/var/log'")
        #expect(call.destination.value == "deploy@server.com")
        #expect(call.port == 22)
    }

    @Test func listDirectoryUsesControlPath() throws {
        let executor = MockSFTPExecutor()
        executor.stubbedOutput = ""

        let profile = makeProfile()
        let client = makeClient(executor: executor, profile: profile)
        _ = try client.listDirectory(path: "/tmp")

        let call = executor.executedCommands[0]
        #expect(call.controlPath == profile.controlPath)
    }

    @Test func listDirectoryThrowsOnError() {
        let executor = MockSFTPExecutor()
        executor.shouldThrow = true

        let client = makeClient(executor: executor)

        #expect(throws: SFTPClientError.self) {
            try client.listDirectory(path: "/tmp")
        }
    }

    // MARK: - Download

    @Test func downloadSendsGetCommand() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("app.log")
        let entry = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 app.log",
            basePath: "/var/log"
        ))
        executor.stubbedOutput =
            "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 app.log\n"

        try client.download(
            entry: entry,
            to: destination
        )

        let commands = executor.executedCommands.map(\.sftpCommand)
        #expect(commands.count == 5)
        #expect(commands[0] == "ls -la '/var/log'")
        let getCommand = try #require(commands.last(where: { $0.hasPrefix("get ") }))
        #expect(getCommand.hasPrefix("get '/var/log/app.log' "))
        #expect(getCommand.contains("/.cocxy-download-"))
        #expect(commands[1].contains("/cocxy-sftp-review-"))
        #expect(commands[2] == "ls -la '/var/log'")
        #expect(commands[4] == "ls -la '/var/log'")
        #expect(!commands.contains { $0.hasPrefix("rename ") || $0.hasPrefix("rm ") })
        #expect(try String(contentsOf: destination, encoding: .utf8) == "downloaded")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["app.log"])
    }

    @Test func downloadQuotesRemoteGlobMetacharactersAsLiteralPathBytes() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("report.txt")
        let entry = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 report[0].txt",
            basePath: "/remote"
        ))
        executor.stubbedOutput =
            "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 report[0].txt\n"

        try client.download(entry: entry, to: destination)

        let getCommand = try #require(executor.executedCommands.first {
            $0.sftpCommand.hasPrefix("get ")
        }?.sftpCommand)
        #expect(getCommand.hasPrefix("get '/remote/report[0].txt' "))
        #expect(try String(contentsOf: destination, encoding: .utf8) == "downloaded")
    }

    @Test func downloadFailureNeverMutatesRemoteNamespace() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("app.log")
        let entry = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 app.log",
            basePath: "/var/log"
        ))
        executor.outputProvider = { command in
            if command.hasPrefix("get ") {
                throw SFTPClientError.commandFailed("connection lost")
            }
            return "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 app.log\n"
        }

        #expect(throws: SFTPClientError.commandFailed("connection lost")) {
            try client.download(entry: entry, to: destination)
        }

        let commands = executor.executedCommands.map(\.sftpCommand)
        #expect(commands.count == 2)
        #expect(commands[0] == "ls -la '/var/log'")
        #expect(commands[1].hasPrefix("get '/var/log/app.log' "))
        #expect(!commands.contains { $0.hasPrefix("rename ") || $0.hasPrefix("rm ") })
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func downloadRejectsRemoteIdentityChangeBeforeLocalPublish() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("app.log")
        let entry = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 app.log",
            basePath: "/var/log"
        ))
        var listingCount = 0
        executor.outputProvider = { command in
            guard command == "ls -la '/var/log'" else { return "" }
            listingCount += 1
            let owner = listingCount == 1 ? "deploy" : "root"
            return "-rw-r--r-- 1 \(owner) deploy 10 Jan 15 10:30 app.log\n"
        }

        #expect(throws: SFTPClientError.remoteDestinationChanged) {
            try client.download(entry: entry, to: destination)
        }

        let commands = executor.executedCommands.map(\.sftpCommand)
        #expect(commands.count == 3)
        #expect(commands[0] == "ls -la '/var/log'")
        #expect(commands[1].hasPrefix("get '/var/log/app.log' "))
        #expect(commands[2] == "ls -la '/var/log'")
        #expect(!commands.contains { $0.hasPrefix("rename ") || $0.hasPrefix("rm ") })
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func downloadRejectsSubstitutedLocalStagingPath() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("app.log")
        let displaced = directory.appendingPathComponent("displaced-download")
        let entry = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 app.log",
            basePath: "/var/log"
        ))
        executor.stubbedOutput =
            "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 app.log\n"
        executor.beforeReturning = { command in
            guard command.hasPrefix("get "),
                  let payloadPath = quotedArguments(in: command).last,
                  payloadPath.contains(".cocxy-download-") else { return }
            try FileManager.default.moveItem(
                at: URL(fileURLWithPath: payloadPath),
                to: displaced
            )
            try Data("substitute".utf8).write(to: URL(fileURLWithPath: payloadPath))
        }

        #expect(throws: SFTPClientError.localPublishFailed) {
            try client.download(entry: entry, to: destination)
        }

        #expect(try String(contentsOf: displaced, encoding: .utf8) == "downloaded")
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func downloadRejectsSameMetadataWithChangedContent() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("app.log")
        let entry = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 app.log",
            basePath: "/var/log"
        ))
        executor.stubbedOutput =
            "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 app.log\n"
        var downloadCount = 0
        executor.downloadPayloadProvider = { _ in
            downloadCount += 1
            return Data((downloadCount == 1 ? "downloaded" : "substitute").utf8)
        }

        #expect(throws: SFTPClientError.remoteDestinationChanged) {
            try client.download(entry: entry, to: destination)
        }

        #expect(downloadCount == 2)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(!executor.executedCommands.contains {
            $0.sftpCommand.hasPrefix("rename ") || $0.sftpCommand.hasPrefix("rm ")
        })
    }

    @Test func downloadThrowsOnError() {
        let executor = MockSFTPExecutor()
        executor.shouldThrow = true
        let client = makeClient(executor: executor)
        let directory = try! privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let entry = try! #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 app.log",
            basePath: "/var/log"
        ))

        #expect(throws: SFTPClientError.self) {
            try client.download(
                entry: entry,
                to: directory.appendingPathComponent("app.log")
            )
        }
        #expect((try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.isEmpty == true)
    }

    @Test func downloadNeverOverwritesDestinationCreatedDuringTransfer() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("app.log")
        let entry = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 app.log",
            basePath: "/var/log"
        ))
        executor.beforeReturning = { command in
            if command.hasPrefix("get ") {
                try Data("local-winner".utf8).write(to: destination)
            }
        }
        executor.stubbedOutput =
            "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 app.log\n"

        #expect(throws: SFTPClientError.destinationExists) {
            try client.download(entry: entry, to: destination)
        }

        #expect(try String(contentsOf: destination, encoding: .utf8) == "local-winner")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["app.log"])
    }

    @Test func downloadReportsPostPublishCleanupFailureWithoutHidingSavedFile() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("app.log")
        let entry = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 app.log",
            basePath: "/var/log"
        ))
        executor.stubbedOutput =
            "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 app.log\n"
        var payloadURL: URL?
        var listingCount = 0
        executor.beforeReturning = { command in
            if command.hasPrefix("get "),
               let payloadPath = quotedArguments(in: command).last,
               payloadPath.contains(".cocxy-download-") {
                payloadURL = URL(fileURLWithPath: payloadPath)
            } else if command == "ls -la '/var/log'" {
                listingCount += 1
                if listingCount == 3, let payloadURL {
                    try Data("block cleanup".utf8).write(
                        to: payloadURL.deletingLastPathComponent()
                            .appendingPathComponent("retained")
                    )
                }
            }
        }

        let outcome = try client.download(entry: entry, to: destination)

        guard case .publishedWithIssues(let state) = outcome else {
            Issue.record("Expected a published download with a cleanup issue")
            return
        }
        #expect(state.destinationURL == destination)
        #expect(state.stagingDirectoryURL != nil)
        #expect(state.issues.contains(.stagingCleanupUnconfirmed))
        #expect(try String(contentsOf: destination, encoding: .utf8) == "downloaded")
    }

    @Test func downloadRejectsGroupWritableParentBeforeExecuting() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o770],
            ofItemAtPath: directory.path
        )

        #expect(throws: SFTPClientError.unsafeLocalDestination) {
            try client.download(
                entry: RemoteFileEntry(
                    id: "/var/log/app.log",
                    name: "app.log",
                    isDirectory: false,
                    size: 10,
                    modifiedDate: .distantPast,
                    permissions: "-rw-r--r--"
                ),
                to: directory.appendingPathComponent("app.log")
            )
        }
        #expect(executor.executedCommands.isEmpty)
    }

    // MARK: - Upload

    @Test func uploadSendsPutCommand() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("config.yaml")
        try Data("enabled: true".utf8).write(to: localFile)

        var stagedSourcePath: String?
        var stagedContents: String?
        executor.beforeReturning = { command in
            guard command.hasPrefix("put "),
                  let path = firstQuotedArgument(in: command) else { return }
            stagedSourcePath = path
            stagedContents = try String(contentsOfFile: path, encoding: .utf8)
        }

        try client.upload(
            localPath: localFile.path,
            remotePath: "/etc/app/config.yaml"
        )

        let commands = executor.executedCommands.map(\.sftpCommand)
        let putCommand = try #require(commands.first)
        #expect(putCommand.hasPrefix("put '"))
        #expect(putCommand.contains("/payload' '/etc/app/.cocxy-upload-"))
        #expect(!putCommand.contains(localFile.path))
        #expect(commands.count == 2)
        #expect(commands[1].hasPrefix("rename -l '/etc/app/.cocxy-upload-"))
        #expect(commands[1].hasSuffix(" '/etc/app/config.yaml'"))
        #expect(stagedContents == "enabled: true")
        #expect(stagedSourcePath.map { !FileManager.default.fileExists(atPath: $0) } == true)
    }

    @Test func uploadCleanupWarningRetainsTheLocalSnapshotDirectory() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("config.yaml")
        try Data("enabled: true".utf8).write(to: localFile)
        var retainedSnapshotDirectory: URL?
        executor.beforeReturning = { command in
            guard command.hasPrefix("put "),
                  let sourcePath = firstQuotedArgument(in: command) else { return }
            let snapshotDirectory = URL(fileURLWithPath: sourcePath)
                .deletingLastPathComponent()
            try Data("retain recovery directory".utf8).write(
                to: snapshotDirectory.appendingPathComponent("retained")
            )
            retainedSnapshotDirectory = snapshotDirectory
        }

        let outcome = try client.upload(
            localPath: localFile.path,
            remotePath: "/etc/app/config.yaml"
        )

        guard case .committedWithIssues(let state) = outcome else {
            Issue.record("Expected a committed upload with a local cleanup issue")
            return
        }
        let recoveryDirectory = try #require(state.localSnapshotURL)
        defer { try? FileManager.default.removeItem(at: recoveryDirectory) }
        #expect(recoveryDirectory == retainedSnapshotDirectory)
        #expect(state.issues.contains(.localSnapshotCleanupUnconfirmed))
        #expect(FileManager.default.fileExists(atPath: recoveryDirectory.path))
        #expect(!FileManager.default.fileExists(
            atPath: recoveryDirectory.appendingPathComponent("payload").path
        ))
    }

    @Test func uploadUsesPinnedSnapshotWhenOriginalPathIsReplaced() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("config.yaml")
        let replacement = directory.appendingPathComponent("replacement.yaml")
        try Data("reviewed".utf8).write(to: localFile)
        try Data("replacement".utf8).write(to: replacement)
        var uploadedContents: String?

        executor.beforeReturning = { command in
            guard command.hasPrefix("put ") else { return }
            try FileManager.default.removeItem(at: localFile)
            try FileManager.default.moveItem(at: replacement, to: localFile)
            let stagedPath = try #require(firstQuotedArgument(in: command))
            uploadedContents = try String(contentsOfFile: stagedPath, encoding: .utf8)
        }

        try client.upload(localPath: localFile.path, remotePath: "/tmp/config.yaml")

        #expect(uploadedContents == "reviewed")
        #expect(try String(contentsOf: localFile, encoding: .utf8) == "replacement")
    }

    @Test func cancelledUploadAttemptsStagingCleanupOutsideTaskCancellation() async throws {
        let executor = RecoveringUploadCancellationSFTPExecutor()
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("config.yaml")
        try Data("reviewed".utf8).write(to: localFile)
        let upload = Task.detached {
            try client.upload(
                localPath: localFile.path,
                remotePath: "/tmp/config.yaml"
            )
        }
        for _ in 0..<200 where !executor.uploadStarted {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(executor.uploadStarted)

        upload.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await upload.value
        }
        let cleanup = try #require(executor.recoveryCommands.first)
        #expect(cleanup.hasPrefix("rm '/tmp/.cocxy-upload-"))
    }

    @Test func failedStagingCleanupReturnsRecoverableNotCommittedOutcome() throws {
        let executor = MockSFTPExecutor()
        executor.outputProvider = { command in
            if command.hasPrefix("put ") {
                throw SFTPClientError.commandFailed("transfer interrupted")
            }
            if command.hasPrefix("rm '/tmp/.cocxy-upload-") {
                throw SFTPClientError.commandFailed("cleanup unavailable")
            }
            return ""
        }
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("config.yaml")
        try Data("reviewed".utf8).write(to: localFile)

        let outcome = try client.upload(
            localPath: localFile.path,
            remotePath: "/tmp/config.yaml"
        )

        guard case .notCommittedWithIssues(let state) = outcome else {
            Issue.record("Expected a recoverable not-committed upload outcome")
            return
        }
        #expect(state.destinationPath == "/tmp/config.yaml")
        #expect(state.stagedPayloadPath?.hasPrefix("/tmp/.cocxy-upload-") == true)
        #expect(state.issues.contains(.remoteStagingRemovalUnconfirmed))
    }

    @Test func uploadRejectsSubstitutedSnapshotPathAfterTransfer() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("config.yaml")
        let displaced = directory.appendingPathComponent("displaced-upload")
        try Data("reviewed".utf8).write(to: localFile)
        executor.beforeReturning = { command in
            guard command.hasPrefix("put "),
                  let payloadPath = firstQuotedArgument(in: command) else { return }
            try FileManager.default.moveItem(
                at: URL(fileURLWithPath: payloadPath),
                to: displaced
            )
            try Data("attacker".utf8).write(to: URL(fileURLWithPath: payloadPath))
        }

        #expect(throws: SFTPClientError.unsafeLocalSource) {
            try client.upload(localPath: localFile.path, remotePath: "/tmp/config.yaml")
        }

        let commands = executor.executedCommands.map(\.sftpCommand)
        #expect(commands.count == 2)
        #expect(commands[0].hasPrefix("put "))
        #expect(commands[1].hasPrefix("rm '/tmp/.cocxy-upload-"))
        #expect(try String(contentsOf: displaced, encoding: .utf8) == "reviewed")
    }

    @Test func uploadRejectsPathReplacedAfterUserReview() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("config.yaml")
        let replacement = directory.appendingPathComponent("replacement.yaml")
        try Data("reviewed".utf8).write(to: localFile)
        try Data("replacement".utf8).write(to: replacement)
        let reviewedIdentity = try SFTPLocalFileIdentity.capture(path: localFile.path)
        try FileManager.default.removeItem(at: localFile)
        try FileManager.default.moveItem(at: replacement, to: localFile)

        #expect(throws: SFTPClientError.unsafeLocalSource) {
            try client.upload(
                localPath: localFile.path,
                remotePath: "/tmp/config.yaml",
                expectedLocalIdentity: reviewedIdentity
            )
        }

        #expect(executor.executedCommands.isEmpty)
    }

    @Test func uploadRejectsSymbolicLinkSourceBeforeExecuting() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("target.txt")
        let link = directory.appendingPathComponent("link.txt")
        try Data("secret".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(throws: SFTPClientError.unsafeLocalSource) {
            try client.upload(localPath: link.path, remotePath: "/tmp/link.txt")
        }
        #expect(executor.executedCommands.isEmpty)
    }

    @Test func createUploadPreservesAmbiguityAfterPromotionFailure() throws {
        let executor = MockSFTPExecutor()
        executor.outputProvider = { command in
            if command.hasPrefix("rename -l "),
               command.hasSuffix(" '/etc/app/config.yaml'") {
                throw SFTPClientError.commandFailed("destination exists")
            }
            return ""
        }
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("config.yaml")
        try Data("reviewed".utf8).write(to: localFile)

        let outcome = try client.upload(
            localPath: localFile.path,
            remotePath: "/etc/app/config.yaml",
            destinationPolicy: .create
        )

        let commands = executor.executedCommands.map(\.sftpCommand)
        #expect(commands.count == 2)
        #expect(commands[0].hasPrefix("put "))
        #expect(commands[1].hasPrefix("rename -l "))
        guard case .commitIndeterminate(let state) = outcome else {
            Issue.record("Expected an indeterminate create outcome")
            return
        }
        #expect(state.destinationPath == "/etc/app/config.yaml")
        #expect(state.stagedPayloadPath?.hasPrefix("/etc/app/.cocxy-upload-") == true)
        #expect(state.issues.contains(.commitStatusUnconfirmed))
    }

    @Test func overwriteUploadPreservesAmbiguityAfterPromotionFailure() throws {
        let executor = MockSFTPExecutor()
        executor.outputProvider = { command in
            if command.hasPrefix("rename ") {
                throw SFTPClientError.commandFailed("connection closed after request")
            }
            return ""
        }
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("config.yaml")
        try Data("reviewed".utf8).write(to: localFile)

        let outcome = try client.upload(
            localPath: localFile.path,
            remotePath: "/etc/app/config.yaml",
            destinationPolicy: .overwrite
        )

        guard case .commitIndeterminate(let state) = outcome else {
            Issue.record("Expected an indeterminate overwrite outcome")
            return
        }
        #expect(state.destinationPath == "/etc/app/config.yaml")
        #expect(state.stagedPayloadPath?.hasPrefix("/etc/app/.cocxy-upload-") == true)
    }

    @Test func replaceUploadRejectsDestinationChangedAfterReview() throws {
        let executor = MockSFTPExecutor()
        var quarantinePath: String?
        executor.beforeReturning = { command in
            let arguments = quotedArguments(in: command)
            if command.hasPrefix("rename -l '/etc/app/config.yaml' ") {
                quarantinePath = arguments.last
            }
        }
        executor.outputProvider = { command in
            guard command == "ls -la '/etc/app'" else { return "" }
            guard let quarantinePath else {
                return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 config.yaml\n"
            }
            return "-rw------- 1 deploy deploy 99 Jan 15 10:31 "
                + URL(fileURLWithPath: quarantinePath).lastPathComponent + "\n"
        }
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("config.yaml")
        try Data("reviewed".utf8).write(to: localFile)
        let expected = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 config.yaml",
            basePath: "/etc/app"
        ))
        let review = try client.prepareReview(entry: expected)

        #expect(throws: SFTPClientError.remoteDestinationChanged) {
            try client.upload(
                localPath: localFile.path,
                remotePath: "/etc/app/config.yaml",
                destinationPolicy: .replace(review)
            )
        }

        let commands = executor.executedCommands.map(\.sftpCommand)
        #expect(commands.contains { $0.hasPrefix("get '/etc/app/config.yaml' ") })
        #expect(commands.contains { $0.hasPrefix("put ") })
        #expect(commands.contains { $0.hasPrefix("rename -l '/etc/app/config.yaml' ") })
        #expect(commands.contains {
            $0.hasPrefix("rename -l '/etc/app/.cocxy-review-")
                && $0.hasSuffix(" '/etc/app/config.yaml'")
        })
        #expect(commands.contains { $0.hasPrefix("rm '/etc/app/.cocxy-upload-") })
        #expect(!commands.contains {
            $0.hasPrefix("rename -l '/etc/app/.cocxy-upload-")
                && $0.hasSuffix(" '/etc/app/config.yaml'")
        })
    }

    @Test func replaceUploadRejectsSameMetadataWithChangedContent() throws {
        let executor = MockSFTPExecutor()
        var quarantinePath: String?
        executor.beforeReturning = { command in
            if command.hasPrefix("rename -l '/etc/app/config.yaml' ") {
                quarantinePath = quotedArguments(in: command).last
            }
        }
        executor.outputProvider = { command in
            guard command == "ls -la '/etc/app'" else { return "" }
            guard let quarantinePath else {
                return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 config.yaml\n"
            }
            return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 "
                + URL(fileURLWithPath: quarantinePath).lastPathComponent + "\n"
        }
        executor.downloadPayloadProvider = { command in
            command.hasPrefix("get '/etc/app/config.yaml' ")
                ? Data(repeating: 0x41, count: 12)
                : Data(repeating: 0x42, count: 12)
        }
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("config.yaml")
        try Data("replacement".utf8).write(to: localFile)
        let expected = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 config.yaml",
            basePath: "/etc/app"
        ))
        let review = try client.prepareReview(entry: expected)

        #expect(throws: SFTPClientError.remoteDestinationChanged) {
            try client.upload(
                localPath: localFile.path,
                remotePath: "/etc/app/config.yaml",
                destinationPolicy: .replace(review)
            )
        }

        let commands = executor.executedCommands.map(\.sftpCommand)
        #expect(commands.contains {
            $0.hasPrefix("get '/etc/app/.cocxy-review-")
        })
        #expect(commands.contains {
            $0.hasPrefix("rename -l '/etc/app/.cocxy-review-")
                && $0.hasSuffix(" '/etc/app/config.yaml'")
        })
        #expect(!commands.contains {
            $0.hasPrefix("rename -l '/etc/app/.cocxy-upload-")
                && $0.hasSuffix(" '/etc/app/config.yaml'")
        })
    }

    @Test func replaceUploadPublishesOnlyAfterQuarantinedIdentityMatches() throws {
        let listing = "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 config.yaml"
        let executor = MockSFTPExecutor()
        var quarantinePath: String?
        executor.beforeReturning = { command in
            let arguments = quotedArguments(in: command)
            if command.hasPrefix("rename -l '/etc/app/config.yaml' ") {
                quarantinePath = arguments.last
            }
        }
        executor.outputProvider = { command in
            guard command == "ls -la '/etc/app'" else { return "" }
            guard let quarantinePath else { return listing + "\n" }
            return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 "
                + URL(fileURLWithPath: quarantinePath).lastPathComponent + "\n"
        }
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("config.yaml")
        try Data("reviewed".utf8).write(to: localFile)
        let expected = try #require(RemoteFileEntry.parse(
            from: listing,
            basePath: "/etc/app"
        ))
        let review = try client.prepareReview(entry: expected)

        let outcome = try client.upload(
            localPath: localFile.path,
            remotePath: "/etc/app/config.yaml",
            destinationPolicy: .replace(review)
        )

        let commands = executor.executedCommands.map(\.sftpCommand)
        let quarantineRename = try #require(commands.firstIndex {
            $0.hasPrefix("rename -l '/etc/app/config.yaml' ")
        })
        let promotion = try #require(commands.firstIndex {
            $0.hasPrefix("rename -l '/etc/app/.cocxy-upload-")
                && $0.hasSuffix(" '/etc/app/config.yaml'")
        })
        #expect(quarantineRename < promotion)
        #expect(commands[..<promotion].contains {
            $0.hasPrefix("get '/etc/app/.cocxy-review-")
        })
        #expect(commands.contains { $0.hasPrefix("rm '/etc/app/.cocxy-review-") })
        #expect(outcome == .completed)
    }

    @Test func replaceUploadRetainsBackupChangedAfterPromotion() throws {
        let executor = MockSFTPExecutor()
        var quarantinePath: String?
        var quarantineVerificationCount = 0
        executor.beforeReturning = { command in
            let arguments = quotedArguments(in: command)
            if command.hasPrefix("rename -l '/etc/app/config.yaml' ") {
                quarantinePath = arguments.last
            }
        }
        executor.outputProvider = { command in
            guard command == "ls -la '/etc/app'" else { return "" }
            guard let quarantinePath else {
                return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 config.yaml\n"
            }
            quarantineVerificationCount += 1
            let size = quarantineVerificationCount == 1 ? 12 : 99
            return "-rw-r--r-- 1 deploy deploy \(size) Jan 15 10:30 "
                + URL(fileURLWithPath: quarantinePath).lastPathComponent + "\n"
        }
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("config.yaml")
        try Data("reviewed".utf8).write(to: localFile)
        let expected = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 config.yaml",
            basePath: "/etc/app"
        ))
        let review = try client.prepareReview(entry: expected)

        let outcome = try client.upload(
            localPath: localFile.path,
            remotePath: "/etc/app/config.yaml",
            destinationPolicy: .replace(review)
        )

        let commands = executor.executedCommands.map(\.sftpCommand)
        #expect(!commands.contains { $0.hasPrefix("rm '/etc/app/.cocxy-review-") })
        #expect(outcome == .committedWithIssues(SFTPUploadRecoveryState(
            destinationPath: "/etc/app/config.yaml",
            stagedPayloadPath: nil,
            remoteBackupPath: quarantinePath,
            issues: [.remoteBackupIdentityChanged]
        )))
    }

    @Test func replaceUploadReportsUnconfirmedBackupRemovalAsCommitted() throws {
        let executor = MockSFTPExecutor()
        var quarantinePath: String?
        executor.beforeReturning = { command in
            if command.hasPrefix("rename -l '/etc/app/config.yaml' ") {
                quarantinePath = quotedArguments(in: command).last
            }
        }
        executor.outputProvider = { command in
            if command.hasPrefix("rm '/etc/app/.cocxy-review-") {
                throw SFTPClientError.commandFailed("cleanup unavailable")
            }
            guard command == "ls -la '/etc/app'" else { return "" }
            guard let quarantinePath else {
                return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 config.yaml\n"
            }
            return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 "
                + URL(fileURLWithPath: quarantinePath).lastPathComponent + "\n"
        }
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("config.yaml")
        try Data("replacement".utf8).write(to: localFile)
        let expected = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 config.yaml",
            basePath: "/etc/app"
        ))
        let review = try client.prepareReview(entry: expected)

        let outcome = try client.upload(
            localPath: localFile.path,
            remotePath: "/etc/app/config.yaml",
            destinationPolicy: .replace(review)
        )

        #expect(outcome == .committedWithIssues(SFTPUploadRecoveryState(
            destinationPath: "/etc/app/config.yaml",
            stagedPayloadPath: nil,
            remoteBackupPath: quarantinePath,
            issues: [.remoteBackupRemovalUnconfirmed]
        )))
        #expect(executor.executedCommands.last?.sftpCommand.hasPrefix(
            "rm '/etc/app/.cocxy-review-"
        ) == true)
    }

    @Test func replaceUploadReturnsIndeterminateOutcomeAfterAmbiguousPromotion() throws {
        let executor = MockSFTPExecutor()
        var quarantinePath: String?
        var stagingPath: String?
        var promotionAttempted = false
        executor.beforeReturning = { command in
            let arguments = quotedArguments(in: command)
            if command.hasPrefix("put ") {
                stagingPath = arguments.last
            } else if command.hasPrefix("rename -l '/etc/app/config.yaml' ") {
                quarantinePath = arguments.last
            }
        }
        executor.outputProvider = { command in
            let arguments = quotedArguments(in: command)
            if command.hasPrefix("rename -l "),
               arguments.first == stagingPath,
               arguments.last == "/etc/app/config.yaml" {
                promotionAttempted = true
                throw SFTPClientError.commandFailed("connection closed after request")
            }
            guard command == "ls -la '/etc/app'" else { return "" }
            guard let quarantinePath else {
                return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 config.yaml\n"
            }
            let backupName = URL(fileURLWithPath: quarantinePath).lastPathComponent
            if promotionAttempted {
                return """
                -rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 \(backupName)
                -rw------- 1 deploy deploy 11 Jan 15 10:31 config.yaml
                """
            }
            return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 \(backupName)\n"
        }
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("config.yaml")
        try Data("replacement".utf8).write(to: localFile)
        let expected = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 config.yaml",
            basePath: "/etc/app"
        ))
        let review = try client.prepareReview(entry: expected)

        let outcome = try client.upload(
            localPath: localFile.path,
            remotePath: "/etc/app/config.yaml",
            destinationPolicy: .replace(review)
        )

        #expect(outcome == .commitIndeterminate(SFTPUploadRecoveryState(
            destinationPath: "/etc/app/config.yaml",
            stagedPayloadPath: stagingPath,
            remoteBackupPath: quarantinePath,
            issues: [.commitStatusUnconfirmed]
        )))
        let commands = executor.executedCommands.map(\.sftpCommand)
        #expect(commands.contains {
            $0.hasPrefix("rename -l '/etc/app/.cocxy-upload-")
                && $0.hasSuffix(" '/etc/app/config.yaml'")
        })
        #expect(!commands.contains { $0.hasPrefix("rm ") })
    }

    @Test func replaceUploadRejectsReviewedSymbolicLinkWithoutExecuting() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let directory = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localFile = directory.appendingPathComponent("config.yaml")
        try Data("reviewed".utf8).write(to: localFile)
        let expected = try #require(RemoteFileEntry.parse(
            from: "lrwxr-xr-x 1 deploy deploy 12 Jan 15 10:30 config.yaml -> target",
            basePath: "/etc/app"
        ))

        #expect(throws: SFTPClientError.unsafeRemoteDestination) {
            try client.prepareReview(entry: expected)
        }

        #expect(executor.executedCommands.isEmpty)
    }

    // MARK: - Mkdir

    @Test func mkdirSendsMkdirCommand() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)

        try client.mkdir(path: "/var/app/logs")

        let call = executor.executedCommands[0]
        #expect(call.sftpCommand == "mkdir '/var/app/logs'")
    }

    @Test func mkdirFailureReturnsIndeterminateCommitState() throws {
        let executor = MockSFTPExecutor()
        executor.shouldThrow = true
        let client = makeClient(executor: executor)

        let outcome = try client.mkdir(path: "/var/app/logs")

        #expect(outcome == .commitIndeterminate(SFTPRemoteMutationRecoveryState(
            targetPath: "/var/app/logs",
            recoveryPath: nil,
            issues: [.commitStatusUnconfirmed]
        )))
    }

    @Test func revokedAuthorizationBeforeMkdirIsNotReportedAsIndeterminate() throws {
        let executor = MockSFTPExecutor()
        let authorization = makeAuthorization()
        let client = try SFTPClient(executor: executor, authorization: authorization)
        authorization.revoke()

        #expect(throws: SFTPClientError.notConnected) {
            _ = try client.mkdir(path: "/tmp/new-dir")
        }
        #expect(executor.executedCommands.isEmpty)
    }

    // MARK: - Remove

    @Test func removeQuarantinesReviewedFileBeforeDeleting() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let entry = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 old-file.txt",
            basePath: "/tmp"
        ))
        var quarantinePath: String?
        executor.beforeReturning = { command in
            if command.hasPrefix("rename -l '/tmp/old-file.txt' ") {
                quarantinePath = quotedArguments(in: command).last
            }
        }
        executor.outputProvider = { command in
            guard command == "ls -la '/tmp'" else { return "" }
            guard let quarantinePath else {
                return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 old-file.txt\n"
            }
            return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 "
                + URL(fileURLWithPath: quarantinePath).lastPathComponent + "\n"
        }

        try client.remove(entry: entry)

        let commands = executor.executedCommands.map(\.sftpCommand)
        let quarantineRename = try #require(commands.firstIndex {
            $0.hasPrefix("rename -l '/tmp/old-file.txt' ")
        })
        let delete = try #require(commands.firstIndex {
            $0.hasPrefix("rm '/tmp/.cocxy-review-")
        })
        #expect(commands.contains { $0.hasPrefix("get '/tmp/old-file.txt' ") })
        #expect(commands[quarantineRename..<delete].contains {
            $0.hasPrefix("get '/tmp/.cocxy-review-")
        })
        #expect(quarantineRename < delete)
    }

    @Test func removeDirectoryQuarantinesReviewedDirectoryBeforeDeleting() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let entry = try #require(RemoteFileEntry.parse(
            from: "drwxr-xr-x 2 deploy deploy 64 Jan 15 10:30 old-directory",
            basePath: "/tmp"
        ))
        var quarantinePath: String?
        executor.beforeReturning = { command in
            if command.hasPrefix("rename -l '/tmp/old-directory' ") {
                quarantinePath = quotedArguments(in: command).last
            }
        }
        executor.outputProvider = { command in
            guard command == "ls -la '/tmp'" else { return "" }
            guard let quarantinePath else {
                return "drwxr-xr-x 2 deploy deploy 64 Jan 15 10:30 old-directory\n"
            }
            return "drwxr-xr-x 2 deploy deploy 64 Jan 15 10:30 "
                + URL(fileURLWithPath: quarantinePath).lastPathComponent + "\n"
        }

        try client.remove(entry: entry)

        #expect(executor.executedCommands.last?.sftpCommand.hasPrefix(
            "rmdir '/tmp/.cocxy-review-"
        ) == true)
    }

    @Test func removePreservesCommittedResultWhenDeleteAckIsLost() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let entry = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 old-file.txt",
            basePath: "/tmp"
        ))
        var quarantinePath: String?
        var deletionAttempted = false
        executor.beforeReturning = { command in
            if command.hasPrefix("rename -l '/tmp/old-file.txt' ") {
                quarantinePath = quotedArguments(in: command).last
            } else if command.hasPrefix("rm '/tmp/.cocxy-review-") {
                deletionAttempted = true
            }
        }
        executor.outputProvider = { command in
            if command.hasPrefix("rm '/tmp/.cocxy-review-") {
                throw SFTPClientError.commandFailed("connection closed after request")
            }
            guard command == "ls -la '/tmp'" else { return "" }
            guard let quarantinePath else {
                return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 old-file.txt\n"
            }
            guard !deletionAttempted else { return "" }
            return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 "
                + URL(fileURLWithPath: quarantinePath).lastPathComponent + "\n"
        }

        let outcome = try client.remove(entry: entry)

        #expect(outcome == .committedWithIssues(SFTPRemoteMutationRecoveryState(
            targetPath: "/tmp/old-file.txt",
            recoveryPath: nil,
            issues: [.commitStatusUnconfirmed]
        )))
    }

    @Test func removeReportsRecoveryPathWhenRestorationCannotBeConfirmed() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let entry = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 old-file.txt",
            basePath: "/tmp"
        ))
        var quarantinePath: String?
        executor.beforeReturning = { command in
            if command.hasPrefix("rename -l '/tmp/old-file.txt' ") {
                quarantinePath = quotedArguments(in: command).last
            }
        }
        executor.outputProvider = { command in
            if command.hasPrefix("rm '/tmp/.cocxy-review-")
                || command.hasSuffix(" '/tmp/old-file.txt'") {
                throw SFTPClientError.commandFailed("connection unavailable")
            }
            guard command == "ls -la '/tmp'" else { return "" }
            guard let quarantinePath else {
                return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 old-file.txt\n"
            }
            return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 "
                + URL(fileURLWithPath: quarantinePath).lastPathComponent + "\n"
        }

        let outcome = try client.remove(entry: entry)

        guard case .notCommittedWithIssues(let state) = outcome else {
            Issue.record("Expected a recoverable not-committed removal")
            return
        }
        #expect(state.targetPath == "/tmp/old-file.txt")
        #expect(state.recoveryPath == quarantinePath)
        #expect(state.issues.contains(.restorationUnconfirmed))
    }

    @Test func cancelledRemovalUsesBoundedRecoveryForRestorationAndClassification() async throws {
        let executor = RecoveringRemovalCancellationSFTPExecutor()
        let client = makeClient(executor: executor)
        let entry = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 old-file.txt",
            basePath: "/tmp"
        ))
        let review = try client.prepareReview(entry: entry)
        let removal = Task.detached {
            try client.remove(reviewedEntry: review)
        }
        for _ in 0..<200 where !executor.deleteStarted {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(executor.deleteStarted)

        removal.cancel()
        let outcome = try await removal.value

        let quarantinePath = try #require(executor.quarantinePath)
        #expect(outcome == .notCommittedWithIssues(SFTPRemoteMutationRecoveryState(
            targetPath: "/tmp/old-file.txt",
            recoveryPath: quarantinePath,
            issues: [.restorationUnconfirmed]
        )))
        #expect(executor.restorationAttempted)
        #expect(executor.recoveryCommands.contains("recovery-list /tmp"))
        #expect(executor.recoveryCommands.contains {
            $0.hasPrefix("get '/tmp/.cocxy-review-")
        })
    }

    @Test func revokedConnectionStopsRemovalRecovery() async throws {
        let executor = RecoveringRemovalCancellationSFTPExecutor()
        let authorization = makeAuthorization()
        let client = try SFTPClient(executor: executor, authorization: authorization)
        let entry = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 old-file.txt",
            basePath: "/tmp"
        ))
        let review = try client.prepareReview(entry: entry)
        let removal = Task.detached {
            try client.remove(reviewedEntry: review)
        }
        for _ in 0..<200 where !executor.deleteStarted {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(executor.deleteStarted)

        authorization.revoke()
        let outcome = try await removal.value

        #expect(outcome == .commitIndeterminate(SFTPRemoteMutationRecoveryState(
            targetPath: "/tmp/old-file.txt",
            recoveryPath: executor.quarantinePath,
            issues: [.commitStatusUnconfirmed]
        )))
        #expect(!executor.restorationAttempted)
        #expect(executor.recoveryCommands.isEmpty)
    }

    // MARK: - Path Sanitization

    @Test func sanitizePathWrapsInSingleQuotes() throws {
        let result = try SFTPClient.sanitizePath("/var/log/app.log")
        #expect(result == "'/var/log/app.log'")
    }

    @Test func sanitizePathEscapesSingleQuotesInPath() throws {
        let result = try SFTPClient.sanitizePath("/tmp/it's a file")
        #expect(result == "'/tmp/it'\\''s a file'")
    }

    @Test func sanitizePathHandlesSpacesInPath() throws {
        let result = try SFTPClient.sanitizePath("/home/user/my documents/file.txt")
        #expect(result == "'/home/user/my documents/file.txt'")
    }

    @Test func sanitizePathHandlesSpecialCharacters() throws {
        let result = try SFTPClient.sanitizePath("/tmp/file;rm -rf /")
        #expect(result == "'/tmp/file;rm -rf /'")
    }

    @Test func rejectsControlCharactersBeforeExecuting() {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)

        #expect(throws: SFTPClientError.invalidPath) {
            try client.remove(path: "/tmp/safe\n!touch /tmp/unsafe")
        }
        #expect(executor.executedCommands.isEmpty)
    }

    @Test func rejectsOptionLikePathsBeforeExecuting() {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)

        #expect(throws: SFTPClientError.invalidPath) {
            try client.remove(path: "-R")
        }
        #expect(executor.executedCommands.isEmpty)
    }

    @Test func rejectsOptionLikeDestinationsBeforeExecuting() {
        let executor = MockSFTPExecutor()
        let profile = RemoteConnectionProfile(
            name: "unsafe",
            host: "-oProxyCommand=/bin/true"
        )

        #expect(throws: SFTPClientError.invalidDestination) {
            _ = try buildAuthorization(profile: profile)
        }
        #expect(executor.executedCommands.isEmpty)
    }

    @Test func rejectsOversizedEscapedCommandsBeforeExecuting() {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let quoteHeavyPath = "/tmp/" + String(repeating: "'", count: 600)
        let directory = try! privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: SFTPClientError.invalidCommand) {
            try client.download(
                remotePath: quoteHeavyPath,
                to: directory.appendingPathComponent("output")
            )
        }
        #expect(executor.executedCommands.isEmpty)
    }

    @Test func rejectsInvalidPortsBeforeExecuting() {
        let executor = MockSFTPExecutor()
        let profile = RemoteConnectionProfile(name: "unsafe", host: "example.com", port: 70_000)

        #expect(throws: SFTPClientError.invalidPort) {
            _ = try buildAuthorization(profile: profile)
        }
        #expect(executor.executedCommands.isEmpty)
    }

    @Test func rejectsControlMasterFromAnotherProfile() {
        let profile = makeProfile()
        let foreignIdentity = SSHControlMasterIdentity(
            processID: 4_242,
            controlPath: "/tmp/cocxy-foreign.sock",
            supervisorID: UUID()
        )

        #expect(throws: SFTPClientError.notConnected) {
            _ = try SFTPConnectionAuthorization(
                profile: profile,
                connectionLeaseID: UUID(),
                controlMasterIdentity: foreignIdentity,
                controlSocketAttestation: SSHControlSocketAttestation(
                    device: 1,
                    inode: 2,
                    peerProcessID: foreignIdentity.processID
                ),
                verifier: {}
            )
        }
    }

    @Test func revokedAuthorizationPreventsAnyCommandExecution() throws {
        let executor = MockSFTPExecutor()
        let authorization = makeAuthorization()
        let client = try SFTPClient(executor: executor, authorization: authorization)
        authorization.revoke()

        #expect(throws: SFTPClientError.notConnected) {
            _ = try client.listDirectory(path: ".")
        }
        #expect(executor.executedCommands.isEmpty)
    }

    @Test func remoteDigestHashingObservesCancellationBetweenChunks() throws {
        let executor = MockSFTPExecutor()
        let byteCount = 128 * 1_024
        executor.stubbedOutput =
            "-rw-r--r-- 1 deploy deploy \(byteCount) Jan 15 10:30 archive.bin\n"
        executor.downloadPayloadProvider = { _ in
            Data(repeating: 0x41, count: byteCount)
        }
        let cancellationChecks = LockedBox(0)
        let client = makeClient(
            executor: executor,
            cancellationRequested: {
                cancellationChecks.withValue { count in
                    count += 1
                    return count > 1
                }
            }
        )
        let entry = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy \(byteCount) Jan 15 10:30 archive.bin",
            basePath: "/remote"
        ))

        #expect(throws: CancellationError.self) {
            _ = try client.prepareReview(entry: entry)
        }
        #expect(cancellationChecks.withValue { $0 } == 2)
        #expect(executor.executedCommands.contains {
            $0.sftpCommand.hasPrefix("get '/remote/archive.bin' ")
        })
    }

    @Test func remoteGlobSanitizerQuotesGlobsAndDoublesLiteralBackslashes() throws {
        let sanitized = try SFTPClient.sanitizeRemoteGlobPath(
            "/tmp/report[0]?*.txt\\name"
        )

        #expect(sanitized == "'/tmp/report[0]?*.txt\\\\name'")
    }

    @Test func clientKeepsCompletedResultWhenAuthorizationChangesAfterExecution() throws {
        let executor = MockSFTPExecutor()
        let probe = SFTPVerifierProbe()
        probe.fail(onCall: 3)
        let authorization = makeAuthorization(verifier: { try probe.verify() })
        let client = try SFTPClient(executor: executor, authorization: authorization)

        _ = try client.listDirectory(path: ".")

        #expect(executor.executedCommands.count == 1)
        #expect(probe.verificationCount == 2)
    }

    @Test func systemArgumentsTerminateOptionsAndBracketIPv6() throws {
        let destination = try SSHConnectionDestination(user: "deploy", host: "2001:db8::10")
        let arguments = SystemSFTPExecutor.arguments(
            destination: destination,
            port: 2_222,
            sshProgramPath: "/Applications/Cocxy Terminal.app/Contents/MacOS/CocxyTerminal"
        )

        #expect(arguments.suffix(2) == ["--", "deploy@[2001:db8::10]"])
        #expect(arguments.contains("-P"))
        #expect(arguments.contains("2222"))
        #expect(arguments.contains("ControlMaster=no"))
        #expect(arguments.contains("ProxyJump=none"))
        #expect(arguments.contains("ProxyCommand=/usr/bin/false"))
        #expect(arguments.contains("BatchMode=yes"))
        #expect(arguments.contains("-S"))
        #expect(arguments.contains(
            "/Applications/Cocxy Terminal.app/Contents/MacOS/CocxyTerminal"
        ))
        #expect(!arguments.contains(where: { $0.hasPrefix("ControlPath=") }))
    }

    @Test func systemExecutorUsesPrivateBatchFileAndCleansItUp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxy-sftp-executor-tests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let processRunner = RecordingSFTPProcessRunner()
        let executor = SystemSFTPExecutor(
            temporaryDirectory: root,
            timeoutSeconds: 2,
            retainedBytesPerStream: 4 * 1_024,
            processRunner: processRunner
        )
        let profile = RemoteConnectionProfile(
            name: "dev",
            host: "example.com",
            user: "deploy",
            port: 22
        )
        let authorization = makeAuthorization(profile: profile)

        let output = try executor.execute(
            sftpCommand: "ls -la '/tmp'",
            authorization: authorization
        )

        #expect(output == "fixture output")
        #expect(processRunner.batchContents == "ls -la '/tmp'\nbye\n")
        #expect(processRunner.batchPermissions == 0o600)
        #expect(processRunner.invocation?.timeoutSeconds == 2)
        #expect(processRunner.invocation?.retainedBytesPerStream == 4 * 1_024)
        #expect(processRunner.invocation?.environment[SFTPMuxSessionContract.modeKey]
            == SFTPMuxSessionContract.modeValue)
        #expect(processRunner.invocation?.environment[
            SFTPMuxSessionContract.controlPathKey
        ] == authorization.controlPath)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func localBatchPreparationFailureIsNotReportedAsRemoteCommitUncertainty() throws {
        let root = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let processRunner = RecordingSFTPProcessRunner()
        let unavailableDirectory = root
            .appendingPathComponent("missing", isDirectory: true)
            .appendingPathComponent("nested", isDirectory: true)
        let executor = SystemSFTPExecutor(
            temporaryDirectory: unavailableDirectory,
            processRunner: processRunner
        )
        let client = try SFTPClient(
            executor: executor,
            authorization: makeAuthorization()
        )

        #expect(throws: (any Error).self) {
            _ = try client.mkdir(path: "/tmp/new-dir")
        }
        #expect(processRunner.invocation == nil)
    }

    @Test func systemRecoveryKeepsFiniteTimeoutAndConnectionRevocationSignal() throws {
        let root = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let processRunner = RecordingSFTPProcessRunner()
        let executor = SystemSFTPExecutor(
            temporaryDirectory: root,
            timeoutSeconds: 0.25,
            processRunner: processRunner
        )
        let authorization = makeAuthorization()

        _ = try executor.executeRecovery(
            sftpCommand: "rename -l '/tmp/recovery' '/tmp/original'",
            authorization: authorization
        )

        #expect(processRunner.invocation?.observesTaskCancellation == false)
        #expect(processRunner.invocation?.timeoutSeconds == 0.25)
        #expect(processRunner.invocation?.cancellationRequested() == false)
        authorization.revoke()
        #expect(processRunner.invocation?.cancellationRequested() == true)
    }

    @Test func systemExecutorVerifiesAuthorizationAroundProcessExecution() throws {
        let processRunner = RecordingSFTPProcessRunner()
        let executor = SystemSFTPExecutor(processRunner: processRunner)
        let probe = SFTPVerifierProbe()
        let authorization = makeAuthorization(verifier: { try probe.verify() })

        _ = try executor.execute(
            sftpCommand: "ls -la '.'",
            authorization: authorization
        )

        #expect(probe.verificationCount == 1)
        #expect(processRunner.invocation != nil)
    }

    @Test func systemDirectoryListingChangesDirectoryBeforeNameOnlyListings() throws {
        let root = try privateTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let processRunner = RecordingSFTPProcessRunner()
        let executor = SystemSFTPExecutor(
            temporaryDirectory: root,
            processRunner: processRunner
        )

        _ = try executor.directoryListing(
            path: "/remote/release notes",
            authorization: makeAuthorization()
        )

        #expect(processRunner.batchContentsHistory == [
            "cd '/remote/release notes'\nls -1a\nbye\n",
            "cd '/remote/release notes'\nls -lan\nbye\n",
        ])
        #expect(processRunner.invocation?.environment["LC_ALL"] == "C")
        #expect(processRunner.invocation?.environment["LANG"] == "C")
    }

    @Test func revokingAuthorizationCancelsAnInFlightSystemExecution() async throws {
        let processRunner = RevocationAwareSFTPProcessRunner()
        let executor = SystemSFTPExecutor(processRunner: processRunner)
        let authorization = makeAuthorization()
        let execution = Task.detached {
            try executor.execute(
                sftpCommand: "ls -la '.'",
                authorization: authorization
            )
        }

        for _ in 0..<200 where !processRunner.started {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(processRunner.started)
        authorization.revoke()

        do {
            _ = try await execution.value
            Issue.record("Revoked SFTP execution unexpectedly completed")
        } catch let error as SFTPClientError {
            #expect(error == .notConnected)
        } catch {
            Issue.record("Unexpected revocation error: \(error)")
        }
    }

    @Test func systemExecutorRejectsTruncatedProcessOutput() throws {
        let processRunner = RecordingSFTPProcessRunner()
        processRunner.result = BoundedProcessResult(
            exitCode: 0,
            stdout: "partial",
            stderr: "",
            stdoutWasTruncated: true,
            stderrWasTruncated: false,
            timedOut: false
        )
        let executor = SystemSFTPExecutor(
            processRunner: processRunner
        )
        let authorization = makeAuthorization(profile: RemoteConnectionProfile(
            name: "dev",
            host: "example.com",
            user: "deploy",
            port: 22
        ))

        #expect(throws: SFTPClientError.commandFailed("SFTP output exceeded the safe limit.")) {
            _ = try executor.execute(
                sftpCommand: "ls -la '/tmp'",
                authorization: authorization
            )
        }
    }

    @Test func listDirectoryWithSpacesInPath() throws {
        let executor = MockSFTPExecutor()
        executor.stubbedOutput = ""

        let client = makeClient(executor: executor)
        _ = try client.listDirectory(path: "/home/user/my docs")

        let call = executor.executedCommands[0]
        #expect(call.sftpCommand == "ls -la '/home/user/my docs'")
    }

    // MARK: - Remote File Entry Parsing

    @Test func parseFileEntryWithStandardFormat() {
        let line = "-rw-r--r--    1 deploy deploy     1234 Feb 20 14:22 README.md"
        let entry = RemoteFileEntry.parse(from: line, basePath: "/home/deploy")

        #expect(entry != nil)
        #expect(entry?.name == "README.md")
        #expect(entry?.isDirectory == false)
        #expect(entry?.size == 1234)
        #expect(entry?.permissions == "-rw-r--r--")
        #expect(entry?.listingLinkCountToken == "1")
        #expect(entry?.listingOwnerToken == "deploy")
        #expect(entry?.listingGroupToken == "deploy")
        #expect(entry?.listingModificationToken == "Feb 20 14:22")
    }

    @Test func parseDirectoryEntry() {
        let line = "drwxr-xr-x    5 user group     4096 Mar 10 09:15 src"
        let entry = RemoteFileEntry.parse(from: line, basePath: "/home")

        #expect(entry != nil)
        #expect(entry?.name == "src")
        #expect(entry?.isDirectory == true)
    }

    @Test func parseEntryWithLargeFileSize() {
        let line = "-rw-r--r--    1 user user 1073741824 Jan 01 00:00 large-file.bin"
        let entry = RemoteFileEntry.parse(from: line, basePath: "/data")

        #expect(entry != nil)
        #expect(entry?.size == 1_073_741_824)
    }

    @Test func parseEntryPreservesSpacesInsideFilename() {
        let line = "-rw-r--r-- 1 user group 12 Jan 01 00:00 release  notes  final.txt"
        let entry = RemoteFileEntry.parse(from: line, basePath: ".")

        #expect(entry?.name == "release  notes  final.txt")
        #expect(entry?.id == "./release  notes  final.txt")
    }

    @Test func parseEntryPreservesLeadingSpacesInFilename() {
        let line = "-rw-r--r-- 1 user group 12 Jan 01 00:00  report.txt"
        let entry = RemoteFileEntry.parse(from: line, basePath: "/remote")

        #expect(entry?.name == " report.txt")
        #expect(entry?.id == "/remote/ report.txt")
    }

    @Test func parseSymbolicLinkSeparatesDisplayTarget() {
        let line = "lrwxr-xr-x 1 user group 18 Jan 01 00:00 current -> releases/v2 final"
        let entry = RemoteFileEntry.parse(from: line, basePath: "/srv/app")

        #expect(entry?.name == "current")
        #expect(entry?.id == "/srv/app/current")
        #expect(entry?.isSymbolicLink == true)
        #expect(entry?.isDirectory == false)
        #expect(entry?.linkTarget == "releases/v2 final")
    }

    @Test func parseSymbolicLinkRejectsAmbiguousArrowBoundary() {
        let line = "lrwxr-xr-x 1 user group 18 Jan 01 00:00 current -> blue -> releases/v2"
        let entry = RemoteFileEntry.parse(from: line, basePath: "/srv/app")

        #expect(entry == nil)
    }

    @Test func parseEntryReturnsNilForMalformedLine() {
        let line = "not a valid ls output"
        let entry = RemoteFileEntry.parse(from: line, basePath: "/tmp")

        #expect(entry == nil)
    }

    @Test func parseEntryReturnsNilForEmptyLine() {
        let entry = RemoteFileEntry.parse(from: "", basePath: "/tmp")
        #expect(entry == nil)
    }

    @Test func remoteFileEntryIdentity() {
        let entry = RemoteFileEntry(
            id: "/home/deploy/file.txt",
            name: "file.txt",
            isDirectory: false,
            size: 1024,
            modifiedDate: Date(),
            permissions: "-rw-r--r--"
        )

        #expect(entry.id == "/home/deploy/file.txt")
        #expect(entry.name == "file.txt")
    }

    @Test func safePathComponentRejectsControlsAndTraversalForms() {
        let invalidNames = [
            "",
            ".",
            "..",
            "../target",
            "subdir/target",
            "/absolute",
            "..\\target",
            "line\nbreak",
            "nul\u{0000}byte",
        ]

        for name in invalidNames {
            #expect(!RemoteFileEntry.isSafePathComponent(name))
        }
        #expect(RemoteFileEntry.isSafePathComponent("report final.txt"))
    }

    @Test func relativeParentNavigationDoesNotAccumulateDotComponents() {
        #expect(SFTPBrowserViewModel.parentPath(of: "./project/src") == "./project")
        #expect(SFTPBrowserViewModel.parentPath(of: "./project") == ".")
        #expect(SFTPBrowserViewModel.parentPath(of: "././project") == ".")
        #expect(SFTPBrowserViewModel.parentPath(of: "/srv/project") == "/srv")
        #expect(SFTPBrowserViewModel.parentPath(of: "/srv") == "/")
    }

    @Test func keyboardSelectionTraversesAndClampsRows() {
        let entryIDs = ["/remote/alpha", "/remote/bravo", "/remote/charlie"]

        #expect(SFTPBrowserView.selectionID(
            current: nil,
            entryIDs: entryIDs,
            moving: .next
        ) == entryIDs.first)
        #expect(SFTPBrowserView.selectionID(
            current: nil,
            entryIDs: entryIDs,
            moving: .previous
        ) == entryIDs.last)
        #expect(SFTPBrowserView.selectionID(
            current: entryIDs[1],
            entryIDs: entryIDs,
            moving: .previous
        ) == entryIDs[0])
        #expect(SFTPBrowserView.selectionID(
            current: entryIDs[1],
            entryIDs: entryIDs,
            moving: .next
        ) == entryIDs[2])
        #expect(SFTPBrowserView.selectionID(
            current: entryIDs[0],
            entryIDs: entryIDs,
            moving: .previous
        ) == entryIDs[0])
        #expect(SFTPBrowserView.selectionID(
            current: entryIDs[2],
            entryIDs: entryIDs,
            moving: .next
        ) == entryIDs[2])
        #expect(SFTPBrowserView.selectionID(
            current: entryIDs[1],
            entryIDs: entryIDs,
            moving: .first
        ) == entryIDs.first)
        #expect(SFTPBrowserView.selectionID(
            current: entryIDs[1],
            entryIDs: entryIDs,
            moving: .last
        ) == entryIDs.last)
        #expect(SFTPBrowserView.selectionID(
            current: nil,
            entryIDs: [],
            moving: .next
        ) == nil)
    }
}

@Suite("SFTP browser download containment", .serialized)
struct SFTPBrowserDownloadContainmentTests {
    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Timed out waiting for the SFTP operation")
    }

    private func profile() -> RemoteConnectionProfile {
        RemoteConnectionProfile(name: "dev", host: "server.com", user: "deploy")
    }

    private func client(executor: any SFTPExecutor) throws -> SFTPClient {
        let profile = profile()
        let identity = SSHControlMasterIdentity(
            processID: 4_242,
            controlPath: profile.controlPath,
            supervisorID: UUID()
        )
        let authorization = try SFTPConnectionAuthorization(
            profile: profile,
            connectionLeaseID: UUID(),
            controlMasterIdentity: identity,
            controlSocketAttestation: SSHControlSocketAttestation(
                device: 1,
                inode: 2,
                peerProcessID: identity.processID
            ),
            verifier: {}
        )
        return try SFTPClient(executor: executor, authorization: authorization)
    }

    private func entry(name: String, remotePath: String? = nil) -> RemoteFileEntry {
        RemoteFileEntry(
            id: remotePath ?? "/remote/\(name)",
            name: name,
            isDirectory: false,
            size: 1,
            modifiedDate: .distantPast,
            permissions: "-rw-r--r--"
        )
    }

    private func temporaryDownloadsDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-sftp-download-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return root
    }

    private func localizationBundle() throws -> Bundle {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return try #require(Bundle(
            url: root.appendingPathComponent("Resources/Localization", isDirectory: true)
        ))
    }

    @MainActor
    private func prepareReview(
        in viewModel: SFTPBrowserViewModel,
        for entry: RemoteFileEntry,
        operation: SFTPBrowserOperation = .remove
    ) async throws -> SFTPReviewedRemoteEntry {
        var reviewedEntry: SFTPReviewedRemoteEntry?
        viewModel.prepareRemoteReview(entry, operation: operation) {
            reviewedEntry = $0
        }
        await waitUntil { reviewedEntry != nil || !viewModel.isMutating }
        return try #require(reviewedEntry)
    }

    @Test("direct traversal-bearing entries never reach the SFTP executor")
    @MainActor func directUnsafeEntriesAreRejected() throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let executor = MockSFTPExecutor()
        let viewModel = SFTPBrowserViewModel(
            sftpClient: try client(executor: executor),
            downloadsDirectory: downloads
        )

        for name in ["../target", "subdir/target", "/absolute", "..\\target", ".", ".."] {
            viewModel.downloadFile(entry(name: name))
        }

        #expect(executor.executedCommands.isEmpty)
        #expect(viewModel.operationErrorMessage != nil)
    }

    @Test("normal filename with spaces targets one strict child of Downloads")
    @MainActor func normalFilenameTargetsDownloadsChild() async throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let executor = MockSFTPExecutor()
        executor.stubbedOutput =
            "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 report final.txt\n"
        let viewModel = SFTPBrowserViewModel(
            sftpClient: try client(executor: executor),
            downloadsDirectory: downloads
        )

        let file = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 report final.txt",
            basePath: "/remote"
        ))
        viewModel.downloadFile(file)
        await waitUntil { !viewModel.isDownloading(file) }

        let commands = executor.executedCommands.map(\.sftpCommand)
        #expect(commands.count == 5)
        #expect(commands[0] == "ls -la '/remote'")
        #expect(commands[1].contains("/cocxy-sftp-review-"))
        #expect(commands[2] == "ls -la '/remote'")
        #expect(commands[3].hasPrefix("get '/remote/report final.txt' "))
        #expect(commands[3].contains("' '\(downloads.path)/.cocxy-download-"))
        #expect(commands[4] == "ls -la '/remote'")
        #expect(try String(
            contentsOf: downloads.appendingPathComponent("report final.txt"),
            encoding: .utf8
        ) == "downloaded")
        #expect(viewModel.operationErrorMessage == nil)
    }

    @Test("directory loading returns immediately while SFTP runs off the main actor")
    @MainActor func directoryLoadingDoesNotBlockMainActor() async throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let executor = MockSFTPExecutor()
        executor.executionDelay = 0.15
        executor.stubbedOutput =
            "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 report.txt\n"
        let viewModel = SFTPBrowserViewModel(
            sftpClient: try client(executor: executor),
            downloadsDirectory: downloads
        )

        viewModel.loadDirectory(at: "/remote")

        #expect(viewModel.isLoading)
        await waitUntil { !viewModel.isLoading }
        #expect(viewModel.currentPath == "/remote")
        #expect(viewModel.entries.map(\.name) == ["report.txt"])
    }

    @Test("start is idempotent and performs one initial listing")
    @MainActor func startIsIdempotent() async throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let executor = MockSFTPExecutor()
        let viewModel = SFTPBrowserViewModel(
            sftpClient: try client(executor: executor),
            downloadsDirectory: downloads
        )

        viewModel.start()
        viewModel.start()
        await waitUntil { !viewModel.isLoading }

        #expect(executor.executedCommands.count == 1)
        #expect(executor.executedCommands.first?.sftpCommand == "ls -la '.'")
    }

    @Test("a failed refresh clears stale entries and disables stale actions")
    @MainActor func failedRefreshClearsEntries() async throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let executor = MockSFTPExecutor()
        executor.stubbedOutput =
            "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 report.txt\n"
        let viewModel = SFTPBrowserViewModel(
            sftpClient: try client(executor: executor),
            downloadsDirectory: downloads
        )

        viewModel.start()
        await waitUntil { !viewModel.isLoading }
        executor.shouldThrow = true
        viewModel.refresh()
        await waitUntil { !viewModel.isLoading }

        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.listingErrorMessage != nil)
    }

    @Test("upload requires explicit replacement for a visible name collision")
    @MainActor func uploadCollisionRequiresExplicitReplacement() async throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let sourceDirectory = downloads.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: false)
        let localFile = sourceDirectory.appendingPathComponent("config.yml")
        try "version: 2".write(to: localFile, atomically: true, encoding: .utf8)
        let executor = MockSFTPExecutor()
        var quarantinePath: String?
        var backupWasRemoved = false
        executor.beforeReturning = { command in
            if command.hasPrefix("rename -l './config.yml' ") {
                quarantinePath = quotedArguments(in: command).last
            } else if command.hasPrefix("rm './.cocxy-review-") {
                backupWasRemoved = true
            }
        }
        executor.outputProvider = { command in
            guard command == "ls -la '.'" else { return "" }
            if let quarantinePath, !backupWasRemoved {
                return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 "
                    + URL(fileURLWithPath: quarantinePath).lastPathComponent + "\n"
            }
            return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 config.yml\n"
        }
        let viewModel = SFTPBrowserViewModel(
            sftpClient: try client(executor: executor),
            downloadsDirectory: downloads
        )
        viewModel.start()
        await waitUntil { !viewModel.isLoading }

        let reviewedUpload = try #require(viewModel.reviewUploadFile(at: localFile))
        viewModel.uploadFile(reviewedUpload)

        #expect(executor.executedCommands.count == 1)
        #expect(viewModel.operationErrorMessage != nil)

        let reviewedEntry = try #require(viewModel.entry(named: "config.yml"))
        let remoteReview = try await prepareReview(
            in: viewModel,
            for: reviewedEntry,
            operation: .upload
        )
        viewModel.uploadFile(reviewedUpload, replacing: remoteReview)
        await waitUntil {
            !viewModel.isMutating && !viewModel.isLoading
        }

        let commands = executor.executedCommands.map(\.sftpCommand)
        let quarantineRename = try #require(commands.firstIndex {
            $0.hasPrefix("rename -l './config.yml' './.cocxy-review-")
        })
        let promotion = try #require(commands.firstIndex {
            $0.hasPrefix("rename -l './.cocxy-upload-")
                && $0.hasSuffix(" './config.yml'")
        })
        #expect(quarantineRename < promotion)
        #expect(commands[..<promotion].contains {
            $0.hasPrefix("get './.cocxy-review-")
        })
        #expect(commands.contains { $0.hasPrefix("rm './.cocxy-review-") })
        #expect(commands.last == "ls -la '.'")
        #expect(viewModel.operationErrorMessage == nil)
    }

    @Test("replacement uses the local identity captured before confirmation")
    @MainActor func replacementUsesSelectionTimeLocalIdentity() async throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let sourceDirectory = downloads.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: false)
        let localFile = sourceDirectory.appendingPathComponent("config.yml")
        try Data("version: 2".utf8).write(to: localFile)
        let executor = MockSFTPExecutor()
        executor.stubbedOutput =
            "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 config.yml\n"
        let viewModel = SFTPBrowserViewModel(
            sftpClient: try client(executor: executor),
            downloadsDirectory: downloads,
            localizer: AppLocalizer(
                languagePreference: .english,
                bundle: try localizationBundle()
            )
        )
        viewModel.start()
        await waitUntil { !viewModel.isLoading }

        let reviewedUpload = try #require(viewModel.reviewUploadFile(at: localFile))
        let reviewedEntry = try #require(viewModel.entry(named: "config.yml"))
        let remoteReview = try await prepareReview(
            in: viewModel,
            for: reviewedEntry,
            operation: .upload
        )
        try Data(repeating: 0x41, count: 4_096).write(to: localFile, options: .atomic)

        viewModel.uploadFile(reviewedUpload, replacing: remoteReview)
        await waitUntil { !viewModel.isMutating }

        #expect(!executor.executedCommands.contains { $0.sftpCommand.hasPrefix("put ") })
        #expect(viewModel.operationErrorMessage == "Select a regular local file to upload.")
    }

    @Test("replacement cleanup uncertainty remains visible after refresh")
    @MainActor func replacementCleanupWarningIsSurfaced() async throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let sourceDirectory = downloads.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: false)
        let localFile = sourceDirectory.appendingPathComponent("config.yml")
        try Data("version: 2".utf8).write(to: localFile)
        let executor = MockSFTPExecutor()
        var quarantinePath: String?
        executor.beforeReturning = { command in
            if command.hasPrefix("rename -l './config.yml' ") {
                quarantinePath = quotedArguments(in: command).last
            }
        }
        executor.outputProvider = { command in
            if command.hasPrefix("rm './.cocxy-review-") {
                throw SFTPClientError.commandFailed("cleanup unavailable")
            }
            guard command == "ls -la '.'" else { return "" }
            guard let quarantinePath else {
                return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 config.yml\n"
            }
            let backupName = URL(fileURLWithPath: quarantinePath).lastPathComponent
            return """
            -rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 \(backupName)
            -rw-r--r-- 1 deploy deploy 10 Jan 15 10:31 config.yml
            """
        }
        let viewModel = SFTPBrowserViewModel(
            sftpClient: try client(executor: executor),
            downloadsDirectory: downloads,
            localizer: AppLocalizer(
                languagePreference: .english,
                bundle: try localizationBundle()
            )
        )
        viewModel.start()
        await waitUntil { !viewModel.isLoading }

        let reviewedUpload = try #require(viewModel.reviewUploadFile(at: localFile))
        let reviewedEntry = try #require(viewModel.entry(named: "config.yml"))
        let remoteReview = try await prepareReview(
            in: viewModel,
            for: reviewedEntry,
            operation: .upload
        )
        viewModel.uploadFile(reviewedUpload, replacing: remoteReview)
        await waitUntil { !viewModel.isMutating && !viewModel.isLoading }

        #expect(viewModel.operationErrorMessage?.contains("./config.yml") == true)
        #expect(viewModel.operationErrorMessage?.contains(
            quarantinePath ?? "missing recovery path"
        ) == true)
        #expect(viewModel.operationRecoveryPath == quarantinePath)
        #expect(executor.executedCommands.last?.sftpCommand == "ls -la '.'")
    }

    @Test("upload snapshot cleanup warning exposes its local recovery directory")
    @MainActor func uploadSnapshotCleanupWarningUsesLocalRecoveryAction() async throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let sourceDirectory = downloads.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: false)
        let localFile = sourceDirectory.appendingPathComponent("config.yml")
        try Data("version: 2".utf8).write(to: localFile)
        let executor = MockSFTPExecutor()
        let retainedSnapshotDirectory = LockedBox<URL?>(nil)
        executor.beforeReturning = { command in
            guard command.hasPrefix("put "),
                  let sourcePath = firstQuotedArgument(in: command) else { return }
            let directory = URL(fileURLWithPath: sourcePath).deletingLastPathComponent()
            try Data("retain recovery directory".utf8).write(
                to: directory.appendingPathComponent("retained")
            )
            retainedSnapshotDirectory.withValue { $0 = directory }
        }
        let viewModel = SFTPBrowserViewModel(
            sftpClient: try client(executor: executor),
            downloadsDirectory: downloads,
            localizer: AppLocalizer(
                languagePreference: .english,
                bundle: try localizationBundle()
            )
        )

        let reviewedUpload = try #require(viewModel.reviewUploadFile(at: localFile))
        viewModel.uploadFile(reviewedUpload)
        await waitUntil {
            !viewModel.isMutating && viewModel.operationErrorMessage != nil
        }

        let recoveryDirectory = try #require(
            retainedSnapshotDirectory.withValue { $0 }
        )
        defer { try? FileManager.default.removeItem(at: recoveryDirectory) }
        #expect(viewModel.operationLocalRecoveryURL == recoveryDirectory)
        #expect(viewModel.operationRecoveryPath == nil)
        #expect(viewModel.operationErrorMessage?.contains(recoveryDirectory.path) == true)
    }

    @Test("an ambiguous replacement commit remains visible after refresh")
    @MainActor func replacementIndeterminateWarningIsSurfaced() async throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let sourceDirectory = downloads.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: false)
        let localFile = sourceDirectory.appendingPathComponent("config.yml")
        try Data("version: 2".utf8).write(to: localFile)
        let executor = MockSFTPExecutor()
        var quarantinePath: String?
        var stagingPath: String?
        var promotionAttempted = false
        executor.beforeReturning = { command in
            let arguments = quotedArguments(in: command)
            if command.hasPrefix("put ") {
                stagingPath = arguments.last
            } else if command.hasPrefix("rename -l './config.yml' ") {
                quarantinePath = arguments.last
            }
        }
        executor.outputProvider = { command in
            let arguments = quotedArguments(in: command)
            if command.hasPrefix("rename -l "),
               arguments.first == stagingPath,
               arguments.last == "./config.yml" {
                promotionAttempted = true
                throw SFTPClientError.commandFailed("connection closed after request")
            }
            guard command == "ls -la '.'" else { return "" }
            guard let quarantinePath else {
                return "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 config.yml\n"
            }
            let backupName = URL(fileURLWithPath: quarantinePath).lastPathComponent
            let backup = "-rw-r--r-- 1 deploy deploy 12 Jan 15 10:30 \(backupName)\n"
            return promotionAttempted
                ? backup + "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:31 config.yml\n"
                : backup
        }
        let viewModel = SFTPBrowserViewModel(
            sftpClient: try client(executor: executor),
            downloadsDirectory: downloads,
            localizer: AppLocalizer(
                languagePreference: .english,
                bundle: try localizationBundle()
            )
        )
        viewModel.start()
        await waitUntil { !viewModel.isLoading }

        let reviewedUpload = try #require(viewModel.reviewUploadFile(at: localFile))
        let reviewedEntry = try #require(viewModel.entry(named: "config.yml"))
        let remoteReview = try await prepareReview(
            in: viewModel,
            for: reviewedEntry,
            operation: .upload
        )
        viewModel.uploadFile(reviewedUpload, replacing: remoteReview)
        await waitUntil { !viewModel.isMutating && !viewModel.isLoading }

        #expect(viewModel.operationErrorMessage?.contains("./config.yml") == true)
        #expect(viewModel.operationErrorMessage?.contains(
            quarantinePath ?? "missing recovery path"
        ) == true)
        #expect(viewModel.operationRecoveryPath == quarantinePath)
        #expect(executor.executedCommands.last?.sftpCommand == "ls -la '.'")
    }

    @Test("special remote entries are not offered to the download pipeline")
    @MainActor func specialRemoteEntryCannotBeDownloaded() throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let executor = MockSFTPExecutor()
        let viewModel = SFTPBrowserViewModel(
            sftpClient: try client(executor: executor),
            downloadsDirectory: downloads
        )
        let socketEntry = RemoteFileEntry(
            id: "/remote/agent.sock",
            name: "agent.sock",
            isDirectory: false,
            size: 0,
            modifiedDate: .distantPast,
            permissions: "srwx------"
        )

        viewModel.downloadFile(socketEntry)

        #expect(executor.executedCommands.isEmpty)
        #expect(!viewModel.isDownloading(socketEntry))
    }

    @Test("a visible SFTP error adopts the current app language")
    @MainActor func visibleErrorUpdatesWithLocalizer() throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let executor = MockSFTPExecutor()
        let viewModel = SFTPBrowserViewModel(
            sftpClient: try client(executor: executor),
            downloadsDirectory: downloads,
            localizer: AppLocalizer(
                languagePreference: .english,
                bundle: try localizationBundle()
            )
        )
        let invalidUpload = downloads.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidUpload, withIntermediateDirectories: false)

        #expect(viewModel.reviewUploadFile(at: invalidUpload) == nil)
        #expect(viewModel.operationErrorMessage == "Select a regular local file to upload.")

        viewModel.updateLocalizer(
            AppLocalizer(
                languagePreference: .spanish,
                bundle: try localizationBundle()
            )
        )
        #expect(viewModel.operationErrorMessage == "Selecciona un archivo local regular para subirlo.")

        viewModel.updateLocalizer(
            AppLocalizer(
                languagePreference: .english,
                bundle: try localizationBundle()
            )
        )
        #expect(viewModel.operationErrorMessage == "Select a regular local file to upload.")
    }

    @Test("SFTP executor failures use localized safe messages")
    @MainActor func executorFailureUsesLocalizedMessage() async throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let executor = MockSFTPExecutor()
        executor.shouldThrow = true
        let viewModel = SFTPBrowserViewModel(
            sftpClient: try client(executor: executor),
            downloadsDirectory: downloads,
            localizer: AppLocalizer(
                languagePreference: .english,
                bundle: try localizationBundle()
            )
        )

        viewModel.start()
        await waitUntil { !viewModel.isLoading }
        #expect(
            viewModel.listingErrorMessage
                == "The SFTP command failed. Check the connection and try again."
        )
        #expect(viewModel.listingErrorMessage?.contains("mock sftp error") == false)

        viewModel.updateLocalizer(
            AppLocalizer(
                languagePreference: .spanish,
                bundle: try localizationBundle()
            )
        )
        #expect(
            viewModel.listingErrorMessage
                == "El comando SFTP falló. Revisa la conexión e inténtalo de nuevo."
        )
    }

    @Test("an entry cannot be deleted while its download is active")
    @MainActor func activeDownloadBlocksDeletion() async throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let executor = MockSFTPExecutor()
        executor.executionDelay = 0.1
        executor.stubbedOutput =
            "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 report.txt\n"
        let viewModel = SFTPBrowserViewModel(
            sftpClient: try client(executor: executor),
            downloadsDirectory: downloads
        )
        let remoteEntry = try #require(RemoteFileEntry.parse(
            from: "-rw-r--r-- 1 deploy deploy 10 Jan 15 10:30 report.txt",
            basePath: "/remote"
        ))

        viewModel.downloadFile(remoteEntry)
        viewModel.prepareRemoteReview(remoteEntry) { _ in
            Issue.record("Deletion review must remain blocked during a download")
        }
        await waitUntil { !viewModel.isDownloading(remoteEntry) }

        let commands = executor.executedCommands.map(\.sftpCommand)
        #expect(commands.count == 5)
        #expect(commands.contains { $0.hasPrefix("get ") })
        #expect(!commands.contains { $0.hasPrefix("rm ") || $0.hasPrefix("rmdir ") })
        #expect(!viewModel.isMutating)
    }

    @Test("closing the browser cancels an active transfer worker")
    @MainActor func closingBrowserCancelsActiveTransfer() async throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let executor = CancellationAwareSFTPExecutor()
        let viewModel = SFTPBrowserViewModel(
            sftpClient: try client(executor: executor),
            downloadsDirectory: downloads
        )
        let remoteEntry = entry(name: "report.txt")

        viewModel.downloadFile(remoteEntry)
        await waitUntil { executor.started }
        viewModel.cancelPendingWork()
        await waitUntil { executor.cancellationObserved }

        #expect(!viewModel.isDownloading(remoteEntry))
        #expect(viewModel.operationErrorMessage == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: downloads.path).isEmpty)
    }

    @Test("reopening the browser preserves one active mutation and its indeterminate result")
    @MainActor func reopeningBrowserPreservesActiveMutationResult() async throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let executor = SFTPLifecycleMutationExecutor()
        defer { executor.releaseFirstMutation() }
        let sftpClient = try client(executor: executor)
        var viewModel: SFTPBrowserViewModel? = SFTPBrowserViewModel(
            sftpClient: sftpClient,
            downloadsDirectory: downloads,
            localizer: AppLocalizer(
                languagePreference: .english,
                bundle: try localizationBundle()
            )
        )

        viewModel?.createDirectory(named: "first")
        await waitUntil { executor.mutationCommands.count == 1 }
        viewModel?.cancelPendingWork()
        viewModel = nil

        let reopenedViewModel = SFTPBrowserViewModel(
            sftpClient: sftpClient,
            downloadsDirectory: downloads,
            localizer: AppLocalizer(
                languagePreference: .english,
                bundle: try localizationBundle()
            )
        )

        #expect(reopenedViewModel.isMutating)
        reopenedViewModel.createDirectory(named: "second")
        try await Task.sleep(for: .milliseconds(50))
        #expect(executor.mutationCommands.count == 1)

        executor.releaseFirstMutation()
        await waitUntil {
            !reopenedViewModel.isMutating
                && reopenedViewModel.operationErrorMessage != nil
        }

        #expect(executor.mutationCommands.count == 1)
        #expect(reopenedViewModel.operationErrorMessage?.contains("first") == true)
    }

    @Test("starting another mutation preserves an earlier recovery warning")
    @MainActor func laterMutationPreservesEarlierRecoveryWarning() async throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let executor = SFTPLifecycleMutationExecutor()
        defer { executor.releaseFirstMutation() }
        let viewModel = SFTPBrowserViewModel(
            sftpClient: try client(executor: executor),
            downloadsDirectory: downloads,
            localizer: AppLocalizer(
                languagePreference: .english,
                bundle: try localizationBundle()
            )
        )

        viewModel.createDirectory(named: "first")
        await waitUntil { executor.mutationCommands.count == 1 }
        executor.releaseFirstMutation()
        await waitUntil {
            !viewModel.isMutating
                && viewModel.operationErrorMessage?.contains("first") == true
        }

        viewModel.createDirectory(named: "second")
        await waitUntil {
            executor.mutationCommands.count == 2 && !viewModel.isMutating
        }

        #expect(viewModel.operationErrorMessage?.contains("first") == true)
        viewModel.dismissOperationError()
        #expect(viewModel.operationErrorMessage == nil)
    }

    @Test("existing symlink destination is rejected without touching its target")
    @MainActor func symbolicLinkDestinationIsRejected() async throws {
        let root = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let external = root.appendingPathComponent("external.txt")
        try "original".write(to: external, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: downloads.appendingPathComponent("report.txt"),
            withDestinationURL: external
        )
        let executor = MockSFTPExecutor()
        let viewModel = SFTPBrowserViewModel(
            sftpClient: try client(executor: executor),
            downloadsDirectory: downloads
        )

        let remoteEntry = entry(name: "report.txt")
        viewModel.downloadFile(remoteEntry)
        await waitUntil { !viewModel.isDownloading(remoteEntry) }

        #expect(executor.executedCommands.isEmpty)
        #expect(try String(contentsOf: external, encoding: .utf8) == "original")
        #expect(viewModel.operationErrorMessage != nil)
    }
}
