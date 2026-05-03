// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PluginUpdater.swift - Local git tag update checks for installed plugins.

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
}

struct PluginUpdater: Sendable {
    typealias GitCommand = @Sendable (_ directory: URL, _ arguments: [String]) throws -> String

    private static let defaultGitCommand: GitCommand = { directory, arguments in
        try runGit(directory: directory, arguments: arguments)
    }

    private let runGitCommand: GitCommand

    init(runGitCommand: @escaping GitCommand = Self.defaultGitCommand) {
        self.runGitCommand = runGitCommand
    }

    func availableUpdates(for manifests: [PluginManifest]) -> [PluginUpdateCandidate] {
        manifests.compactMap { manifest in
            let directory = URL(fileURLWithPath: manifest.directoryPath, isDirectory: true)
            guard let latestVersion = try? latestVersion(in: directory),
                  Self.compareVersions(latestVersion, manifest.version) == .orderedDescending
            else { return nil }

            return PluginUpdateCandidate(
                pluginID: manifest.id,
                currentVersion: manifest.version,
                latestVersion: latestVersion,
                pluginDirectory: directory
            )
        }
    }

    private func latestVersion(in directory: URL) throws -> String? {
        _ = try? runGitCommand(directory, ["fetch", "--tags", "--quiet"])
        let output = try runGitCommand(directory, ["tag", "--sort=-v:refname"])
        return output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .map(Self.normalizedVersion)
            .first { !$0.isEmpty }
    }

    private static func runGit(directory: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PluginUpdaterError.gitFailed(process.terminationStatus)
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = normalizedVersion(lhs)
            .split(separator: ".")
            .map { Int($0) ?? 0 }
        let right = normalizedVersion(rhs)
            .split(separator: ".")
            .map { Int($0) ?? 0 }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func normalizedVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }
}
