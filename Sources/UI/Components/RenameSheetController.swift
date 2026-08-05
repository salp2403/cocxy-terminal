// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RenameSheetController.swift - Translucent floating rename panel.

import AppKit

// MARK: - Rename Sheet Controller

enum RenameSheetResult: Equatable {
    case confirmed(String?)
    case cancelled
}

/// Presents a translucent floating panel for renaming tabs and panels.
///
/// The panel uses `NSVisualEffectView` with `.popover` material for a
/// native macOS translucent glass look. It floats centered over the
/// parent window with a semi-transparent backdrop.
@MainActor
final class RenameSheetController {

    nonisolated(unsafe) private static var coordinatorAssociationKey: UInt8 = 0

    @discardableResult
    static func present(
        on window: NSWindow,
        currentName: String,
        placeholder: String? = nil,
        icon: String = "pencil.line",
        localizer: AppLocalizer = AppLocalizer(languagePreference: .system),
        onComplete: @escaping (RenameSheetResult) -> Void
    ) -> NSPanel {
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
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary]

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
        ApplicationLayoutDirectionCoordinator.markAsApplicationManaged(panel)
        ApplicationLayoutDirectionCoordinator.apply(
            ApplicationLayoutDirectionCoordinator.resolvedDirection(for: localizer),
            to: effectView
        )

        // Icon + title row.
        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium)) {
            iconView.image = img
        }
        iconView.contentTintColor = CocxyColors.subtext0
        iconView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: Self.localizedTitle(using: localizer))
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
        textField.placeholderString = placeholder ?? Self.localizedDefaultPlaceholder(using: localizer)
        textField.stringValue = currentName
        textField.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(textField)

        // Rename button.
        let renameBtn = NSButton()
        renameBtn.title = Self.localizedDone(using: localizer)
        renameBtn.bezelStyle = .accessoryBarAction
        renameBtn.isBordered = false
        renameBtn.wantsLayer = true
        renameBtn.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        renameBtn.layer?.cornerRadius = 6
        renameBtn.contentTintColor = CocxyColors.text
        renameBtn.font = .systemFont(ofSize: 11, weight: .semibold)
        renameBtn.translatesAutoresizingMaskIntoConstraints = false
        renameBtn.keyEquivalent = "\r"
        renameBtn.setAccessibilityLabel(Self.localizedDone(using: localizer))
        effectView.addSubview(renameBtn)

        // Cancel button.
        let cancelBtn = NSButton()
        let cancelTitle = localizer.string("common.cancel", fallback: "Cancel")
        cancelBtn.title = cancelTitle
        cancelBtn.bezelStyle = .accessoryBarAction
        cancelBtn.isBordered = false
        cancelBtn.wantsLayer = true
        cancelBtn.layer?.cornerRadius = 5
        cancelBtn.contentTintColor = CocxyColors.overlay1
        cancelBtn.font = .systemFont(ofSize: 11, weight: .medium)
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.keyEquivalent = "\u{1b}"
        cancelBtn.setAccessibilityLabel(cancelTitle)
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
        let coordinator = FloatingPanelCoordinator(
            parentWindow: window,
            panel: panel,
            textField: textField,
            onComplete: onComplete
        )
        renameBtn.target = coordinator
        renameBtn.action = #selector(FloatingPanelCoordinator.confirm)
        cancelBtn.target = coordinator
        cancelBtn.action = #selector(FloatingPanelCoordinator.dismiss)
        panel.delegate = coordinator
        objc_setAssociatedObject(
            panel,
            &coordinatorAssociationKey,
            coordinator,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )

        // Show and focus.
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textField)
        textField.selectText(nil)
        DispatchQueue.main.async { [weak panel, weak textField] in
            guard let panel, let textField, panel.isVisible else { return }
            panel.makeFirstResponder(textField)
            textField.selectText(nil)
        }

        return panel
    }

    static func hasRetainedCoordinator(for panel: NSPanel) -> Bool {
        objc_getAssociatedObject(panel, &coordinatorAssociationKey) != nil
    }

    fileprivate static func releaseCoordinator(from panel: NSPanel) {
        objc_setAssociatedObject(
            panel,
            &coordinatorAssociationKey,
            nil,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    static func localizedTitle(using localizer: AppLocalizer) -> String {
        localizer.string("renameSheet.title", fallback: "Rename")
    }

    static func localizedDone(using localizer: AppLocalizer) -> String {
        localizer.string("renameSheet.done", fallback: "Done")
    }

    static func localizedDefaultPlaceholder(using localizer: AppLocalizer) -> String {
        localizer.string("renameSheet.placeholder", fallback: "Enter name...")
    }
}

// MARK: - Floating Panel Coordinator

@MainActor
private final class FloatingPanelCoordinator: NSObject, NSWindowDelegate {
    let panel: NSPanel
    let textField: NSTextField
    let onComplete: (RenameSheetResult) -> Void
    private var hasFinished = false
    private var isParentWindowClosing = false

    init(
        parentWindow: NSWindow,
        panel: NSPanel,
        textField: NSTextField,
        onComplete: @escaping (RenameSheetResult) -> Void
    ) {
        self.panel = panel
        self.textField = textField
        self.onComplete = onComplete
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(parentWindowWillClose),
            name: NSWindow.willCloseNotification,
            object: parentWindow
        )
    }

    @objc func confirm() {
        let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        finish(with: .confirmed(value.isEmpty ? nil : value))
    }

    @objc func dismiss() {
        finish(with: .cancelled)
    }

    func windowWillClose(_ notification: Notification) {
        finish(
            with: .cancelled,
            orderOut: false,
            notifyCompletion: !isParentWindowClosing
        )
    }

    @objc private func parentWindowWillClose(_ notification: Notification) {
        isParentWindowClosing = true
    }

    private func finish(
        with result: RenameSheetResult,
        orderOut: Bool = true,
        notifyCompletion: Bool = true
    ) {
        guard !hasFinished else { return }
        hasFinished = true

        NotificationCenter.default.removeObserver(self)
        panel.parent?.removeChildWindow(panel)
        panel.delegate = nil
        RenameSheetController.releaseCoordinator(from: panel)
        if orderOut {
            panel.orderOut(nil)
        }
        if notifyCompletion && !isParentWindowClosing {
            onComplete(result)
        }
    }
}
