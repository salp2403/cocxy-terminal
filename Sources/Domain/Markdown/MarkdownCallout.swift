// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownCallout.swift - Callout/admonition helpers for markdown parsing/rendering.

import Foundation

public enum MarkdownCalloutType: String, CaseIterable, Equatable, Sendable {
    case note
    case tip
    case important
    case warning
    case caution
    case abstract
    case todo
    case bug

    public var marker: String {
        rawValue.uppercased()
    }

    public var title: String {
        switch self {
        case .note: return "Note"
        case .tip: return "Tip"
        case .important: return "Important"
        case .warning: return "Warning"
        case .caution: return "Caution"
        case .abstract: return "Abstract"
        case .todo: return "Todo"
        case .bug: return "Bug"
        }
    }

    public var icon: String {
        switch self {
        case .note: return "ℹ"
        case .tip: return "💡"
        case .important: return "❗"
        case .warning: return "⚠"
        case .caution: return "⛔"
        case .abstract: return "📋"
        case .todo: return "☑"
        case .bug: return "🐞"
        }
    }
}

enum MarkdownCallout {
    static func parseHeader(_ line: String) -> (type: MarkdownCalloutType, title: String, isFolded: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[!"), let closing = trimmed.firstIndex(of: "]") else {
            return nil
        }

        let rawType = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<closing]
        guard let type = MarkdownCalloutType(rawValue: rawType.lowercased()) else {
            return nil
        }

        var remainder = trimmed[trimmed.index(after: closing)...]
        var isFolded = false
        if remainder.first == "-" {
            isFolded = true
            remainder = remainder.dropFirst()
        }

        let customTitle = remainder.trimmingCharacters(in: .whitespaces)
        return (
            type: type,
            title: customTitle.isEmpty ? type.title : customTitle,
            isFolded: isFolded
        )
    }
}
