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
    case generationFailed(String)
    case agentError(String)
}

// MARK: - Key Executor Protocol

/// Abstraction over process execution for SSH key operations.
protocol SSHKeyExecuting: Sendable {
    func execute(command: String, arguments: [String]) throws -> ProcessResult
    func execute(command: String, arguments: [String], stdinData: Data) throws -> ProcessResult
}

extension SSHKeyExecuting {
    /// Default implementation that ignores stdin, for backward compatibility.
    func execute(command: String, arguments: [String], stdinData: Data) throws -> ProcessResult {
        try execute(command: command, arguments: arguments)
    }
}

// MARK: - Key File System Protocol

/// Abstraction over filesystem for SSH key discovery.
protocol SSHKeyFileSystem: Sendable {
    func listDirectory(at path: String) throws -> [String]
    func fileExists(at path: String) -> Bool
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
    /// Passes the passphrase via stdin pipe instead of command-line arguments
    /// to prevent it from appearing in process listings (`ps`).
    /// The `-N` flag reads from stdin when given an empty string argument
    /// combined with piped input.
    ///
    /// - Parameters:
    ///   - type: The cryptographic algorithm to use.
    ///   - name: The file name for the new key (stored in the SSH directory).
    ///   - passphrase: The passphrase to protect the key (empty string for none).
    func generateKey(type: SSHKeyType, name: String, passphrase: String) throws {
        let keyPath = "\(sshDirectoryPath)/\(name)"

        // ssh-keygen expects the passphrase twice (passphrase + confirmation)
        // when reading from stdin. We provide both separated by a newline.
        let stdinContent = "\(passphrase)\n\(passphrase)\n"
        guard let stdinData = stdinContent.data(using: .utf8) else {
            throw SSHKeyManagerError.generationFailed("Failed to encode passphrase")
        }

        let result = try executor.execute(
            command: "/usr/bin/ssh-keygen",
            arguments: ["-t", type.rawValue, "-f", keyPath],
            stdinData: stdinData
        )

        guard result.exitCode == 0 else {
            throw SSHKeyManagerError.generationFailed(result.stderr)
        }
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
}
