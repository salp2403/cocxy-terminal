// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultArgvExtractor.swift - Session id extraction and argv redaction.

import Foundation

public enum VaultArgvExtractor {
    private static let sessionFlags: Set<String> = [
        "--session",
        "--session-id",
        "--conversation",
        "--conversation-id",
        "--resume",
        "--restore",
    ]

    private static let sensitiveFlags: Set<String> = [
        "--api-key",
        "--auth-token",
        "--key",
        "--token",
        "--access-token",
        "--secret",
        "--password",
        "--prompt",
        "--message",
        "--input",
    ]

    private static let sensitiveKeyFragments = [
        "api_key",
        "apikey",
        "access_token",
        "auth_token",
        "token",
        "secret",
        "password",
    ]

    public static func extractSessionID(from arguments: [String]) -> String? {
        guard !arguments.isEmpty else { return nil }

        for (index, argument) in arguments.enumerated() {
            if let separator = argument.firstIndex(of: "=") {
                let key = String(argument[..<separator]).lowercased()
                let value = String(argument[argument.index(after: separator)...])
                if sessionFlags.contains(key), !value.isEmpty {
                    return value
                }
            }

            if sessionFlags.contains(argument.lowercased()), index + 1 < arguments.count {
                let value = arguments[index + 1]
                if !value.hasPrefix("-"), !value.isEmpty {
                    return value
                }
            }
        }

        for keyword in ["resume", "restore", "continue"] {
            if let index = arguments.firstIndex(where: { $0.lowercased() == keyword }),
               index + 1 < arguments.count {
                let value = arguments[index + 1]
                if !value.hasPrefix("-"), !value.isEmpty {
                    return value
                }
            }
        }

        return nil
    }

    public static func sanitizedArguments(from arguments: [String]) -> [String] {
        var sanitized: [String] = []
        var redactNext = false

        for argument in arguments {
            if redactNext {
                sanitized.append("<redacted>")
                redactNext = false
                continue
            }

            if let separator = argument.firstIndex(of: "=") {
                let key = String(argument[..<separator])
                let normalizedKey = key.lowercased()
                if sensitiveFlags.contains(normalizedKey) || containsSensitiveFragment(normalizedKey) {
                    sanitized.append("\(key)=<redacted>")
                    continue
                }
            }

            let normalized = argument.lowercased()
            if sensitiveFlags.contains(normalized) {
                sanitized.append(argument)
                redactNext = true
                continue
            }

            sanitized.append(argument)
        }

        return sanitized
    }

    private static func containsSensitiveFragment(_ key: String) -> Bool {
        sensitiveKeyFragments.contains { key.contains($0) }
    }
}
