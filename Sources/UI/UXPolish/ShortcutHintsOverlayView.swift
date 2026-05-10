// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ShortcutHintsOverlayView.swift - Lightweight always-show shortcut hints.

import SwiftUI

struct ShortcutHintsOverlayView: View {
    let hints: [ShortcutHint]
    let config: UXPolishConfig
    var shortcutLabelProvider: (String) -> String?

    var body: some View {
        if config.alwaysShowShortcutHints {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(hints) { hint in
                    if let shortcut = shortcutLabelProvider(hint.actionId) {
                        HStack(spacing: 6) {
                            Text(hint.title)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(shortcut)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
            .scaleEffect(config.shortcutHintScale)
            .offset(x: config.shortcutHintOffsetX, y: config.shortcutHintOffsetY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

struct ShortcutHintsDebugWindow: View {
    let config: UXPolishConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shortcut Hints")
                .font(.headline)
            Text("x \(Self.format(config.shortcutHintOffsetX))")
            Text("y \(Self.format(config.shortcutHintOffsetY))")
            Text("scale \(Self.format(config.shortcutHintScale))")
        }
        .padding(12)
        .frame(minWidth: 180, alignment: .leading)
    }

    private static func format(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return "\(rounded)"
    }
}

final class ShortcutHintPassthroughHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
