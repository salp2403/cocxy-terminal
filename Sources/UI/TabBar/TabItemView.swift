// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabItemView.swift - Individual tab row in the sidebar tab bar.

import AppKit

// MARK: - Tab Item View

/// A single row in the tab bar representing one workspace tab.
///
/// Rich layout with 3 lines:
/// - Line 1: Title + relative time
/// - Line 2: Agent status text with state indicator
/// - Line 3: Directory path + git branch
///
/// Left accent strip colored by agent state.
@MainActor
final class TabItemView: NSView {

    // MARK: - Callbacks

    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onContextMenu: (() -> NSMenu?)?
    var onRename: ((TabID, String) -> Void)?

    /// When true, shows a confirmation alert before closing the tab.
    /// Set by the parent view based on `confirmCloseProcess` config.
    var shouldConfirmClose: Bool = false

    // MARK: - Layers

    /// Left accent strip indicating agent state color.
    private let accentStrip: CALayer = {
        let layer = CALayer()
        layer.cornerRadius = 3
        return layer
    }()

    /// Background glow layer for notification state.
    private let glowLayer: CAGradientLayer = {
        let layer = CAGradientLayer()
        layer.type = .radial
        layer.startPoint = CGPoint(x: 0, y: 0.5)
        layer.endPoint = CGPoint(x: 1, y: 1)
        layer.opacity = 0
        layer.cornerRadius = 10
        return layer
    }()

    // MARK: - Subviews

    /// Process type icon (terminal, network, globe, etc.).
    private let processIcon: NSImageView = {
        let iv = NSImageView()
        iv.contentTintColor = CocxyColors.blue
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.setContentHuggingPriority(.required, for: .horizontal)
        return iv
    }()

    /// Pin icon shown when the tab is pinned.
    private let pinIcon: NSImageView = {
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        let image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")?
            .withSymbolConfiguration(config)
        let iv = NSImageView(image: image ?? NSImage())
        iv.contentTintColor = CocxyColors.yellow
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.isHidden = true
        iv.setContentHuggingPriority(.required, for: .horizontal)
        return iv
    }()

    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = CocxyColors.text
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let timeLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        label.textColor = CocxyColors.overlay1
        label.alignment = .right
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let statusDot: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 4
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let statusLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let pathLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        label.textColor = CocxyColors.subtext0
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    /// Close button — visible on hover, positioned top-right.
    private let closeButton: NSButton = {
        let button = NSButton()
        button.bezelStyle = .inline
        button.isBordered = false
        if let img = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Tab") {
            button.image = img.withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
        }
        button.contentTintColor = CocxyColors.subtext1
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setAccessibilityLabel("Close Tab")
        button.isHidden = true
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        return button
    }()

    /// Whether the rename sheet is currently presented, used to guard against repeated clicks.
    private(set) var isEditing: Bool = false

    // MARK: - State

    private(set) var displayItem: TabDisplayItem

    // MARK: - Initialization

    init(displayItem: TabDisplayItem) {
        self.displayItem = displayItem
        super.init(frame: .zero)
        setupSubviews()
        configure(with: displayItem)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TabItemView does not support NSCoding")
    }

    // MARK: - Setup

    private func setupSubviews() {
        wantsLayer = true
        layer?.cornerRadius = 10

        // Add glow layer behind content.
        layer?.addSublayer(glowLayer)

        // Add accent strip.
        layer?.addSublayer(accentStrip)

        addSubview(processIcon)
        addSubview(pinIcon)
        addSubview(titleLabel)
        addSubview(timeLabel)
        addSubview(closeButton)
        addSubview(statusDot)
        addSubview(statusLabel)
        addSubview(pathLabel)

        closeButton.target = self
        closeButton.action = #selector(handleCloseButton)

        let textLeading: CGFloat = 14

        NSLayoutConstraint.activate([
            processIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textLeading),
            processIcon.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            processIcon.widthAnchor.constraint(equalToConstant: 14),
            processIcon.heightAnchor.constraint(equalToConstant: 14),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24),

            pinIcon.leadingAnchor.constraint(equalTo: processIcon.trailingAnchor, constant: 4),
            pinIcon.centerYAnchor.constraint(equalTo: processIcon.centerYAnchor),
            pinIcon.widthAnchor.constraint(equalToConstant: 10),
            pinIcon.heightAnchor.constraint(equalToConstant: 10),

            titleLabel.leadingAnchor.constraint(equalTo: pinIcon.trailingAnchor, constant: 3),
            titleLabel.centerYAnchor.constraint(equalTo: processIcon.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -4),

            timeLabel.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
            timeLabel.firstBaselineAnchor.constraint(equalTo: titleLabel.firstBaselineAnchor),
            timeLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 36),

            statusDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textLeading + 20),
            statusDot.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: 6),
            statusDot.heightAnchor.constraint(equalToConstant: 6),

            statusLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 5),
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),

            pathLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textLeading + 20),
            pathLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 2),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
        ])
    }

    override func layout() {
        super.layout()
        let stripWidth = displayItem.isActive ? 5.0 : 2.0
        accentStrip.frame = NSRect(x: 0, y: 8, width: stripWidth, height: bounds.height - 16)
        glowLayer.frame = bounds
    }

    // MARK: - Update

    func update(with item: TabDisplayItem) {
        self.displayItem = item
        configure(with: item)
    }

    private func configure(with item: TabDisplayItem) {
        titleLabel.stringValue = item.displayTitle
        timeLabel.stringValue = item.timeSinceActivity

        pinIcon.isHidden = !item.isPinned

        let statusText: String
        if item.agentStatusText.isEmpty {
            if let process = item.processName, process != "zsh" && process != "bash" && process != "fish" {
                statusText = process
            } else {
                statusText = "Ready"
            }
        } else {
            statusText = item.agentStatusText
        }
        statusLabel.stringValue = statusText

        var pathText = item.directoryPath
        if let branch = item.gitBranch {
            pathText += " \u{2022} \(branch)"
        }
        pathLabel.stringValue = pathText
        pathLabel.isHidden = pathText.isEmpty

        let iconName: String
        let iconColor: NSColor
        if item.sshDisplay != nil {
            iconName = "network"
            iconColor = CocxyColors.yellow
        } else if item.agentState == .working || item.agentState == .launched {
            iconName = "bolt.fill"
            iconColor = CocxyColors.blue
        } else if item.agentState == .waitingInput {
            iconName = "exclamationmark.bubble.fill"
            iconColor = CocxyColors.yellow
        } else if item.agentState == .error {
            iconName = "xmark.circle.fill"
            iconColor = CocxyColors.red
        } else if item.agentState == .finished {
            iconName = "checkmark.circle.fill"
            iconColor = CocxyColors.green
        } else {
            iconName = "terminal.fill"
            iconColor = CocxyColors.overlay1
        }
        if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
            processIcon.image = img.withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        }
        processIcon.contentTintColor = iconColor

        let stateColor = stateNSColor(for: item.agentState)
        accentStrip.backgroundColor = stateColor.cgColor
        statusDot.layer?.backgroundColor = stateColor.cgColor
        statusDot.isHidden = (item.agentState == .idle)

        switch item.agentState {
        case .idle:
            statusLabel.textColor = CocxyColors.subtext0
        case .launched:
            statusLabel.textColor = CocxyColors.peach
        case .working:
            statusLabel.textColor = CocxyColors.blue
        case .waitingInput:
            statusLabel.textColor = CocxyColors.yellow
        case .finished:
            statusLabel.textColor = CocxyColors.green
        case .error:
            statusLabel.textColor = CocxyColors.red
        }

        if item.isActive {
            layer?.backgroundColor = CocxyColors.surface1.withAlphaComponent(0.6).cgColor
            titleLabel.textColor = CocxyColors.text
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            timeLabel.textColor = CocxyColors.subtext1
            pathLabel.textColor = CocxyColors.subtext0
            accentStrip.frame.size.width = 5
            accentStrip.backgroundColor = CocxyColors.blue.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            titleLabel.textColor = CocxyColors.subtext1
            titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            timeLabel.textColor = CocxyColors.overlay1
            pathLabel.textColor = CocxyColors.subtext0
            accentStrip.frame.size.width = 2
        }

        let needsAttention = !item.isActive && (item.agentState == .waitingInput || item.hasUnreadNotification)
        if needsAttention {
            applyAttentionBorder(color: stateColor)
            applyGlowEffect(color: stateColor)
        } else {
            removeAttentionBorder()
            removeGlowEffect()
        }

        if item.agentState == .working {
            startAccentPulse(color: stateColor)
        } else {
            stopAccentPulse()
        }

        setAccessibilityRole(.button)
        setAccessibilityLabel(item.displayTitle)
        setAccessibilityValue("Agent: \(item.agentState.accessibilityDescription)")
        setAccessibilityHelp("Activate this tab")
    }

    // MARK: - Attention Border (Notification Ring)

    private func applyAttentionBorder(color: NSColor) {
        layer?.borderColor = color.cgColor
        layer?.borderWidth = 1.5
        layer?.shadowColor = color.cgColor
        layer?.shadowRadius = 6
        layer?.shadowOpacity = 0.5
        layer?.shadowOffset = .zero
    }

    private func removeAttentionBorder() {
        layer?.borderWidth = 0
        layer?.shadowOpacity = 0
    }

    // MARK: - Glow Effect

    private func applyGlowEffect(color: NSColor) {
        let glowColor = color.withAlphaComponent(0.12).cgColor
        let clearColor = NSColor.clear.cgColor
        glowLayer.colors = [glowColor, clearColor]

        guard !AnimationConfig.reduceMotion else {
            glowLayer.opacity = 0.6
            return
        }
        guard glowLayer.animation(forKey: "glowPulse") == nil else { return }

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.4
        animation.toValue = 1.0
        animation.duration = 1.5
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowLayer.opacity = 1.0
        glowLayer.add(animation, forKey: "glowPulse")
    }

    private func removeGlowEffect() {
        glowLayer.removeAnimation(forKey: "glowPulse")
        glowLayer.opacity = 0
    }

    // MARK: - Accent Pulse

    private func startAccentPulse(color: NSColor) {
        guard !AnimationConfig.reduceMotion else {
            accentStrip.opacity = 1.0
            return
        }
        guard accentStrip.animation(forKey: "accentPulse") == nil else { return }

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 0.5
        animation.toValue = 1.0
        animation.duration = 1.2
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        accentStrip.add(animation, forKey: "accentPulse")
    }

    private func stopAccentPulse() {
        accentStrip.removeAnimation(forKey: "accentPulse")
        accentStrip.opacity = 1.0
    }

    // MARK: - Color Mapping

    private func stateNSColor(for state: AgentState) -> NSColor {
        switch state {
        case .idle:     return CocxyColors.overlay0
        case .launched: return CocxyColors.peach
        case .working:  return CocxyColors.blue
        case .waitingInput: return CocxyColors.yellow
        case .finished: return CocxyColors.green
        case .error:    return CocxyColors.red
        }
    }

    // MARK: - Keyboard Accessibility

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 || event.keyCode == 36 {
            onSelect?()
        } else {
            super.keyDown(with: event)
        }
    }

    // MARK: - Close Button

    @objc private func handleCloseButton() {
        guard shouldConfirmClose else {
            onClose?()
            return
        }

        let alert = NSAlert()
        alert.messageText = "Close this tab?"
        alert.informativeText = "A process may still be running in this tab."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Close")
        alert.addButton(withTitle: "Cancel")

        if let parentWindow = window {
            alert.beginSheetModal(for: parentWindow) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    self?.onClose?()
                }
            }
        } else {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                onClose?()
            }
        }
    }

    // MARK: - Mouse Interaction

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Pending single-click work item, cancelled if a double-click arrives.
    private var pendingSelectWork: DispatchWorkItem?

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if closeButton.frame.contains(localPoint) { return }
        if isEditing { return }

        pendingSelectWork?.cancel()
        pendingSelectWork = nil

        if event.clickCount >= 2 {
            startEditing()
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.onSelect?()
            self?.pendingSelectWork = nil
        }
        pendingSelectWork = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + NSEvent.doubleClickInterval,
            execute: work
        )
    }

    // MARK: - Inline Rename

    /// Enters rename mode: shows the edit field over the title label.
    func startEditing() {
        guard !isEditing, let parentWindow = window else { return }
        isEditing = true

        let tabID = displayItem.id
        RenameSheetController.present(
            on: parentWindow,
            currentName: titleLabel.stringValue,
            placeholder: "Tab name",
            icon: "terminal.fill",
            onComplete: { [weak self] newTitle in
                self?.isEditing = false
                if let newTitle {
                    self?.onRename?(tabID, newTitle)
                }
            }
        )
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = onContextMenu?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: - Tracking Area (Hover)

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
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
        closeButton.isHidden = displayItem.isPinned
        timeLabel.isHidden = true
        if !displayItem.isActive {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.allowsImplicitAnimation = true
                self.layer?.backgroundColor = CocxyColors.surface0.withAlphaComponent(0.3).cgColor
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.pop()
        closeButton.isHidden = true
        timeLabel.isHidden = false
        if !displayItem.isActive {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.allowsImplicitAnimation = true
                self.layer?.backgroundColor = NSColor.clear.cgColor
            }
        }
    }

    // MARK: - Focus Ring

    override var focusRingType: NSFocusRingType {
        get { .exterior }
        set { /* Ignored: always exterior for keyboard accessibility. */ }
    }

    override func drawFocusRingMask() {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        path.fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }
}

// MARK: - Flipped Views for Top-Aligned Scroll Content

/// Clip view with flipped coordinate system so content starts from the top.
final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

/// Document view with flipped coordinate system for top-aligned layout.
final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
