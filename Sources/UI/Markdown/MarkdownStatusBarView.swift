// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MarkdownStatusBarView.swift - Bottom status bar showing word/character/line counts.

import AppKit
import CocxyMarkdownLib

// MARK: - Status Bar View

/// Thin status bar at the bottom of the markdown panel showing document statistics.
///
/// Displays: `Words: N  |  Characters: N  |  Lines: N`
///
/// The bar updates via the `wordCount` property setter — no internal timers.
@MainActor
final class MarkdownStatusBarView: NSView {

    // MARK: - Properties

    private let wordsLabel = NSTextField(labelWithString: "Words: 0")
    private let charsLabel = NSTextField(labelWithString: "Chars: 0")
    private let linesLabel = NSTextField(labelWithString: "Lines: 0")

    /// Height of the status bar.
    static let height: CGFloat = 22

    /// Current word count. Setting updates the displayed labels.
    var wordCount: MarkdownWordCount = .zero {
        didSet { updateLabels() }
    }

    // MARK: - Init

    init() {
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MarkdownStatusBarView does not support NSCoding")
    }

    // MARK: - Setup

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = CocxyColors.mantle.cgColor

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = CocxyColors.surface0.cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        let stack = NSStackView(views: [wordsLabel, makeSeparatorDot(), charsLabel, makeSeparatorDot(), linesLabel])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for label in [wordsLabel, charsLabel, linesLabel] {
            label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            label.textColor = CocxyColors.subtext0
            label.lineBreakMode = .byClipping
        }

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0.5),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12)
        ])
    }

    private func makeSeparatorDot() -> NSTextField {
        let dot = NSTextField(labelWithString: "·")
        dot.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        dot.textColor = CocxyColors.surface2
        return dot
    }

    // MARK: - Update

    private func updateLabels() {
        wordsLabel.stringValue = "Words: \(wordCount.words)"
        charsLabel.stringValue = "Chars: \(wordCount.characters)"
        linesLabel.stringValue = "Lines: \(wordCount.lines)"
    }
}
