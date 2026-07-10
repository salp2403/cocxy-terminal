// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginUpdater.swift - Provenance-bound remote tag checks for installed plugins.

import Foundation

struct PluginUpdateCandidate: Identifiable, Equatable, Sendable {
    var id: String { pluginID }
    let pluginID: String
    let currentVersion: String
    let latestVersion: String
    let pluginDirectory: URL
}

enum PluginUpdaterError: Error, Equatable {
    case gitFailed(Int32)
    case invalidUpdateSource
    case outputTooLarge(Int)
}

struct PluginUpdateSource: Codable, Equatable, Sendable {
    static let maxURLBytes = 4_096

    let repositoryURL: URL

    static func remoteRepository(_ url: URL) -> PluginUpdateSource? {
        let allowedSchemes: Set<String> = ["git", "https", "ssh"]
        guard let scheme = url.scheme?.lowercased(),
              allowedSchemes.contains(scheme),
              let host = url.host,
              !host.isEmpty,
              !host.hasPrefix("-"),
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              url.absoluteString.utf8.count <= maxURLBytes,
              !url.absoluteString.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              scheme != "https" || url.user == nil
        else {
            return nil
        }
        if let port = url.port, !(1...65_535).contains(port) {
            return nil
        }
        return PluginUpdateSource(repositoryURL: url)
    }
}

struct PluginUpdateSourceStore: Sendable {
    private static let directoryName = ".update-sources"

    let directoryURL: URL

    init(pluginsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".cocxy/plugins", isDirectory: true)) {
        self.directoryURL = pluginsDirectory
            .appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    func source(for pluginID: String) throws -> PluginUpdateSource? {
        try PluginValidator.validatePluginID(pluginID)
        let url = sourceURL(for: pluginID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let source = try JSONDecoder().decode(
            PluginUpdateSource.self,
            from: Data(contentsOf: url, options: [.uncached])
        )
        return PluginUpdateSource.remoteRepository(source.repositoryURL)
    }

    func save(_ source: PluginUpdateSource, for pluginID: String) throws {
        try PluginValidator.validatePluginID(pluginID)
        guard PluginUpdateSource.remoteRepository(source.repositoryURL) == source else {
            throw PluginUpdaterError.invalidUpdateSource
        }
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directoryURL.path
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let destination = sourceURL(for: pluginID)
        try encoder.encode(source).write(to: destination, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
        )
    }

    func removeSource(for pluginID: String) throws {
        try PluginValidator.validatePluginID(pluginID)
        let url = sourceURL(for: pluginID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func sourceURL(for pluginID: String) -> URL {
        directoryURL.appendingPathComponent("\(pluginID).json", isDirectory: false)
    }
}

struct PluginUpdater: Sendable {
    typealias RemoteTagQuery = @Sendable (_ sourceURL: URL) async throws -> String

    private static let maxTagOutputBytes = 4 * 1_024 * 1_024

    private static let defaultRemoteTagQuery: RemoteTagQuery = { sourceURL in
        try await Task.detached(priority: .utility) {
            try runGitTagQuery(sourceURL: sourceURL)
        }.value
    }

    private let sourceStore: PluginUpdateSourceStore
    private let queryRemoteTags: RemoteTagQuery

    init(
        sourceStore: PluginUpdateSourceStore = PluginUpdateSourceStore(),
        queryRemoteTags: @escaping RemoteTagQuery = Self.defaultRemoteTagQuery
    ) {
        self.sourceStore = sourceStore
        self.queryRemoteTags = queryRemoteTags
    }

    func availableUpdates(for manifests: [PluginManifest]) async -> [PluginUpdateCandidate] {
        var updates: [PluginUpdateCandidate] = []
        for manifest in manifests {
            guard let source = try? sourceStore.source(for: manifest.id),
                  let latestVersion = try? await latestVersion(from: source.repositoryURL),
                  Self.compareVersions(latestVersion, manifest.version) == .orderedDescending
            else {
                continue
            }

            updates.append(PluginUpdateCandidate(
                pluginID: manifest.id,
                currentVersion: manifest.version,
                latestVersion: latestVersion,
                pluginDirectory: URL(fileURLWithPath: manifest.directoryPath, isDirectory: true)
            ))
        }
        return updates
    }

    private func latestVersion(from sourceURL: URL) async throws -> String? {
        let output = try await queryRemoteTags(sourceURL)
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap(Self.versionFromRemoteTagLine)
            .max { Self.compareVersions($0, $1) == .orderedAscending }
    }

    private static func versionFromRemoteTagLine(_ line: Substring) -> String? {
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count == 2 else { return nil }
        let prefix = "refs/tags/"
        let reference = String(fields[1])
        guard reference.hasPrefix(prefix) else { return nil }
        let version = String(reference.dropFirst(prefix.count))
        guard parsedVersion(version) != nil else { return nil }
        return normalizedVersion(version)
    }

    private static func runGitTagQuery(sourceURL: URL) throws -> String {
        guard PluginUpdateSource.remoteRepository(sourceURL) != nil else {
            throw PluginValidationError.invalidSourceScheme(sourceURL.scheme)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "-c", "protocol.ext.allow=never",
            "-c", "protocol.file.allow=never",
            "ls-remote", "--tags", "--refs", "--", sourceURL.absoluteString,
        ]
        let inheritedEnvironment = ProcessInfo.processInfo.environment
        var environment: [String: String] = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "PATH": "/usr/bin:/bin",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_SSH_COMMAND": "/usr/bin/ssh -F /dev/null -oBatchMode=yes -oPermitLocalCommand=no -oProxyCommand=none",
        ]
        for key in ["LANG", "LC_ALL", "SSH_AUTH_SOCK", "TMPDIR"] {
            if let value = inheritedEnvironment[key] {
                environment[key] = value
            }
        }
        process.environment = environment

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        try process.run()

        var data = Data()
        while let chunk = try stdout.fileHandleForReading.read(upToCount: 64 * 1_024),
              !chunk.isEmpty {
            guard chunk.count <= maxTagOutputBytes - data.count else {
                process.terminate()
                process.waitUntilExit()
                throw PluginUpdaterError.outputTooLarge(maxTagOutputBytes)
            }
            data.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PluginUpdaterError.gitFailed(process.terminationStatus)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        guard let left = parsedVersion(lhs), let right = parsedVersion(rhs) else {
            return .orderedSame
        }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func parsedVersion(_ version: String) -> [Int]? {
        let normalized = normalizedVersion(version)
        let fields = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...8).contains(fields.count) else { return nil }
        var result: [Int] = []
        result.reserveCapacity(fields.count)
        for field in fields {
            guard !field.isEmpty,
                  field.count <= 9,
                  field.allSatisfy(\.isNumber),
                  let value = Int(field)
            else {
                return nil
            }
            result.append(value)
        }
        return result
    }

    private static func normalizedVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }
}
