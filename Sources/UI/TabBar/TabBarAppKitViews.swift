// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabBarAppKitViews.swift - AppKit support views shared by tab bar components.

import AppKit

/// A plain view that keeps child controls from starting background window drags.
@MainActor
final class NonDraggableView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
}

/// An interactive image view that does not act as draggable window background.
@MainActor
final class ClickableImageView: NSImageView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Clip view with flipped coordinates so content starts from the top.
final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

/// Document view with flipped coordinates for top-aligned layout.
final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
