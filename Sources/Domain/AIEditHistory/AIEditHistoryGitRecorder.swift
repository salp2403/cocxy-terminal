// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AIEditHistoryGitRecorder.swift - Local Git-backed edit history capture.

import CryptoKit
import Foundation

protocol AIEditHistoryRecording: Sendable {
    func recordSession(
        sessionID: String,
        agentID: String,
        workingDirectory: URL,
        baseRef: String?,
        trackedFiles: Set<String>
    ) throws -> AIEditRecord?
}

struct AIEditRepositoryIdentifier: Sendable {
    static let idLength = 16

    static func id(for workingDirectory: URL) throws -> String {
        let root = try repositoryRoot(for: workingDirectory)
        let digest = SHA256.hash(data: Data(root.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return String(digest.prefix(idLength))
    }

    static func repositoryRoot(
        for workingDirectory: URL,
        gitRunner: (@Sendable (URL, [String]) throws -> String)? = nil
    ) throws -> URL {
        let runner: @Sendable (URL, [String]) throws -> String = gitRunner ?? { workingDirectory, arguments in
            try SessionDiffTrackerImpl.runGit(workingDirectory, arguments)
        }
        let output = try? runner(workingDirectory, ["rev-parse", "--show-toplevel"])
        let path = output?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty else {
            return workingDirectory.standardizedFileURL
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }
}

struct AIEditHistoryGitRecorder: AIEditHistoryRecording, @unchecked Sendable {
    let store: AIEditStore
    private let gitRunner: @Sendable (URL, [String]) throws -> String
    private let fileManager: FileManager

    init(
        store: AIEditStore = AIEditStore(),
        gitRunner: (@Sendable (URL, [String]) throws -> String)? = nil,
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.gitRunner = gitRunner ?? { workingDirectory, arguments in
            try SessionDiffTrackerImpl.runGit(workingDirectory, arguments)
        }
        self.fileManager = fileManager
    }

    func recordSession(
        sessionID: String,
        agentID: String,
        workingDirectory: URL,
        baseRef: String?,
        trackedFiles: Set<String>
    ) throws -> AIEditRecord? {
        guard !trackedFiles.isEmpty else { return nil }
        let repoRoot = try AIEditRepositoryIdentifier.repositoryRoot(for: workingDirectory, gitRunner: gitRunner)
        let changes = try trackedFiles
            .compactMap { try recordableChange(for: $0, repoRoot: repoRoot, baseRef: baseRef) }
            .sorted { $0.filePath.localizedCaseInsensitiveCompare($1.filePath) == .orderedAscending }
        guard !changes.isEmpty else { return nil }

        let record = AIEditRecord(
            sessionID: sessionID,
            agentID: agentID.isEmpty ? "local-agent" : agentID,
            summary: "Recorded \(changes.count) file \(changes.count == 1 ? "change" : "changes")",
            changes: changes
        )
        try store.append(record, repoID: try AIEditRepositoryIdentifier.id(for: repoRoot))
        return record
    }

    private func recordableChange(
        for rawPath: String,
        repoRoot: URL,
        baseRef: String?
    ) throws -> AIEditChange? {
        guard let relativePath = safeRelativePath(rawPath, repoRoot: repoRoot) else {
            return nil
        }
        let before = baseRef.flatMap { contentAtBase(ref: $0, path: relativePath, repoRoot: repoRoot) }
        let fileURL = repoRoot.appendingPathComponent(relativePath).standardizedFileURL
        let after = currentContent(at: fileURL)

        if baseRef == nil, before == nil, after != nil {
            let status = (try? gitRunner(repoRoot, ["status", "--porcelain", "--", relativePath])) ?? ""
            guard status.hasPrefix("??") || status.hasPrefix("A ") || status.hasPrefix("AM") else {
                return nil
            }
        }

        guard before != after else { return nil }
        return AIEditChange(filePath: relativePath, beforeContent: before, afterContent: after)
    }

    private func contentAtBase(ref: String, path: String, repoRoot: URL) -> String? {
        try? gitRunner(repoRoot, ["show", "\(ref):\(path)"])
    }

    private func currentContent(at fileURL: URL) -> String? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    private func safeRelativePath(_ rawPath: String, repoRoot: URL) -> String? {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0") else { return nil }

        let relative: String
        if trimmed.hasPrefix("/") {
            let fileURL = URL(fileURLWithPath: trimmed).standardizedFileURL
            guard let descendant = Self.relativePathIfDescendant(fileURL, parent: repoRoot) else {
                return nil
            }
            relative = descendant
        } else {
            relative = trimmed
        }

        let components = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return relative
    }

    private static func relativePathIfDescendant(_ fileURL: URL, parent: URL) -> String? {
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        let parentComponents = parent.standardizedFileURL.pathComponents
        guard fileComponents.count >= parentComponents.count else { return nil }
        guard Array(fileComponents.prefix(parentComponents.count)) == parentComponents else { return nil }
        return fileComponents.dropFirst(parentComponents.count).joined(separator: "/")
    }
}
