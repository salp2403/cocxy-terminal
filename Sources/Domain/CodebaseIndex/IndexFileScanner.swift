// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// IndexFileScanner.swift - Shared local file scanner for codebase indexing.

import Foundation

struct CodebaseIndexedFile: Sendable, Equatable {
    let url: URL
    let relativePath: String
}

struct CodebaseIndexFileScanner {
    let workspace: AgentWorkspace
    let maxFileBytes: Int

    init(workspace: AgentWorkspace, maxFileBytes: Int = 1_000_000) {
        self.workspace = workspace
        self.maxFileBytes = maxFileBytes
    }

    func regularFiles(startingAt rootURL: URL) -> [CodebaseIndexedFile] {
        let ignorePatterns = CodebaseIndexIgnorePatterns(rootURL: workspace.rootURL)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        var files: [CodebaseIndexedFile] = []

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
            files.append(CodebaseIndexedFile(url: url, relativePath: relativePath))
        }

        return files.sorted { $0.relativePath < $1.relativePath }
    }

    func readTextFile(_ file: CodebaseIndexedFile) throws -> String {
        try readTextFile(file.url, relativePath: file.relativePath)
    }

    func readTextFile(relativePath: String) throws -> String {
        let url = try workspace.requireRegularFile(relativePath)
        return try readTextFile(url, relativePath: workspace.relativePath(for: url))
    }

    private func readTextFile(_ url: URL, relativePath: String) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let fileSize = values.fileSize ?? 0
        guard fileSize <= maxFileBytes else {
            throw AgentWorkspaceError.fileTooLarge(path: relativePath, maxBytes: maxFileBytes)
        }

        let data = try Data(contentsOf: url)
        guard !data.contains(0), let content = String(data: data, encoding: .utf8) else {
            throw AgentWorkspaceError.nonUTF8File(relativePath)
        }
        return content
    }
}
