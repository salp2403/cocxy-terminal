// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownSyntaxHighlighter.swift - Applies per-token styling to raw markdown source.

import AppKit

// MARK: - Syntax Highlighter

/// Applies syntax highlighting to a raw markdown source string, producing
/// an attributed string ready to drop into an `NSTextView`.
///
/// The highlighter does NOT parse blocks recursively — it is a line-level
/// pass over the raw source that recognises:
/// - Headings (`#` ... `######`)
/// - Blockquotes (`>`)
/// - List markers (`-`, `*`, `+`, `N.`, `N)`)
/// - Task markers (`[ ]`, `[x]`)
/// - Fenced code blocks (inside ``` ... ```)
/// - Inline markers (`**`, `*`, `_`, `~~`, `` ` ``, `[...](...)`)
///
/// Using the source directly (rather than the AST) keeps positions aligned
/// with the original text so the user can select any character without
/// surprises. For the preview pane we use `MarkdownRenderer` instead.
@MainActor
public struct MarkdownSyntaxHighlighter {

    public let theme: MarkdownRenderTheme

    public init(theme: MarkdownRenderTheme = .cocxyDefault) {
        self.theme = theme
    }

    // MARK: - Entry Point

    /// Highlights `source` in place, returning a new attributed string.
    public func highlight(_ source: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: source, attributes: defaultAttributes)

        let lines = source.components(separatedBy: "\n")
        var inFence = false
        var cursor = 0

        for line in lines {
            let lineRange = NSRange(location: cursor, length: line.utf16.count)
            applyLineHighlight(line: line, range: lineRange, into: result, inFence: &inFence)
            cursor += line.utf16.count + 1 // +1 for the \n separator
        }

        return result
    }

    // MARK: - Line Pass

    private var defaultAttributes: [NSAttributedString.Key: Any] {
        [
            .font: theme.codeFont,
            .foregroundColor: theme.textColor
        ]
    }

    private func applyLineHighlight(
        line: String,
        range: NSRange,
        into output: NSMutableAttributedString,
        inFence: inout Bool
    ) {
        // Fenced code: toggle state on triple-backtick line.
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
            output.addAttributes([
                .foregroundColor: theme.subtleColor
            ], range: range)
            inFence.toggle()
            return
        }
        if inFence {
            output.addAttributes([
                .foregroundColor: theme.codeColor,
                .backgroundColor: theme.codeBackground
            ], range: range)
            return
        }

        // Blank line: nothing to highlight.
        if trimmed.isEmpty { return }

        // Headings.
        if let level = atxHeadingLevel(trimmed) {
            let idx = max(0, min(theme.headingColors.count - 1, level - 1))
            output.addAttributes([
                .foregroundColor: theme.headingColors[idx],
                .font: theme.boldFont
            ], range: range)
            return
        }

        // Horizontal rule.
        if trimmed.count >= 3,
           let first = trimmed.first,
           "-_*".contains(first),
           trimmed.allSatisfy({ $0 == first || $0 == " " }) {
            output.addAttributes([.foregroundColor: theme.subtleColor], range: range)
            return
        }

        // Blockquote.
        if trimmed.hasPrefix(">") {
            output.addAttributes([
                .foregroundColor: theme.quoteColor,
                .font: theme.italicFont
            ], range: range)
            return
        }

        // List marker prefix.
        if let markerRange = leadingListMarkerRange(line: line, absoluteStart: range.location) {
            output.addAttributes([
                .foregroundColor: theme.linkColor,
                .font: theme.boldFont
            ], range: markerRange)
        }

        // Task marker `[ ]` / `[x]`.
        highlightTaskMarker(line: line, lineStart: range.location, into: output)

        // Inline markers.
        highlightInlineMarkers(line: line, lineStart: range.location, into: output)
    }

    // MARK: - Headings

    private func atxHeadingLevel(_ trimmed: String) -> Int? {
        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let afterHashes = trimmed.dropFirst(level)
        guard afterHashes.first == " " || afterHashes.first == "\t" else { return nil }
        return level
    }

    // MARK: - List Markers

    private func leadingListMarkerRange(
        line: String,
        absoluteStart: Int
    ) -> NSRange? {
        // Skip leading spaces.
        var i = 0
        let chars = Array(line)
        while i < chars.count && chars[i] == " " && i < 4 {
            i += 1
        }
        guard i < chars.count else { return nil }

        // Unordered marker.
        if "-*+".contains(chars[i]) {
            if i + 1 >= chars.count || chars[i + 1] == " " {
                return NSRange(location: absoluteStart + i, length: 1)
            }
        }

        // Ordered marker.
        var j = i
        while j < chars.count && chars[j].isNumber { j += 1 }
        if j > i, j < chars.count, chars[j] == "." || chars[j] == ")" {
            if j + 1 >= chars.count || chars[j + 1] == " " {
                return NSRange(location: absoluteStart + i, length: (j - i) + 1)
            }
        }

        return nil
    }

    // MARK: - Task Marker

    private func highlightTaskMarker(
        line: String,
        lineStart: Int,
        into output: NSMutableAttributedString
    ) {
        let nsLine = line as NSString
        let checkedRange = nsLine.range(of: "[x]", options: [.caseInsensitive])
        let uncheckedRange = nsLine.range(of: "[ ]")
        if checkedRange.location != NSNotFound {
            output.addAttributes([
                .foregroundColor: theme.linkColor,
                .font: theme.boldFont
            ], range: NSRange(
                location: lineStart + checkedRange.location,
                length: checkedRange.length
            ))
        }
        if uncheckedRange.location != NSNotFound {
            output.addAttributes([
                .foregroundColor: theme.subtleColor,
                .font: theme.boldFont
            ], range: NSRange(
                location: lineStart + uncheckedRange.location,
                length: uncheckedRange.length
            ))
        }
    }

    // MARK: - Inline Markers

    private func highlightInlineMarkers(
        line: String,
        lineStart: Int,
        into output: NSMutableAttributedString
    ) {
        let nsLine = line as NSString
        let length = nsLine.length

        // Inline code `...`.
        applyRegex(pattern: "`[^`\n]+`",
                   attributes: [
                       .foregroundColor: theme.codeColor,
                       .backgroundColor: theme.codeBackground
                   ],
                   line: nsLine,
                   length: length,
                   lineStart: lineStart,
                   into: output)

        // Strong `**...**`.
        applyRegex(pattern: "\\*\\*[^*\n]+\\*\\*",
                   attributes: [
                       .font: theme.boldFont,
                       .foregroundColor: theme.textColor
                   ],
                   line: nsLine,
                   length: length,
                   lineStart: lineStart,
                   into: output)

        // Emphasis `*...*` (not matching `**`).
        applyRegex(pattern: "(?<!\\*)\\*[^*\n]+\\*(?!\\*)",
                   attributes: [
                       .font: theme.italicFont,
                       .foregroundColor: theme.textColor
                   ],
                   line: nsLine,
                   length: length,
                   lineStart: lineStart,
                   into: output)

        // Strike `~~...~~`.
        applyRegex(pattern: "~~[^~\n]+~~",
                   attributes: [
                       .foregroundColor: theme.strikeColor,
                       .strikethroughStyle: NSUnderlineStyle.single.rawValue
                   ],
                   line: nsLine,
                   length: length,
                   lineStart: lineStart,
                   into: output)

        // Link `[text](url)`.
        applyRegex(pattern: "\\[[^\\]\n]+\\]\\([^)\n]+\\)",
                   attributes: [
                       .foregroundColor: theme.linkColor,
                       .underlineStyle: NSUnderlineStyle.single.rawValue
                   ],
                   line: nsLine,
                   length: length,
                   lineStart: lineStart,
                   into: output)
    }

    private func applyRegex(
        pattern: String,
        attributes: [NSAttributedString.Key: Any],
        line: NSString,
        length: Int,
        lineStart: Int,
        into output: NSMutableAttributedString
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: length)
        regex.enumerateMatches(in: line as String, range: range) { match, _, _ in
            guard let match else { return }
            let absolute = NSRange(
                location: lineStart + match.range.location,
                length: match.range.length
            )
            output.addAttributes(attributes, range: absolute)
        }
    }
}
