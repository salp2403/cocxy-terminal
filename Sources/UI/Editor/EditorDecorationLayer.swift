// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorDecorationLayer.swift - Applies domain decorations to attributed editor text.

import AppKit

enum EditorDecorationLayer {
    static func apply(_ decorationSet: EditorDecorationSet, to textStorage: NSTextStorage, textLength: Int) {
        let fullRange = NSRange(location: 0, length: max(0, textLength))
        textStorage.beginEditing()
        textStorage.removeAttribute(.foregroundColor, range: fullRange)
        textStorage.removeAttribute(.backgroundColor, range: fullRange)
        textStorage.removeAttribute(.underlineStyle, range: fullRange)
        textStorage.removeAttribute(.underlineColor, range: fullRange)

        for decoration in decorationSet.decorations {
            let clamped = decoration.range.clamped(to: textLength)
            guard clamped.length > 0 else { continue }
            let range = NSRange(location: clamped.location, length: clamped.length)
            textStorage.addAttributes(attributes(for: decoration), range: range)
        }

        textStorage.endEditing()
    }

    private static func attributes(for decoration: EditorDecoration) -> [NSAttributedString.Key: Any] {
        switch decoration.kind {
        case .searchResult:
            return [.backgroundColor: NSColor.systemYellow.withAlphaComponent(0.28)]
        case .diagnostic:
            let color: NSColor
            switch decoration.severity {
            case .error:
                color = .systemRed
            case .warning:
                color = .systemOrange
            case .info, nil:
                color = .systemBlue
            }
            return [
                .underlineStyle: NSUnderlineStyle.patternDot.rawValue | NSUnderlineStyle.single.rawValue,
                .underlineColor: color,
            ]
        case .syntaxToken:
            return [.foregroundColor: syntaxColor(for: decoration.message)]
        case .selection:
            return [.backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.18)]
        case .inlineHint:
            return [.foregroundColor: CocxyColors.overlay1]
        case .custom:
            return [.backgroundColor: NSColor.controlAccentColor.withAlphaComponent(0.12)]
        }
    }

    private static func syntaxColor(for message: String?) -> NSColor {
        switch message {
        case "syntax.keyword":
            return CocxyColors.mauve
        case "syntax.string":
            return CocxyColors.green
        case "syntax.comment":
            return CocxyColors.overlay1
        case "syntax.function":
            return CocxyColors.blue
        case "syntax.type":
            return CocxyColors.lavender
        case "syntax.variable":
            return CocxyColors.text
        case "syntax.number":
            return CocxyColors.peach
        case "syntax.operatorToken", "syntax.operator":
            return CocxyColors.sky
        case "syntax.punctuation":
            return CocxyColors.subtext1
        default:
            return CocxyColors.text
        }
    }
}
