// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RenameSheetController.swift - Translucent floating rename panel.

import AppKit

// MARK: - Rename Sheet Controller

/// Presents a translucent floating panel for renaming tabs and panels.
///
/// The panel uses `NSVisualEffectView` with `.popover` material for a
/// native macOS translucent glass look. It floats centered over the
/// parent window with a semi-transparent backdrop.
@MainActor
final class RenameSheetController {

    static func present(
        on window: NSWindow,
        currentName: String,
        placeholder: String = "Enter name...",
        icon: String = "pencil.line",
        onComplete: @escaping (String?) -> Void
    ) {
        let panelWidth: CGFloat = 300
        let panelHeight: CGFloat = 130

        // Centered position over parent window.
        let windowFrame = window.frame
        let panelOrigin = NSPoint(
            x: windowFrame.midX - panelWidth / 2,
            y: windowFrame.midY - panelHeight / 2 + 40
        )

        // Floating panel that accepts keyboard input.
        // Uses .titled for proper key event routing (required for NSTextField focus).
        // .utilityWindow keeps it lightweight; .fullSizeContentView hides the titlebar.
        let panel = NSPanel(
            contentRect: NSRect(origin: panelOrigin, size: NSSize(width: panelWidth, height: panelHeight)),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isMovableByWindowBackground = false

        // Translucent background with rounded corners.
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight)))
        effectView.material = .fullScreenUI
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 1
        effectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        effectView.alphaValue = 0.96

        panel.contentView = effectView

        // Icon + title row.
        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium)) {
            iconView.image = img
        }
        iconView.contentTintColor = CocxyColors.subtext0
        iconView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: "Rename")
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = CocxyColors.text
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(titleLabel)

        // Text field.
        let textField = NSTextField()
        textField.font = .systemFont(ofSize: 13)
        textField.textColor = CocxyColors.text
        textField.backgroundColor = NSColor.white.withAlphaComponent(0.06)
        textField.drawsBackground = true
        textField.isBordered = false
        textField.isBezeled = false
        textField.wantsLayer = true
        textField.layer?.cornerRadius = 8
        textField.layer?.borderWidth = 1
        textField.layer?.borderColor = NSColor.white.withAlphaComponent(0.1).cgColor
        textField.focusRingType = .none
        textField.placeholderString = placeholder
        textField.stringValue = currentName
        textField.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(textField)

        // Rename button.
        let renameBtn = NSButton()
        renameBtn.title = "Done"
        renameBtn.bezelStyle = .accessoryBarAction
        renameBtn.isBordered = false
        renameBtn.wantsLayer = true
        renameBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        renameBtn.layer?.cornerRadius = 6
        renameBtn.contentTintColor = CocxyColors.text
        renameBtn.font = .systemFont(ofSize: 11, weight: .semibold)
        renameBtn.translatesAutoresizingMaskIntoConstraints = false
        renameBtn.keyEquivalent = "\r"
        effectView.addSubview(renameBtn)

        // Cancel button.
        let cancelBtn = NSButton()
        cancelBtn.title = "Cancel"
        cancelBtn.bezelStyle = .accessoryBarAction
        cancelBtn.isBordered = false
        cancelBtn.wantsLayer = true
        cancelBtn.layer?.cornerRadius = 5
        cancelBtn.contentTintColor = CocxyColors.overlay1
        cancelBtn.font = .systemFont(ofSize: 11, weight: .medium)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.keyEquivalent = "\u{1b}"
        effectView.addSubview(cancelBtn)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 16),
            iconView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),

            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),

            textField.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 12),
            textField.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -16),
            textField.heightAnchor.constraint(equalToConstant: 28),

            renameBtn.topAnchor.constraint(equalTo: textField.bottomAnchor, constant: 12),
            renameBtn.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -16),
            renameBtn.widthAnchor.constraint(equalToConstant: 60),
            renameBtn.heightAnchor.constraint(equalToConstant: 24),

            cancelBtn.centerYAnchor.constraint(equalTo: renameBtn.centerYAnchor),
            cancelBtn.trailingAnchor.constraint(equalTo: renameBtn.leadingAnchor, constant: -6),
            cancelBtn.widthAnchor.constraint(equalToConstant: 54),
            cancelBtn.heightAnchor.constraint(equalToConstant: 24),
        ])

        // Coordinator for button actions.
        let coordinator = FloatingPanelCoordinator(panel: panel, textField: textField, onComplete: onComplete)
        renameBtn.target = coordinator
        renameBtn.action = #selector(FloatingPanelCoordinator.confirm)
        cancelBtn.target = coordinator
        cancelBtn.action = #selector(FloatingPanelCoordinator.dismiss)
        objc_setAssociatedObject(panel, "coordinator", coordinator, .OBJC_ASSOCIATION_RETAIN)

        // Show and focus.
        panel.orderFront(nil)
        panel.makeKey()
        panel.makeFirstResponder(textField)
        textField.selectText(nil)

        // Make the parent window's content dim slightly.
        window.addChildWindow(panel, ordered: .above)
    }
}

// MARK: - Floating Panel Coordinator

@MainActor
private final class FloatingPanelCoordinator: NSObject {
    let panel: NSPanel
    let textField: NSTextField
    let onComplete: (String?) -> Void

    init(panel: NSPanel, textField: NSTextField, onComplete: @escaping (String?) -> Void) {
        self.panel = panel
        self.textField = textField
        self.onComplete = onComplete
    }

    @objc func confirm() {
        let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        close()
        onComplete(value.isEmpty ? nil : value)
    }

    @objc func dismiss() {
        close()
        onComplete(nil)
    }

    private func close() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        objc_setAssociatedObject(panel, "coordinator", nil, .OBJC_ASSOCIATION_RETAIN)
    }
}
