// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AIEditReverter.swift - Conservative single-edit revert for local history.

import Foundation

enum AIEditRevertError: Error, Equatable, Sendable {
    case unsafePath(String)
    case currentContentChanged(String)
}

struct AIEditRevertResult: Equatable, Sendable {
    let revertedFiles: [String]
}

struct AIEditReverter {
    private struct PlannedRevert {
        let change: AIEditChange
        let fileURL: URL
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func revert(
        _ record: AIEditRecord,
        in workingDirectory: URL
    ) throws -> AIEditRevertResult {
        let root = workingDirectory.resolvingSymlinksInPath().standardizedFileURL
        let planned = try record.changes.map { change in
            let fileURL = try safeURL(for: change.filePath, root: root)
            let current = try currentContent(at: fileURL)
            guard current == change.afterContent else {
                throw AIEditRevertError.currentContentChanged(change.filePath)
            }
            return PlannedRevert(change: change, fileURL: fileURL)
        }

        var reverted: [String] = []
        for plan in planned {
            let change = plan.change
            let fileURL = plan.fileURL
            if let before = change.beforeContent {
                try fileManager.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try before.write(to: fileURL, atomically: true, encoding: .utf8)
            } else if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            reverted.append(change.filePath)
        }
        return AIEditRevertResult(revertedFiles: reverted.sorted())
    }

    private func currentContent(at url: URL) throws -> String? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func safeURL(for relativePath: String, root: URL) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\0") else {
            throw AIEditRevertError.unsafePath(relativePath)
        }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw AIEditRevertError.unsafePath(relativePath)
        }

        let rootPath = root.path.hasSuffix("/") ? root.path : "\(root.path)/"
        var current = root
        for component in components {
            current = current.appendingPathComponent(String(component)).standardizedFileURL
            guard current.path.hasPrefix(rootPath) else {
                throw AIEditRevertError.unsafePath(relativePath)
            }
            if fileManager.fileExists(atPath: current.path) {
                let resolved = current.resolvingSymlinksInPath().standardizedFileURL
                guard resolved.path.hasPrefix(rootPath) else {
                    throw AIEditRevertError.unsafePath(relativePath)
                }
            }
        }

        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        guard url.path.hasPrefix(rootPath) else {
            throw AIEditRevertError.unsafePath(relativePath)
        }
        return url
    }
}
