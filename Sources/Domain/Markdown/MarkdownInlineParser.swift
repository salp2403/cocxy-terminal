// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownInlineParser.swift - Converts raw inline markdown text into AST nodes.

import Foundation

// MARK: - Inline Parser

/// Parses inline markdown syntax into `MarkdownInline` trees.
///
/// The inline parser is stateless and re-entrant: `parse(_:)` produces a
/// fresh array for each call. It recognizes code spans first (so inline
/// code wins over any delimiter contained inside its backticks), then
/// strong/emphasis/strike, then links and autolinks.
///
/// Adjacent text fragments are collapsed so consumers can assume no two
/// consecutive `.text` cases appear in the output.
public struct MarkdownInlineParser {

    public init() {}

    /// Parses a single inline string into AST nodes.
    public func parse(_ text: String) -> [MarkdownInline] {
        if text.isEmpty { return [] }
        var scanner = Scanner(text)
        let inlines = scanner.parseRun()
        return MarkdownInlineParser.flatten(inlines)
    }

    // MARK: - Flatten

    /// Merges adjacent `.text` runs so `[.text("a"), .text("b")]` becomes
    /// `[.text("ab")]`. Applied recursively inside emphasis/strong/strike/link.
    static func flatten(_ inlines: [MarkdownInline]) -> [MarkdownInline] {
        var result: [MarkdownInline] = []
        result.reserveCapacity(inlines.count)
        for inline in inlines {
            let normalized = flattenSingle(inline)
            if case .text(let newText) = normalized,
               case .text(let previousText)? = result.last {
                result[result.count - 1] = .text(previousText + newText)
            } else {
                result.append(normalized)
            }
        }
        return result
    }

    private static func flattenSingle(_ inline: MarkdownInline) -> MarkdownInline {
        switch inline {
        case .text, .code, .autolink, .lineBreak, .image, .footnoteRef:
            return inline
        case .strong(let nested):
            return .strong(inlines: flatten(nested))
        case .emphasis(let nested):
            return .emphasis(inlines: flatten(nested))
        case .strike(let nested):
            return .strike(inlines: flatten(nested))
        case .highlight(let nested):
            return .highlight(inlines: flatten(nested))
        case .superscript(let nested):
            return .superscript(inlines: flatten(nested))
        case .`subscript`(let nested):
            return .`subscript`(inlines: flatten(nested))
        case .link(let nested, let url):
            return .link(text: flatten(nested), url: url)
        }
    }
}

// MARK: - Scanner

private extension MarkdownInlineParser {

    /// Character-level scanner with cursor + lookahead. Designed for one
    /// pass per inline parse; callers never share a scanner.
    struct Scanner {
        let chars: [Character]
        var index: Int = 0

        init(_ text: String) {
            self.chars = Array(text)
        }

        var isAtEnd: Bool { index >= chars.count }

        // MARK: Parsing

        /// Parses a run of inlines until the end of the input or an early
        /// terminator (used by link text parsing). `stopAt` is a closing
        /// bracket expected by a parent context.
        mutating func parseRun(stopAt: Character? = nil) -> [MarkdownInline] {
            var output: [MarkdownInline] = []
            var textBuffer = ""

            func flushText() {
                if !textBuffer.isEmpty {
                    output.append(.text(textBuffer))
                    textBuffer = ""
                }
            }

            while !isAtEnd {
                let ch = chars[index]

                if let stop = stopAt, ch == stop {
                    flushText()
                    return output
                }

                switch ch {
                case "\\":
                    // Backslash escape: `\*` → literal `*`.
                    if index + 1 < chars.count {
                        let next = chars[index + 1]
                        if Self.isEscapable(next) {
                            textBuffer.append(next)
                            index += 2
                            continue
                        }
                    }
                    textBuffer.append(ch)
                    index += 1

                case "`":
                    // Inline code span. Consume as many backticks as appear
                    // at the opening and then match the same run length.
                    if let (code, newIndex) = parseCodeSpan(from: index) {
                        flushText()
                        output.append(.code(text: code))
                        index = newIndex
                    } else {
                        textBuffer.append(ch)
                        index += 1
                    }

                case "*", "_":
                    if let (nodes, newIndex) = parseEmphasis(from: index) {
                        flushText()
                        output.append(contentsOf: nodes)
                        index = newIndex
                    } else {
                        textBuffer.append(ch)
                        index += 1
                    }

                case "~":
                    if let (node, newIndex) = parseStrike(from: index) {
                        flushText()
                        output.append(node)
                        index = newIndex
                    } else if let (node, newIndex) = parseSubscript(from: index) {
                        flushText()
                        output.append(node)
                        index = newIndex
                    } else {
                        textBuffer.append(ch)
                        index += 1
                    }

                case "=":
                    if let (node, newIndex) = parseHighlight(from: index) {
                        flushText()
                        output.append(node)
                        index = newIndex
                    } else {
                        textBuffer.append(ch)
                        index += 1
                    }

                case "^":
                    if let (node, newIndex) = parseSuperscript(from: index) {
                        flushText()
                        output.append(node)
                        index = newIndex
                    } else {
                        textBuffer.append(ch)
                        index += 1
                    }

                case "!":
                    if index + 1 < chars.count, chars[index + 1] == "[",
                       let (node, newIndex) = parseImage(from: index) {
                        flushText()
                        output.append(node)
                        index = newIndex
                    } else {
                        textBuffer.append(ch)
                        index += 1
                    }

                case "[":
                    if let (node, newIndex) = parseFootnoteRef(from: index) {
                        flushText()
                        output.append(node)
                        index = newIndex
                    } else if let (node, newIndex) = parseLink(from: index) {
                        flushText()
                        output.append(node)
                        index = newIndex
                    } else {
                        textBuffer.append(ch)
                        index += 1
                    }

                case "<":
                    if let (node, newIndex) = parseAutolink(from: index) {
                        flushText()
                        output.append(node)
                        index = newIndex
                    } else {
                        textBuffer.append(ch)
                        index += 1
                    }

                case ":":
                    if let (emoji, newIndex) = parseEmoji(from: index) {
                        flushText()
                        output.append(.text(emoji))
                        index = newIndex
                    } else {
                        textBuffer.append(ch)
                        index += 1
                    }

                default:
                    textBuffer.append(ch)
                    index += 1
                }
            }

            flushText()
            return output
        }

        // MARK: Code Span

        func parseCodeSpan(from start: Int) -> (String, Int)? {
            var openCount = 0
            var i = start
            while i < chars.count, chars[i] == "`" {
                openCount += 1
                i += 1
            }
            guard openCount > 0 else { return nil }

            var contentStart = i
            while contentStart < chars.count {
                if chars[contentStart] == "`" {
                    var runLen = 0
                    var j = contentStart
                    while j < chars.count, chars[j] == "`" {
                        runLen += 1
                        j += 1
                    }
                    if runLen == openCount {
                        let content = String(chars[i..<contentStart])
                        // CommonMark: trim single leading/trailing space if
                        // the content isn't only spaces and starts+ends with
                        // a space.
                        let trimmed = Self.trimCodeSpan(content)
                        return (trimmed, j)
                    } else {
                        contentStart = j
                    }
                } else {
                    contentStart += 1
                }
            }
            return nil
        }

        static func trimCodeSpan(_ raw: String) -> String {
            guard raw.count >= 2, raw.first == " ", raw.last == " " else {
                return raw
            }
            if raw.allSatisfy({ $0 == " " }) { return raw }
            return String(raw.dropFirst().dropLast())
        }

        // MARK: Emphasis / Strong

        /// Parses `**strong**`, `__strong__`, `*emphasis*`, `_emphasis_` and
        /// combinations like `***both***`. Returns the parsed nodes and the
        /// new cursor position.
        mutating func parseEmphasis(from start: Int) -> ([MarkdownInline], Int)? {
            let marker = chars[start]
            guard marker == "*" || marker == "_" else { return nil }

            // Count opening marker run.
            var runStart = start
            var runLen = 0
            while runStart < chars.count, chars[runStart] == marker {
                runLen += 1
                runStart += 1
            }
            guard runLen > 0 else { return nil }

            // For `_` we require word-boundary semantics: emphasis can't
            // open in the middle of a word (CommonMark section 6.4).
            if marker == "_", start > 0, Self.isAlphaNum(chars[start - 1]) {
                return nil
            }

            // Find matching closing run of at least 1 marker.
            let target = min(runLen, 2) // cap at strong (2). Triple is strong+em.
            let tripleMode = runLen >= 3

            // Walk forward looking for a closing run of length `target` at
            // minimum. Skip content inside code spans and nested brackets.
            var i = runStart
            while i < chars.count {
                let ch = chars[i]

                if ch == "\\" && i + 1 < chars.count {
                    i += 2
                    continue
                }
                if ch == "`" {
                    if let (_, endCode) = parseCodeSpan(from: i) {
                        i = endCode
                        continue
                    }
                }

                if ch == marker {
                    var closeLen = 0
                    var j = i
                    while j < chars.count, chars[j] == marker {
                        closeLen += 1
                        j += 1
                    }

                    // For `_`, the close must not be followed by alnum
                    // (word boundary).
                    if marker == "_", j < chars.count, Self.isAlphaNum(chars[j]) {
                        i = j
                        continue
                    }
                    // For `*`, the close must not be preceded by whitespace
                    // directly (already guaranteed by bounds) and not
                    // followed by alnum-run adjacency... we keep it simple
                    // and accept any non-empty run.

                    if closeLen >= target {
                        let innerText = String(chars[runStart..<i])
                        let innerNodes = MarkdownInlineParser().parse(innerText)
                        if tripleMode && closeLen >= 3 {
                            let wrapped: [MarkdownInline] = [
                                .strong(inlines: [.emphasis(inlines: innerNodes)])
                            ]
                            return (wrapped, i + 3)
                        } else if target == 2 {
                            return ([.strong(inlines: innerNodes)], i + 2)
                        } else {
                            return ([.emphasis(inlines: innerNodes)], i + 1)
                        }
                    }
                    i = j
                    continue
                }

                i += 1
            }

            return nil
        }

        // MARK: Strikethrough (GFM)

        mutating func parseStrike(from start: Int) -> (MarkdownInline, Int)? {
            guard start + 1 < chars.count,
                  chars[start] == "~",
                  chars[start + 1] == "~" else { return nil }

            let contentStart = start + 2
            var i = contentStart
            while i + 1 < chars.count {
                if chars[i] == "\\" {
                    i += 2
                    continue
                }
                if chars[i] == "~" && chars[i + 1] == "~" {
                    let innerText = String(chars[contentStart..<i])
                    let innerNodes = MarkdownInlineParser().parse(innerText)
                    return (.strike(inlines: innerNodes), i + 2)
                }
                i += 1
            }
            return nil
        }

        // MARK: Highlight

        mutating func parseHighlight(from start: Int) -> (MarkdownInline, Int)? {
            guard start + 1 < chars.count,
                  chars[start] == "=",
                  chars[start + 1] == "=" else { return nil }

            let contentStart = start + 2
            var i = contentStart
            while i + 1 < chars.count {
                if chars[i] == "\\" {
                    i += 2
                    continue
                }
                if chars[i] == "=" && chars[i + 1] == "=" {
                    let innerText = String(chars[contentStart..<i])
                    guard !innerText.isEmpty else { return nil }
                    let innerNodes = MarkdownInlineParser().parse(innerText)
                    return (.highlight(inlines: innerNodes), i + 2)
                }
                i += 1
            }
            return nil
        }

        // MARK: Superscript / Subscript

        mutating func parseSuperscript(from start: Int) -> (MarkdownInline, Int)? {
            parseSingleMarkerInline(from: start, marker: "^", wrap: { .superscript(inlines: $0) })
        }

        mutating func parseSubscript(from start: Int) -> (MarkdownInline, Int)? {
            guard start + 1 >= chars.count || chars[start + 1] != "~" else { return nil }
            return parseSingleMarkerInline(from: start, marker: "~", wrap: { .`subscript`(inlines: $0) })
        }

        mutating func parseSingleMarkerInline(
            from start: Int,
            marker: Character,
            wrap: ([MarkdownInline]) -> MarkdownInline
        ) -> (MarkdownInline, Int)? {
            guard start < chars.count, chars[start] == marker else { return nil }
            let contentStart = start + 1
            guard contentStart < chars.count else { return nil }

            var i = contentStart
            while i < chars.count {
                if chars[i] == "\\" {
                    i += 2
                    continue
                }
                if chars[i] == marker {
                    let innerText = String(chars[contentStart..<i])
                    guard !innerText.isEmpty,
                          !innerText.hasPrefix(" "),
                          !innerText.hasSuffix(" "),
                          !innerText.contains("\n") else { return nil }
                    let innerNodes = MarkdownInlineParser().parse(innerText)
                    return (wrap(innerNodes), i + 1)
                }
                i += 1
            }
            return nil
        }

        // MARK: Link

        mutating func parseFootnoteRef(from start: Int) -> (MarkdownInline, Int)? {
            guard start + 3 < chars.count,
                  chars[start] == "[",
                  chars[start + 1] == "^" else { return nil }

            var i = start + 2
            var idBuffer = ""
            while i < chars.count, chars[i] != "]" {
                if chars[i] == "\n" { return nil }
                idBuffer.append(chars[i])
                i += 1
            }
            guard i < chars.count,
                  chars[i] == "]",
                  !idBuffer.isEmpty,
                  !idBuffer.contains("["),
                  !idBuffer.contains("]") else {
                return nil
            }
            return (.footnoteRef(id: idBuffer), i + 1)
        }

        mutating func parseLink(from start: Int) -> (MarkdownInline, Int)? {
            guard start < chars.count, chars[start] == "[" else { return nil }

            // Find matching `]` respecting nested brackets.
            var depth = 1
            var i = start + 1
            while i < chars.count {
                let ch = chars[i]
                if ch == "\\" { i += 2; continue }
                if ch == "[" { depth += 1 }
                else if ch == "]" {
                    depth -= 1
                    if depth == 0 { break }
                }
                i += 1
            }
            guard i < chars.count, depth == 0 else { return nil }

            let textRange = (start + 1)..<i
            let afterBracket = i + 1

            // Expect immediately a `(` for an inline link.
            guard afterBracket < chars.count, chars[afterBracket] == "(" else {
                return nil
            }

            // Parse URL up to the matching `)`, allowing balanced parentheses
            // inside the URL itself (`foo(bar).png`).
            var j = afterBracket + 1
            var urlBuffer = ""
            var parenDepth = 1
            while j < chars.count {
                if chars[j] == "\\" && j + 1 < chars.count {
                    urlBuffer.append(chars[j + 1])
                    j += 2
                    continue
                }
                if chars[j] == "(" {
                    parenDepth += 1
                    urlBuffer.append(chars[j])
                    j += 1
                    continue
                }
                if chars[j] == ")" {
                    parenDepth -= 1
                    if parenDepth == 0 {
                        break
                    }
                    urlBuffer.append(chars[j])
                    j += 1
                    continue
                }
                urlBuffer.append(chars[j])
                j += 1
            }
            guard j < chars.count, chars[j] == ")", parenDepth == 0 else { return nil }

            let linkText = String(chars[textRange])
            let innerNodes = MarkdownInlineParser().parse(linkText)
            return (.link(text: innerNodes, url: urlBuffer.trimmingCharacters(in: .whitespaces)), j + 1)
        }

        // MARK: Image

        mutating func parseImage(from start: Int) -> (MarkdownInline, Int)? {
            // Image syntax: ![alt](url)
            // start points to '!', start+1 must be '['
            guard start + 1 < chars.count, chars[start] == "!", chars[start + 1] == "[" else {
                return nil
            }

            // Reuse link parsing from the '[' position
            guard let (linkNode, endIndex) = parseLink(from: start + 1) else {
                return nil
            }

            // Extract alt text and URL from the link node
            if case .link(let textInlines, let url) = linkNode {
                let alt = MarkdownOutline.plainText(from: textInlines)
                return (.image(alt: alt, url: url), endIndex)
            }
            return nil
        }

        // MARK: Autolink

        func parseAutolink(from start: Int) -> (MarkdownInline, Int)? {
            guard start < chars.count, chars[start] == "<" else { return nil }

            var i = start + 1
            var buffer = ""
            while i < chars.count, chars[i] != ">" {
                if chars[i] == " " || chars[i] == "\n" { return nil }
                buffer.append(chars[i])
                i += 1
            }
            guard i < chars.count, chars[i] == ">", !buffer.isEmpty else {
                return nil
            }

            // Must look like a URL scheme: `scheme:rest` with scheme
            // starting with ASCII alpha, up to 32 chars, then `:`.
            guard Self.isAutolinkURL(buffer) else { return nil }

            return (.autolink(url: buffer), i + 1)
        }

        // MARK: Emoji

        mutating func parseEmoji(from start: Int) -> (String, Int)? {
            guard start < chars.count, chars[start] == ":" else { return nil }
            var i = start + 1
            var shortcode = ""
            while i < chars.count, chars[i] != ":" {
                let ch = chars[i]
                guard ch.isLetter || ch.isNumber || ch == "_" || ch == "+" || ch == "-" else {
                    return nil
                }
                shortcode.append(ch)
                i += 1
            }
            guard i < chars.count, chars[i] == ":", !shortcode.isEmpty else { return nil }
            guard let emoji = MarkdownEmoji.resolve(shortcode) else { return nil }
            return (emoji, i + 1)
        }

        // MARK: Character Classes

        static func isEscapable(_ ch: Character) -> Bool {
            let escapable: Set<Character> = [
                "\\", "`", "*", "_", "{", "}", "[", "]", "(", ")",
                "#", "+", "-", ".", "!", "|", "~", ">", "<"
            ]
            return escapable.contains(ch)
        }

        static func isAlphaNum(_ ch: Character) -> Bool {
            ch.isLetter || ch.isNumber
        }

        static func isAutolinkURL(_ text: String) -> Bool {
            let colonIndex = text.firstIndex(of: ":")
            guard let colon = colonIndex else { return false }
            let scheme = text[..<colon]
            guard !scheme.isEmpty, scheme.count <= 32 else { return false }
            guard scheme.first?.isLetter == true else { return false }
            for ch in scheme {
                if !(ch.isLetter || ch.isNumber || ch == "+" || ch == "." || ch == "-") {
                    return false
                }
            }
            return colon != text.index(before: text.endIndex)
        }
    }
}
