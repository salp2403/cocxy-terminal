// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SkillLoader.swift - Reads local Markdown skill files.

import Foundation

struct SkillLoader: Sendable {
    func loadSkill(from directory: URL, source: SkillSource) throws -> Skill? {
        let skillFile = directory.standardizedFileURL.appendingPathComponent("SKILL.md")
        guard FileManager.default.isReadableFile(atPath: skillFile.path) else {
            return nil
        }

        let text = try String(contentsOf: skillFile, encoding: .utf8)
        let parsed = try parseSkillFile(text, fileURL: skillFile)
        let fallbackID = directory.lastPathComponent.lowercased()
        let id = parsed.metadata["id"]?.lowercased() ?? fallbackID
        guard Self.isValidIdentifier(id) else {
            throw SkillError.invalidIdentifier(id)
        }

        let name = parsed.metadata["name"]
            ?? id.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        let summary = parsed.metadata["description"] ?? ""

        return Skill(
            id: id,
            name: name,
            summary: summary,
            body: parsed.body,
            source: source,
            fileURL: skillFile
        )
    }

    private func parseSkillFile(
        _ text: String,
        fileURL: URL
    ) throws -> (metadata: [String: String], body: String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n") else {
            throw SkillError.invalidFrontMatter(fileURL)
        }

        let afterOpening = normalized.dropFirst(4)
        guard let closingRange = afterOpening.range(of: "\n---") else {
            throw SkillError.invalidFrontMatter(fileURL)
        }

        let frontMatter = String(afterOpening[..<closingRange.lowerBound])
        var body = String(afterOpening[closingRange.upperBound...])
        if body.hasPrefix("\n") {
            body.removeFirst()
        }

        var metadata: [String: String] = [:]
        for line in frontMatter.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw SkillError.invalidFrontMatter(fileURL)
            }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = stripQuotes(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            metadata[key] = value
        }

        return (metadata, body.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func stripQuotes(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    static func isValidIdentifier(_ id: String) -> Bool {
        guard (1...64).contains(id.count) else { return false }
        guard let first = id.unicodeScalars.first,
              isLowercaseASCII(first) || isDigitASCII(first) else {
            return false
        }
        return id.unicodeScalars.allSatisfy { scalar in
            isLowercaseASCII(scalar)
                || isDigitASCII(scalar)
                || scalar == "-"
                || scalar == "_"
        }
    }

    private static func isLowercaseASCII(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 97 && scalar.value <= 122
    }

    private static func isDigitASCII(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 48 && scalar.value <= 57
    }
}
