// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// InlineGhostText.swift - Lightweight ghost text overlay for inline completions.

import AppKit

@MainActor
final class InlineGhostText {
    private let label = NSTextField(labelWithString: "")
    private weak var textView: NSTextView?
    private var caretLocation: Int = 0

    var isVisible: Bool {
        label.superview != nil && !label.isHidden
    }

    var text: String? {
        isVisible ? label.stringValue : nil
    }

    init() {
        label.isEditable = false
        label.isSelectable = false
        label.drawsBackground = false
        label.isBordered = false
        label.lineBreakMode = .byTruncatingTail
        label.alphaValue = 0.58
        label.textColor = CocxyColors.overlay1
        label.translatesAutoresizingMaskIntoConstraints = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    func show(text: String, atUTF16Location location: Int, in textView: NSTextView) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            hide()
            return
        }

        self.textView = textView
        self.caretLocation = min(max(0, location), (textView.string as NSString).length)
        label.stringValue = text
        label.font = textView.font ?? .monospacedSystemFont(ofSize: 13, weight: .regular)
        if label.superview !== textView {
            textView.addSubview(label)
        }
        label.isHidden = false
        layout()
    }

    func hide() {
        label.removeFromSuperview()
        textView = nil
    }

    func layout() {
        guard let textView else { return }
        let origin = caretOrigin(in: textView, at: caretLocation)
        let availableWidth = max(40, textView.bounds.maxX - origin.x - 8)
        let height = ceil((label.font ?? NSFont.systemFont(ofSize: 13)).boundingRectForFont.height) + 4
        label.frame = NSRect(
            x: origin.x,
            y: origin.y - 1,
            width: availableWidth,
            height: height
        )
    }

    private func caretOrigin(in textView: NSTextView, at location: Int) -> NSPoint {
        if let window = textView.window {
            let screenRect = textView.firstRect(
                forCharacterRange: NSRange(location: location, length: 0),
                actualRange: nil
            )
            if !screenRect.isEmpty {
                let windowRect = window.convertFromScreen(screenRect)
                return textView.convert(windowRect.origin, from: nil)
            }
        }

        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else {
            return NSPoint(x: textView.textContainerInset.width, y: textView.textContainerInset.height)
        }

        layoutManager.ensureLayout(for: textContainer)
        let textLength = (textView.string as NSString).length
        if textLength == 0 || location == 0 {
            return NSPoint(x: textView.textContainerInset.width, y: textView.textContainerInset.height)
        }

        let characterIndex = min(max(0, location - 1), textLength - 1)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        var rect = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        rect.origin.x += textView.textContainerInset.width
        rect.origin.y += textView.textContainerInset.height

        if location >= textLength {
            rect.origin.x = rect.maxX
        }
        return rect.origin
    }
}
