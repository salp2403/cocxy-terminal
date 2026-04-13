// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownInlineParser+ReferenceLinks.swift - Link/image parsing helpers.

import Foundation

extension MarkdownInlineParser.Scanner {
    mutating func parseLink(from start: Int) -> (MarkdownInline, Int)? {
        guard start < chars.count, chars[start] == "[" else { return nil }

        var depth = 1
        var i = start + 1
        while i < chars.count {
            let ch = chars[i]
            if ch == "\\" {
                i += 2
                continue
            }
            if ch == "[" {
                depth += 1
            } else if ch == "]" {
                depth -= 1
                if depth == 0 { break }
            }
            i += 1
        }
        guard i < chars.count, depth == 0 else { return nil }

        let textRange = (start + 1)..<i
        let afterBracket = i + 1
        let linkText = String(chars[textRange])
        let innerNodes = parseNested(linkText)

        if afterBracket < chars.count, chars[afterBracket] == "(" {
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
                    if parenDepth == 0 { break }
                    urlBuffer.append(chars[j])
                    j += 1
                    continue
                }
                urlBuffer.append(chars[j])
                j += 1
            }

            guard j < chars.count, chars[j] == ")", parenDepth == 0 else { return nil }
            return (.link(text: innerNodes, url: urlBuffer.trimmingCharacters(in: .whitespaces)), j + 1)
        }

        func resolveReference(label: String) -> MarkdownInline? {
            let normalized = MarkdownParser.normalizedReferenceLinkLabel(label)
            guard let url = linkDefinitions[normalized] else { return nil }
            return .link(text: innerNodes, url: url)
        }

        if afterBracket < chars.count, chars[afterBracket] == "[" {
            var j = afterBracket + 1
            var labelBuffer = ""
            while j < chars.count, chars[j] != "]" {
                if chars[j] == "\\" && j + 1 < chars.count {
                    labelBuffer.append(chars[j + 1])
                    j += 2
                    continue
                }
                if chars[j] == "\n" { return nil }
                labelBuffer.append(chars[j])
                j += 1
            }
            guard j < chars.count, chars[j] == "]" else { return nil }

            let referenceLabel = labelBuffer.isEmpty ? linkText : labelBuffer
            guard let link = resolveReference(label: referenceLabel) else { return nil }
            return (link, j + 1)
        }

        if let link = resolveReference(label: linkText) {
            return (link, afterBracket)
        }

        return nil
    }

    mutating func parseImage(from start: Int) -> (MarkdownInline, Int)? {
        guard start + 1 < chars.count, chars[start] == "!", chars[start + 1] == "[" else {
            return nil
        }

        guard let (linkNode, endIndex) = parseLink(from: start + 1) else {
            return nil
        }

        if case .link(let textInlines, let url) = linkNode {
            let alt = MarkdownOutline.plainText(from: textInlines)
            return (.image(alt: alt, url: url), endIndex)
        }
        return nil
    }
}
