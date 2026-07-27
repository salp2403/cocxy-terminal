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

struct PluginUpdateCheckResult: Equatable, Sendable {
    let updates: [PluginUpdateCandidate]
    let checkedSourceCount: Int
    let failedSourceCount: Int
    let wasCancelled: Bool
}

enum PluginUpdaterError: Error, Equatable {
    case gitFailed(Int32)
    case invalidUpdateSource
    case outputTooLarge(Int)
    case timedOut(TimeInterval)
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
        let task = Task.detached(priority: .utility) {
            try runGitTagQuery(sourceURL: sourceURL)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private let sourceStore: PluginUpdateSourceStore
    private let validator: PluginValidator
    private let queryRemoteTags: RemoteTagQuery

    init(
        sourceStore: PluginUpdateSourceStore = PluginUpdateSourceStore(),
        validator: PluginValidator = PluginValidator(),
        queryRemoteTags: @escaping RemoteTagQuery = Self.defaultRemoteTagQuery
    ) {
        self.sourceStore = sourceStore
        self.validator = validator
        self.queryRemoteTags = queryRemoteTags
    }

    func availableUpdates(for manifests: [PluginManifest]) async -> [PluginUpdateCandidate] {
        await checkAvailableUpdates(for: manifests).updates
    }

    func checkAvailableUpdates(for manifests: [PluginManifest]) async -> PluginUpdateCheckResult {
        var updates: [PluginUpdateCandidate] = []
        var checkedSourceCount = 0
        var failedSourceCount = 0

        guard !Task.isCancelled else {
            return PluginUpdateCheckResult(
                updates: [],
                checkedSourceCount: 0,
                failedSourceCount: 0,
                wasCancelled: true
            )
        }

        for manifest in manifests {
            if Task.isCancelled {
                return PluginUpdateCheckResult(
                    updates: updates,
                    checkedSourceCount: checkedSourceCount,
                    failedSourceCount: failedSourceCount,
                    wasCancelled: true
                )
            }

            let source: PluginUpdateSource?
            do {
                source = try sourceStore.source(for: manifest.id)
            } catch {
                failedSourceCount += 1
                continue
            }
            guard let source else { continue }

            do {
                let pluginDirectory = URL(
                    fileURLWithPath: manifest.directoryPath,
                    isDirectory: true
                )
                let installedManifest = try PluginRegistry.loadManifest(from: pluginDirectory)
                guard installedManifest == manifest else {
                    failedSourceCount += 1
                    continue
                }
                let report = try validator.validate(
                    manifest: installedManifest,
                    sourceURL: source.repositoryURL,
                    pluginDirectory: pluginDirectory
                )
                guard report.signatureStatus == .verified else {
                    failedSourceCount += 1
                    continue
                }
            } catch {
                failedSourceCount += 1
                continue
            }

            let latestAvailableVersion: String?
            do {
                latestAvailableVersion = try await latestVersion(from: source.repositoryURL)
            } catch is CancellationError {
                return PluginUpdateCheckResult(
                    updates: updates,
                    checkedSourceCount: checkedSourceCount,
                    failedSourceCount: failedSourceCount,
                    wasCancelled: true
                )
            } catch {
                failedSourceCount += 1
                continue
            }
            checkedSourceCount += 1

            guard let latestAvailableVersion,
                  Self.compareVersions(
                      latestAvailableVersion,
                      manifest.version
                  ) == .orderedDescending
            else { continue }

            updates.append(PluginUpdateCandidate(
                pluginID: manifest.id,
                currentVersion: manifest.version,
                latestVersion: latestAvailableVersion,
                pluginDirectory: URL(fileURLWithPath: manifest.directoryPath, isDirectory: true)
            ))
        }
        return PluginUpdateCheckResult(
            updates: updates,
            checkedSourceCount: checkedSourceCount,
            failedSourceCount: failedSourceCount,
            wasCancelled: Task.isCancelled
        )
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

    static func runGitTagQuery(
        sourceURL: URL,
        processRunner: MarketplaceGitProcessRunner = MarketplaceGitProcessRunner(
            maximumRetainedBytesPerStream: maxTagOutputBytes
        )
    ) throws -> String {
        guard PluginUpdateSource.remoteRepository(sourceURL) != nil else {
            throw PluginValidationError.invalidSourceScheme(sourceURL.scheme)
        }

        let result = try processRunner.run(arguments: [
            "ls-remote", "--tags", "--refs", "--", sourceURL.absoluteString,
        ])
        if result.timedOut {
            throw PluginUpdaterError.timedOut(processRunner.timeoutSeconds)
        }
        if result.stdoutWasTruncated {
            throw PluginUpdaterError.outputTooLarge(
                processRunner.maximumRetainedBytesPerStream
            )
        }
        guard result.exitCode == 0 else {
            throw PluginUpdaterError.gitFailed(result.exitCode)
        }
        return result.stdout
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
