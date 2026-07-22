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
        destination: SSHConnectionDestination,
        port: Int?,
        controlPath: String
    ) throws -> String {
        lock.lock()
        commandStorage.append((sftpCommand, destination, port, controlPath))
        let output = stubbedOutput
        let throwsError = shouldThrow
        let delay = executionDelay
        lock.unlock()
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
        if throwsError {
            throw SFTPClientError.commandFailed("mock sftp error")
        }
        return output
    }
}

final class RecordingSFTPProcessRunner: SFTPProcessRunning, @unchecked Sendable {
    var invocation: SFTPProcessInvocation?
    var batchContents: String?
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
            let attributes = try FileManager.default.attributesOfItem(atPath: batchPath)
            batchPermissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        }
        return result
    }
}

// MARK: - SFTP Client Tests

@Suite("SFTPClient")
struct SFTPClientTests {

    private func makeClient(executor: MockSFTPExecutor = MockSFTPExecutor()) -> SFTPClient {
        SFTPClient(executor: executor)
    }

    private func makeProfile() -> RemoteConnectionProfile {
        RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "deploy", port: 22
        )
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
        let entries = try client.listDirectory(path: "/home/deploy", on: makeProfile())

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
        let entries = try client.listDirectory(path: "/tmp", on: makeProfile())

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
        let entries = try client.listDirectory(path: "/home", on: makeProfile())

        #expect(entries.count == 1)
        #expect(entries.first?.name == "file.txt")
    }

    @Test func listDirectoryRejectsNamesThatAreNotSinglePathComponents() throws {
        let executor = MockSFTPExecutor()
        executor.stubbedOutput = """
        -rw-r--r-- 1 user user 1 Jan 01 00:00 ../target
        -rw-r--r-- 1 user user 1 Jan 01 00:00 subdir/target
        -rw-r--r-- 1 user user 1 Jan 01 00:00 /absolute
        -rw-r--r-- 1 user user 1 Jan 01 00:00 ..\\target
        -rw-r--r-- 1 user user 1 Jan 01 00:00 safe file.txt
        """

        let entries = try makeClient(executor: executor).listDirectory(
            path: "/home",
            on: makeProfile()
        )

        #expect(entries.map(\.name) == ["safe file.txt"])
    }

    @Test func listDirectorySendsCorrectCommand() throws {
        let executor = MockSFTPExecutor()
        executor.stubbedOutput = ""

        let client = makeClient(executor: executor)
        _ = try client.listDirectory(path: "/var/log", on: makeProfile())

        #expect(executor.executedCommands.count == 1)
        let call = executor.executedCommands[0]
        #expect(call.sftpCommand == "ls -la '/var/log'")
        #expect(call.destination.value == "deploy@server.com")
        #expect(call.port == 22)
    }

    @Test func listDirectoryUsesControlPath() throws {
        let executor = MockSFTPExecutor()
        executor.stubbedOutput = ""

        let client = makeClient(executor: executor)
        let profile = makeProfile()
        _ = try client.listDirectory(path: "/tmp", on: profile)

        let call = executor.executedCommands[0]
        #expect(call.controlPath == profile.controlPath)
    }

    @Test func listDirectoryThrowsOnError() {
        let executor = MockSFTPExecutor()
        executor.shouldThrow = true

        let client = makeClient(executor: executor)

        #expect(throws: SFTPClientError.self) {
            try client.listDirectory(path: "/tmp", on: makeProfile())
        }
    }

    // MARK: - Download

    @Test func downloadSendsGetCommand() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)

        try client.download(
            remotePath: "/var/log/app.log",
            localPath: "/tmp/app.log",
            on: makeProfile()
        )

        let call = executor.executedCommands[0]
        #expect(call.sftpCommand == "get '/var/log/app.log' '/tmp/app.log'")
    }

    @Test func downloadThrowsOnError() {
        let executor = MockSFTPExecutor()
        executor.shouldThrow = true
        let client = makeClient(executor: executor)

        #expect(throws: SFTPClientError.self) {
            try client.download(
                remotePath: "/var/log/app.log",
                localPath: "/tmp/app.log",
                on: makeProfile()
            )
        }
    }

    // MARK: - Upload

    @Test func uploadSendsPutCommand() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)

        try client.upload(
            localPath: "/tmp/config.yaml",
            remotePath: "/etc/app/config.yaml",
            on: makeProfile()
        )

        let call = executor.executedCommands[0]
        #expect(call.sftpCommand == "put '/tmp/config.yaml' '/etc/app/config.yaml'")
    }

    // MARK: - Mkdir

    @Test func mkdirSendsMkdirCommand() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)

        try client.mkdir(path: "/var/app/logs", on: makeProfile())

        let call = executor.executedCommands[0]
        #expect(call.sftpCommand == "mkdir '/var/app/logs'")
    }

    // MARK: - Remove

    @Test func removeSendsRmCommand() throws {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)

        try client.remove(path: "/tmp/old-file.txt", on: makeProfile())

        let call = executor.executedCommands[0]
        #expect(call.sftpCommand == "rm '/tmp/old-file.txt'")
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
            try client.remove(path: "/tmp/safe\n!touch /tmp/unsafe", on: makeProfile())
        }
        #expect(executor.executedCommands.isEmpty)
    }

    @Test func rejectsOptionLikePathsBeforeExecuting() {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)

        #expect(throws: SFTPClientError.invalidPath) {
            try client.remove(path: "-R", on: makeProfile())
        }
        #expect(executor.executedCommands.isEmpty)
    }

    @Test func rejectsOptionLikeDestinationsBeforeExecuting() {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let profile = RemoteConnectionProfile(
            name: "unsafe",
            host: "-oProxyCommand=/bin/true"
        )

        #expect(throws: SFTPClientError.invalidDestination) {
            try client.mkdir(path: "/tmp/example", on: profile)
        }
        #expect(executor.executedCommands.isEmpty)
    }

    @Test func rejectsOversizedEscapedCommandsBeforeExecuting() {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let quoteHeavyPath = "/tmp/" + String(repeating: "'", count: 600)

        #expect(throws: SFTPClientError.invalidCommand) {
            try client.download(
                remotePath: quoteHeavyPath,
                localPath: "/tmp/output",
                on: makeProfile()
            )
        }
        #expect(executor.executedCommands.isEmpty)
    }

    @Test func rejectsInvalidPortsBeforeExecuting() {
        let executor = MockSFTPExecutor()
        let client = makeClient(executor: executor)
        let profile = RemoteConnectionProfile(name: "unsafe", host: "example.com", port: 70_000)

        #expect(throws: SFTPClientError.invalidPort) {
            try client.mkdir(path: "/tmp/example", on: profile)
        }
        #expect(executor.executedCommands.isEmpty)
    }

    @Test func systemArgumentsTerminateOptionsAndBracketIPv6() throws {
        let destination = try SSHConnectionDestination(user: "deploy", host: "2001:db8::10")
        let arguments = SystemSFTPExecutor.arguments(
            destination: destination,
            port: 2_222,
            controlPath: "/tmp/control.sock"
        )

        #expect(arguments.suffix(2) == ["--", "deploy@[2001:db8::10]"])
        #expect(arguments.contains("-P"))
        #expect(arguments.contains("2222"))
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
        let destination = try SSHConnectionDestination(user: "deploy", host: "example.com")

        let output = try executor.execute(
            sftpCommand: "ls -la '/tmp'",
            destination: destination,
            port: 22,
            controlPath: "/tmp/control.sock"
        )

        #expect(output == "fixture output")
        #expect(processRunner.batchContents == "ls -la '/tmp'\nbye\n")
        #expect(processRunner.batchPermissions == 0o600)
        #expect(processRunner.invocation?.timeoutSeconds == 2)
        #expect(processRunner.invocation?.retainedBytesPerStream == 4 * 1_024)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
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
        let destination = try SSHConnectionDestination(user: "deploy", host: "example.com")

        #expect(throws: SFTPClientError.commandFailed("SFTP output exceeded the safe limit.")) {
            _ = try executor.execute(
                sftpCommand: "ls -la '/tmp'",
                destination: destination,
                port: 22,
                controlPath: "/tmp/control.sock"
            )
        }
    }

    @Test func listDirectoryWithSpacesInPath() throws {
        let executor = MockSFTPExecutor()
        executor.stubbedOutput = ""

        let client = makeClient(executor: executor)
        _ = try client.listDirectory(path: "/home/user/my docs", on: makeProfile())

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
}

@Suite("SFTP browser download containment")
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
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("direct traversal-bearing entries never reach the SFTP executor")
    @MainActor func directUnsafeEntriesAreRejected() throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let executor = MockSFTPExecutor()
        let viewModel = SFTPBrowserViewModel(
            sftpClient: SFTPClient(executor: executor),
            profile: profile(),
            downloadsDirectory: downloads
        )

        for name in ["../target", "subdir/target", "/absolute", "..\\target", ".", ".."] {
            viewModel.downloadFile(entry(name: name))
        }

        #expect(executor.executedCommands.isEmpty)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("normal filename with spaces targets one strict child of Downloads")
    @MainActor func normalFilenameTargetsDownloadsChild() async throws {
        let downloads = try temporaryDownloadsDirectory()
        defer { try? FileManager.default.removeItem(at: downloads) }
        let executor = MockSFTPExecutor()
        let viewModel = SFTPBrowserViewModel(
            sftpClient: SFTPClient(executor: executor),
            profile: profile(),
            downloadsDirectory: downloads
        )

        let file = entry(
            name: "report final.txt",
            remotePath: "/remote/report final.txt"
        )
        viewModel.downloadFile(file)
        await waitUntil { !viewModel.isDownloading(file) }

        #expect(executor.executedCommands.count == 1)
        #expect(executor.executedCommands.first?.sftpCommand ==
            "get '/remote/report final.txt' '\(downloads.path)/report final.txt'")
        #expect(viewModel.errorMessage == nil)
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
            sftpClient: SFTPClient(executor: executor),
            profile: profile(),
            downloadsDirectory: downloads
        )

        viewModel.loadDirectory(at: "/remote")

        #expect(viewModel.isLoading)
        await waitUntil { !viewModel.isLoading }
        #expect(viewModel.currentPath == "/remote")
        #expect(viewModel.entries.map(\.name) == ["report.txt"])
    }

    @Test("existing symlink destination is rejected without touching its target")
    @MainActor func symbolicLinkDestinationIsRejected() throws {
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
            sftpClient: SFTPClient(executor: executor),
            profile: profile(),
            downloadsDirectory: downloads
        )

        viewModel.downloadFile(entry(name: "report.txt"))

        #expect(executor.executedCommands.isEmpty)
        #expect(try String(contentsOf: external, encoding: .utf8) == "original")
        #expect(viewModel.errorMessage != nil)
    }
}
