// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// FileChunker.swift - Deterministic text chunking for local codebase indexing.

import Foundation

struct CodebaseFileChunk: Sendable, Equatable {
    let path: String
    let startLine: Int
    let endLine: Int
    let text: String
}

struct CodebaseFileChunker: Sendable {
    let maxChunkBytes: Int

    init(maxChunkBytes: Int = 8_192) {
        self.maxChunkBytes = max(1, maxChunkBytes)
    }

    func chunks(for content: String, path: String) -> [CodebaseFileChunk] {
        var lines = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        if content.hasSuffix("\n"), lines.last == "" {
            lines.removeLast()
        }
        guard !lines.isEmpty else {
            return [CodebaseFileChunk(path: path, startLine: 1, endLine: 1, text: "")]
        }

        var chunks: [CodebaseFileChunk] = []
        var currentLines: [String] = []
        var currentStartLine = 1
        var currentBytes = 0

        for (index, line) in lines.enumerated() {
            let lineNumber = index + 1
            let lineBytes = Data(line.utf8).count
            let separatorBytes = currentLines.isEmpty ? 0 : 1

            if !currentLines.isEmpty, currentBytes + separatorBytes + lineBytes > maxChunkBytes {
                chunks.append(CodebaseFileChunk(
                    path: path,
                    startLine: currentStartLine,
                    endLine: lineNumber - 1,
                    text: currentLines.joined(separator: "\n")
                ))
                currentLines = []
                currentStartLine = lineNumber
                currentBytes = 0
            }

            currentLines.append(line)
            currentBytes += separatorBytes + lineBytes
        }

        if !currentLines.isEmpty {
            chunks.append(CodebaseFileChunk(
                path: path,
                startLine: currentStartLine,
                endLine: currentStartLine + currentLines.count - 1,
                text: currentLines.joined(separator: "\n")
            ))
        }

        return chunks
    }
}
