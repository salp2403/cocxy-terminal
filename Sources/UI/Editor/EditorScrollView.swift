// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorScrollView.swift - Scroll container for the native reusable text editor.

import AppKit

@MainActor
final class EditorScrollView: NSScrollView {
    init(textView: EditorTextView) {
        super.init(frame: .zero)

        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        drawsBackground = true
        backgroundColor = CocxyColors.base
        contentView.drawsBackground = true
        contentView.backgroundColor = CocxyColors.base

        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = false

        documentView = textView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EditorScrollView does not support NSCoding")
    }
}
