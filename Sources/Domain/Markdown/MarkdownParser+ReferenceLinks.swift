// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownParser+ReferenceLinks.swift - Reference-style link definition helpers.

import Foundation

extension MarkdownParser {
    static func collectReferenceLinkDefinitions(from lines: [String]) -> ([String: String], Set<Int>) {
        var definitions: [String: String] = [:]
        var consumedLines = Set<Int>()

        for (index, line) in lines.enumerated() {
            guard let (label, url) = parseReferenceLinkDefinition(line) else { continue }
            definitions[normalizedReferenceLinkLabel(label)] = url
            consumedLines.insert(index)
        }

        return (definitions, consumedLines)
    }

    static func normalizedReferenceLinkLabel(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func parseReferenceLinkDefinition(_ line: String) -> (String, String)? {
        let pattern = #"^\s{0,3}\[([^\]]+)\]:\s+(\S+)(?:\s+(?:"[^"]*"|'[^']*'|\([^)]*\)))?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(location: 0, length: (line as NSString).length)
        guard let match = regex.firstMatch(in: line, range: range),
              match.numberOfRanges >= 3 else {
            return nil
        }

        let nsLine = line as NSString
        let label = nsLine.substring(with: match.range(at: 1))
        let url = nsLine.substring(with: match.range(at: 2))
        return (label, url)
    }
}
