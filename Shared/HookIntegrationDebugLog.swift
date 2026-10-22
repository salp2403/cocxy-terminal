// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HookIntegrationDebugLog.swift - Opt-in local diagnostics for hook delivery.

import Darwin
import Foundation

public enum HookIntegrationDebugLog {
    public static let enabledEnvironmentKey = "COCXY_HOOK_DEBUG_LOG"
    public static let pathOverrideEnvironmentKey = "COCXY_HOOK_DEBUG_LOG_PATH"
    public static let maximumFileBytes: Int64 = 1_048_576
    public static let rotatedFileSuffix = ".1"

    public static var defaultFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Cocxy", isDirectory: true)
            .appendingPathComponent("hook-integration.log", isDirectory: false)
    }

    public static func isEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment[enabledEnvironmentKey] == "1"
    }

    public static func append(
        _ message: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        timestamp: Date = Date()
    ) {
        guard isEnabled(environment: environment) else { return }

        let fileURL = environment[pathOverrideEnvironmentKey]
            .map { URL(fileURLWithPath: $0) }
            ?? defaultFileURL
        let directoryURL = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: 0o700)]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o700)],
                ofItemAtPath: directoryURL.path
            )
        } catch {
            return
        }

        let sanitized = String(message.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? " " : Character(scalar)
        })
        let bounded = String(decoding: sanitized.utf8.prefix(4_096), as: UTF8.self)
        let date = ISO8601DateFormatter().string(from: timestamp)
        let line = "\(date) [hook-integration] \(bounded)\n"

        let data = Data(line.utf8)
        withRotationLock(for: fileURL) {
            guard let descriptor = openLogFile(at: fileURL) else { return }
            var activeDescriptor = descriptor
            if shouldRotate(descriptor: activeDescriptor, incomingByteCount: data.count) {
                Darwin.close(activeDescriptor)
                guard rotate(fileURL), let replacement = openLogFile(at: fileURL) else {
                    return
                }
                activeDescriptor = replacement
            }
            defer { Darwin.close(activeDescriptor) }
            write(data, to: activeDescriptor)
        }
    }

    private static func withRotationLock(for fileURL: URL, perform: () -> Void) {
        let lockPath = fileURL.path + ".lock"
        lockPath.withCString { path in
            let descriptor = Darwin.open(
                path,
                O_WRONLY | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
                0o600
            )
            guard descriptor >= 0 else { return }
            defer { Darwin.close(descriptor) }
            guard Darwin.fchmod(descriptor, 0o600) == 0,
                  Darwin.lockf(descriptor, F_LOCK, 0) == 0 else {
                return
            }
            defer { _ = Darwin.lockf(descriptor, F_ULOCK, 0) }
            perform()
        }
    }

    private static func openLogFile(at fileURL: URL) -> Int32? {
        fileURL.path.withCString { path in
            let descriptor = Darwin.open(
                path,
                O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW,
                0o600
            )
            guard descriptor >= 0 else { return nil }
            var metadata = stat()
            guard Darwin.fchmod(descriptor, 0o600) == 0,
                  Darwin.fstat(descriptor, &metadata) == 0,
                  metadata.st_mode & S_IFMT == S_IFREG else {
                Darwin.close(descriptor)
                return nil
            }
            return descriptor
        }
    }

    private static func shouldRotate(descriptor: Int32, incomingByteCount: Int) -> Bool {
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0 else { return true }
        return metadata.st_size + Int64(incomingByteCount) > maximumFileBytes
    }

    private static func rotate(_ fileURL: URL) -> Bool {
        let backupPath = fileURL.path + rotatedFileSuffix
        _ = backupPath.withCString { Darwin.unlink($0) }
        return fileURL.path.withCString { source in
            backupPath.withCString { destination in
                Darwin.rename(source, destination) == 0
            }
        }
    }

    private static func write(_ data: Data, to descriptor: Int32) {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var written = 0
            while written < rawBuffer.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    rawBuffer.count - written
                )
                if result > 0 {
                    written += result
                } else if result < 0, errno == EINTR {
                    continue
                } else {
                    return
                }
            }
        }
    }
}
