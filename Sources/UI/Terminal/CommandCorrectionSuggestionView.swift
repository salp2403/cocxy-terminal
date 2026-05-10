// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandCorrectionSuggestionView.swift - Local command correction prompt.

import AppKit
import CocxyCommandCorrections

@MainActor
final class CommandCorrectionSuggestionView: NSView {
    private let suggestionLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")
    private var localizer: AppLocalizer

    override var isFlipped: Bool { true }

    init(localizer: AppLocalizer) {
        self.localizer = localizer
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.42).cgColor
        configureLabels()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CommandCorrectionSuggestionView does not support NSCoding")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(
        correction: CommandCorrection,
        showConfidenceBadge: Bool,
        localizer: AppLocalizer
    ) {
        self.localizer = localizer
        let confidence = Int((correction.confidence * 100).rounded())
        let suffix = showConfidenceBadge ? "  \(confidence)%" : ""
        suggestionLabel.stringValue = correction.suggestion + suffix
        hintLabel.stringValue = localizer.string(
            "terminal.commandCorrections.shortcutHint",
            fallback: "Tab accept · Esc dismiss"
        )
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 10
        let hintWidth: CGFloat = 150
        hintLabel.frame = NSRect(
            x: bounds.width - hintWidth - inset,
            y: 5,
            width: hintWidth,
            height: bounds.height - 10
        )
        suggestionLabel.frame = NSRect(
            x: inset,
            y: 5,
            width: max(0, hintLabel.frame.minX - inset * 2),
            height: bounds.height - 10
        )
    }

    private func configureLabels() {
        suggestionLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        suggestionLabel.textColor = .labelColor
        suggestionLabel.lineBreakMode = .byTruncatingMiddle

        hintLabel.font = .systemFont(ofSize: 11, weight: .medium)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .right
        hintLabel.lineBreakMode = .byTruncatingTail

        addSubview(suggestionLabel)
        addSubview(hintLabel)
    }
}
