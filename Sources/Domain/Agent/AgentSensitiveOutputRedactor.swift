// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentSensitiveOutputRedactor.swift - Local redaction before approved terminal context egress.

import Foundation

enum AgentSensitiveOutputRedactor {
    static func redacted(_ text: String) -> String {
        patterns.reduce(text) { output, pattern in
            output.replacingOccurrences(
                of: pattern.expression,
                with: pattern.replacement,
                options: .regularExpression
            )
        }
    }

    private static let patterns: [(expression: String, replacement: String)] = [
        (
            #"(?s)-----BEGIN (?:[A-Z0-9 ]+ )?PRIVATE KEY-----.*?-----END (?:[A-Z0-9 ]+ )?PRIVATE KEY-----"#,
            "[redacted-private-key]"
        ),
        (
            #"(?im)\b(authorization\s*:\s*(?:bearer|basic)\s+)[^\s]+"#,
            "$1[redacted]"
        ),
        (
            #"(?im)\b((?:api[_-]?key|token|secret|password|passwd|pwd|access[_-]?key|client[_-]?secret)\s*[:=]\s*)(\"[^\"\r\n]*\"|'[^'\r\n]*'|[^\s,;]+)"#,
            "$1[redacted]"
        ),
        (#"\b(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})\b"#, "[redacted-token]"),
        (#"\bsk-[A-Za-z0-9_-]{16,}\b"#, "[redacted-token]"),
        (#"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"#, "[redacted-access-key]"),
        (#"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#, "[redacted-token]"),
        (#"://[^\s/@:]+:[^\s/@]+@"#, "://[redacted]@"),
    ]
}
