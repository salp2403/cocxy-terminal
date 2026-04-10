// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownSourceView.swift - NSTextView subview showing the raw markdown source with syntax highlighting.

import AppKit

// MARK: - Source View

/// Read-only text view that displays a markdown document's raw source with
/// per-line syntax highlighting applied.
///
/// In Fase 1 the source view is read-only: it is meant for reading and
/// scrolling alongside the preview. A future iteration will enable editing
/// by wiring an `NSTextStorageDelegate` to the highlighter so keystrokes
/// re-style affected ranges incrementally.
@MainActor
final class MarkdownSourceView: NSView {

    // MARK: - Properties

    private let scrollView = NSScrollView()
    private let textView: NSTextView
    private let highlighter: MarkdownSyntaxHighlighter

    /// Current document. Setting this re-applies highlighting.
    var document: MarkdownDocument = .empty {
        didSet { render() }
    }

    // MARK: - Init

    init(highlighter: MarkdownSyntaxHighlighter = MarkdownSyntaxHighlighter()) {
        self.highlighter = highlighter
        self.textView = NSTextView()
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MarkdownSourceView does not support NSCoding")
    }

    // MARK: - Public

    /// Scrolls the view so `sourceLine` (0-based) is visible.
    func scrollToSourceLine(_ sourceLine: Int) {
        let lines = document.source.components(separatedBy: "\n")
        guard sourceLine >= 0, sourceLine < lines.count else { return }
        var charIndex = 0
        for (index, line) in lines.enumerated() {
            if index == sourceLine { break }
            charIndex += line.count + 1
        }
        let range = NSRange(location: charIndex, length: 0)
        textView.scrollRangeToVisible(range)
        textView.setSelectedRange(range)
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = CocxyColors.base.cgColor

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 18, height: 14)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.linkTextAttributes = [
            .foregroundColor: CocxyColors.blue,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand
        ]

        scrollView.documentView = textView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: - Rendering

    private func render() {
        let attributed = highlighter.highlight(document.source)
        textView.textStorage?.setAttributedString(attributed)
    }
}
