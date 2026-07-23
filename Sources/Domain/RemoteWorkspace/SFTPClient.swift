// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SFTPClient.swift - Wraps sftp commands for remote file operations.

import Darwin
import CryptoKit
import Foundation

private enum SFTPBatchCommandBoundary {
    static let maximumByteCount = 2_000

    static func contains(_ command: String) -> Bool {
        !command.isEmpty
            && command.utf8.count <= maximumByteCount
            && !command.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

// MARK: - Active Connection Authorization

private final class SFTPConnectionAuthority: @unchecked Sendable {
    private let lock = NSLock()
    private var isActive = true
    private let verifier: @Sendable () throws -> Void

    init(verifier: @escaping @Sendable () throws -> Void) {
        self.verifier = verifier
    }

    func verify() throws {
        lock.lock()
        let activeBeforeVerification = isActive
        lock.unlock()
        guard activeBeforeVerification else { throw SFTPClientError.notConnected }
        do {
            try verifier()
        } catch {
            throw SFTPClientError.notConnected
        }
        lock.lock()
        let activeAfterVerification = isActive
        lock.unlock()
        guard activeAfterVerification else { throw SFTPClientError.notConnected }
    }

    func revoke() {
        lock.lock()
        isActive = false
        lock.unlock()
    }

    var isRevoked: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isActive
    }
}

struct SFTPConnectionAuthorization: Sendable {
    let profileID: UUID
    let connectionLeaseID: UUID
    let destination: SSHConnectionDestination
    let port: Int?
    let controlPath: String
    let controlMasterIdentity: SSHControlMasterIdentity
    let controlSocketAttestation: SSHControlSocketAttestation
    private let authority: SFTPConnectionAuthority

    init(
        profile: RemoteConnectionProfile,
        connectionLeaseID: UUID,
        controlMasterIdentity: SSHControlMasterIdentity,
        controlSocketAttestation: SSHControlSocketAttestation,
        verifier: @escaping @Sendable () throws -> Void
    ) throws {
        guard profile.port.map({ (1...65_535).contains($0) }) ?? true else {
            throw SFTPClientError.invalidPort
        }
        guard controlMasterIdentity.processID > 1,
              controlMasterIdentity.supervisorID != nil,
              controlMasterIdentity.controlPath == profile.controlPath,
              controlMasterIdentity.controlPath.first == "/",
              controlMasterIdentity.controlPath.utf8.count < 104,
              !controlMasterIdentity.controlPath.unicodeScalars.contains(
                  where: CharacterSet.controlCharacters.contains
              ),
              controlSocketAttestation.peerProcessID == controlMasterIdentity.processID,
              controlSocketAttestation.device != 0,
              controlSocketAttestation.inode != 0 else {
            throw SFTPClientError.notConnected
        }
        let destination: SSHConnectionDestination
        do {
            destination = try SSHConnectionDestination(user: profile.user, host: profile.host)
        } catch {
            throw SFTPClientError.invalidDestination
        }
        self.profileID = profile.id
        self.connectionLeaseID = connectionLeaseID
        self.destination = destination
        self.port = profile.port
        self.controlPath = controlMasterIdentity.controlPath
        self.controlMasterIdentity = controlMasterIdentity
        self.controlSocketAttestation = controlSocketAttestation
        self.authority = SFTPConnectionAuthority(verifier: verifier)
    }

    func verify() throws {
        try authority.verify()
    }

    func revoke() {
        authority.revoke()
    }

    var isRevoked: Bool {
        authority.isRevoked
    }
}

struct SFTPConnectionScope: Hashable, Sendable {
    let profileID: UUID
    let connectionLeaseID: UUID
}

// MARK: - SFTP Executor Protocol

/// Abstraction over sftp command execution for testability.
///
/// The production implementation pipes commands to the `sftp` binary and
/// opens its subsystem through Cocxy's descriptor-attested MUX helper.
protocol SFTPExecutor: Sendable {

    /// Executes an SFTP command on a remote host.
    ///
    /// - Parameters:
    ///   - sftpCommand: The SFTP sub-command (e.g., "ls -la /tmp").
    ///   - destination: A validated remote SSH destination.
    ///   - port: The explicit SSH port, if configured.
    ///   - controlPath: The SSH ControlMaster socket path.
    /// - Returns: The raw stdout output from sftp.
    func execute(
        sftpCommand: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> String

    /// Executes a bounded compensating command after task cancellation.
    /// Connection revocation remains authoritative and still cancels recovery.
    func executeRecovery(
        sftpCommand: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> String

    func directoryListing(
        path: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> SFTPDirectoryListingOutput

    /// Performs a bounded listing used only to reconcile an interrupted mutation.
    /// UI task cancellation is ignored; authorization revocation remains authoritative.
    func directoryListingRecovery(
        path: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> SFTPDirectoryListingOutput
}

struct SFTPDirectoryListingOutput: Sendable {
    let canonicalNames: String?
    let longListing: String
}

private struct SFTPCommandNotDispatchedError: Error {
    let underlying: Error
}

private struct SFTPCommandDispatchIndeterminateError: Error {
    let underlying: Error
}

extension SFTPExecutor {
    func executeRecovery(
        sftpCommand: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> String {
        try execute(sftpCommand: sftpCommand, authorization: authorization)
    }

    func directoryListing(
        path: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> SFTPDirectoryListingOutput {
        SFTPDirectoryListingOutput(
            canonicalNames: nil,
            longListing: try execute(
                sftpCommand: "ls -la \(try SFTPClient.sanitizePath(path))",
                authorization: authorization
            )
        )
    }

    func directoryListingRecovery(
        path: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> SFTPDirectoryListingOutput {
        SFTPDirectoryListingOutput(
            canonicalNames: nil,
            longListing: try executeRecovery(
                sftpCommand: "ls -la \(try SFTPClient.sanitizePath(path))",
                authorization: authorization
            )
        )
    }
}

// MARK: - System SFTP Executor

struct SFTPProcessInvocation: Sendable {
    let executableURL: URL
    let arguments: [String]
    let workingDirectory: URL
    let environment: [String: String]
    let timeoutSeconds: TimeInterval
    let retainedBytesPerStream: Int
    let observesTaskCancellation: Bool
    let cancellationRequested: @Sendable () -> Bool
}

protocol SFTPProcessRunning: Sendable {
    func run(_ invocation: SFTPProcessInvocation) throws -> BoundedProcessResult
}

struct BoundedSFTPProcessRunner: SFTPProcessRunning {
    func run(_ invocation: SFTPProcessInvocation) throws -> BoundedProcessResult {
        try BoundedProcessRunner(
            maximumRetainedBytesPerStream: invocation.retainedBytesPerStream,
            observesTaskCancellation: invocation.observesTaskCancellation,
            externalCancellationRequested: invocation.cancellationRequested
        ).run(
            executableURL: invocation.executableURL,
            arguments: invocation.arguments,
            workingDirectory: invocation.workingDirectory,
            environment: invocation.environment,
            timeoutSeconds: invocation.timeoutSeconds,
            timeoutDiagnostic: "SFTP command timed out."
        )
    }
}

/// Production implementation that pipes commands to `/usr/bin/sftp` in batch mode.
///
/// Reuses the active SSH session through a helper that verifies the peer on
/// the connected Unix descriptor before requesting the SFTP subsystem.
final class SystemSFTPExecutor: SFTPExecutor, @unchecked Sendable {
    static let defaultTimeoutSeconds: TimeInterval = 30 * 60
    static let maximumRetainedBytesPerStream = 4 * 1_024 * 1_024

    private let executableURL: URL
    private let temporaryDirectory: URL
    private let sshProgramURL: URL
    private let fileManager: FileManager
    private let timeoutSeconds: TimeInterval
    private let retainedBytesPerStream: Int
    private let processRunner: any SFTPProcessRunning

    init(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/sftp"),
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        sshProgramURL: URL? = nil,
        fileManager: FileManager = .default,
        timeoutSeconds: TimeInterval = SystemSFTPExecutor.defaultTimeoutSeconds,
        retainedBytesPerStream: Int = SystemSFTPExecutor.maximumRetainedBytesPerStream,
        processRunner: any SFTPProcessRunning = BoundedSFTPProcessRunner()
    ) {
        self.executableURL = executableURL
        self.temporaryDirectory = temporaryDirectory
        self.sshProgramURL = sshProgramURL
            ?? Bundle.main.executableURL
            ?? URL(fileURLWithPath: CommandLine.arguments[0])
        self.fileManager = fileManager
        self.timeoutSeconds = timeoutSeconds
        self.retainedBytesPerStream = retainedBytesPerStream
        self.processRunner = processRunner
    }

    func execute(
        sftpCommand: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> String {
        try execute(
            sftpCommand: sftpCommand,
            authorization: authorization,
            observesTaskCancellation: true
        )
    }

    func executeRecovery(
        sftpCommand: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> String {
        try execute(
            sftpCommand: sftpCommand,
            authorization: authorization,
            observesTaskCancellation: false
        )
    }

    func directoryListing(
        path: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> SFTPDirectoryListingOutput {
        try directoryListing(
            path: path,
            authorization: authorization,
            observesTaskCancellation: true
        )
    }

    func directoryListingRecovery(
        path: String,
        authorization: SFTPConnectionAuthorization
    ) throws -> SFTPDirectoryListingOutput {
        try directoryListing(
            path: path,
            authorization: authorization,
            observesTaskCancellation: false
        )
    }

    private func directoryListing(
        path: String,
        authorization: SFTPConnectionAuthorization,
        observesTaskCancellation: Bool
    ) throws -> SFTPDirectoryListingOutput {
        let safePath = try SFTPClient.sanitizePath(path)
        let canonicalNames = try execute(
            sftpCommands: ["cd \(safePath)", "ls -1a"],
            authorization: authorization,
            observesTaskCancellation: observesTaskCancellation
        )
        let longListing = try execute(
            sftpCommands: ["cd \(safePath)", "ls -lan"],
            authorization: authorization,
            observesTaskCancellation: observesTaskCancellation
        )
        return SFTPDirectoryListingOutput(
            canonicalNames: canonicalNames,
            longListing: longListing
        )
    }

    private func execute(
        sftpCommand: String,
        authorization: SFTPConnectionAuthorization,
        observesTaskCancellation: Bool
    ) throws -> String {
        try execute(
            sftpCommands: [sftpCommand],
            authorization: authorization,
            observesTaskCancellation: observesTaskCancellation
        )
    }

    private func execute(
        sftpCommands: [String],
        authorization: SFTPConnectionAuthorization,
        observesTaskCancellation: Bool
    ) throws -> String {
        let batchDirectory = temporaryDirectory.appendingPathComponent(
            "cocxy-sftp-batch-\(UUID().uuidString)",
            isDirectory: true
        )
        let invocation: SFTPProcessInvocation
        do {
            guard !sftpCommands.isEmpty,
                  sftpCommands.allSatisfy(SFTPBatchCommandBoundary.contains),
                  sftpCommands.joined(separator: "\n").utf8.count
                    <= SFTPBatchCommandBoundary.maximumByteCount * 2 else {
                throw SFTPClientError.invalidCommand
            }
            guard sshProgramURL.isFileURL,
                  sshProgramURL.path.first == "/",
                  !sshProgramURL.path.unicodeScalars.contains(
                      where: CharacterSet.controlCharacters.contains
                  ),
                  fileManager.isExecutableFile(atPath: sshProgramURL.path) else {
                throw SFTPClientError.commandFailed(
                    "The verified SFTP session helper is unavailable."
                )
            }
            try authorization.verify()
            try fileManager.createDirectory(
                at: batchDirectory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )

            let batchFile = batchDirectory.appendingPathComponent("commands.sftp")
            let batch = (sftpCommands + ["bye"]).joined(separator: "\n") + "\n"
            try Data(batch.utf8).write(to: batchFile, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: batchFile.path
            )

            var environment = SFTPMuxSessionContract.environment(
                authorization: authorization
            )
            environment["LC_ALL"] = "C"
            environment["LANG"] = "C"
            invocation = SFTPProcessInvocation(
                executableURL: executableURL,
                arguments: Self.arguments(
                    destination: authorization.destination,
                    port: authorization.port,
                    sshProgramPath: sshProgramURL.path,
                    batchFilePath: batchFile.path
                ),
                workingDirectory: batchDirectory,
                environment: environment,
                timeoutSeconds: timeoutSeconds,
                retainedBytesPerStream: retainedBytesPerStream,
                observesTaskCancellation: observesTaskCancellation,
                cancellationRequested: { authorization.isRevoked }
            )
        } catch {
            try? fileManager.removeItem(at: batchDirectory)
            throw SFTPCommandNotDispatchedError(underlying: error)
        }
        defer { try? fileManager.removeItem(at: batchDirectory) }
        let result: BoundedProcessResult
        do {
            result = try processRunner.run(invocation)
        } catch {
            if error is CancellationError, authorization.isRevoked {
                throw SFTPClientError.notConnected
            }
            throw error
        }
        guard !result.stdoutWasTruncated, !result.stderrWasTruncated else {
            throw SFTPClientError.commandFailed("SFTP output exceeded the safe limit.")
        }
        guard result.exitCode == 0 else {
            throw SFTPClientError.commandFailed(
                result.stderr.isEmpty
                    ? "sftp exited with code \(result.exitCode)"
                    : result.stderr
            )
        }

        return result.stdout
    }

    static func arguments(
        destination: SSHConnectionDestination,
        port: Int?,
        sshProgramPath: String,
        batchFilePath: String = "-"
    ) -> [String] {
        var arguments = [
            "-b", batchFilePath,
            "-o", "BatchMode=yes",
            "-o", "NumberOfPasswordPrompts=0",
            "-o", "ConnectionAttempts=1",
            "-o", "ControlMaster=no",
            "-o", "ControlPersist=no",
            "-o", "ProxyJump=none",
            "-o", "ProxyCommand=/usr/bin/false",
            "-S", sshProgramPath,
        ]
        if let port {
            arguments.append(contentsOf: ["-P", String(port)])
        }
        arguments.append(contentsOf: ["--", destination.sftpValue])
        return arguments
    }

}

// MARK: - SFTP Errors

/// Errors that can occur during SFTP operations.
enum SFTPClientError: Error, Equatable, LocalizedError, Sendable {
    case commandFailed(String)
    case parseFailed(String)
    case transferFailed(String)
    case notConnected
    case invalidDestination
    case invalidPort
    case invalidPath
    case invalidCommand
    case unsafeLocalSource
    case unsafeLocalDestination
    case destinationExists
    case localPublishFailed
    case remoteDestinationExists
    case remoteDestinationChanged
    case remoteDirectoryNotEmpty
    case unsafeRemoteDestination

    var errorDescription: String? {
        switch self {
        case .commandFailed(let detail), .parseFailed(let detail), .transferFailed(let detail):
            return detail
        case .notConnected:
            return "The active SSH connection is no longer available"
        case .invalidDestination:
            return "Invalid SFTP destination"
        case .invalidPort:
            return "Invalid SFTP port"
        case .invalidPath:
            return "Invalid SFTP path"
        case .invalidCommand:
            return "SFTP command exceeds the safe batch boundary"
        case .unsafeLocalSource:
            return "The local upload source is not a safe regular file"
        case .unsafeLocalDestination:
            return "The local download destination is not safe"
        case .destinationExists:
            return "A file already exists at the download destination"
        case .localPublishFailed:
            return "The downloaded file could not be published safely"
        case .remoteDestinationExists:
            return "An item already exists at the remote upload destination"
        case .remoteDestinationChanged:
            return "The remote item changed after it was reviewed"
        case .remoteDirectoryNotEmpty:
            return "Only an empty remote directory can be reviewed for removal"
        case .unsafeRemoteDestination:
            return "The remote upload destination is not a regular file"
        }
    }
}

enum SFTPUploadPostCommitIssue: Sendable, Equatable {
    case commitStatusUnconfirmed
    case remoteStagingRemovalUnconfirmed
    case remoteBackupIdentityChanged
    case remoteBackupVerificationFailed
    case remoteBackupRemovalUnconfirmed
    case connectionVerificationFailed
    case localSnapshotCleanupUnconfirmed
}

struct SFTPUploadRecoveryState: Sendable, Equatable {
    let destinationPath: String
    let stagedPayloadPath: String?
    let remoteBackupPath: String?
    let issues: [SFTPUploadPostCommitIssue]
    let localSnapshotURL: URL?

    init(
        destinationPath: String,
        stagedPayloadPath: String?,
        remoteBackupPath: String?,
        issues: [SFTPUploadPostCommitIssue],
        localSnapshotURL: URL? = nil
    ) {
        self.destinationPath = destinationPath
        self.stagedPayloadPath = stagedPayloadPath
        self.remoteBackupPath = remoteBackupPath
        self.issues = issues
        self.localSnapshotURL = localSnapshotURL
    }
}

enum SFTPUploadOutcome: Sendable, Equatable {
    case completed
    case notCommittedWithIssues(SFTPUploadRecoveryState)
    case committedWithIssues(SFTPUploadRecoveryState)
    case commitIndeterminate(SFTPUploadRecoveryState)
}

enum SFTPRemoteMutationIssue: Sendable, Equatable {
    case commitStatusUnconfirmed
    case restorationUnconfirmed
}

struct SFTPRemoteMutationRecoveryState: Sendable, Equatable {
    let targetPath: String
    let recoveryPath: String?
    let issues: [SFTPRemoteMutationIssue]
}

enum SFTPRemoteMutationOutcome: Sendable, Equatable {
    case completed
    case notCommittedWithIssues(SFTPRemoteMutationRecoveryState)
    case committedWithIssues(SFTPRemoteMutationRecoveryState)
    case commitIndeterminate(SFTPRemoteMutationRecoveryState)
}

enum SFTPDownloadPostPublishIssue: Sendable, Equatable {
    case destinationVerificationUnconfirmed
    case durabilityUnconfirmed
    case stagingCleanupUnconfirmed
}

struct SFTPDownloadRecoveryState: Sendable, Equatable {
    let destinationURL: URL
    let stagingDirectoryURL: URL?
    let issues: [SFTPDownloadPostPublishIssue]
}

enum SFTPDownloadOutcome: Sendable, Equatable {
    case completed
    case publishedWithIssues(SFTPDownloadRecoveryState)
}

private struct SFTPQuarantineIndeterminateError: Error {
    let quarantinePath: String
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

    /// Whether this entry is a symbolic link.
    let isSymbolicLink: Bool

    /// Display-only target reported by the remote long listing.
    let linkTarget: String?

    /// File size in bytes.
    let size: Int64

    /// Last modification date.
    let modifiedDate: Date

    /// POSIX permission string (e.g., "drwxr-xr-x").
    let permissions: String

    /// Extra tokens rendered by OpenSSH's long listing. These strengthen
    /// repeated-review comparisons but are not inode or generation identities.
    let listingLinkCountToken: String?
    let listingOwnerToken: String?
    let listingGroupToken: String?
    let listingModificationToken: String?

    var isRegularFile: Bool {
        permissions.hasPrefix("-") && !isDirectory && !isSymbolicLink
    }

    init(
        id: String,
        name: String,
        isDirectory: Bool,
        isSymbolicLink: Bool = false,
        linkTarget: String? = nil,
        size: Int64,
        modifiedDate: Date,
        permissions: String,
        listingLinkCountToken: String? = nil,
        listingOwnerToken: String? = nil,
        listingGroupToken: String? = nil,
        listingModificationToken: String? = nil
    ) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.isSymbolicLink = isSymbolicLink
        self.linkTarget = linkTarget
        self.size = size
        self.modifiedDate = modifiedDate
        self.permissions = permissions
        self.listingLinkCountToken = listingLinkCountToken
        self.listingOwnerToken = listingOwnerToken
        self.listingGroupToken = listingGroupToken
        self.listingModificationToken = listingModificationToken
    }
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
    static func parse(
        from line: String,
        basePath: String,
        canonicalName: String? = nil
    ) -> RemoteFileEntry? {
        let normalizedLine = line.last == "\r" ? String(line.dropLast()) : line
        guard let (metadata, rawName) = longListingFields(from: normalizedLine) else {
            return nil
        }
        let permissions = metadata[0]

        // Permissions must start with d, -, l, c, b, p, or s.
        let validPrefixes: Set<Character> = ["d", "-", "l", "c", "b", "p", "s"]
        guard let firstChar = permissions.first,
              validPrefixes.contains(firstChar) else {
            return nil
        }

        let isDirectory = permissions.hasPrefix("d")
        let isSymbolicLink = permissions.hasPrefix("l")

        guard let size = Int64(metadata[4]) else { return nil }

        let name: String
        let linkTarget: String?
        if isSymbolicLink, let canonicalName {
            name = canonicalName
            if rawName == canonicalName {
                linkTarget = nil
            } else {
                let targetPrefix = canonicalName + " -> "
                guard rawName.hasPrefix(targetPrefix) else { return nil }
                let target = String(rawName.dropFirst(targetPrefix.count))
                guard !target.isEmpty,
                      !target.unicodeScalars.contains(
                          where: CharacterSet.controlCharacters.contains
                      ) else { return nil }
                linkTarget = target
            }
        } else if isSymbolicLink {
            let fields = rawName.components(separatedBy: " -> ")
            if fields.count == 1 {
                name = rawName
                linkTarget = nil
            } else {
                guard fields.count == 2 else { return nil }
                name = fields[0]
                let target = fields[1]
                guard !target.isEmpty,
                      !target.unicodeScalars.contains(
                          where: CharacterSet.controlCharacters.contains
                      ) else { return nil }
                linkTarget = target
            }
        } else {
            name = rawName
            linkTarget = nil
        }

        guard isSafePathComponent(name) else { return nil }

        // Build a rough modification date from month/day/time.
        let dateString = "\(metadata[5]) \(metadata[6]) \(metadata[7])"
        let modifiedDate = parseDate(dateString) ?? Date.distantPast

        let fullPath = joinedPath(basePath: basePath, name: name)

        return RemoteFileEntry(
            id: fullPath,
            name: name,
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            linkTarget: linkTarget,
            size: size,
            modifiedDate: modifiedDate,
            permissions: permissions,
            listingLinkCountToken: metadata[1],
            listingOwnerToken: metadata[2],
            listingGroupToken: metadata[3],
            listingModificationToken: dateString
        )
    }

    static func isSafePathComponent(_ name: String) -> Bool {
        guard !name.isEmpty,
              name.utf8.count <= 1_024,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\\"),
              !name.contains("\u{FFFD}"),
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            return false
        }
        return (name as NSString).lastPathComponent == name
    }

    static func isDotEntryListingLine(_ line: String) -> Bool {
        let normalizedLine = line.last == "\r" ? String(line.dropLast()) : line
        guard let (_, rawName) = longListingFields(from: normalizedLine) else {
            return false
        }
        return rawName == "." || rawName == ".."
    }

    private static func longListingFields(
        from line: String
    ) -> (metadata: [String], name: String)? {
        var index = line.startIndex
        var metadata: [String] = []
        metadata.reserveCapacity(8)

        while index < line.endIndex, line[index].isWhitespace {
            index = line.index(after: index)
        }
        for fieldIndex in 0..<8 {
            guard index < line.endIndex else { return nil }
            let start = index
            while index < line.endIndex, !line[index].isWhitespace {
                index = line.index(after: index)
            }
            guard start < index else { return nil }
            metadata.append(String(line[start..<index]))
            if fieldIndex == 7 {
                guard index < line.endIndex, line[index].isWhitespace else {
                    return nil
                }
                index = line.index(after: index)
            } else {
                while index < line.endIndex, line[index].isWhitespace {
                    index = line.index(after: index)
                }
            }
        }
        guard index < line.endIndex else { return nil }
        return (metadata, String(line[index...]))
    }

    private static func joinedPath(basePath: String, name: String) -> String {
        if basePath == "/" { return "/\(name)" }
        if basePath.hasSuffix("/") { return "\(basePath)\(name)" }
        return "\(basePath)/\(name)"
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

enum SFTPUploadDestinationPolicy: Sendable {
    case overwrite
    case create
    case replace(SFTPReviewedRemoteEntry)
}

struct SFTPReviewedRemoteEntry: Sendable {
    enum Identity: Sendable {
        case regularFileSHA256(Data)
        case emptyDirectory
    }

    let entry: RemoteFileEntry
    fileprivate let profileID: UUID
    fileprivate let connectionLeaseID: UUID
    fileprivate let identity: Identity
}

struct SFTPLocalFileIdentity: Sendable, Equatable {
    let device: dev_t
    let inode: ino_t
    let size: off_t
    let mode: mode_t
    let linkCount: nlink_t
    let modificationSeconds: Int
    let modificationNanoseconds: Int
    let changeSeconds: Int
    let changeNanoseconds: Int

    static func capture(path: String) throws -> SFTPLocalFileIdentity {
        var status = stat()
        guard path.first == "/",
              lstat(path, &status) == 0,
              status.st_mode & S_IFMT == S_IFREG,
              status.st_nlink >= 1,
              status.st_size >= 0 else {
            throw SFTPClientError.unsafeLocalSource
        }
        return SFTPLocalFileIdentity(status: status)
    }

    fileprivate init(status: stat) {
        device = status.st_dev
        inode = status.st_ino
        size = status.st_size
        mode = status.st_mode
        linkCount = status.st_nlink
        modificationSeconds = status.st_mtimespec.tv_sec
        modificationNanoseconds = status.st_mtimespec.tv_nsec
        changeSeconds = status.st_ctimespec.tv_sec
        changeNanoseconds = status.st_ctimespec.tv_nsec
    }

    fileprivate func matches(_ status: stat) -> Bool {
        device == status.st_dev
            && inode == status.st_ino
            && size == status.st_size
            && mode == status.st_mode
            && linkCount == status.st_nlink
            && modificationSeconds == status.st_mtimespec.tv_sec
            && modificationNanoseconds == status.st_mtimespec.tv_nsec
            && changeSeconds == status.st_ctimespec.tv_sec
            && changeNanoseconds == status.st_ctimespec.tv_nsec
    }
}

private final class SFTPLocalUploadSnapshot {
    private static let payloadName = "payload"

    let payloadURL: URL
    var recoveryDirectoryURL: URL { payloadURL.deletingLastPathComponent() }
    private let parentDescriptor: Int32
    private let directoryDescriptor: Int32
    private let payloadDescriptor: Int32
    private let directoryName: String
    private let payloadIdentity: SFTPLocalFileIdentity
    private var cleaned = false

    private init(
        payloadURL: URL,
        parentDescriptor: Int32,
        directoryDescriptor: Int32,
        payloadDescriptor: Int32,
        directoryName: String,
        payloadIdentity: SFTPLocalFileIdentity
    ) {
        self.payloadURL = payloadURL
        self.parentDescriptor = parentDescriptor
        self.directoryDescriptor = directoryDescriptor
        self.payloadDescriptor = payloadDescriptor
        self.directoryName = directoryName
        self.payloadIdentity = payloadIdentity
    }

    deinit {
        try? cleanup()
        _ = Darwin.close(payloadDescriptor)
        _ = Darwin.close(directoryDescriptor)
        _ = Darwin.close(parentDescriptor)
    }

    static func create(
        sourcePath: String,
        expectedIdentity: SFTPLocalFileIdentity? = nil,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> SFTPLocalUploadSnapshot {
        guard sourcePath.first == "/",
              temporaryDirectory.isFileURL else {
            throw SFTPClientError.unsafeLocalSource
        }

        let parentURL = temporaryDirectory.standardizedFileURL
        let parentDescriptor = Darwin.open(
            parentURL.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard parentDescriptor >= 0 else {
            throw SFTPClientError.unsafeLocalSource
        }
        var keepParentDescriptor = false
        defer {
            if !keepParentDescriptor { _ = Darwin.close(parentDescriptor) }
        }

        var parentStatus = stat()
        guard fstat(parentDescriptor, &parentStatus) == 0,
              parentStatus.st_uid == geteuid(),
              parentStatus.st_mode & S_IFMT == S_IFDIR,
              parentStatus.st_mode & 0o022 == 0 else {
            throw SFTPClientError.unsafeLocalSource
        }

        let directoryName = ".cocxy-upload-\(UUID().uuidString.lowercased())"
        guard mkdirat(parentDescriptor, directoryName, S_IRWXU) == 0 else {
            throw SFTPClientError.unsafeLocalSource
        }
        var keepDirectory = false
        defer {
            if !keepDirectory {
                _ = unlinkat(
                    parentDescriptor,
                    "\(directoryName)/\(Self.payloadName)",
                    0
                )
                _ = unlinkat(parentDescriptor, directoryName, AT_REMOVEDIR)
            }
        }

        let directoryDescriptor = openat(
            parentDescriptor,
            directoryName,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard directoryDescriptor >= 0 else {
            throw SFTPClientError.unsafeLocalSource
        }
        var keepDirectoryDescriptor = false
        defer {
            if !keepDirectoryDescriptor { _ = Darwin.close(directoryDescriptor) }
        }

        var directoryStatus = stat()
        guard fstat(directoryDescriptor, &directoryStatus) == 0,
              directoryStatus.st_uid == geteuid(),
              directoryStatus.st_mode & S_IFMT == S_IFDIR,
              directoryStatus.st_mode & 0o777 == S_IRWXU else {
            throw SFTPClientError.unsafeLocalSource
        }

        let sourceDescriptor = Darwin.open(
            sourcePath,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        guard sourceDescriptor >= 0 else {
            throw SFTPClientError.unsafeLocalSource
        }
        defer { _ = Darwin.close(sourceDescriptor) }

        var sourceBefore = stat()
        guard fstat(sourceDescriptor, &sourceBefore) == 0,
              sourceBefore.st_mode & S_IFMT == S_IFREG,
              sourceBefore.st_nlink >= 1,
              sourceBefore.st_size >= 0,
              expectedIdentity?.matches(sourceBefore) ?? true else {
            throw SFTPClientError.unsafeLocalSource
        }
        let openedIdentity = SFTPLocalFileIdentity(status: sourceBefore)

        let payloadDescriptor = openat(
            directoryDescriptor,
            Self.payloadName,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard payloadDescriptor >= 0 else {
            throw SFTPClientError.unsafeLocalSource
        }
        var keepPayloadDescriptor = false
        defer {
            if !keepPayloadDescriptor { _ = Darwin.close(payloadDescriptor) }
        }

        var copiedBytes: off_t = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while true {
            let bytesRead = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(sourceDescriptor, bytes.baseAddress, bytes.count)
            }
            if bytesRead == 0 { break }
            if bytesRead < 0 {
                if errno == EINTR { continue }
                throw SFTPClientError.unsafeLocalSource
            }

            var offset = 0
            while offset < bytesRead {
                let bytesWritten = buffer.withUnsafeBytes { bytes in
                    Darwin.write(
                        payloadDescriptor,
                        bytes.baseAddress?.advanced(by: offset),
                        bytesRead - offset
                    )
                }
                if bytesWritten < 0 {
                    if errno == EINTR { continue }
                    throw SFTPClientError.unsafeLocalSource
                }
                guard bytesWritten > 0 else {
                    throw SFTPClientError.unsafeLocalSource
                }
                offset += bytesWritten
            }
            copiedBytes += off_t(bytesRead)
        }

        var sourceAfter = stat()
        var pathAfter = stat()
        guard fstat(sourceDescriptor, &sourceAfter) == 0,
              lstat(sourcePath, &pathAfter) == 0,
              copiedBytes == sourceBefore.st_size,
              openedIdentity.matches(sourceAfter),
              openedIdentity.matches(pathAfter),
              sourceAfter.st_mode & S_IFMT == S_IFREG,
              sourceAfter.st_nlink >= 1,
              fsync(payloadDescriptor) == 0 else {
            throw SFTPClientError.unsafeLocalSource
        }

        var payloadStatus = stat()
        guard fstat(payloadDescriptor, &payloadStatus) == 0,
              payloadStatus.st_uid == geteuid(),
              payloadStatus.st_mode & S_IFMT == S_IFREG,
              payloadStatus.st_mode & 0o777 == (S_IRUSR | S_IWUSR),
              payloadStatus.st_nlink == 1 else {
            throw SFTPClientError.unsafeLocalSource
        }

        let directoryURL = parentURL.appendingPathComponent(directoryName, isDirectory: true)
        let payloadIdentity = SFTPLocalFileIdentity(status: payloadStatus)
        keepParentDescriptor = true
        keepDirectoryDescriptor = true
        keepPayloadDescriptor = true
        keepDirectory = true
        return SFTPLocalUploadSnapshot(
            payloadURL: directoryURL.appendingPathComponent(Self.payloadName),
            parentDescriptor: parentDescriptor,
            directoryDescriptor: directoryDescriptor,
            payloadDescriptor: payloadDescriptor,
            directoryName: directoryName,
            payloadIdentity: payloadIdentity
        )
    }

    func verifyPathBinding() throws {
        var heldDirectory = stat()
        var parentEntry = stat()
        var absoluteDirectory = stat()
        let directoryURL = payloadURL.deletingLastPathComponent()
        guard fstat(directoryDescriptor, &heldDirectory) == 0,
              fstatat(
                  parentDescriptor,
                  directoryName,
                  &parentEntry,
                  AT_SYMLINK_NOFOLLOW
              ) == 0,
              lstat(directoryURL.path, &absoluteDirectory) == 0,
              heldDirectory.st_dev == parentEntry.st_dev,
              heldDirectory.st_ino == parentEntry.st_ino,
              heldDirectory.st_dev == absoluteDirectory.st_dev,
              heldDirectory.st_ino == absoluteDirectory.st_ino,
              heldDirectory.st_uid == geteuid(),
              heldDirectory.st_mode & S_IFMT == S_IFDIR,
              heldDirectory.st_mode & 0o777 == S_IRWXU else {
            throw SFTPClientError.unsafeLocalSource
        }

        var heldPayload = stat()
        var directoryEntry = stat()
        var absolutePayload = stat()
        guard fstat(payloadDescriptor, &heldPayload) == 0,
              fstatat(
                  directoryDescriptor,
                  Self.payloadName,
                  &directoryEntry,
                  AT_SYMLINK_NOFOLLOW
              ) == 0,
              lstat(payloadURL.path, &absolutePayload) == 0,
              payloadIdentity.matches(heldPayload),
              payloadIdentity.matches(directoryEntry),
              payloadIdentity.matches(absolutePayload),
              heldPayload.st_uid == geteuid(),
              heldPayload.st_mode & S_IFMT == S_IFREG,
              heldPayload.st_nlink == 1 else {
            throw SFTPClientError.unsafeLocalSource
        }
    }

    func cleanup() throws {
        guard !cleaned else { return }
        if unlinkat(directoryDescriptor, Self.payloadName, 0) != 0, errno != ENOENT {
            throw SFTPClientError.transferFailed("Upload snapshot cleanup failed.")
        }
        guard fsync(directoryDescriptor) == 0 else {
            throw SFTPClientError.transferFailed("Upload snapshot cleanup failed.")
        }
        if unlinkat(parentDescriptor, directoryName, AT_REMOVEDIR) != 0, errno != ENOENT {
            throw SFTPClientError.transferFailed("Upload snapshot cleanup failed.")
        }
        guard fsync(parentDescriptor) == 0 else {
            throw SFTPClientError.transferFailed("Upload snapshot cleanup failed.")
        }
        cleaned = true
    }
}

private final class SFTPLocalDownloadReservation {
    private static let payloadName = "payload"

    let payloadURL: URL
    private let destinationURL: URL
    private let stagingDirectoryURL: URL
    private let destinationName: String
    private let stagingName: String
    private let parentDescriptor: Int32
    private let stagingDescriptor: Int32
    private let payloadDescriptor: Int32
    private var downloadedIdentity: SFTPLocalFileIdentity?
    private var published = false
    private var cleaned = false

    init(destinationURL: URL) throws {
        let standardizedDestination = destinationURL.standardizedFileURL
        let parentURL = standardizedDestination.deletingLastPathComponent()
        let destinationName = standardizedDestination.lastPathComponent
        guard destinationURL.isFileURL,
              destinationURL.path == standardizedDestination.path,
              RemoteFileEntry.isSafePathComponent(destinationName) else {
            throw SFTPClientError.unsafeLocalDestination
        }

        let parentDescriptor = Darwin.open(
            parentURL.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard parentDescriptor >= 0 else {
            throw SFTPClientError.unsafeLocalDestination
        }
        var parentStatus = stat()
        guard fstat(parentDescriptor, &parentStatus) == 0,
              parentStatus.st_uid == geteuid(),
              parentStatus.st_mode & S_IFMT == S_IFDIR,
              parentStatus.st_mode & 0o022 == 0 else {
            _ = Darwin.close(parentDescriptor)
            throw SFTPClientError.unsafeLocalDestination
        }
        var destinationStatus = stat()
        if fstatat(
            parentDescriptor,
            destinationName,
            &destinationStatus,
            AT_SYMLINK_NOFOLLOW
        ) == 0 {
            _ = Darwin.close(parentDescriptor)
            throw SFTPClientError.destinationExists
        }
        guard errno == ENOENT else {
            _ = Darwin.close(parentDescriptor)
            throw SFTPClientError.unsafeLocalDestination
        }

        var stagingName: String?
        for _ in 0..<16 {
            let candidate = ".cocxy-download-\(UUID().uuidString.lowercased())"
            if mkdirat(parentDescriptor, candidate, S_IRWXU) == 0 {
                stagingName = candidate
                break
            }
            guard errno == EEXIST else {
                _ = Darwin.close(parentDescriptor)
                throw SFTPClientError.localPublishFailed
            }
        }
        guard let stagingName else {
            _ = Darwin.close(parentDescriptor)
            throw SFTPClientError.localPublishFailed
        }

        let stagingDescriptor = openat(
            parentDescriptor,
            stagingName,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard stagingDescriptor >= 0 else {
            _ = unlinkat(parentDescriptor, stagingName, AT_REMOVEDIR)
            _ = Darwin.close(parentDescriptor)
            throw SFTPClientError.localPublishFailed
        }
        var stagingStatus = stat()
        guard fstat(stagingDescriptor, &stagingStatus) == 0,
              stagingStatus.st_uid == geteuid(),
              stagingStatus.st_mode & S_IFMT == S_IFDIR,
              stagingStatus.st_mode & 0o777 == S_IRWXU else {
            _ = Darwin.close(stagingDescriptor)
            _ = unlinkat(parentDescriptor, stagingName, AT_REMOVEDIR)
            _ = Darwin.close(parentDescriptor)
            throw SFTPClientError.localPublishFailed
        }

        let payloadDescriptor = openat(
            stagingDescriptor,
            Self.payloadName,
            O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            S_IRUSR | S_IWUSR
        )
        guard payloadDescriptor >= 0 else {
            _ = Darwin.close(stagingDescriptor)
            _ = unlinkat(parentDescriptor, stagingName, AT_REMOVEDIR)
            _ = Darwin.close(parentDescriptor)
            throw SFTPClientError.localPublishFailed
        }
        var payloadStatus = stat()
        guard fstat(payloadDescriptor, &payloadStatus) == 0,
              payloadStatus.st_uid == geteuid(),
              payloadStatus.st_mode & S_IFMT == S_IFREG,
              payloadStatus.st_mode & 0o777 == (S_IRUSR | S_IWUSR),
              payloadStatus.st_nlink == 1 else {
            _ = Darwin.close(payloadDescriptor)
            _ = unlinkat(stagingDescriptor, Self.payloadName, 0)
            _ = Darwin.close(stagingDescriptor)
            _ = unlinkat(parentDescriptor, stagingName, AT_REMOVEDIR)
            _ = Darwin.close(parentDescriptor)
            throw SFTPClientError.localPublishFailed
        }

        self.destinationName = destinationName
        self.stagingName = stagingName
        self.parentDescriptor = parentDescriptor
        self.stagingDescriptor = stagingDescriptor
        self.payloadDescriptor = payloadDescriptor
        self.destinationURL = standardizedDestination
        self.stagingDirectoryURL = parentURL
            .appendingPathComponent(stagingName, isDirectory: true)
        self.payloadURL = stagingDirectoryURL
            .appendingPathComponent(Self.payloadName, isDirectory: false)
    }

    deinit {
        try? cleanup()
        _ = Darwin.close(payloadDescriptor)
        _ = Darwin.close(stagingDescriptor)
        _ = Darwin.close(parentDescriptor)
    }

    func verifyPayload(expectedByteCount: Int64) throws {
        guard expectedByteCount >= 0 else {
            throw SFTPClientError.remoteDestinationChanged
        }
        let identity = try verifiedPayloadIdentity()
        guard identity.size == off_t(expectedByteCount),
              fsync(payloadDescriptor) == 0 else {
            throw SFTPClientError.remoteDestinationChanged
        }
        downloadedIdentity = identity
    }

    func contentSHA256(
        observesTaskCancellation: Bool,
        cancellationRequested: () -> Bool
    ) throws -> Data {
        guard let downloadedIdentity else {
            throw SFTPClientError.localPublishFailed
        }
        _ = try verifiedPayloadIdentity(expectedIdentity: downloadedIdentity)
        var hasher = SHA256()
        var offset: off_t = 0
        var buffer = [UInt8](repeating: 0, count: 64 * 1_024)
        while offset < downloadedIdentity.size {
            if observesTaskCancellation, cancellationRequested() {
                throw CancellationError()
            }
            let requested = min(
                buffer.count,
                Int(downloadedIdentity.size - offset)
            )
            let count = buffer.withUnsafeMutableBytes { bytes in
                pread(payloadDescriptor, bytes.baseAddress, requested, offset)
            }
            if count < 0 {
                if errno == EINTR { continue }
                throw SFTPClientError.localPublishFailed
            }
            guard count > 0 else {
                throw SFTPClientError.localPublishFailed
            }
            hasher.update(data: Data(buffer.prefix(count)))
            offset += off_t(count)
        }
        _ = try verifiedPayloadIdentity(expectedIdentity: downloadedIdentity)
        return Data(hasher.finalize())
    }

    func publish() throws -> SFTPDownloadOutcome {
        guard !published, !cleaned,
              let downloadedIdentity else {
            throw SFTPClientError.localPublishFailed
        }
        let payloadIdentity = try verifiedPayloadIdentity(
            expectedIdentity: downloadedIdentity
        )
        guard
              fsync(payloadDescriptor) == 0 else {
            throw SFTPClientError.localPublishFailed
        }

        var destinationStatus = stat()
        if fstatat(
            parentDescriptor,
            destinationName,
            &destinationStatus,
            AT_SYMLINK_NOFOLLOW
        ) == 0 {
            throw SFTPClientError.destinationExists
        }
        guard errno == ENOENT else { throw SFTPClientError.localPublishFailed }
        guard renameatx_np(
            stagingDescriptor,
            Self.payloadName,
            parentDescriptor,
            destinationName,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            if errno == EEXIST { throw SFTPClientError.destinationExists }
            throw SFTPClientError.localPublishFailed
        }
        published = true
        var issues: [SFTPDownloadPostPublishIssue] = []
        var publishedStatus = stat()
        if fstatat(
            parentDescriptor,
            destinationName,
            &publishedStatus,
            AT_SYMLINK_NOFOLLOW
        ) != 0
            || publishedStatus.st_dev != payloadIdentity.device
            || publishedStatus.st_ino != payloadIdentity.inode
            || publishedStatus.st_size != payloadIdentity.size
            || publishedStatus.st_mode != payloadIdentity.mode
            || publishedStatus.st_nlink != payloadIdentity.linkCount
            || publishedStatus.st_mode & S_IFMT != S_IFREG {
            issues.append(.destinationVerificationUnconfirmed)
        }
        if fsync(parentDescriptor) != 0 {
            issues.append(.durabilityUnconfirmed)
        }
        if unlinkat(parentDescriptor, stagingName, AT_REMOVEDIR) == 0 || errno == ENOENT {
            cleaned = true
            if fsync(parentDescriptor) != 0,
               !issues.contains(.durabilityUnconfirmed) {
                issues.append(.durabilityUnconfirmed)
            }
        } else {
            issues.append(.stagingCleanupUnconfirmed)
        }
        guard !issues.isEmpty else { return .completed }
        return .publishedWithIssues(SFTPDownloadRecoveryState(
            destinationURL: destinationURL,
            stagingDirectoryURL: cleaned ? nil : stagingDirectoryURL,
            issues: issues
        ))
    }

    private func verifiedPayloadIdentity(
        expectedIdentity: SFTPLocalFileIdentity? = nil
    ) throws -> SFTPLocalFileIdentity {
        var heldDirectory = stat()
        var parentEntry = stat()
        var absoluteDirectory = stat()
        let directoryURL = payloadURL.deletingLastPathComponent()
        guard fstat(stagingDescriptor, &heldDirectory) == 0,
              fstatat(
                  parentDescriptor,
                  stagingName,
                  &parentEntry,
                  AT_SYMLINK_NOFOLLOW
              ) == 0,
              lstat(directoryURL.path, &absoluteDirectory) == 0,
              heldDirectory.st_dev == parentEntry.st_dev,
              heldDirectory.st_ino == parentEntry.st_ino,
              heldDirectory.st_dev == absoluteDirectory.st_dev,
              heldDirectory.st_ino == absoluteDirectory.st_ino,
              heldDirectory.st_uid == geteuid(),
              heldDirectory.st_mode & S_IFMT == S_IFDIR,
              heldDirectory.st_mode & 0o777 == S_IRWXU else {
            throw SFTPClientError.localPublishFailed
        }

        var heldPayload = stat()
        var directoryEntry = stat()
        var absolutePayload = stat()
        guard fstat(payloadDescriptor, &heldPayload) == 0,
              fstatat(
                  stagingDescriptor,
                  Self.payloadName,
                  &directoryEntry,
                  AT_SYMLINK_NOFOLLOW
              ) == 0,
              lstat(payloadURL.path, &absolutePayload) == 0 else {
            throw SFTPClientError.localPublishFailed
        }
        let identity = SFTPLocalFileIdentity(status: heldPayload)
        guard identity.matches(directoryEntry),
              identity.matches(absolutePayload),
              expectedIdentity?.matches(heldPayload) ?? true,
              heldPayload.st_uid == geteuid(),
              heldPayload.st_mode & S_IFMT == S_IFREG,
              heldPayload.st_mode & 0o777 == (S_IRUSR | S_IWUSR),
              heldPayload.st_nlink == 1 else {
            throw SFTPClientError.localPublishFailed
        }
        return identity
    }

    func cleanup() throws {
        guard !cleaned else { return }
        if unlinkat(stagingDescriptor, Self.payloadName, 0) != 0, errno != ENOENT {
            throw SFTPClientError.localPublishFailed
        }
        if unlinkat(parentDescriptor, stagingName, AT_REMOVEDIR) != 0, errno != ENOENT {
            throw SFTPClientError.localPublishFailed
        }
        guard fsync(parentDescriptor) == 0 else {
            throw SFTPClientError.localPublishFailed
        }
        cleaned = true
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
    private let authorization: SFTPConnectionAuthorization
    private let cancellationRequested: @Sendable () -> Bool

    var connectionScope: SFTPConnectionScope {
        SFTPConnectionScope(
            profileID: authorization.profileID,
            connectionLeaseID: authorization.connectionLeaseID
        )
    }

    // MARK: - Initialization

    init(
        executor: any SFTPExecutor,
        authorization: SFTPConnectionAuthorization,
        cancellationRequested: @escaping @Sendable () -> Bool = { Task.isCancelled }
    ) throws {
        self.executor = executor
        self.authorization = authorization
        self.cancellationRequested = cancellationRequested
        try authorization.verify()
    }

    // MARK: - Directory Listing

    /// Lists the contents of a remote directory.
    ///
    /// Runs `ls -la <path>` via sftp and parses the output into structured
    /// file entries.
    ///
    /// - Parameter path: Absolute path on the remote filesystem.
    /// - Returns: Parsed file and directory entries.
    func listDirectory(
        path: String
    ) throws -> [RemoteFileEntry] {
        try listDirectory(path: path, recovery: false)
    }

    private func listDirectory(
        path: String,
        recovery: Bool
    ) throws -> [RemoteFileEntry] {
        _ = try Self.sanitizePath(path)
        try authorization.verify()
        let output: SFTPDirectoryListingOutput
        do {
            output = if recovery {
                try executor.directoryListingRecovery(
                    path: path,
                    authorization: authorization
                )
            } else {
                try executor.directoryListing(
                    path: path,
                    authorization: authorization
                )
            }
        } catch let error as SFTPCommandNotDispatchedError {
            throw error.underlying
        }
        let canonicalNames = try output.canonicalNames.map(Self.parseCanonicalNames)
        let entries = try Self.parseLongListing(
            output.longListing,
            basePath: path,
            canonicalNames: canonicalNames
        )
        guard let canonicalNames else {
            return entries
        }
        guard canonicalNames.count == entries.count,
              zip(canonicalNames, entries).allSatisfy({ $0 == $1.name }) else {
            throw SFTPClientError.parseFailed(
                "The remote directory name and metadata listings did not match."
            )
        }
        return entries
    }

    func prepareReview(entry: RemoteFileEntry) throws -> SFTPReviewedRemoteEntry {
        guard !entry.isSymbolicLink,
              entry.isDirectory || entry.isRegularFile else {
            throw SFTPClientError.unsafeRemoteDestination
        }
        try Self.preflightReviewedEntryOperation(at: entry.id)
        try verifyReviewedEntry(entry, at: entry.id)
        let identity: SFTPReviewedRemoteEntry.Identity
        if entry.isRegularFile {
            identity = .regularFileSHA256(
                try remoteContentDigest(path: entry.id, expectedByteCount: entry.size)
            )
        } else {
            guard try listDirectory(path: entry.id).isEmpty else {
                throw SFTPClientError.remoteDirectoryNotEmpty
            }
            identity = .emptyDirectory
        }
        try verifyReviewedEntry(entry, at: entry.id)
        return SFTPReviewedRemoteEntry(
            entry: entry,
            profileID: authorization.profileID,
            connectionLeaseID: authorization.connectionLeaseID,
            identity: identity
        )
    }

    // MARK: - Download

    /// Downloads a file from the remote host to the local filesystem.
    ///
    /// - Parameters:
    ///   - remotePath: Absolute path of the file on the remote host.
    ///   - destinationURL: Local filesystem URL for the downloaded file.
    @discardableResult
    func download(
        remotePath: String,
        to destinationURL: URL
    ) throws -> SFTPDownloadOutcome {
        try Self.preflightReviewedEntryOperation(at: remotePath)
        let (parentPath, name) = try Self.remoteParentAndName(for: remotePath)
        guard let currentEntry = try listDirectory(path: parentPath).first(
            where: { $0.name == name }
        ) else {
            throw SFTPClientError.remoteDestinationChanged
        }
        return try download(entry: currentEntry, to: destinationURL)
    }

    @discardableResult
    func download(
        entry: RemoteFileEntry,
        to destinationURL: URL
    ) throws -> SFTPDownloadOutcome {
        guard entry.isRegularFile,
              !entry.isSymbolicLink else {
            throw SFTPClientError.unsafeRemoteDestination
        }
        try Self.preflightReviewedEntryOperation(at: entry.id)
        let reservation = try SFTPLocalDownloadReservation(destinationURL: destinationURL)
        do {
            let review = try prepareReview(entry: entry)
            guard case .regularFileSHA256(let expectedDigest) = review.identity else {
                throw SFTPClientError.unsafeRemoteDestination
            }
            _ = try execute(
                command: "get \(try Self.sanitizeRemoteGlobPath(entry.id)) "
                    + "\(try Self.sanitizePath(reservation.payloadURL.path))"
            )
            try reservation.verifyPayload(expectedByteCount: entry.size)
            let downloadedDigest = try reservation.contentSHA256(
                observesTaskCancellation: true,
                cancellationRequested: cancellationRequested
            )
            guard downloadedDigest == expectedDigest else {
                throw SFTPClientError.remoteDestinationChanged
            }
            try verifyReviewedEntry(entry, at: entry.id)
            return try reservation.publish()
        } catch let originalError {
            do {
                try reservation.cleanup()
            } catch {
                throw SFTPClientError.transferFailed(
                    "Download cleanup could not be verified after "
                        + "\(originalError.localizedDescription): \(error.localizedDescription)"
                )
            }
            throw originalError
        }
    }

    // MARK: - Upload

    /// Uploads a local file to the remote host.
    ///
    /// - Parameters:
    ///   - localPath: Path to the local file to upload.
    ///   - remotePath: Destination path on the remote host.
    @discardableResult
    func upload(
        localPath: String,
        remotePath: String,
        expectedLocalIdentity: SFTPLocalFileIdentity? = nil,
        destinationPolicy: SFTPUploadDestinationPolicy = .create
    ) throws -> SFTPUploadOutcome {
        if case .replace(let review) = destinationPolicy {
            guard review.profileID == authorization.profileID,
                  review.connectionLeaseID == authorization.connectionLeaseID,
                  review.entry.id == remotePath,
                  review.entry.isRegularFile,
                  !review.entry.isSymbolicLink,
                  case .regularFileSHA256 = review.identity else {
                throw SFTPClientError.unsafeRemoteDestination
            }
        }
        let snapshot = try SFTPLocalUploadSnapshot.create(
            sourcePath: localPath,
            expectedIdentity: expectedLocalIdentity
        )
        let stagingPath = try Self.remoteOperationPath(
            adjacentTo: remotePath,
            prefix: ".cocxy-upload-"
        )
        do {
            // The shared runner closes arbitrary inherited descriptors. Keep the
            // snapshot in a random 0700 directory and attest its held fd around sftp.
            try snapshot.verifyPathBinding()
            do {
                _ = try execute(
                    command: "put \(try Self.sanitizePath(snapshot.payloadURL.path)) "
                        + "\(try Self.sanitizePath(stagingPath))"
                )
                try snapshot.verifyPathBinding()
            } catch {
                return try finalizeStagingFailure(
                    error,
                    snapshot: snapshot,
                    stagingPath: stagingPath,
                    destinationPath: remotePath
                )
            }
            switch destinationPolicy {
            case .create:
                do {
                    try promoteWithoutReplacing(from: stagingPath, to: remotePath)
                } catch {
                    return finalizeUpload(
                        .commitIndeterminate(SFTPUploadRecoveryState(
                            destinationPath: remotePath,
                            stagedPayloadPath: stagingPath,
                            remoteBackupPath: nil,
                            issues: [.commitStatusUnconfirmed]
                        )),
                        snapshot: snapshot,
                        destinationPath: remotePath
                    )
                }
            case .overwrite:
                do {
                    _ = try execute(
                        command: "rename \(try Self.sanitizePath(stagingPath)) "
                            + "\(try Self.sanitizePath(remotePath))"
                    )
                } catch {
                    return finalizeUpload(
                        .commitIndeterminate(SFTPUploadRecoveryState(
                            destinationPath: remotePath,
                            stagedPayloadPath: stagingPath,
                            remoteBackupPath: nil,
                            issues: [.commitStatusUnconfirmed]
                        )),
                        snapshot: snapshot,
                        destinationPath: remotePath
                    )
                }
            case .replace(let review):
                do {
                    let outcome = try replaceReviewedEntry(
                        review,
                        stagedPayloadPath: stagingPath,
                        destinationPath: remotePath
                    )
                    return finalizeUpload(
                        outcome,
                        snapshot: snapshot,
                        destinationPath: remotePath
                    )
                } catch {
                    return try finalizeStagingFailure(
                        error,
                        snapshot: snapshot,
                        stagingPath: stagingPath,
                        destinationPath: remotePath
                    )
                }
            }
            return finalizeUpload(
                .completed,
                snapshot: snapshot,
                destinationPath: remotePath
            )
        } catch let originalError {
            do {
                try snapshot.cleanup()
            } catch {
                throw SFTPClientError.transferFailed(
                    "Upload snapshot cleanup could not be verified after "
                        + "\(originalError.localizedDescription): \(error.localizedDescription)"
                )
            }
            throw originalError
        }
    }

    // MARK: - Directory Creation

    /// Creates a directory on the remote host.
    ///
    /// - Parameter path: Absolute path of the directory to create.
    @discardableResult
    func mkdir(
        path: String
    ) throws -> SFTPRemoteMutationOutcome {
        let command = "mkdir \(try Self.sanitizePath(path))"
        do {
            _ = try executeMutation(command: command)
            return .completed
        } catch is SFTPCommandDispatchIndeterminateError {
            return .commitIndeterminate(SFTPRemoteMutationRecoveryState(
                targetPath: path,
                recoveryPath: nil,
                issues: [.commitStatusUnconfirmed]
            ))
        }
    }

    // MARK: - File Removal

    /// Removes a file on the remote host.
    ///
    /// - Parameter path: Absolute path of the file to remove.
    @discardableResult
    func remove(
        path: String
    ) throws -> SFTPRemoteMutationOutcome {
        try Self.preflightReviewedEntryOperation(at: path)
        let entry = try requireRemoteEntry(at: path)
        return try remove(entry: entry)
    }

    @discardableResult
    func removeDirectory(path: String) throws -> SFTPRemoteMutationOutcome {
        try Self.preflightReviewedEntryOperation(at: path)
        let entry = try requireRemoteEntry(at: path)
        guard entry.isDirectory else {
            throw SFTPClientError.unsafeRemoteDestination
        }
        return try remove(entry: entry)
    }

    @discardableResult
    func remove(entry: RemoteFileEntry) throws -> SFTPRemoteMutationOutcome {
        try remove(reviewedEntry: prepareReview(entry: entry))
    }

    @discardableResult
    func remove(
        reviewedEntry review: SFTPReviewedRemoteEntry
    ) throws -> SFTPRemoteMutationOutcome {
        let entry = review.entry
        guard review.profileID == authorization.profileID,
              review.connectionLeaseID == authorization.connectionLeaseID,
              !entry.isSymbolicLink,
              entry.isDirectory || entry.isRegularFile else {
            throw SFTPClientError.unsafeRemoteDestination
        }
        let quarantine: String
        do {
            quarantine = try quarantineReviewedEntry(review)
        } catch let error as SFTPQuarantineIndeterminateError {
            return .commitIndeterminate(SFTPRemoteMutationRecoveryState(
                targetPath: entry.id,
                recoveryPath: error.quarantinePath,
                issues: [.commitStatusUnconfirmed]
            ))
        }
        do {
            let command = entry.isDirectory ? "rmdir" : "rm"
            _ = try execute(
                command: "\(command) \(try Self.sanitizePath(quarantine))"
            )
            return .completed
        } catch let originalError {
            let quarantineEntry: RemoteFileEntry?
            do {
                quarantineEntry = try remoteEntry(
                    at: quarantine,
                    recovery: true
                )
            } catch {
                return .commitIndeterminate(SFTPRemoteMutationRecoveryState(
                    targetPath: entry.id,
                    recoveryPath: quarantine,
                    issues: [.commitStatusUnconfirmed]
                ))
            }
            guard let quarantineEntry else {
                return .committedWithIssues(SFTPRemoteMutationRecoveryState(
                    targetPath: entry.id,
                    recoveryPath: nil,
                    issues: [.commitStatusUnconfirmed]
                ))
            }
            guard Self.remoteContentIdentityMatches(
                observed: quarantineEntry,
                expected: entry
            ) else {
                return .commitIndeterminate(SFTPRemoteMutationRecoveryState(
                    targetPath: entry.id,
                    recoveryPath: quarantine,
                    issues: [.commitStatusUnconfirmed]
                ))
            }
            do {
                try verifyRelocatedEntry(
                    review,
                    at: quarantine,
                    recovery: true
                )
            } catch {
                return .commitIndeterminate(SFTPRemoteMutationRecoveryState(
                    targetPath: entry.id,
                    recoveryPath: quarantine,
                    issues: [.commitStatusUnconfirmed]
                ))
            }
            do {
                try restoreQuarantinedEntry(from: quarantine, to: entry.id)
            } catch {
                return classifyFailedRestoration(
                    review: review,
                    quarantinePath: quarantine
                )
            }
            throw originalError
        }
    }

    // MARK: - Helpers

    private func execute(command: String) throws -> String {
        guard SFTPBatchCommandBoundary.contains(command) else {
            throw SFTPClientError.invalidCommand
        }
        try authorization.verify()
        do {
            return try executor.execute(
                sftpCommand: command,
                authorization: authorization
            )
        } catch let error as SFTPCommandNotDispatchedError {
            throw error.underlying
        }
    }

    private func executeMutation(command: String) throws -> String {
        guard SFTPBatchCommandBoundary.contains(command) else {
            throw SFTPClientError.invalidCommand
        }
        try authorization.verify()
        do {
            return try executor.execute(
                sftpCommand: command,
                authorization: authorization
            )
        } catch let error as SFTPCommandNotDispatchedError {
            throw error.underlying
        } catch {
            throw SFTPCommandDispatchIndeterminateError(underlying: error)
        }
    }

    private func remoteContentDigest(
        path: String,
        expectedByteCount: Int64,
        recovery: Bool = false
    ) throws -> Data {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxy-sftp-review-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let reservation = try SFTPLocalDownloadReservation(
            destinationURL: root.appendingPathComponent("reviewed-payload")
        )
        do {
            let command = "get \(try Self.sanitizeRemoteGlobPath(path)) "
                + "\(try Self.sanitizePath(reservation.payloadURL.path))"
            if recovery {
                _ = try executeRecovery(command: command)
            } else {
                _ = try execute(command: command)
            }
            try reservation.verifyPayload(expectedByteCount: expectedByteCount)
            let digest = try reservation.contentSHA256(
                observesTaskCancellation: !recovery,
                cancellationRequested: cancellationRequested
            )
            try reservation.cleanup()
            return digest
        } catch let originalError {
            do {
                try reservation.cleanup()
            } catch {
                throw SFTPClientError.transferFailed(
                    "Remote review cleanup could not be verified after "
                        + "\(originalError.localizedDescription): \(error.localizedDescription)"
                )
            }
            throw originalError
        }
    }

    private func replaceReviewedEntry(
        _ review: SFTPReviewedRemoteEntry,
        stagedPayloadPath: String,
        destinationPath: String
    ) throws -> SFTPUploadOutcome {
        let expectedEntry = review.entry
        guard expectedEntry.id == destinationPath,
              expectedEntry.isRegularFile,
              !expectedEntry.isSymbolicLink,
              review.profileID == authorization.profileID,
              review.connectionLeaseID == authorization.connectionLeaseID,
              case .regularFileSHA256 = review.identity else {
            throw SFTPClientError.unsafeRemoteDestination
        }
        let quarantine: String
        do {
            quarantine = try quarantineReviewedEntry(review)
        } catch let error as SFTPQuarantineIndeterminateError {
            return .commitIndeterminate(SFTPUploadRecoveryState(
                destinationPath: destinationPath,
                stagedPayloadPath: stagedPayloadPath,
                remoteBackupPath: error.quarantinePath,
                issues: [.commitStatusUnconfirmed]
            ))
        }
        do {
            try promoteWithoutReplacing(
                from: stagedPayloadPath,
                to: destinationPath
            )
        } catch {
            return .commitIndeterminate(SFTPUploadRecoveryState(
                destinationPath: destinationPath,
                stagedPayloadPath: stagedPayloadPath,
                remoteBackupPath: quarantine,
                issues: [.commitStatusUnconfirmed]
            ))
        }

        do {
            try verifyRelocatedEntry(review, at: quarantine)
        } catch SFTPClientError.remoteDestinationChanged {
            return .committedWithIssues(SFTPUploadRecoveryState(
                destinationPath: destinationPath,
                stagedPayloadPath: nil,
                remoteBackupPath: quarantine,
                issues: [.remoteBackupIdentityChanged]
            ))
        } catch {
            return .committedWithIssues(SFTPUploadRecoveryState(
                destinationPath: destinationPath,
                stagedPayloadPath: nil,
                remoteBackupPath: quarantine,
                issues: [.remoteBackupVerificationFailed]
            ))
        }
        guard cleanupRemoteFile(quarantine) == nil else {
            return .committedWithIssues(SFTPUploadRecoveryState(
                destinationPath: destinationPath,
                stagedPayloadPath: nil,
                remoteBackupPath: quarantine,
                issues: [.remoteBackupRemovalUnconfirmed]
            ))
        }
        return .completed
    }

    private func finalizeStagingFailure(
        _ originalError: Error,
        snapshot: SFTPLocalUploadSnapshot,
        stagingPath: String,
        destinationPath: String
    ) throws -> SFTPUploadOutcome {
        guard cleanupRemoteFile(stagingPath, recovery: true) != nil else {
            do {
                try snapshot.cleanup()
            } catch {
                throw SFTPClientError.transferFailed(
                    "Upload snapshot cleanup could not be verified after "
                        + "\(originalError.localizedDescription): \(error.localizedDescription)"
                )
            }
            throw originalError
        }
        return finalizeUpload(
            .notCommittedWithIssues(SFTPUploadRecoveryState(
                destinationPath: destinationPath,
                stagedPayloadPath: stagingPath,
                remoteBackupPath: nil,
                issues: [.remoteStagingRemovalUnconfirmed]
            )),
            snapshot: snapshot,
            destinationPath: destinationPath
        )
    }

    private func finalizeUpload(
        _ outcome: SFTPUploadOutcome,
        snapshot: SFTPLocalUploadSnapshot,
        destinationPath: String
    ) -> SFTPUploadOutcome {
        var finalized = outcome
        do {
            try authorization.verify()
        } catch {
            finalized = addingPostCommitIssue(
                .connectionVerificationFailed,
                to: finalized,
                destinationPath: destinationPath
            )
        }
        do {
            try snapshot.cleanup()
        } catch {
            finalized = addingPostCommitIssue(
                .localSnapshotCleanupUnconfirmed,
                to: finalized,
                destinationPath: destinationPath,
                localSnapshotURL: snapshot.recoveryDirectoryURL
            )
        }
        return finalized
    }

    private func addingPostCommitIssue(
        _ issue: SFTPUploadPostCommitIssue,
        to outcome: SFTPUploadOutcome,
        destinationPath: String,
        localSnapshotURL: URL? = nil
    ) -> SFTPUploadOutcome {
        switch outcome {
        case .completed:
            return .committedWithIssues(SFTPUploadRecoveryState(
                destinationPath: destinationPath,
                stagedPayloadPath: nil,
                remoteBackupPath: nil,
                issues: [issue],
                localSnapshotURL: localSnapshotURL
            ))
        case .notCommittedWithIssues(let state):
            return .notCommittedWithIssues(SFTPUploadRecoveryState(
                destinationPath: state.destinationPath,
                stagedPayloadPath: state.stagedPayloadPath,
                remoteBackupPath: state.remoteBackupPath,
                issues: state.issues + [issue],
                localSnapshotURL: localSnapshotURL ?? state.localSnapshotURL
            ))
        case .committedWithIssues(let state):
            return .committedWithIssues(SFTPUploadRecoveryState(
                destinationPath: state.destinationPath,
                stagedPayloadPath: state.stagedPayloadPath,
                remoteBackupPath: state.remoteBackupPath,
                issues: state.issues + [issue],
                localSnapshotURL: localSnapshotURL ?? state.localSnapshotURL
            ))
        case .commitIndeterminate(let state):
            return .commitIndeterminate(SFTPUploadRecoveryState(
                destinationPath: state.destinationPath,
                stagedPayloadPath: state.stagedPayloadPath,
                remoteBackupPath: state.remoteBackupPath,
                issues: state.issues + [issue],
                localSnapshotURL: localSnapshotURL ?? state.localSnapshotURL
            ))
        }
    }

    private func quarantineReviewedEntry(
        _ review: SFTPReviewedRemoteEntry
    ) throws -> String {
        let expectedEntry = review.entry
        guard !expectedEntry.isSymbolicLink,
              expectedEntry.isDirectory || expectedEntry.isRegularFile else {
            throw SFTPClientError.unsafeRemoteDestination
        }
        var lastError: Error = SFTPClientError.remoteDestinationChanged
        for _ in 0..<3 {
            let quarantine = try Self.remoteOperationPath(
                adjacentTo: expectedEntry.id,
                prefix: ".cocxy-review-"
            )
            do {
                _ = try execute(
                    command: "rename -l \(try Self.sanitizePath(expectedEntry.id)) "
                        + "\(try Self.sanitizePath(quarantine))"
                )
            } catch {
                lastError = error
                let observed: (original: RemoteFileEntry?, recovery: RemoteFileEntry?)
                do {
                    observed = try remoteEntries(
                        originalPath: expectedEntry.id,
                        recoveryPath: quarantine,
                        recovery: true
                    )
                } catch {
                    throw SFTPQuarantineIndeterminateError(
                        quarantinePath: quarantine
                    )
                }
                if let recovery = observed.recovery,
                   Self.remoteContentIdentityMatches(
                       observed: recovery,
                       expected: expectedEntry
                    ) {
                    do {
                        try verifyRelocatedEntry(
                            review,
                            at: quarantine,
                            recovery: true
                        )
                        return quarantine
                    } catch let validationError {
                        do {
                            try restoreQuarantinedEntry(
                                from: quarantine,
                                to: expectedEntry.id
                            )
                        } catch {
                            throw SFTPQuarantineIndeterminateError(
                                quarantinePath: quarantine
                            )
                        }
                        throw validationError
                    }
                }
                if let original = observed.original,
                   Self.remoteIdentityMatches(
                       observed: original,
                       expected: expectedEntry
                   ) {
                    continue
                }
                if observed.original == nil, observed.recovery == nil {
                    throw SFTPQuarantineIndeterminateError(
                        quarantinePath: quarantine
                    )
                }
                if observed.recovery != nil {
                    throw SFTPQuarantineIndeterminateError(
                        quarantinePath: quarantine
                    )
                } else {
                    throw SFTPClientError.remoteDestinationChanged
                }
            }

            do {
                try verifyRelocatedEntry(review, at: quarantine)
                return quarantine
            } catch let validationError {
                do {
                    try restoreQuarantinedEntry(
                        from: quarantine,
                        to: expectedEntry.id
                    )
                } catch {
                    throw SFTPQuarantineIndeterminateError(
                        quarantinePath: quarantine
                    )
                }
                throw validationError
            }
        }
        throw lastError
    }

    private func verifyReviewedEntry(
        _ expectedEntry: RemoteFileEntry,
        at path: String
    ) throws {
        guard let observedEntry = try remoteEntry(at: path),
              Self.remoteIdentityMatches(
                  observed: observedEntry,
                  expected: expectedEntry
              ) else {
            throw SFTPClientError.remoteDestinationChanged
        }
    }

    private func verifyRelocatedEntry(
        _ review: SFTPReviewedRemoteEntry,
        at relocatedPath: String,
        recovery: Bool = false
    ) throws {
        let expectedEntry = review.entry
        guard let relocatedEntry = try remoteEntry(
            at: relocatedPath,
            recovery: recovery
        ),
              Self.remoteContentIdentityMatches(
                  observed: relocatedEntry,
                  expected: expectedEntry
              ) else {
            throw SFTPClientError.remoteDestinationChanged
        }
        switch review.identity {
        case .regularFileSHA256(let expectedDigest):
            let observedDigest = try remoteContentDigest(
                path: relocatedPath,
                expectedByteCount: expectedEntry.size,
                recovery: recovery
            )
            guard observedDigest == expectedDigest else {
                throw SFTPClientError.remoteDestinationChanged
            }
        case .emptyDirectory:
            guard relocatedEntry.isDirectory,
                  try listDirectory(
                      path: relocatedPath,
                      recovery: recovery
                  ).isEmpty else {
                throw SFTPClientError.remoteDestinationChanged
            }
        }
    }

    private func restoreQuarantinedEntry(
        from quarantinePath: String,
        to destinationPath: String
    ) throws {
        _ = try executeRecovery(
            command: "rename -l \(try Self.sanitizePath(quarantinePath)) "
                + "\(try Self.sanitizePath(destinationPath))"
        )
    }

    private func classifyFailedRestoration(
        review: SFTPReviewedRemoteEntry,
        quarantinePath: String
    ) -> SFTPRemoteMutationOutcome {
        let expectedEntry = review.entry
        let observed: (original: RemoteFileEntry?, recovery: RemoteFileEntry?)
        do {
            observed = try remoteEntries(
                originalPath: expectedEntry.id,
                recoveryPath: quarantinePath,
                recovery: true
            )
        } catch {
            return .commitIndeterminate(SFTPRemoteMutationRecoveryState(
                targetPath: expectedEntry.id,
                recoveryPath: quarantinePath,
                issues: [.commitStatusUnconfirmed, .restorationUnconfirmed]
            ))
        }
        if observed.original != nil, observed.recovery == nil {
            do {
                try verifyRelocatedEntry(
                    review,
                    at: expectedEntry.id,
                    recovery: true
                )
                return .notCommittedWithIssues(SFTPRemoteMutationRecoveryState(
                    targetPath: expectedEntry.id,
                    recoveryPath: nil,
                    issues: [.commitStatusUnconfirmed]
                ))
            } catch {
                return .commitIndeterminate(SFTPRemoteMutationRecoveryState(
                    targetPath: expectedEntry.id,
                    recoveryPath: nil,
                    issues: [.commitStatusUnconfirmed, .restorationUnconfirmed]
                ))
            }
        }
        if observed.recovery != nil, observed.original == nil {
            do {
                try verifyRelocatedEntry(
                    review,
                    at: quarantinePath,
                    recovery: true
                )
                return .notCommittedWithIssues(SFTPRemoteMutationRecoveryState(
                    targetPath: expectedEntry.id,
                    recoveryPath: quarantinePath,
                    issues: [.restorationUnconfirmed]
                ))
            } catch {
                return .commitIndeterminate(SFTPRemoteMutationRecoveryState(
                    targetPath: expectedEntry.id,
                    recoveryPath: quarantinePath,
                    issues: [.commitStatusUnconfirmed, .restorationUnconfirmed]
                ))
            }
        }
        if observed.recovery == nil, observed.original == nil {
            return .committedWithIssues(SFTPRemoteMutationRecoveryState(
                targetPath: expectedEntry.id,
                recoveryPath: nil,
                issues: [.commitStatusUnconfirmed]
            ))
        }
        return .commitIndeterminate(SFTPRemoteMutationRecoveryState(
            targetPath: expectedEntry.id,
            recoveryPath: quarantinePath,
            issues: [.commitStatusUnconfirmed, .restorationUnconfirmed]
        ))
    }

    private func promoteWithoutReplacing(
        from stagingPath: String,
        to destinationPath: String
    ) throws {
        _ = try execute(
            command: "rename -l \(try Self.sanitizePath(stagingPath)) "
                + "\(try Self.sanitizePath(destinationPath))"
        )
    }

    private func cleanupRemoteFile(_ path: String, recovery: Bool = false) -> Error? {
        do {
            let command = "rm \(try Self.sanitizePath(path))"
            if recovery {
                _ = try executeRecovery(command: command)
            } else {
                _ = try execute(command: command)
            }
            return nil
        } catch {
            return error
        }
    }

    private func executeRecovery(command: String) throws -> String {
        guard SFTPBatchCommandBoundary.contains(command) else {
            throw SFTPClientError.invalidCommand
        }
        try authorization.verify()
        do {
            return try executor.executeRecovery(
                sftpCommand: command,
                authorization: authorization
            )
        } catch let error as SFTPCommandNotDispatchedError {
            throw error.underlying
        }
    }

    private func requireRemoteEntry(at path: String) throws -> RemoteFileEntry {
        guard let entry = try remoteEntry(at: path) else {
            throw SFTPClientError.remoteDestinationChanged
        }
        return entry
    }

    private func remoteEntry(
        at path: String,
        recovery: Bool = false
    ) throws -> RemoteFileEntry? {
        let (parentPath, name) = try Self.remoteParentAndName(for: path)
        return try listDirectory(
            path: parentPath,
            recovery: recovery
        ).first { $0.name == name }
    }

    private func remoteEntries(
        originalPath: String,
        recoveryPath: String,
        recovery: Bool = false
    ) throws -> (original: RemoteFileEntry?, recovery: RemoteFileEntry?) {
        let (originalParent, originalName) = try Self.remoteParentAndName(
            for: originalPath
        )
        let (recoveryParent, recoveryName) = try Self.remoteParentAndName(
            for: recoveryPath
        )
        guard originalParent == recoveryParent else {
            throw SFTPClientError.invalidPath
        }
        let entries = try listDirectory(
            path: originalParent,
            recovery: recovery
        )
        return (
            entries.first { $0.name == originalName },
            entries.first { $0.name == recoveryName }
        )
    }

    private static func parseCanonicalNames(_ output: String) throws -> [String] {
        var lines = output.components(separatedBy: .newlines)
        while lines.last?.isEmpty == true { lines.removeLast() }
        var names: [String] = []
        var seen: Set<String> = []
        for rawLine in lines {
            let name = rawLine.last == "\r" ? String(rawLine.dropLast()) : rawLine
            if name.isEmpty { continue }
            if name == "." || name == ".." { continue }
            guard RemoteFileEntry.isSafePathComponent(name),
                  seen.insert(name).inserted else {
                throw SFTPClientError.parseFailed(
                    "The remote directory contains an unsupported or duplicate name."
                )
            }
            names.append(name)
        }
        return names
    }

    private static func parseLongListing(
        _ output: String,
        basePath: String,
        canonicalNames: [String]? = nil
    ) throws -> [RemoteFileEntry] {
        var lines = output.components(separatedBy: .newlines)
        while lines.last?.isEmpty == true { lines.removeLast() }
        var entries: [RemoteFileEntry] = []
        var seen: Set<String> = []
        var canonicalIndex = 0
        for line in lines {
            if line.isEmpty || line == "\r" { continue }
            if RemoteFileEntry.isDotEntryListingLine(line) { continue }
            let canonicalName = canonicalNames.flatMap { names in
                canonicalIndex < names.count ? names[canonicalIndex] : nil
            }
            guard let entry = RemoteFileEntry.parse(
                from: line,
                basePath: basePath,
                canonicalName: canonicalName
            ),
                  seen.insert(entry.name).inserted else {
                throw SFTPClientError.parseFailed(
                    "The remote directory metadata listing was incomplete or ambiguous."
                )
            }
            entries.append(entry)
            canonicalIndex += 1
        }
        if let canonicalNames, canonicalIndex != canonicalNames.count {
            throw SFTPClientError.parseFailed(
                "The remote directory name and metadata listings did not match."
            )
        }
        return entries
    }

    private static func remoteParentAndName(for path: String) throws -> (String, String) {
        guard !path.isEmpty,
              path != "/",
              !path.hasSuffix("/"),
              let separator = path.lastIndex(of: "/") else {
            guard RemoteFileEntry.isSafePathComponent(path) else {
                throw SFTPClientError.invalidPath
            }
            return (".", path)
        }

        let name = String(path[path.index(after: separator)...])
        guard RemoteFileEntry.isSafePathComponent(name) else {
            throw SFTPClientError.invalidPath
        }
        if separator == path.startIndex { return ("/", name) }
        let parent = String(path[..<separator])
        return (parent.isEmpty ? "." : parent, name)
    }

    private static func remoteIdentityMatches(
        observed: RemoteFileEntry,
        expected: RemoteFileEntry
    ) -> Bool {
        observed.id == expected.id
            && observed.name == expected.name
            && remoteContentIdentityMatches(observed: observed, expected: expected)
    }

    private static func remoteContentIdentityMatches(
        observed: RemoteFileEntry,
        expected: RemoteFileEntry
    ) -> Bool {
        observed.isDirectory == expected.isDirectory
            && observed.isSymbolicLink == expected.isSymbolicLink
            && observed.linkTarget == expected.linkTarget
            && observed.size == expected.size
            && observed.modifiedDate == expected.modifiedDate
            && observed.permissions == expected.permissions
            && listingTokenMatches(
                observed: observed.listingLinkCountToken,
                expected: expected.listingLinkCountToken
            )
            && listingTokenMatches(
                observed: observed.listingOwnerToken,
                expected: expected.listingOwnerToken
            )
            && listingTokenMatches(
                observed: observed.listingGroupToken,
                expected: expected.listingGroupToken
            )
            && listingTokenMatches(
                observed: observed.listingModificationToken,
                expected: expected.listingModificationToken
            )
    }

    private static func listingTokenMatches(
        observed: String?,
        expected: String?
    ) -> Bool {
        guard let expected else { return true }
        return observed == expected
    }

    private static func remoteOperationPath(
        adjacentTo path: String,
        prefix: String
    ) throws -> String {
        let (parentPath, _) = try remoteParentAndName(for: path)
        return try appendingRemotePath(
            "\(prefix)\(UUID().uuidString.lowercased())",
            to: parentPath
        )
    }

    private static func preflightReviewedEntryOperation(at path: String) throws {
        let quarantine = try remoteOperationPath(
            adjacentTo: path,
            prefix: ".cocxy-review-"
        )
        let command = "rename -l \(try sanitizePath(path)) "
            + "\(try sanitizePath(quarantine))"
        guard SFTPBatchCommandBoundary.contains(command) else {
            throw SFTPClientError.invalidCommand
        }
    }

    static func appendingRemotePath(_ component: String, to basePath: String) throws -> String {
        guard RemoteFileEntry.isSafePathComponent(component) else {
            throw SFTPClientError.invalidPath
        }
        if basePath == "/" { return "/\(component)" }
        if basePath.hasSuffix("/") { return "\(basePath)\(component)" }
        return "\(basePath)/\(component)"
    }

    /// Wraps a path in single quotes with proper escaping to prevent command injection.
    ///
    /// Any embedded single quotes are replaced with the sequence `'\''` which
    /// terminates the current quoted string, inserts a literal single quote
    /// via backslash escaping, then reopens the quoted string.
    static func sanitizePath(_ path: String) throws -> String {
        guard !path.isEmpty,
              path.utf8.count <= 1_024,
              path.first != "-",
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw SFTPClientError.invalidPath
        }
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }

    static func sanitizeRemoteGlobPath(_ path: String) throws -> String {
        // OpenSSH marks glob metacharacters inside quotes as literal. A path
        // backslash still needs one extra level to survive its command parser.
        let literalPath = path.replacingOccurrences(of: "\\", with: "\\\\")
        return try sanitizePath(literalPath)
    }
}
