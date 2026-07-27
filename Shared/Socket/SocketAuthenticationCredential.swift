// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SocketAuthenticationCredential.swift - Secure local credential-file contract.

import Darwin
import Foundation

public enum SocketAuthenticationCredentialError: Error, Equatable, Sendable {
    case fileOperationFailed(reason: String)
    case unsafeCredentialFile
    case invalidToken
}

extension SocketAuthenticationCredentialError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileOperationFailed(let reason):
            return "Socket authentication credential file failed: \(reason)"
        case .unsafeCredentialFile:
            return "Socket authentication credential file is missing or unsafe."
        case .invalidToken:
            return "Socket authentication credential is malformed."
        }
    }
}

/// Shared file and token rules used by the app server and bundled CLI.
///
/// The token file is an ephemeral delivery channel, not configuration. It is
/// accepted only when it is a single-link regular file owned by the effective
/// user with exact `0600` permissions. `O_NOFOLLOW` prevents symlink traversal.
public enum SocketAuthenticationCredential {
    public static let tokenByteCount = 32
    public static let encodedTokenLength = tokenByteCount * 2
    public static let filePermissions: mode_t = 0o600

    public static func path(forSocketPath socketPath: String) -> String {
        socketPath + ".token"
    }

    public static func isValidToken(_ token: String) -> Bool {
        guard token.utf8.count == encodedTokenLength else { return false }
        return token.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102)
        }
    }

    /// Compares without an early exit so a request cannot learn token bytes
    /// from response timing. Token length is fixed, but length is folded into
    /// the same accumulated difference for fail-closed behavior.
    public static func securelyMatches(_ candidate: String?, expected: String) -> Bool {
        let candidateBytes = Array((candidate ?? "").utf8)
        let expectedBytes = Array(expected.utf8)
        let count = max(candidateBytes.count, expectedBytes.count)
        var difference = candidateBytes.count ^ expectedBytes.count

        for index in 0..<count {
            let lhs = index < candidateBytes.count ? candidateBytes[index] : 0
            let rhs = index < expectedBytes.count ? expectedBytes[index] : 0
            difference |= Int(lhs ^ rhs)
        }
        return difference == 0
    }

    public static func write(_ token: String, to path: String) throws {
        guard isValidToken(token) else {
            throw SocketAuthenticationCredentialError.invalidToken
        }

        if Darwin.unlink(path) != 0, errno != ENOENT {
            throw fileError("could not remove stale credential", errno: errno)
        }

        let flags = O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC
        let fd = path.withCString {
            Darwin.open($0, flags, filePermissions)
        }
        guard fd >= 0 else {
            throw fileError("could not create credential", errno: errno)
        }

        var removeOnFailure = true
        defer {
            Darwin.close(fd)
            if removeOnFailure {
                Darwin.unlink(path)
            }
        }

        guard Darwin.fchmod(fd, filePermissions) == 0 else {
            throw fileError("could not restrict credential permissions", errno: errno)
        }

        let bytes = Array(token.utf8)
        var written = 0
        while written < bytes.count {
            let result = bytes.withUnsafeBytes { buffer in
                Darwin.write(
                    fd,
                    buffer.baseAddress!.advanced(by: written),
                    bytes.count - written
                )
            }
            if result < 0, errno == EINTR { continue }
            guard result > 0 else {
                throw fileError("could not write credential", errno: errno)
            }
            written += result
        }

        guard Darwin.fsync(fd) == 0 else {
            throw fileError("could not persist credential", errno: errno)
        }
        removeOnFailure = false
    }

    public static func read(from path: String) throws -> String {
        let fd = path.withCString {
            Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        }
        guard fd >= 0 else {
            throw SocketAuthenticationCredentialError.unsafeCredentialFile
        }
        defer { Darwin.close(fd) }

        var metadata = stat()
        guard Darwin.fstat(fd, &metadata) == 0,
              (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              metadata.st_uid == geteuid(),
              metadata.st_nlink == 1,
              (metadata.st_mode & 0o777) == filePermissions,
              metadata.st_size == off_t(encodedTokenLength)
        else {
            throw SocketAuthenticationCredentialError.unsafeCredentialFile
        }

        var bytes = [UInt8](repeating: 0, count: encodedTokenLength)
        var totalRead = 0
        while totalRead < bytes.count {
            let remaining = bytes.count - totalRead
            let result = bytes.withUnsafeMutableBytes { buffer in
                Darwin.read(
                    fd,
                    buffer.baseAddress!.advanced(by: totalRead),
                    remaining
                )
            }
            if result < 0, errno == EINTR { continue }
            guard result > 0 else {
                throw SocketAuthenticationCredentialError.unsafeCredentialFile
            }
            totalRead += result
        }

        guard let token = String(bytes: bytes, encoding: .utf8),
              isValidToken(token)
        else {
            throw SocketAuthenticationCredentialError.invalidToken
        }
        return token
    }

    public static func remove(at path: String) {
        _ = Darwin.unlink(path)
    }

    private static func fileError(
        _ operation: String,
        errno errorNumber: Int32
    ) -> SocketAuthenticationCredentialError {
        .fileOperationFailed(
            reason: "\(operation): \(String(cString: strerror(errorNumber)))"
        )
    }
}
