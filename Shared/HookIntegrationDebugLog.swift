// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HookIntegrationDebugLog.swift - Opt-in local diagnostics for hook delivery.

import Darwin
import Foundation

public enum HookIntegrationDebugLog {
    public static let enabledEnvironmentKey = "COCXY_HOOK_DEBUG_LOG"
    public static let pathOverrideEnvironmentKey = "COCXY_HOOK_DEBUG_LOG_PATH"

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

        fileURL.path.withCString { path in
            let descriptor = Darwin.open(
                path,
                O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW,
                0o600
            )
            guard descriptor >= 0 else { return }
            defer { Darwin.close(descriptor) }
            guard Darwin.fchmod(descriptor, 0o600) == 0,
                  Darwin.lockf(descriptor, F_LOCK, 0) == 0 else {
                return
            }
            defer { _ = Darwin.lockf(descriptor, F_ULOCK, 0) }

            let data = Data(line.utf8)
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
}
