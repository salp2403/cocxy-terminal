// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MiniAgentPillView.swift - Compact per-split agent pill used inside
// `TabItemView` when the owning tab has multiple surfaces running
// agents. Extracted to its own file to keep `TabItemView` under the
// project's 600 LOC ceiling; the view's public surface is unchanged.

import AppKit

/// Compact per-split pill rendered inside `TabItemView` when the owning
/// tab has multiple surfaces running agents.
///
/// Shows a colored dot (state color) followed by the agent's two-letter
/// abbreviation. When `snapshot.isFocused` is `true`, the pill draws a
/// 1.5pt border in the state color to echo the accent strip of the
/// primary tab indicator. Click routing goes through `onClick`, which
/// the owning `TabItemView` wires to `onFocusSplit(surfaceID)` so the
/// host can activate the tab and focus the right split.
///
/// The view is a custom `NSView` rather than an `NSButton` because we
/// need a compound layout (dot + label) with a precise fixed size and
/// a border that follows the layer, not the button bezel. Click
/// handling stays robust because `acceptsFirstMouse` lets a click
/// activate the window and fire in the same gesture, and
/// `mouseDownCanMoveWindow` returns `false` so the pill is not
/// swallowed by `isMovableByWindowBackground` on the parent window.
///
/// The class is `internal` (the default) so it stays scoped to the
/// `CocxyTerminal` target and is reachable from `TabItemView` in the
/// same target. `final` is kept because inheritance has no planned use.
@MainActor
final class MiniAgentPillView: NSView {

    /// Invoked when the user single-clicks the pill. Carries the
    /// surface identifier so the host can target the correct split.
    var onClick: ((SurfaceID) -> Void)?

    private let surfaceID: SurfaceID
    private let dotLayer = CALayer()
    private let abbreviationLabel: NSTextField
    private let backgroundColor = CocxyColors.surface1.withAlphaComponent(0.35)

    init(snapshot: SurfaceAgentSnapshot, stateColor: NSColor) {
        self.surfaceID = snapshot.surfaceID

        let label = NSTextField(labelWithString: snapshot.agentAbbreviation)
        label.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        label.textColor = CocxyColors.subtext1
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        self.abbreviationLabel = label

        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = backgroundColor.cgColor

        dotLayer.cornerRadius = 3
        dotLayer.backgroundColor = stateColor.cgColor
        layer?.addSublayer(dotLayer)

        addSubview(abbreviationLabel)
        NSLayoutConstraint.activate([
            abbreviationLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            abbreviationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            abbreviationLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 14),
            widthAnchor.constraint(equalToConstant: 30),
        ])

        if snapshot.isFocused {
            layer?.borderWidth = 1.5
            layer?.borderColor = stateColor.cgColor
        } else {
            layer?.borderWidth = 0
        }

        let agentName = snapshot.state.detectedAgent?.displayName
            ?? snapshot.state.detectedAgent?.name
            ?? "unknown agent"
        let stateLabel = snapshot.state.agentState.accessibilityDescription
        let focusSuffix = snapshot.isFocused ? ", focused" : ""
        setAccessibilityLabel("\(agentName), \(stateLabel)\(focusSuffix)")
        toolTip = "\(agentName) — \(stateLabel)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MiniAgentPillView does not support NSCoding")
    }

    override func layout() {
        super.layout()
        // Center the 6x6 dot vertically, 5pt from the leading edge.
        dotLayer.frame = NSRect(x: 5, y: (bounds.height - 6) / 2, width: 6, height: 6)
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(surfaceID)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.push()
        layer?.backgroundColor = CocxyColors.surface1.withAlphaComponent(0.55).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
        layer?.backgroundColor = backgroundColor.cgColor
    }
}
