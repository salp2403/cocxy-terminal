// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SFTPClientTests.swift - Tests for SFTP file operations wrapper.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Mock SFTP Executor

final class MockSFTPExecutor: SFTPExecutor, @unchecked Sendable {
    var executedCommands: [(sftpCommand: String, host: String, controlPath: String)] = []
    var stubbedOutput = ""
    var shouldThrow = false

    func execute(
        sftpCommand: String,
        host: String,
        controlPath: String
    ) throws -> String {
        executedCommands.append((sftpCommand, host, controlPath))
        if shouldThrow {
            throw SFTPClientError.commandFailed("mock sftp error")
        }
        return stubbedOutput
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

    @Test func listDirectorySendsCorrectCommand() throws {
        let executor = MockSFTPExecutor()
        executor.stubbedOutput = ""

        let client = makeClient(executor: executor)
        _ = try client.listDirectory(path: "/var/log", on: makeProfile())

        #expect(executor.executedCommands.count == 1)
        let call = executor.executedCommands[0]
        #expect(call.sftpCommand == "ls -la '/var/log'")
        #expect(call.host == "deploy@server.com")
    }

    @Test func listDirectoryUsesControlPath() throws {
        let executor = MockSFTPExecutor()
        executor.stubbedOutput = ""

        let client = makeClient(executor: executor)
        _ = try client.listDirectory(path: "/tmp", on: makeProfile())

        let call = executor.executedCommands[0]
        let home = NSHomeDirectory()
        #expect(call.controlPath == "\(home)/.config/cocxy/sockets/deploy@server.com:22")
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

    @Test func sanitizePathWrapsInSingleQuotes() {
        let result = SFTPClient.sanitizePath("/var/log/app.log")
        #expect(result == "'/var/log/app.log'")
    }

    @Test func sanitizePathEscapesSingleQuotesInPath() {
        let result = SFTPClient.sanitizePath("/tmp/it's a file")
        #expect(result == "'/tmp/it'\\''s a file'")
    }

    @Test func sanitizePathHandlesSpacesInPath() {
        let result = SFTPClient.sanitizePath("/home/user/my documents/file.txt")
        #expect(result == "'/home/user/my documents/file.txt'")
    }

    @Test func sanitizePathHandlesSpecialCharacters() {
        let result = SFTPClient.sanitizePath("/tmp/file;rm -rf /")
        #expect(result == "'/tmp/file;rm -rf /'")
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
}
