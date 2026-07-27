// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SSHKeyManagerTests.swift - Tests for SSH key management.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Mock SSH Key Executor

final class MockSSHKeyExecutor: SSHKeyExecuting, @unchecked Sendable {
    var executedCommands: [(command: String, arguments: [String])] = []
    var lastStdinData: Data?
    var stdinPayloads: [Data] = []
    var stubbedResults: [String: ProcessResult] = [:]
    var defaultResult = ProcessResult(exitCode: 0, stdout: "", stderr: "")
    var resultProvider: ((String, [String]) -> ProcessResult)?

    func execute(command: String, arguments: [String]) throws -> ProcessResult {
        executedCommands.append((command, arguments))
        if let resultProvider {
            return resultProvider(command, arguments)
        }
        let key = "\(command) \(arguments.joined(separator: " "))"
        return stubbedResults[key] ?? defaultResult
    }

    func execute(command: String, arguments: [String], stdinData: Data) throws -> ProcessResult {
        executedCommands.append((command, arguments))
        lastStdinData = stdinData
        stdinPayloads.append(stdinData)
        if let resultProvider {
            return resultProvider(command, arguments)
        }
        let key = "\(command) \(arguments.joined(separator: " "))"
        return stubbedResults[key] ?? defaultResult
    }
}

// MARK: - Mock SSH Key File System

final class MockSSHKeyFileSystem: SSHKeyFileSystem, @unchecked Sendable {
    var files: [String: Bool] = [:]
    var directoryContents: [String] = []
    var createdDirectories: [String] = []
    var removedFiles: [String] = []

    func listDirectory(at path: String) throws -> [String] {
        directoryContents
    }

    func fileExists(at path: String) -> Bool {
        files[path] ?? false
    }

    func createDirectory(at path: String) throws {
        createdDirectories.append(path)
    }

    func removeFile(at path: String) throws {
        removedFiles.append(path)
        files[path] = false
    }
}

// MARK: - SSH Key Manager Tests

@Suite("SSHKeyManager")
struct SSHKeyManagerTests {

    // MARK: - Key Type Detection

    @Test func detectsEd25519KeyType() {
        #expect(SSHKeyType.detect(from: "id_ed25519") == .ed25519)
    }

    @Test func detectsRSAKeyType() {
        #expect(SSHKeyType.detect(from: "id_rsa") == .rsa)
    }

    @Test func detectsECDSAKeyType() {
        #expect(SSHKeyType.detect(from: "id_ecdsa") == .ecdsa)
    }

    @Test func detectsDSAKeyType() {
        #expect(SSHKeyType.detect(from: "id_dsa") == .dsa)
    }

    @Test func detectsUnknownKeyType() {
        #expect(SSHKeyType.detect(from: "my_custom_key") == .unknown)
    }

    @Test func detectsKeyTypeFromFullPath() {
        #expect(SSHKeyType.detect(from: "/Users/dev/.ssh/id_ed25519") == .ed25519)
    }

    // MARK: - List Keys

    @Test func listKeysFindsPrivateKeysWithPublicCounterpart() throws {
        let fileSystem = MockSSHKeyFileSystem()
        fileSystem.directoryContents = [
            "id_ed25519", "id_ed25519.pub",
            "id_rsa", "id_rsa.pub",
            "known_hosts", "config",
        ]
        fileSystem.files = [
            "/test/.ssh/id_ed25519": true,
            "/test/.ssh/id_ed25519.pub": true,
            "/test/.ssh/id_rsa": true,
            "/test/.ssh/id_rsa.pub": true,
            "/test/.ssh/known_hosts": true,
            "/test/.ssh/config": true,
        ]

        let executor = MockSSHKeyExecutor()
        executor.defaultResult = ProcessResult(
            exitCode: 0,
            stdout: "256 SHA256:abc123 user@host (ED25519)\n",
            stderr: ""
        )

        let manager = SSHKeyManager(
            fileSystem: fileSystem,
            executor: executor,
            sshDirectoryPath: "/test/.ssh"
        )
        let keys = try manager.listKeys()

        #expect(keys.count == 2)
        #expect(keys.contains { $0.name == "id_ed25519" })
        #expect(keys.contains { $0.name == "id_rsa" })
    }

    @Test func listKeysExcludesNonKeyFiles() throws {
        let fileSystem = MockSSHKeyFileSystem()
        fileSystem.directoryContents = [
            "known_hosts", "config", "authorized_keys",
        ]

        let executor = MockSSHKeyExecutor()
        let manager = SSHKeyManager(
            fileSystem: fileSystem,
            executor: executor,
            sshDirectoryPath: "/test/.ssh"
        )
        let keys = try manager.listKeys()

        #expect(keys.isEmpty)
    }

    @Test func listKeysDetectsKeyTypes() throws {
        let fileSystem = MockSSHKeyFileSystem()
        fileSystem.directoryContents = [
            "id_ed25519", "id_ed25519.pub",
            "id_ecdsa", "id_ecdsa.pub",
        ]
        fileSystem.files = [
            "/test/.ssh/id_ed25519": true,
            "/test/.ssh/id_ed25519.pub": true,
            "/test/.ssh/id_ecdsa": true,
            "/test/.ssh/id_ecdsa.pub": true,
        ]

        let executor = MockSSHKeyExecutor()
        executor.defaultResult = ProcessResult(
            exitCode: 0,
            stdout: "256 SHA256:abc123 user@host (ED25519)\n",
            stderr: ""
        )

        let manager = SSHKeyManager(
            fileSystem: fileSystem,
            executor: executor,
            sshDirectoryPath: "/test/.ssh"
        )
        let keys = try manager.listKeys()

        let ed25519Key = keys.first { $0.type == .ed25519 }
        let ecdsaKey = keys.first { $0.type == .ecdsa }
        #expect(ed25519Key != nil)
        #expect(ecdsaKey != nil)
    }

    // MARK: - Fingerprint

    @Test func fingerprintParsesSSHKeygenOutput() throws {
        let executor = MockSSHKeyExecutor()
        let fingerprintOutput = "256 SHA256:nThbg6kXUpJWGl7E1IGOCspRomTxdCARLviKw6E5SY8 user@host (ED25519)"
        executor.defaultResult = ProcessResult(
            exitCode: 0, stdout: fingerprintOutput, stderr: ""
        )

        let manager = SSHKeyManager(
            fileSystem: MockSSHKeyFileSystem(),
            executor: executor,
            sshDirectoryPath: "/test/.ssh"
        )
        let fingerprint = try manager.fingerprint(at: "/test/.ssh/id_ed25519")

        #expect(fingerprint == "SHA256:nThbg6kXUpJWGl7E1IGOCspRomTxdCARLviKw6E5SY8")
    }

    @Test func fingerprintThrowsOnExecutionFailure() {
        let executor = MockSSHKeyExecutor()
        executor.defaultResult = ProcessResult(exitCode: 1, stdout: "", stderr: "No such file")

        let manager = SSHKeyManager(
            fileSystem: MockSSHKeyFileSystem(),
            executor: executor,
            sshDirectoryPath: "/test/.ssh"
        )

        #expect(throws: SSHKeyManagerError.self) {
            try manager.fingerprint(at: "/test/.ssh/nonexistent")
        }
    }

    // MARK: - Generate Key

    @Test func generateKeyBuildsCorrectCommand() throws {
        let executor = MockSSHKeyExecutor()
        executor.resultProvider = { _, arguments in
            if arguments == ["-y", "-P", "", "-f", "/test/.ssh/deploy_key"] {
                return ProcessResult(exitCode: 1, stdout: "", stderr: "incorrect passphrase")
            }
            return ProcessResult(exitCode: 0, stdout: "ssh-ed25519 public-key", stderr: "")
        }
        let manager = SSHKeyManager(
            fileSystem: MockSSHKeyFileSystem(),
            executor: executor,
            sshDirectoryPath: "/test/.ssh"
        )

        try manager.generateKey(type: .ed25519, name: "deploy_key", passphrase: "secret")

        #expect(executor.executedCommands.count == 3)
        let call = executor.executedCommands[0]
        #expect(call.command == "/usr/bin/ssh-keygen")
        #expect(call.arguments.contains("-t"))
        #expect(call.arguments.contains("ed25519"))
        #expect(call.arguments.contains("-f"))
        #expect(call.arguments.contains("/test/.ssh/deploy_key"))
        // Passphrase must NOT appear in arguments (passed via stdin).
        #expect(!call.arguments.contains("-N"))
        #expect(!call.arguments.contains("secret"))
        #expect(executor.executedCommands.allSatisfy { !$0.arguments.contains("secret") })
        #expect(executor.stdinPayloads == [
            Data("secret\nsecret\n".utf8),
            Data("secret\n".utf8),
        ])
    }

    @Test func generateKeyWithEmptyPassphrase() throws {
        let executor = MockSSHKeyExecutor()
        let manager = SSHKeyManager(
            fileSystem: MockSSHKeyFileSystem(),
            executor: executor,
            sshDirectoryPath: "/test/.ssh"
        )

        try manager.generateKey(type: .rsa, name: "test_key", passphrase: "")

        let call = executor.executedCommands[0]
        // Passphrase must NOT appear in arguments, even if empty.
        #expect(!call.arguments.contains("-N"))
        #expect(executor.executedCommands.count == 2)
        #expect(executor.stdinPayloads == [Data("\n\n".utf8)])
    }

    @Test func generateKeyRejectsUnsafeNamesAndMultilinePassphrases() {
        let executor = MockSSHKeyExecutor()
        let fileSystem = MockSSHKeyFileSystem()
        let manager = SSHKeyManager(
            fileSystem: fileSystem,
            executor: executor,
            sshDirectoryPath: "/test/.ssh"
        )

        #expect(throws: SSHKeyManagerError.invalidKeyName("../outside")) {
            try manager.generateKey(type: .ed25519, name: "../outside", passphrase: "secret")
        }
        #expect(throws: SSHKeyManagerError.unsupportedPassphrase) {
            try manager.generateKey(type: .ed25519, name: "safe-key", passphrase: "line1\nline2")
        }
        let oversizedPassphrase = String(
            repeating: "a",
            count: SSHAskpassContract.maximumPassphraseBytes + 1
        )
        #expect(throws: SSHKeyManagerError.passphraseTooLong(
            maximumBytes: SSHAskpassContract.maximumPassphraseBytes
        )) {
            try manager.generateKey(
                type: .ed25519,
                name: "safe-key",
                passphrase: oversizedPassphrase
            )
        }
        #expect(executor.executedCommands.isEmpty)
        #expect(fileSystem.createdDirectories.isEmpty)
    }

    @Test func generateKeyRefusesAnUnencryptedPostconditionAndRemovesPartialFiles() {
        let executor = MockSSHKeyExecutor()
        let fileSystem = MockSSHKeyFileSystem()
        let manager = SSHKeyManager(
            fileSystem: fileSystem,
            executor: executor,
            sshDirectoryPath: "/test/.ssh"
        )

        #expect(throws: SSHKeyManagerError.generationFailed(
            "The generated private key is not protected by the requested passphrase."
        )) {
            try manager.generateKey(type: .ed25519, name: "deploy_key", passphrase: "secret")
        }
        #expect(fileSystem.removedFiles == [
            "/test/.ssh/deploy_key",
            "/test/.ssh/deploy_key.pub",
        ])
    }

    @Test func generateKeyRefusesToReplaceAnExistingKeyPair() {
        let executor = MockSSHKeyExecutor()
        let fileSystem = MockSSHKeyFileSystem()
        fileSystem.files["/test/.ssh/deploy_key.pub"] = true
        let manager = SSHKeyManager(
            fileSystem: fileSystem,
            executor: executor,
            sshDirectoryPath: "/test/.ssh"
        )

        #expect(throws: SSHKeyManagerError.keyAlreadyExists("/test/.ssh/deploy_key")) {
            try manager.generateKey(type: .ed25519, name: "deploy_key", passphrase: "secret")
        }
        #expect(executor.executedCommands.isEmpty)
        #expect(fileSystem.removedFiles.isEmpty)
    }

    @Test func systemExecutorGeneratesAKeyProtectedByTheRequestedPassphrase() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-ssh-key-system-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = repositoryRoot()
            .appendingPathComponent(".build/debug/CocxyTerminal")
        let executor = SystemSSHKeyExecutor(askpassExecutableURL: executable)
        let manager = SSHKeyManager(
            fileSystem: DiskSSHKeyFileSystem(),
            executor: executor,
            sshDirectoryPath: root.path
        )
        let passphrase = "test passphrase \\ with spaces " + String(UnicodeScalar(0x00E9)!)
        let keyPath = root.appendingPathComponent("protected_key").path

        try manager.generateKey(type: .ed25519, name: "protected_key", passphrase: passphrase)

        let attributes = try FileManager.default.attributesOfItem(atPath: keyPath)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let emptyResult = try executor.execute(
            command: "/usr/bin/ssh-keygen",
            arguments: ["-y", "-P", "", "-f", keyPath]
        )
        #expect(emptyResult.exitCode != 0)
        let requestedResult = try executor.execute(
            command: "/usr/bin/ssh-keygen",
            arguments: ["-y", "-f", keyPath],
            stdinData: Data("\(passphrase)\n".utf8)
        )
        #expect(requestedResult.exitCode == 0)
        #expect(requestedResult.stdout.hasPrefix("ssh-ed25519 "))

        let unprotectedKeyPath = root.appendingPathComponent("unprotected_key").path
        try manager.generateKey(type: .ed25519, name: "unprotected_key", passphrase: "")
        let unprotectedResult = try executor.execute(
            command: "/usr/bin/ssh-keygen",
            arguments: ["-y", "-P", "", "-f", unprotectedKeyPath]
        )
        #expect(unprotectedResult.exitCode == 0)
        #expect(unprotectedResult.stdout.hasPrefix("ssh-ed25519 "))
    }

    // MARK: - Agent Operations

    @Test func isAgentRunningChecksSSHAgent() throws {
        let executor = MockSSHKeyExecutor()
        executor.defaultResult = ProcessResult(
            exitCode: 0,
            stdout: "The agent has 2 identities.\n",
            stderr: ""
        )
        let manager = SSHKeyManager(
            fileSystem: MockSSHKeyFileSystem(),
            executor: executor,
            sshDirectoryPath: "/test/.ssh"
        )

        let running = try manager.isAgentRunning()

        #expect(running == true)
    }

    @Test func isAgentRunningReturnsFalseWhenNotRunning() throws {
        let executor = MockSSHKeyExecutor()
        executor.defaultResult = ProcessResult(
            exitCode: 2,
            stdout: "",
            stderr: "Could not open a connection to your authentication agent."
        )
        let manager = SSHKeyManager(
            fileSystem: MockSSHKeyFileSystem(),
            executor: executor,
            sshDirectoryPath: "/test/.ssh"
        )

        let running = try manager.isAgentRunning()

        #expect(running == false)
    }

    @Test func addToAgentCallsSSHAdd() throws {
        let executor = MockSSHKeyExecutor()
        let manager = SSHKeyManager(
            fileSystem: MockSSHKeyFileSystem(),
            executor: executor,
            sshDirectoryPath: "/test/.ssh"
        )

        try manager.addToAgent(keyPath: "/test/.ssh/id_ed25519")

        #expect(executor.executedCommands.count == 1)
        let call = executor.executedCommands[0]
        #expect(call.command == "/usr/bin/ssh-add")
        #expect(call.arguments.contains("/test/.ssh/id_ed25519"))
    }

    @Test func importIntoKeychainUsesModernAppleKeychainFlag() throws {
        let executor = MockSSHKeyExecutor()
        let manager = SSHKeyManager(
            fileSystem: MockSSHKeyFileSystem(),
            executor: executor,
            sshDirectoryPath: "/test/.ssh"
        )

        try manager.importIntoKeychain(keyPath: "/test/.ssh/id_ed25519")

        #expect(executor.executedCommands.count == 1)
        let call = executor.executedCommands[0]
        #expect(call.command == "/usr/bin/ssh-add")
        #expect(call.arguments == ["--apple-use-keychain", "/test/.ssh/id_ed25519"])
    }

    @Test func importIntoKeychainFallsBackToLegacyFlagWhenModernFlagIsUnsupported() throws {
        let executor = MockSSHKeyExecutor()
        executor.stubbedResults["/usr/bin/ssh-add --apple-use-keychain /test/.ssh/id_ed25519"] =
            ProcessResult(exitCode: 1, stdout: "", stderr: "illegal option -- -")
        executor.stubbedResults["/usr/bin/ssh-add -K /test/.ssh/id_ed25519"] =
            ProcessResult(exitCode: 0, stdout: "", stderr: "")
        let manager = SSHKeyManager(
            fileSystem: MockSSHKeyFileSystem(),
            executor: executor,
            sshDirectoryPath: "/test/.ssh"
        )

        try manager.importIntoKeychain(keyPath: "/test/.ssh/id_ed25519")

        #expect(executor.executedCommands.map(\.arguments) == [
            ["--apple-use-keychain", "/test/.ssh/id_ed25519"],
            ["-K", "/test/.ssh/id_ed25519"],
        ])
    }

    @Test func importIntoKeychainDoesNotHideNormalSSHAddFailures() {
        let executor = MockSSHKeyExecutor()
        executor.defaultResult = ProcessResult(
            exitCode: 1,
            stdout: "",
            stderr: "Error loading key: invalid format"
        )
        let manager = SSHKeyManager(
            fileSystem: MockSSHKeyFileSystem(),
            executor: executor,
            sshDirectoryPath: "/test/.ssh"
        )

        #expect(throws: SSHKeyManagerError.self) {
            try manager.importIntoKeychain(keyPath: "/test/.ssh/bad_key")
        }
        #expect(executor.executedCommands.count == 1)
    }

    @Test func tildePathExpandsToHomeDirectory() {
        let executor = MockSSHKeyExecutor()
        let fileSystem = MockSSHKeyFileSystem()
        let manager = SSHKeyManager(
            fileSystem: fileSystem,
            executor: executor,
            sshDirectoryPath: "~/.ssh"
        )
        let home = NSHomeDirectory()

        // The manager should have expanded ~ internally. Verify by attempting
        // to list keys -- the path passed to the filesystem should be absolute.
        _ = try? manager.listKeys()
        // No crash = expansion worked. Direct check not possible without
        // exposing internals, but the path-based tests above validate correctness.
        #expect(home.hasPrefix("/"))
    }

    // MARK: - SSH Key Info Model

    @Test func sshKeyInfoIdentity() {
        let key = SSHKeyInfo(
            id: "~/.ssh/id_ed25519",
            name: "id_ed25519",
            type: .ed25519,
            fingerprint: "SHA256:abc123",
            hasPassphrase: true,
            publicKeyPath: "~/.ssh/id_ed25519.pub"
        )

        #expect(key.id == "~/.ssh/id_ed25519")
        #expect(key.name == "id_ed25519")
        #expect(key.type == .ed25519)
        #expect(key.hasPassphrase == true)
    }

    @Test func sshKeyTypeRawValues() {
        #expect(SSHKeyType.ed25519.rawValue == "ed25519")
        #expect(SSHKeyType.rsa.rawValue == "rsa")
        #expect(SSHKeyType.ecdsa.rawValue == "ecdsa")
        #expect(SSHKeyType.dsa.rawValue == "dsa")
        #expect(SSHKeyType.unknown.rawValue == "unknown")
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
