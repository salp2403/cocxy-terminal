// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SnippetParser.swift - VS Code-style numeric placeholder expansion.

import Foundation

struct SnippetTextRange: Codable, Equatable, Sendable {
    let location: Int
    let length: Int
}

struct SnippetTabStop: Codable, Equatable, Sendable {
    let index: Int
    let range: SnippetTextRange
    let placeholder: String
}

struct SnippetExpansion: Equatable, Sendable {
    let renderedText: String
    let tabStops: [SnippetTabStop]

    var orderedTabStops: [SnippetTabStop] {
        tabStops.sorted { lhs, rhs in
            if lhs.index == rhs.index {
                return lhs.range.location < rhs.range.location
            }
            if lhs.index == 0 { return false }
            if rhs.index == 0 { return true }
            return lhs.index < rhs.index
        }
    }

    func nextTabStop(after currentIndex: Int?) -> SnippetTabStop? {
        let ordered = orderedTabStops
        guard let currentIndex else {
            return ordered.first
        }
        return ordered.first { $0.index > currentIndex || (currentIndex != 0 && $0.index == 0) }
    }
}

enum SnippetParserError: Error, Equatable, Sendable {
    case unterminatedPlaceholder(String)
    case invalidPlaceholder(String)
}

struct SnippetParser: Sendable {
    func expand(_ body: String) throws -> SnippetExpansion {
        var output = ""
        var tabStops: [SnippetTabStop] = []
        var index = body.startIndex

        while index < body.endIndex {
            let character = body[index]
            if character == "\\",
               let next = body.index(index, offsetBy: 1, limitedBy: body.endIndex),
               next < body.endIndex,
               body[next] == "$" {
                output.append("$")
                index = body.index(after: next)
                continue
            }

            guard character == "$",
                  let next = body.index(index, offsetBy: 1, limitedBy: body.endIndex),
                  next < body.endIndex else {
                output.append(character)
                index = body.index(after: index)
                continue
            }

            if body[next].isNumber {
                let result = parseNumericTabStop(in: body, startingAt: next)
                appendTabStop(
                    index: result.index,
                    placeholder: "",
                    to: &tabStops,
                    output: &output
                )
                index = result.endIndex
                continue
            }

            if body[next] == "{" {
                let result = try parseBracedPlaceholder(
                    in: body,
                    dollarIndex: index,
                    openingBrace: next
                )
                appendTabStop(
                    index: result.index,
                    placeholder: result.placeholder,
                    to: &tabStops,
                    output: &output
                )
                index = result.endIndex
                continue
            }

            output.append(character)
            index = body.index(after: index)
        }

        return SnippetExpansion(renderedText: output, tabStops: tabStops)
    }

    private func parseNumericTabStop(
        in body: String,
        startingAt start: String.Index
    ) -> (index: Int, endIndex: String.Index) {
        var cursor = start
        var digits = ""
        while cursor < body.endIndex, body[cursor].isNumber {
            digits.append(body[cursor])
            cursor = body.index(after: cursor)
        }
        return (Int(digits) ?? 0, cursor)
    }

    private func parseBracedPlaceholder(
        in body: String,
        dollarIndex: String.Index,
        openingBrace: String.Index
    ) throws -> (index: Int, placeholder: String, endIndex: String.Index) {
        var cursor = body.index(after: openingBrace)
        var inner = ""
        while cursor < body.endIndex, body[cursor] != "}" {
            inner.append(body[cursor])
            cursor = body.index(after: cursor)
        }
        guard cursor < body.endIndex else {
            throw SnippetParserError.unterminatedPlaceholder(String(body[dollarIndex...]))
        }

        let parts = inner.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard let rawIndex = parts.first,
              let tabIndex = Int(rawIndex),
              tabIndex >= 0 else {
            throw SnippetParserError.invalidPlaceholder(inner)
        }

        let placeholder = parts.dropFirst().first.map(String.init) ?? ""
        return (tabIndex, placeholder, body.index(after: cursor))
    }

    private func appendTabStop(
        index: Int,
        placeholder: String,
        to tabStops: inout [SnippetTabStop],
        output: inout String
    ) {
        let location = (output as NSString).length
        output.append(placeholder)
        tabStops.append(SnippetTabStop(
            index: index,
            range: SnippetTextRange(
                location: location,
                length: (placeholder as NSString).length
            ),
            placeholder: placeholder
        ))
    }
}
