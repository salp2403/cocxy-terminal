// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RichInputSnippetExpander.swift - Inline snippet expansion for terminal rich input.

import Foundation

struct RichInputTextEdit: Equatable, Sendable {
    let text: String
    let selectedRange: NSRange
}

struct RichInputSnippetExpander {
    private let snippetManager: SnippetManager
    private let scope: String?

    init(
        snippetManager: SnippetManager = SnippetManager(),
        scope: String? = nil
    ) {
        self.snippetManager = snippetManager
        self.scope = scope
    }

    func expandSnippet(in text: String, selectedRange: NSRange) -> RichInputTextEdit? {
        guard selectedRange.length == 0 else { return nil }
        let nsText = text as NSString
        let cursor = min(max(0, selectedRange.location), nsText.length)
        guard let token = colonTriggerToken(in: nsText, endingAt: cursor) else { return nil }

        let expansion = expansion(for: token.trigger)
        guard let expansion else { return nil }

        let before = nsText.substring(to: token.range.location)
        let after = nsText.substring(from: cursor)
        let replacement = expansion.renderedText
        let editedText = before + replacement + after
        let baseLocation = (before as NSString).length
        let selectedRange = selectionRange(for: expansion, baseLocation: baseLocation)
        return RichInputTextEdit(text: editedText, selectedRange: selectedRange)
    }

    private func expansion(for trigger: String) -> SnippetExpansion? {
        if let expansion = try? snippetManager.expand(trigger: trigger, scope: scope) {
            return expansion
        }
        return try? snippetManager.expand(trigger: ":\(trigger)", scope: scope)
    }

    private func selectionRange(
        for expansion: SnippetExpansion,
        baseLocation: Int
    ) -> NSRange {
        guard let firstStop = expansion.nextTabStop(after: nil) else {
            return NSRange(
                location: baseLocation + (expansion.renderedText as NSString).length,
                length: 0
            )
        }
        return NSRange(
            location: baseLocation + firstStop.range.location,
            length: firstStop.range.length
        )
    }

    private func colonTriggerToken(
        in text: NSString,
        endingAt cursor: Int
    ) -> (trigger: String, range: NSRange)? {
        guard cursor > 1 else { return nil }

        var start = cursor
        while start > 0 {
            let scalar = text.character(at: start - 1)
            guard !CharacterSet.whitespacesAndNewlines.contains(UnicodeScalar(scalar) ?? " ") else {
                break
            }
            start -= 1
        }

        let range = NSRange(location: start, length: cursor - start)
        guard range.length > 1 else { return nil }
        let token = text.substring(with: range)
        guard token.hasPrefix(":") else { return nil }

        let trigger = String(token.dropFirst())
        guard trigger.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return (trigger, range)
    }
}
