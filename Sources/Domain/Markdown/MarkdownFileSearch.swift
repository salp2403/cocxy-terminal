// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownFileSearch.swift - Search engine for finding text across markdown files.

import Foundation

// MARK: - Search Result

/// A single match within a markdown file.
struct MarkdownSearchResult: Equatable, Sendable {
    /// Path to the file containing the match.
    let fileURL: URL

    /// The file name (for display).
    let fileName: String

    /// 1-based line number of the match.
    let lineNumber: Int

    /// The text of the matching line (trimmed).
    let lineText: String
}

// MARK: - Search Engine

/// Searches for text across all markdown files in a directory tree.
///
/// All operations are synchronous and intended to be called from a background
/// queue. The caller is responsible for dispatching to main for UI updates.
struct MarkdownFileSearch: Sendable {

    /// Searches all .md/.markdown files under `root` for lines containing `query`.
    ///
    /// - Parameters:
    ///   - query: The text to search for (case-insensitive).
    ///   - root: The root directory to scan recursively.
    ///   - maxResults: Maximum number of results to return (default 200).
    /// - Returns: An array of search results sorted by file name then line number.
    static func search(
        query: String,
        in root: URL,
        maxResults: Int = 200
    ) -> [MarkdownSearchResult] {
        guard !query.isEmpty else { return [] }

        let fm = FileManager.default
        let lowercasedQuery = query.lowercased()
        var results: [MarkdownSearchResult] = []

        let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )

        while let url = enumerator?.nextObject() as? URL {
            guard results.count < maxResults else { break }

            let ext = url.pathExtension.lowercased()
            guard ext == "md" || ext == "markdown" else { continue }

            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let lines = content.components(separatedBy: .newlines)
            let fileName = url.lastPathComponent

            for (index, line) in lines.enumerated() {
                guard results.count < maxResults else { break }

                if line.lowercased().contains(lowercasedQuery) {
                    results.append(MarkdownSearchResult(
                        fileURL: url,
                        fileName: fileName,
                        lineNumber: index + 1,
                        lineText: line.trimmingCharacters(in: .whitespaces)
                    ))
                }
            }
        }

        return results.sorted { lhs, rhs in
            if lhs.fileName != rhs.fileName {
                return lhs.fileName.localizedCaseInsensitiveCompare(rhs.fileName) == .orderedAscending
            }
            return lhs.lineNumber < rhs.lineNumber
        }
    }
}
