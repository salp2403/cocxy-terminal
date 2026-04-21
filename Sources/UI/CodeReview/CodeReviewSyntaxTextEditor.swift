// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewSyntaxTextEditor.swift - AppKit-backed syntax editor for Code Review.

import AppKit
import SwiftUI

struct CodeReviewSyntaxTextEditor: NSViewRepresentable {
    @Binding var text: String
    let language: String
    let fontSize: CGFloat
    let commandToken: CodeReviewEditorCommandToken?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = CocxyColors.base

        let textView = NSTextView()
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false
        textView.backgroundColor = CocxyColors.base
        textView.insertionPointColor = CocxyColors.text
        textView.delegate = context.coordinator

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.apply(parent: self)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.apply(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeReviewSyntaxTextEditor
        weak var textView: NSTextView?
        private var isApplying = false
        private var lastLanguage = ""
        private var lastFontSize: CGFloat = 0
        private var lastCommandID: UUID?

        init(parent: CodeReviewSyntaxTextEditor) {
            self.parent = parent
        }

        func apply(parent: CodeReviewSyntaxTextEditor) {
            guard let textView else { return }
            let needsTextSync = textView.string != parent.text
            let needsStyleSync = lastLanguage != parent.language || lastFontSize != parent.fontSize

            if needsTextSync || needsStyleSync {
                isApplying = true
                let selectedRange = textView.selectedRange()
                let scrollOrigin = textView.enclosingScrollView?.contentView.bounds.origin ?? .zero
                let highlighted = CodeReviewSyntaxHighlighter.highlighted(
                    parent.text,
                    language: parent.language,
                    fontSize: parent.fontSize
                )
                textView.textStorage?.setAttributedString(highlighted)
                let safeLocation = min(selectedRange.location, highlighted.length)
                let safeLength = min(selectedRange.length, max(highlighted.length - safeLocation, 0))
                textView.setSelectedRange(NSRange(location: safeLocation, length: safeLength))
                if let clipView = textView.enclosingScrollView?.contentView {
                    clipView.scroll(to: scrollOrigin)
                    textView.enclosingScrollView?.reflectScrolledClipView(clipView)
                }
                lastLanguage = parent.language
                lastFontSize = parent.fontSize
                isApplying = false
            }

            if let commandToken = parent.commandToken, commandToken.id != lastCommandID {
                lastCommandID = commandToken.id
                switch commandToken.kind {
                case .undo:
                    textView.undoManager?.undo()
                case .redo:
                    textView.undoManager?.redo()
                }
                parent.text = textView.string
                // Re-apply highlighting because AppKit undo restores plain
                // attributed runs from the undo stack.
                lastLanguage = ""
                apply(parent: parent)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplying, let textView else { return }
            parent.text = textView.string
            apply(parent: parent)
        }
    }
}

enum CodeReviewSyntaxHighlighter {
    static func highlighted(_ text: String, language: String, fontSize: CGFloat) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: CocxyColors.text,
                .backgroundColor: CocxyColors.base,
            ]
        )

        guard !text.isEmpty else { return result }
        let fullRange = NSRange(text.startIndex..., in: text)
        let tokenSet = TokenSet(language: language)

        apply(patterns: tokenSet.commentPatterns, color: CocxyColors.overlay1, to: result, in: text, range: fullRange)
        apply(patterns: tokenSet.stringPatterns, color: CocxyColors.green, to: result, in: text, range: fullRange)
        apply(patterns: tokenSet.numberPatterns, color: CocxyColors.peach, to: result, in: text, range: fullRange)
        apply(patterns: tokenSet.keywordPatterns, color: CocxyColors.mauve, to: result, in: text, range: fullRange, weight: .semibold)
        apply(patterns: tokenSet.typePatterns, color: CocxyColors.blue, to: result, in: text, range: fullRange, weight: .semibold)

        return result
    }

    private static func apply(
        patterns: [String],
        color: NSColor,
        to result: NSMutableAttributedString,
        in text: String,
        range: NSRange,
        weight: NSFont.Weight = .regular
    ) {
        guard !patterns.isEmpty else { return }
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
                continue
            }
            regex.enumerateMatches(in: text, range: range) { match, _, _ in
                guard let match else { return }
                result.addAttribute(.foregroundColor, value: color, range: match.range)
                if weight != .regular {
                    let size = (result.attribute(.font, at: match.range.location, effectiveRange: nil) as? NSFont)?.pointSize ?? 13
                    result.addAttribute(
                        .font,
                        value: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
                        range: match.range
                    )
                }
            }
        }
    }

    private struct TokenSet {
        let keywordPatterns: [String]
        let typePatterns: [String]
        let stringPatterns: [String]
        let commentPatterns: [String]
        let numberPatterns: [String]

        init(language: String) {
            let lower = language.lowercased()
            stringPatterns = [
                #""(?:\\.|[^"\\])*""#,
                #"'(?:\\.|[^'\\])*'"#,
                #"`(?:\\.|[^`\\])*`"#,
            ]
            numberPatterns = [#"\b[0-9]+(?:\.[0-9]+)?\b"#]

            switch lower {
            case "swift":
                keywordPatterns = Self.keywordPattern([
                    "actor", "as", "async", "await", "case", "catch", "class", "defer", "do", "else",
                    "enum", "extension", "for", "func", "guard", "if", "import", "in", "let", "private",
                    "protocol", "public", "return", "static", "struct", "switch", "throw", "try", "var", "while",
                ])
                typePatterns = Self.typePattern(["Bool", "CGFloat", "Date", "Double", "Int", "NSColor", "String", "URL", "UUID", "View"])
                commentPatterns = [#"//.*$"#, #"/\*[\s\S]*?\*/"#]
            case "php":
                keywordPatterns = Self.keywordPattern([
                    "abstract", "and", "array", "as", "break", "case", "catch", "class", "const", "continue",
                    "declare", "default", "do", "echo", "else", "elseif", "extends", "final", "for", "foreach",
                    "function", "if", "implements", "interface", "namespace", "new", "private", "protected",
                    "public", "return", "static", "switch", "throw", "trait", "try", "use", "while",
                ])
                typePatterns = [#"\$[A-Za-z_][A-Za-z0-9_]*"#]
                commentPatterns = [#"//.*$"#, #"#.*$"#, #"/\*[\s\S]*?\*/"#]
            case "javascript", "typescript":
                keywordPatterns = Self.keywordPattern([
                    "async", "await", "break", "case", "catch", "class", "const", "continue", "default",
                    "else", "export", "extends", "for", "from", "function", "if", "import", "let", "new",
                    "return", "switch", "throw", "try", "type", "var", "while",
                ])
                typePatterns = Self.typePattern(["Array", "Boolean", "Error", "Map", "Number", "Promise", "Record", "Set", "String"])
                commentPatterns = [#"//.*$"#, #"/\*[\s\S]*?\*/"#]
            case "zig":
                keywordPatterns = Self.keywordPattern([
                    "align", "allowzero", "and", "anyframe", "anytype", "asm", "async", "await", "break",
                    "catch", "comptime", "const", "continue", "defer", "else", "enum", "errdefer", "error",
                    "export", "extern", "fn", "for", "if", "inline", "noalias", "nosuspend", "opaque",
                    "or", "orelse", "packed", "pub", "resume", "return", "struct", "suspend", "switch",
                    "test", "threadlocal", "try", "union", "unreachable", "usingnamespace", "var", "volatile", "while",
                ])
                typePatterns = Self.typePattern(["bool", "comptime_int", "comptime_float", "i32", "u32", "usize", "void"])
                commentPatterns = [#"//.*$"#]
            case "java", "go", "rust", "c", "c++":
                keywordPatterns = Self.keywordPattern([
                    "break", "case", "catch", "class", "const", "continue", "defer", "default", "do", "else",
                    "enum", "extends", "final", "fn", "for", "func", "go", "guard", "if", "impl", "import",
                    "include", "interface", "let", "match", "mut", "new", "package", "private", "protected",
                    "public", "return", "static", "struct", "switch", "throw", "try", "type", "unsafe",
                    "use", "var", "while",
                ])
                typePatterns = Self.typePattern(["bool", "char", "double", "float", "int", "long", "String", "usize", "void"])
                commentPatterns = [#"//.*$"#, #"/\*[\s\S]*?\*/"#]
            case "python":
                keywordPatterns = Self.keywordPattern([
                    "and", "as", "async", "await", "break", "class", "continue", "def", "elif", "else",
                    "except", "False", "finally", "for", "from", "if", "import", "in", "is", "lambda",
                    "None", "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield",
                ])
                typePatterns = []
                commentPatterns = [#"#.*$"#]
            case "ruby", "shell":
                keywordPatterns = Self.keywordPattern([
                    "begin", "case", "class", "def", "do", "done", "elif", "else", "end", "fi",
                    "for", "function", "if", "in", "module", "return", "then", "unless", "until", "while",
                ])
                typePatterns = []
                commentPatterns = [#"#.*$"#]
            case "json", "toml", "yaml":
                keywordPatterns = [#"\b(true|false|null)\b"#]
                typePatterns = [#"(^|\n)\s*[A-Za-z0-9_.-]+(?=\s*[:=])"#]
                commentPatterns = lower == "json" ? [] : [#"#.*$"#]
            case "html":
                keywordPatterns = [#"</?[A-Za-z][A-Za-z0-9:-]*"#]
                typePatterns = [#"\s[A-Za-z_:][-A-Za-z0-9_:.]*(?=\=)"#]
                commentPatterns = [#"<!--[\s\S]*?-->"#]
            case "css":
                keywordPatterns = [#"[.#]?[A-Za-z_-][A-Za-z0-9_-]*(?=\s*\{)"#, #"[A-Za-z-]+(?=\s*:)"#]
                typePatterns = []
                commentPatterns = [#"/\*[\s\S]*?\*/"#]
            case "markdown":
                keywordPatterns = [#"^#{1,6}\s+.*$"#, #"[*_-]{3,}"#]
                typePatterns = [#"`[^`]+`"#, #"\[[^\]]+\]\([^)]+\)"#]
                commentPatterns = [#"<!--[\s\S]*?-->"#]
            default:
                keywordPatterns = []
                typePatterns = []
                commentPatterns = [#"//.*$"#, #"#.*$"#]
            }
        }

        private static func keywordPattern(_ words: [String]) -> [String] {
            [#"\b("# + words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + #")\b"#]
        }

        private static func typePattern(_ words: [String]) -> [String] {
            [#"\b("# + words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + #")\b"#]
        }
    }
}
