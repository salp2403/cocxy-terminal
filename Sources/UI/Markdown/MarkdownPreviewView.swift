// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownPreviewView.swift - Read-only NSTextView that renders a MarkdownDocument.

import AppKit

// MARK: - Preview View

/// Renders a `MarkdownDocument` into a read-only `NSTextView` using
/// `MarkdownRenderer` to produce the attributed string.
///
/// Unlike the source view, the preview hides the markdown syntax markers
/// and applies the final typographic styling: heading sizes, bold / italic
/// / strikethrough, code blocks, list bullets, blockquotes with a left
/// indent, and GFM table rules.
@MainActor
final class MarkdownPreviewView: NSView {

    // MARK: - Properties

    private let scrollView = NSScrollView()
    private let textView: NSTextView
    private let renderer: MarkdownRenderer

    /// Current document. Setting this re-renders immediately.
    var document: MarkdownDocument = .empty {
        didSet { render() }
    }

    // MARK: - Init

    init(renderer: MarkdownRenderer = MarkdownRenderer()) {
        self.renderer = renderer
        self.textView = NSTextView()
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MarkdownPreviewView does not support NSCoding")
    }

    // MARK: - Public

    /// Scrolls the preview so a specific heading (identified by its title)
    /// is visible at the top. Used by the outline view's tap-to-navigate.
    func scrollToHeading(title: String) {
        let string = textView.string as NSString
        let range = string.range(of: title)
        guard range.location != NSNotFound else { return }
        textView.scrollRangeToVisible(range)
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
        textView.textContainerInset = NSSize(width: 22, height: 16)
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
        let attributed = renderer.render(document)
        textView.textStorage?.setAttributedString(attributed)
    }
}
