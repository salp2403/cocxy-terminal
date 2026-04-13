// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownParser+CodeBlocks.swift - Fenced and indented code block parsing helpers.

import Foundation

extension MarkdownParser {
    func parseFencedCodeBlock(
        lines: [String],
        at start: Int
    ) -> (MarkdownBlock, Int)? {
        let line = lines[start]
        let trimmed = Self.leadingSpacesTrimmed(line, max: 3)
        guard trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") else { return nil }

        let fenceChar: Character = trimmed.first!
        var fenceLen = 0
        for ch in trimmed {
            if ch == fenceChar { fenceLen += 1 } else { break }
        }
        guard fenceLen >= 3 else { return nil }

        let info = String(trimmed.dropFirst(fenceLen)).trimmingCharacters(in: .whitespaces)
        var language: String?
        var title: String?
        if !info.isEmpty {
            if let titleRange = info.range(of: #"title="([^"]+)""#, options: .regularExpression) {
                let titleMatch = String(info[titleRange])
                if let firstQuote = titleMatch.firstIndex(of: "\""),
                   let lastQuote = titleMatch.lastIndex(of: "\""),
                   firstQuote < lastQuote {
                    title = String(titleMatch[titleMatch.index(after: firstQuote)..<lastQuote])
                }
                let remainder = info.replacingCharacters(in: titleRange, with: "")
                    .trimmingCharacters(in: .whitespaces)
                language = remainder.isEmpty ? nil : String(remainder.split(separator: " ").first ?? Substring(remainder))
            } else {
                language = String(info.split(separator: " ").first ?? Substring(info))
            }
        }

        var collected: [String] = []
        var cursor = start + 1
        while cursor < lines.count {
            let raw = lines[cursor]
            let stripped = Self.leadingSpacesTrimmed(raw, max: 3)
            if stripped.hasPrefix(String(repeating: String(fenceChar), count: fenceLen)) &&
               stripped.allSatisfy({ $0 == fenceChar || $0 == " " }) {
                return (
                    .codeBlock(language: language, title: title, text: collected.joined(separator: "\n")),
                    cursor - start + 1
                )
            }
            collected.append(raw)
            cursor += 1
        }

        return (
            .codeBlock(language: language, title: title, text: collected.joined(separator: "\n")),
            cursor - start
        )
    }

    func parseIndentedCodeBlock(
        lines: [String],
        at start: Int
    ) -> (MarkdownBlock, Int)? {
        let line = lines[start]
        guard line.hasPrefix("    ") else { return nil }

        var collected: [String] = []
        var cursor = start
        while cursor < lines.count {
            let raw = lines[cursor]
            if raw.hasPrefix("    ") {
                collected.append(String(raw.dropFirst(4)))
                cursor += 1
            } else if raw.trimmingCharacters(in: .whitespaces).isEmpty {
                let next = cursor + 1
                if next < lines.count, lines[next].hasPrefix("    ") {
                    collected.append("")
                    cursor += 1
                } else {
                    break
                }
            } else {
                break
            }
        }

        while let last = collected.last, last.isEmpty {
            collected.removeLast()
        }
        if collected.isEmpty { return nil }

        return (.codeBlock(language: nil, title: nil, text: collected.joined(separator: "\n")), cursor - start)
    }
}
