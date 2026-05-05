// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentErrorPresentation.swift - User-safe Agent error descriptions.

import Foundation

enum AgentErrorPresentation {
    static func message(for error: Error) -> String {
        redacted(error.localizedDescription)
    }

    static func redacted(_ message: String, maxLength: Int = 300) -> String {
        let normalized = message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var result = String(normalized.prefix(4_000))

        for pattern in secretPatterns {
            result = replacingMatches(of: pattern, in: result, with: "[redacted]")
        }

        guard !result.isEmpty else {
            return "Request failed."
        }
        guard result.count > maxLength else {
            return result
        }

        let prefix = result
            .prefix(maxLength)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)..."
    }

    private static let secretPatterns = [
        #"\bsk-[A-Za-z0-9][A-Za-z0-9._-]{6,}\b"#,
        #"\bAIza[0-9A-Za-z_-]{16,}\b"#,
        #"\b[A-Za-z0-9_-]{32,}\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\b"#,
        #"(?i)\bbearer\s+[A-Za-z0-9._-]{8,}\b"#,
        #"(?i)\b(?:api[_ -]?key|token|secret|authorization)\s*[=:]\s*[^\s,;]+"#,
    ]

    private static func replacingMatches(
        of pattern: String,
        in text: String,
        with replacement: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: replacement
        )
    }
}
