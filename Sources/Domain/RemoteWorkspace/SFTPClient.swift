// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SFTPClient.swift - Wraps sftp commands for remote file operations.

import Foundation

// MARK: - SFTP Executor Protocol

/// Abstraction over sftp command execution for testability.
///
/// The production implementation pipes commands to the `sftp` binary
/// using the SSH ControlMaster socket path for connection reuse.
protocol SFTPExecutor: Sendable {

    /// Executes an SFTP command on a remote host.
    ///
    /// - Parameters:
    ///   - sftpCommand: The SFTP sub-command (e.g., "ls -la /tmp").
    ///   - host: The remote host in "user@host" format.
    ///   - controlPath: The SSH ControlMaster socket path.
    /// - Returns: The raw stdout output from sftp.
    func execute(
        sftpCommand: String,
        host: String,
        controlPath: String
    ) throws -> String
}

// MARK: - System SFTP Executor

/// Production implementation that pipes commands to `/usr/bin/sftp` in batch mode.
///
/// Uses the SSH ControlMaster socket for connection reuse, so the existing
/// SSH session is shared without re-authentication.
final class SystemSFTPExecutor: SFTPExecutor {

    func execute(
        sftpCommand: String,
        host: String,
        controlPath: String
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
        process.arguments = [
            "-b", "-",
            "-o", "ControlPath=\(controlPath)",
            host,
        ]

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        if let commandData = "\(sftpCommand)\nbye\n".data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(commandData)
        }
        stdinPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        let stdout = String(
            data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            throw SFTPClientError.commandFailed(stderr.isEmpty ? "sftp exited with code \(process.terminationStatus)" : stderr)
        }

        return stdout
    }
}

// MARK: - SFTP Errors

/// Errors that can occur during SFTP operations.
enum SFTPClientError: Error, Equatable {
    case commandFailed(String)
    case parseFailed(String)
    case transferFailed(String)
}

// MARK: - Remote File Entry

/// Represents a file or directory on a remote filesystem.
struct RemoteFileEntry: Identifiable, Sendable {

    /// Full path on the remote filesystem.
    let id: String

    /// File or directory name (last path component).
    let name: String

    /// Whether this entry is a directory.
    let isDirectory: Bool

    /// File size in bytes.
    let size: Int64

    /// Last modification date.
    let modifiedDate: Date

    /// POSIX permission string (e.g., "drwxr-xr-x").
    let permissions: String
}

// MARK: - Remote File Entry Parsing

extension RemoteFileEntry {

    /// Parses a file entry from `ls -la` output.
    ///
    /// Expected format:
    /// ```
    /// drwxr-xr-x    3 user group     4096 Jan 15 10:30 .config
    /// -rw-r--r--    1 user group     1234 Feb 20 14:22 README.md
    /// ```
    ///
    /// - Parameters:
    ///   - line: A single line of ls -la output.
    ///   - basePath: The directory being listed (used to build full paths).
    /// - Returns: A parsed file entry, or nil if the line cannot be parsed.
    static func parse(from line: String, basePath: String) -> RemoteFileEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Split into whitespace-separated components.
        let components = trimmed.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        // Minimum: permissions, links, owner, group, size, month, day, time, name
        guard components.count >= 9 else { return nil }

        let permissions = components[0]

        // Permissions must start with d, -, l, c, b, p, or s.
        let validPrefixes: Set<Character> = ["d", "-", "l", "c", "b", "p", "s"]
        guard let firstChar = permissions.first,
              validPrefixes.contains(firstChar) else {
            return nil
        }

        let isDirectory = permissions.hasPrefix("d")

        guard let size = Int64(components[4]) else { return nil }

        // Name is everything from component 8 onwards (handles names with spaces).
        let name = components[8...].joined(separator: " ")

        // Skip "." and ".." entries.
        guard name != "." && name != ".." else { return nil }

        // Build a rough modification date from month/day/time.
        let dateString = "\(components[5]) \(components[6]) \(components[7])"
        let modifiedDate = parseDate(dateString) ?? Date.distantPast

        let normalizedBase = basePath.hasSuffix("/") ? basePath : "\(basePath)/"
        let fullPath = "\(normalizedBase)\(name)"

        return RemoteFileEntry(
            id: fullPath,
            name: name,
            isDirectory: isDirectory,
            size: size,
            modifiedDate: modifiedDate,
            permissions: permissions
        )
    }

    /// Formatter for recent files: "Jan 15 10:30" style.
    private static let recentDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM dd HH:mm"
        return formatter
    }()

    /// Formatter for older files: "Jan 15 2024" style.
    private static let olderDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM dd yyyy"
        return formatter
    }()

    /// Attempts to parse a date from `ls -la` format ("Jan 15 10:30" or "Jan 15 2024").
    private static func parseDate(_ string: String) -> Date? {
        if let date = recentDateFormatter.date(from: string) {
            return date
        }
        return olderDateFormatter.date(from: string)
    }
}

// MARK: - SFTP Client

/// Wraps the `sftp` command for file operations on remote hosts.
///
/// Uses the SSH ControlMaster socket path from the connection profile
/// to reuse the existing SSH connection, avoiding re-authentication
/// for every file operation.
///
/// All operations are synchronous command executions against the sftp binary.
/// For large transfers, consider running them in a background task.
final class SFTPClient: Sendable {

    // MARK: - Properties

    private let executor: any SFTPExecutor

    // MARK: - Initialization

    init(executor: any SFTPExecutor) {
        self.executor = executor
    }

    // MARK: - Directory Listing

    /// Lists the contents of a remote directory.
    ///
    /// Runs `ls -la <path>` via sftp and parses the output into structured
    /// file entries.
    ///
    /// - Parameters:
    ///   - path: Absolute path on the remote filesystem.
    ///   - profile: The connection profile for the remote host.
    /// - Returns: Parsed file and directory entries.
    func listDirectory(
        path: String,
        on profile: RemoteConnectionProfile
    ) throws -> [RemoteFileEntry] {
        let output = try executor.execute(
            sftpCommand: "ls -la \(Self.sanitizePath(path))",
            host: sftpHost(for: profile),
            controlPath: profile.controlPath
        )

        return output
            .components(separatedBy: .newlines)
            .compactMap { RemoteFileEntry.parse(from: $0, basePath: path) }
    }

    // MARK: - Download

    /// Downloads a file from the remote host to the local filesystem.
    ///
    /// - Parameters:
    ///   - remotePath: Absolute path of the file on the remote host.
    ///   - localPath: Local filesystem path to save the downloaded file.
    ///   - profile: The connection profile for the remote host.
    func download(
        remotePath: String,
        localPath: String,
        on profile: RemoteConnectionProfile
    ) throws {
        _ = try executor.execute(
            sftpCommand: "get \(Self.sanitizePath(remotePath)) \(Self.sanitizePath(localPath))",
            host: sftpHost(for: profile),
            controlPath: profile.controlPath
        )
    }

    // MARK: - Upload

    /// Uploads a local file to the remote host.
    ///
    /// - Parameters:
    ///   - localPath: Path to the local file to upload.
    ///   - remotePath: Destination path on the remote host.
    ///   - profile: The connection profile for the remote host.
    func upload(
        localPath: String,
        remotePath: String,
        on profile: RemoteConnectionProfile
    ) throws {
        _ = try executor.execute(
            sftpCommand: "put \(Self.sanitizePath(localPath)) \(Self.sanitizePath(remotePath))",
            host: sftpHost(for: profile),
            controlPath: profile.controlPath
        )
    }

    // MARK: - Directory Creation

    /// Creates a directory on the remote host.
    ///
    /// - Parameters:
    ///   - path: Absolute path of the directory to create.
    ///   - profile: The connection profile for the remote host.
    func mkdir(
        path: String,
        on profile: RemoteConnectionProfile
    ) throws {
        _ = try executor.execute(
            sftpCommand: "mkdir \(Self.sanitizePath(path))",
            host: sftpHost(for: profile),
            controlPath: profile.controlPath
        )
    }

    // MARK: - File Removal

    /// Removes a file on the remote host.
    ///
    /// - Parameters:
    ///   - path: Absolute path of the file to remove.
    ///   - profile: The connection profile for the remote host.
    func remove(
        path: String,
        on profile: RemoteConnectionProfile
    ) throws {
        _ = try executor.execute(
            sftpCommand: "rm \(Self.sanitizePath(path))",
            host: sftpHost(for: profile),
            controlPath: profile.controlPath
        )
    }

    // MARK: - Helpers

    /// Builds the sftp host string from a profile: "user@host" or just "host".
    private func sftpHost(for profile: RemoteConnectionProfile) -> String {
        if let user = profile.user {
            return "\(user)@\(profile.host)"
        }
        return profile.host
    }

    /// Wraps a path in single quotes with proper escaping to prevent command injection.
    ///
    /// Any embedded single quotes are replaced with the sequence `'\''` which
    /// terminates the current quoted string, inserts a literal single quote
    /// via backslash escaping, then reopens the quoted string.
    static func sanitizePath(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
