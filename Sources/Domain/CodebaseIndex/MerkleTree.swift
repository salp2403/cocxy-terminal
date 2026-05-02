// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MerkleTree.swift - File snapshot signatures for incremental codebase indexing.

import CryptoKit
import Foundation

struct CodebaseMerkleSnapshot: Sendable, Equatable {
    let fileDigests: [String: String]

    func changedFiles(comparedTo previous: CodebaseMerkleSnapshot?) -> [String] {
        guard let previous else {
            return fileDigests.keys.sorted()
        }
        return fileDigests
            .compactMap { path, digest in
                previous.fileDigests[path] == digest ? nil : path
            }
            .sorted()
    }

    func removedFiles(comparedTo previous: CodebaseMerkleSnapshot) -> [String] {
        previous.fileDigests.keys
            .filter { fileDigests[$0] == nil }
            .sorted()
    }
}

struct CodebaseMerkleTreeBuilder {
    let workspace: AgentWorkspace
    let maxFileBytes: Int

    init(workspace: AgentWorkspace, maxFileBytes: Int = 1_000_000) {
        self.workspace = workspace
        self.maxFileBytes = maxFileBytes
    }

    func snapshot() throws -> CodebaseMerkleSnapshot {
        let ignorePatterns = CodebaseIndexIgnorePatterns(rootURL: workspace.rootURL)
        var fileDigests: [String: String] = [:]

        for url in regularFiles(ignorePatterns: ignorePatterns) {
            let relativePath = workspace.relativePath(for: url)
            guard let digest = try? digest(for: url, relativePath: relativePath) else {
                continue
            }
            fileDigests[relativePath] = digest
        }

        return CodebaseMerkleSnapshot(fileDigests: fileDigests)
    }

    private func regularFiles(ignorePatterns: CodebaseIndexIgnorePatterns) -> [URL] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        let enumerator = FileManager.default.enumerator(
            at: workspace.rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        var files: [URL] = []

        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: keys)
            let relativePath = workspace.relativePath(for: url)
            let isDirectory = values?.isDirectory == true

            if ignorePatterns.isIgnored(relativePath: relativePath, isDirectory: isDirectory) {
                if isDirectory {
                    enumerator?.skipDescendants()
                }
                continue
            }
            guard values?.isRegularFile == true else { continue }
            files.append(url)
        }

        return files.sorted { workspace.relativePath(for: $0) < workspace.relativePath(for: $1) }
    }

    private func digest(for url: URL, relativePath: String) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = values.fileSize ?? 0
        guard fileSize <= maxFileBytes else {
            throw AgentWorkspaceError.fileTooLarge(path: relativePath, maxBytes: maxFileBytes)
        }

        let data = try Data(contentsOf: url)
        guard !data.contains(0) else {
            throw AgentWorkspaceError.binaryFile(relativePath)
        }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
