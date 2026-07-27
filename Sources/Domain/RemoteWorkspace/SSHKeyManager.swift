// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SSHKeyManager.swift - Lists and manages SSH keys.

import Foundation

// MARK: - SSH Key Type

/// The cryptographic algorithm of an SSH key pair.
enum SSHKeyType: String, Codable, Sendable, CaseIterable {
    case ed25519
    case rsa
    case ecdsa
    case dsa
    case unknown

    /// Detects the key type from a file name or path.
    ///
    /// Inspects the file name for standard SSH key naming conventions
    /// (e.g., `id_ed25519`, `id_rsa`).
    static func detect(from fileName: String) -> SSHKeyType {
        let name = (fileName as NSString).lastPathComponent.lowercased()
        if name.contains("ed25519") { return .ed25519 }
        if name.contains("ecdsa") { return .ecdsa }
        if name.contains("dsa") && !name.contains("ecdsa") { return .dsa }
        if name.contains("rsa") { return .rsa }
        return .unknown
    }
}

// MARK: - SSH Key Info

/// Information about a discovered SSH key on the local filesystem.
struct SSHKeyInfo: Identifiable, Sendable {

    /// Unique identity: the full path to the private key.
    let id: String

    /// Human-readable name (file name without path).
    let name: String

    /// Cryptographic algorithm.
    let type: SSHKeyType

    /// SHA256 fingerprint of the key.
    let fingerprint: String

    /// Whether the key is protected by a passphrase.
    let hasPassphrase: Bool

    /// Path to the corresponding public key, if it exists.
    let publicKeyPath: String?
}

// MARK: - Key Manager Errors

/// Errors that can occur during SSH key operations.
enum SSHKeyManagerError: Error, Equatable {
    case keyNotFound(String)
    case fingerprintFailed(String)
    case invalidKeyName(String)
    case keyAlreadyExists(String)
    case unsupportedPassphrase
    case passphraseTooLong(maximumBytes: Int)
    case generationFailed(String)
    case agentError(String)
    case keychainImportFailed(String)
}

extension SSHKeyManagerError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .keyNotFound(let path):
            return "SSH key not found: \(path)"
        case .fingerprintFailed(let message):
            return "Could not read SSH key fingerprint: \(message)"
        case .invalidKeyName(let name):
            return "Invalid SSH key name: \(name)"
        case .keyAlreadyExists(let path):
            return "An SSH key already exists at \(path)."
        case .unsupportedPassphrase:
            return "SSH key passphrases cannot contain null bytes, newlines, or carriage returns."
        case .passphraseTooLong(let maximumBytes):
            return "SSH key passphrases cannot exceed \(maximumBytes) UTF-8 bytes."
        case .generationFailed(let message):
            return "Could not generate SSH key: \(message)"
        case .agentError(let message):
            return "Could not add SSH key to agent: \(message)"
        case .keychainImportFailed(let message):
            return "Could not import SSH key into macOS Keychain: \(message)"
        }
    }
}

// MARK: - Key Executor Protocol

/// Abstraction over process execution for SSH key operations.
protocol SSHKeyExecuting: Sendable {
    func execute(command: String, arguments: [String]) throws -> ProcessResult
    func execute(command: String, arguments: [String], stdinData: Data) throws -> ProcessResult
}

enum SSHAskpassContract {
    static let environmentKey = "COCXY_SSH_ASKPASS"
    static let environmentValue = "1"
    static let maximumPassphraseBytes = 4_096
}

// MARK: - Key File System Protocol

/// Abstraction over filesystem for SSH key discovery.
protocol SSHKeyFileSystem: Sendable {
    func listDirectory(at path: String) throws -> [String]
    func fileExists(at path: String) -> Bool
    func createDirectory(at path: String) throws
    func removeFile(at path: String) throws
}

// MARK: - SSH Key Manager

/// Lists, inspects, and generates SSH keys.
///
/// Scans `~/.ssh/` for private key files that have a corresponding `.pub`
/// file, then uses `ssh-keygen` to extract fingerprints and key metadata.
///
/// All filesystem and process interactions are abstracted behind protocols
/// for testability.
final class SSHKeyManager: Sendable {

    // MARK: - Properties

    private let fileSystem: any SSHKeyFileSystem
    private let executor: any SSHKeyExecuting
    private let sshDirectoryPath: String

    /// Files that are never SSH keys, regardless of naming.
    private static let excludedFiles: Set<String> = [
        "known_hosts", "known_hosts.old",
        "config", "authorized_keys",
        "environment",
    ]

    // MARK: - Initialization

    init(
        fileSystem: any SSHKeyFileSystem,
        executor: any SSHKeyExecuting,
        sshDirectoryPath: String = "~/.ssh"
    ) {
        self.fileSystem = fileSystem
        self.executor = executor

        // Expand ~ to the absolute home directory path so that
        // filesystem operations resolve correctly at runtime.
        if sshDirectoryPath.hasPrefix("~") {
            self.sshDirectoryPath = sshDirectoryPath
                .replacingOccurrences(
                    of: "~",
                    with: NSHomeDirectory(),
                    range: sshDirectoryPath.startIndex..<sshDirectoryPath.index(
                        sshDirectoryPath.startIndex, offsetBy: 1
                    )
                )
        } else {
            self.sshDirectoryPath = sshDirectoryPath
        }
    }

    // MARK: - List Keys

    /// Scans the SSH directory for key pairs.
    ///
    /// A file is considered a private key if:
    /// 1. It is not in the excluded files list.
    /// 2. It does not end with `.pub`.
    /// 3. A corresponding `.pub` file exists.
    ///
    /// - Returns: Information about each discovered key pair.
    func listKeys() throws -> [SSHKeyInfo] {
        let allFiles: [String]
        do {
            allFiles = try fileSystem.listDirectory(at: sshDirectoryPath)
        } catch {
            return []
        }

        let publicKeyNames = Set(allFiles.filter { $0.hasSuffix(".pub") })

        return allFiles
            .filter { fileName in
                !fileName.hasSuffix(".pub")
                    && !Self.excludedFiles.contains(fileName)
                    && publicKeyNames.contains("\(fileName).pub")
            }
            .compactMap { fileName -> SSHKeyInfo? in
                let privatePath = "\(sshDirectoryPath)/\(fileName)"
                let publicPath = "\(sshDirectoryPath)/\(fileName).pub"
                let keyType = SSHKeyType.detect(from: fileName)

                let fingerprintValue: String
                do {
                    fingerprintValue = try fingerprint(at: privatePath)
                } catch {
                    fingerprintValue = ""
                }

                return SSHKeyInfo(
                    id: privatePath,
                    name: fileName,
                    type: keyType,
                    fingerprint: fingerprintValue,
                    hasPassphrase: false,
                    publicKeyPath: publicPath
                )
            }
    }

    // MARK: - Fingerprint

    /// Reads the SHA256 fingerprint of a key file.
    ///
    /// Runs `ssh-keygen -l -f <path>` and extracts the fingerprint hash
    /// from the output.
    ///
    /// - Parameter path: Path to the key file (private or public).
    /// - Returns: The fingerprint string (e.g., "SHA256:abc123...").
    func fingerprint(at path: String) throws -> String {
        let result = try executor.execute(
            command: "/usr/bin/ssh-keygen",
            arguments: ["-l", "-f", path]
        )

        guard result.exitCode == 0 else {
            throw SSHKeyManagerError.fingerprintFailed(result.stderr)
        }

        return parseFingerprint(from: result.stdout)
    }

    // MARK: - Generate Key

    /// Generates a new SSH key pair.
    ///
    /// Passes the passphrase through the executor's private credential channel
    /// instead of command-line arguments, then verifies the resulting key.
    ///
    /// - Parameters:
    ///   - type: The cryptographic algorithm to use.
    ///   - name: The file name for the new key (stored in the SSH directory).
    ///   - passphrase: The passphrase to protect the key (empty string for none).
    func generateKey(type: SSHKeyType, name: String, passphrase: String) throws {
        guard Self.isValidKeyName(name) else {
            throw SSHKeyManagerError.invalidKeyName(name)
        }
        guard !passphrase.unicodeScalars.contains(where: { scalar in
            scalar.value == 0 || scalar.value == 10 || scalar.value == 13
        }) else {
            throw SSHKeyManagerError.unsupportedPassphrase
        }
        guard passphrase.utf8.count <= SSHAskpassContract.maximumPassphraseBytes else {
            throw SSHKeyManagerError.passphraseTooLong(
                maximumBytes: SSHAskpassContract.maximumPassphraseBytes
            )
        }

        let keyPath = "\(sshDirectoryPath)/\(name)"
        let publicKeyPath = "\(keyPath).pub"
        try fileSystem.createDirectory(at: sshDirectoryPath)
        guard !fileSystem.fileExists(at: keyPath),
              !fileSystem.fileExists(at: publicKeyPath) else {
            throw SSHKeyManagerError.keyAlreadyExists(keyPath)
        }

        var generationSucceeded = false
        defer {
            if !generationSucceeded {
                try? fileSystem.removeFile(at: keyPath)
                try? fileSystem.removeFile(at: publicKeyPath)
            }
        }

        let stdinData = Data("\(passphrase)\n\(passphrase)\n".utf8)

        let result = try executor.execute(
            command: "/usr/bin/ssh-keygen",
            arguments: ["-q", "-t", type.rawValue, "-f", keyPath],
            stdinData: stdinData
        )

        guard result.exitCode == 0 else {
            throw SSHKeyManagerError.generationFailed(result.stderr)
        }

        try verifyGeneratedKey(at: keyPath, passphrase: passphrase)
        generationSucceeded = true
    }

    // MARK: - Agent Operations

    /// Checks whether the SSH agent is running and accessible.
    ///
    /// Runs `ssh-add -l` and checks the exit code. Exit code 0 or 1 means
    /// the agent is running (1 = running but no identities loaded).
    func isAgentRunning() throws -> Bool {
        let result = try executor.execute(
            command: "/usr/bin/ssh-add",
            arguments: ["-l"]
        )
        // Exit code 0: agent running with keys.
        // Exit code 1: agent running, no keys loaded.
        // Exit code 2: agent not running.
        return result.exitCode == 0 || result.exitCode == 1
    }

    /// Adds a key to the SSH agent.
    ///
    /// Runs `ssh-add <keyPath>`.
    func addToAgent(keyPath: String) throws {
        let result = try executor.execute(
            command: "/usr/bin/ssh-add",
            arguments: [keyPath]
        )

        guard result.exitCode == 0 else {
            throw SSHKeyManagerError.agentError(result.stderr)
        }
    }

    /// Imports a private key into the macOS OpenSSH Keychain integration.
    ///
    /// Modern macOS OpenSSH uses `--apple-use-keychain`; older builds used
    /// `-K`. The legacy flag is attempted only when the modern flag is not
    /// recognized so normal SSH errors are not hidden by a fallback path.
    func importIntoKeychain(keyPath: String) throws {
        let result = try executor.execute(
            command: "/usr/bin/ssh-add",
            arguments: ["--apple-use-keychain", keyPath]
        )

        guard result.exitCode != 0 else { return }

        guard Self.shouldRetryLegacyKeychainFlag(for: result) else {
            throw SSHKeyManagerError.keychainImportFailed(result.stderr)
        }

        let legacyResult = try executor.execute(
            command: "/usr/bin/ssh-add",
            arguments: ["-K", keyPath]
        )
        guard legacyResult.exitCode == 0 else {
            throw SSHKeyManagerError.keychainImportFailed(legacyResult.stderr)
        }
    }

    // MARK: - Parsing

    /// Extracts the SHA256 hash from ssh-keygen output.
    ///
    /// Input format: "256 SHA256:abc123... user@host (ED25519)"
    /// Extracted: "SHA256:abc123..."
    private func parseFingerprint(from output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.components(separatedBy: " ")

        guard components.count >= 2 else { return trimmed }

        let fingerprintComponent = components[1]
        if fingerprintComponent.hasPrefix("SHA256:") || fingerprintComponent.hasPrefix("MD5:") {
            return fingerprintComponent
        }

        return trimmed
    }

    private static func shouldRetryLegacyKeychainFlag(for result: ProcessResult) -> Bool {
        let message = "\(result.stdout)\n\(result.stderr)".lowercased()
        return message.contains("illegal option")
            || message.contains("unknown option")
            || message.contains("unrecognized option")
    }

    private func verifyGeneratedKey(at keyPath: String, passphrase: String) throws {
        let emptyPassphraseResult = try executor.execute(
            command: "/usr/bin/ssh-keygen",
            arguments: ["-y", "-P", "", "-f", keyPath]
        )

        if passphrase.isEmpty {
            guard emptyPassphraseResult.exitCode == 0 else {
                throw SSHKeyManagerError.generationFailed(
                    "The generated private key could not be verified with an empty passphrase."
                )
            }
            return
        }

        guard emptyPassphraseResult.exitCode != 0 else {
            throw SSHKeyManagerError.generationFailed(
                "The generated private key is not protected by the requested passphrase."
            )
        }

        let requestedPassphraseResult = try executor.execute(
            command: "/usr/bin/ssh-keygen",
            arguments: ["-y", "-f", keyPath],
            stdinData: Data("\(passphrase)\n".utf8)
        )
        guard requestedPassphraseResult.exitCode == 0 else {
            throw SSHKeyManagerError.generationFailed(
                "The generated private key did not accept the requested passphrase."
            )
        }
    }

    private static func isValidKeyName(_ name: String) -> Bool {
        guard (1...128).contains(name.utf8.count),
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            return false
        }
        return (name as NSString).lastPathComponent == name
    }
}
