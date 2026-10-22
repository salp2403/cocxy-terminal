// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalHistoryPillView.swift - Local scrollback position and return action.

import AppKit

@MainActor
final class TerminalHistoryPillView: NSButton {
    private var localizer: AppLocalizer
    private var trackingAreaReference: NSTrackingArea?
    private var isPointerInside = false
    private(set) var linesAbove: UInt32 = 0
    var onJumpToBottom: (() -> Void)?

    init(localizer: AppLocalizer = AppLocalizer(languagePreference: .system)) {
        self.localizer = localizer
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setButtonType(.momentaryPushIn)
        bezelStyle = .regularSquare
        isBordered = false
        focusRingType = .none
        font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        image = NSImage(systemSymbolName: "arrow.down.to.line", accessibilityDescription: nil)
        imagePosition = .imageLeading
        imageScaling = .scaleProportionallyDown
        contentTintColor = CocxyColors.subtext1
        cell?.lineBreakMode = .byTruncatingMiddle
        target = self
        action = #selector(jumpToBottom(_:))
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        isHidden = true
        updateLayerAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TerminalHistoryPillView does not support NSCoding")
    }

    func update(linesAbove: UInt32) {
        self.linesAbove = linesAbove
        guard linesAbove > 0 else {
            isHidden = true
            return
        }

        let key = linesAbove == 1
            ? "terminal.historyPill.one"
            : "terminal.historyPill.many"
        let fallback = linesAbove == 1
            ? "History · %d line up · ↩ jump to bottom"
            : "History · %d lines up · ↩ jump to bottom"
        title = String(
            format: localizer.string(key, fallback: fallback),
            Int(linesAbove)
        )
        toolTip = localizer.string(
            "terminal.historyPill.help",
            fallback: "Return to live terminal output"
        )
        setAccessibilityLabel(title)
        isHidden = false
        invalidateIntrinsicContentSize()
    }

    func updateLocalizer(_ localizer: AppLocalizer) {
        self.localizer = localizer
        update(linesAbove: linesAbove)
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isPointerInside = true
        updateLayerAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isPointerInside = false
        updateLayerAppearance()
    }

    @objc private func jumpToBottom(_ sender: Any?) {
        onJumpToBottom?()
    }

    private func updateLayerAppearance() {
        layer?.backgroundColor = (isPointerInside ? CocxyColors.surface1 : CocxyColors.surface0)
            .withAlphaComponent(0.94)
            .cgColor
        layer?.borderColor = CocxyColors.overlay0.withAlphaComponent(0.65).cgColor
    }
}
