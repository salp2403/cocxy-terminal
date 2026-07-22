// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarketplaceGitProcessRunner.swift - Shared bounded Git execution for marketplace sources.

import Darwin
import Foundation

struct MarketplaceGitProcessRunner: Sendable {
    static let defaultTimeoutSeconds: TimeInterval = 30
    static let defaultMaximumRetainedBytesPerStream = 4 * 1_024 * 1_024

    let gitExecutableURL: URL
    let workingDirectory: URL
    let timeoutSeconds: TimeInterval
    let maximumRetainedBytesPerStream: Int
    private let environment: [String: String]

    init(
        gitExecutableURL: URL = URL(fileURLWithPath: "/usr/bin/git"),
        workingDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        timeoutSeconds: TimeInterval = defaultTimeoutSeconds,
        maximumRetainedBytesPerStream: Int = defaultMaximumRetainedBytesPerStream,
        inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.gitExecutableURL = gitExecutableURL
        self.workingDirectory = workingDirectory
        self.timeoutSeconds = timeoutSeconds
        self.maximumRetainedBytesPerStream = maximumRetainedBytesPerStream
        environment = Self.hardenedEnvironment(
            homeDirectory: workingDirectory,
            inheritedEnvironment: inheritedEnvironment
        )
    }

    func run(arguments: [String]) throws -> BoundedProcessResult {
        let canonicalWorkingDirectory = try Self.canonicalExistingDirectory(workingDirectory)
        let isolatedDirectory = canonicalWorkingDirectory.appendingPathComponent(
            ".cocxy-marketplace-git-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: isolatedDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: isolatedDirectory) }

        var invocationEnvironment = environment
        invocationEnvironment["GIT_CEILING_DIRECTORIES"] = isolatedDirectory.path
        let safetyArguments = [
            "-c", "core.askPass=/usr/bin/false",
            "-c", "core.gitProxy=none",
            "-c", "credential.helper=",
            "-c", "protocol.ext.allow=never",
            "-c", "protocol.file.allow=never",
        ]
        return try BoundedProcessRunner(
            maximumRetainedBytesPerStream: maximumRetainedBytesPerStream
        ).run(
            executableURL: gitExecutableURL,
            arguments: safetyArguments + arguments,
            workingDirectory: isolatedDirectory,
            environment: invocationEnvironment,
            timeoutSeconds: timeoutSeconds
        )
    }

    func clone(sourceURL: URL, destinationURL: URL) throws -> BoundedProcessResult {
        try run(arguments: [
            "clone", "--depth", "1", "--",
            sourceURL.absoluteString,
            destinationURL.path,
        ])
    }

    private static func canonicalExistingDirectory(_ directory: URL) throws -> URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let resolved = directory.path.withCString { path in
            buffer.withUnsafeMutableBufferPointer { storage in
                realpath(path, storage.baseAddress)
            }
        }
        guard resolved != nil else {
            throw BoundedProcessRunnerError.systemCallFailed(
                operation: "realpath",
                code: errno
            )
        }
        return URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
    }

    private static func hardenedEnvironment(
        homeDirectory: URL,
        inheritedEnvironment: [String: String]
    ) -> [String: String] {
        var result: [String: String] = [
            "GIT_ASKPASS": "/usr/bin/false",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_OPTIONAL_LOCKS": "0",
            "GIT_SSH_COMMAND": "/usr/bin/ssh -F /dev/null -oBatchMode=yes -oPermitLocalCommand=no -oProxyCommand=none -oClearAllForwardings=yes",
            "GIT_TERMINAL_PROMPT": "0",
            "HOME": homeDirectory.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "SSH_ASKPASS": "/usr/bin/false",
        ]
        for key in ["LANG", "LC_ALL", "SSH_AUTH_SOCK", "TMPDIR"] {
            if let value = inheritedEnvironment[key] {
                result[key] = value
            }
        }
        return result
    }
}
