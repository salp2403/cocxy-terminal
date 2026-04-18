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

    /// Provides the drag data for cross-window tab transfer.
    /// Returns nil if dragging is not allowed (e.g., pinned tab).
    var onDragData: (() -> SessionDragData?)?

    /// Invoked when the user clicks a per-split mini-pill inside this
    /// tab row. The host (`MainWindowController`) activates the owning
    /// tab if needed and focuses the split that matches the surface ID.
    var onFocusSplit: ((SurfaceID) -> Void)?

    /// When true, shows a confirmation alert before closing the tab.
    /// Set by the parent view based on `confirmCloseProcess` config.
    var shouldConfirmClose: Bool = false

    /// When true, attention borders and glow effects are applied on unread tabs.
    /// Set by the parent view from `notifications.flash-tab` config.
    var flashTabEnabled: Bool = true

    /// When true, unread notification count badges are shown on inactive tabs.
    /// Set by the parent view from `notifications.badge-on-tab` config.
    var badgeOnTabEnabled: Bool = true

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

    /// Notification count badge — small red circle positioned top-right.
    private let notificationBadge: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        label.isBordered = false
        label.isEditable = false
        label.drawsBackground = false
        label.wantsLayer = true
        label.layer?.backgroundColor = CocxyColors.red.cgColor
        label.layer?.cornerRadius = 8
        label.layer?.masksToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    /// Inline stats chips shown when an agent is active (tools/errors/duration).
    private let statsStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    /// Mini indicators for additional splits of the tab running agents
    /// whose state did not drive the primary pill. Fase 3e renders one
    /// small colored dot per entry (max 5, with a `+N` overflow label),
    /// positioned on the status-label row so the user sees every agent
    /// across the tab's splits without opening it.
    private let miniIndicatorsStack: NSStackView = {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.isHidden = true
        stack.setAccessibilityLabel("Additional active agents")
        return stack
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
        addSubview(miniIndicatorsStack)
        addSubview(pathLabel)
        addSubview(statsStack)
        addSubview(notificationBadge)

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
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: miniIndicatorsStack.leadingAnchor, constant: -6),

            miniIndicatorsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            miniIndicatorsStack.centerYAnchor.constraint(equalTo: statusLabel.centerYAnchor),

            pathLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: textLeading + 20),
            pathLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 2),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: statsStack.leadingAnchor, constant: -4),

            statsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            statsStack.centerYAnchor.constraint(equalTo: pathLabel.centerYAnchor),

            // Notification badge — top-right corner, to the left of close button.
            notificationBadge.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -2),
            notificationBadge.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            notificationBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
            notificationBadge.heightAnchor.constraint(equalToConstant: 16),
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

        configureStatsChips(with: item)
        configureMiniIndicators(with: item)

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

        // Notification badge: show count for inactive tabs with unread notifications.
        // Gated by the `badge-on-tab` config toggle.
        let unreadCount = item.unreadNotificationCount
        if badgeOnTabEnabled && unreadCount > 0 && !item.isActive {
            notificationBadge.stringValue = unreadCount > 9 ? "9+" : "\(unreadCount)"
            notificationBadge.isHidden = false
        } else {
            notificationBadge.isHidden = true
        }

        // Hover tooltip: show latest notification preview.
        toolTip = item.notificationPreview

        // Attention effects (border glow, pulse) gated by `flash-tab` config toggle.
        let needsAttention = !item.isActive && (item.agentState == .waitingInput || item.hasUnreadNotification || unreadCount > 0)
        if flashTabEnabled && needsAttention {
            applyAttentionBorder(color: stateColor)
            applyGlowEffect(color: stateColor)
        } else {
            removeAttentionBorder()
            removeGlowEffect()
        }

        if flashTabEnabled && item.agentState == .working {
            startAccentPulse(color: stateColor)
        } else {
            stopAccentPulse()
        }

        setAccessibilityRole(.button)
        setAccessibilityLabel(item.displayTitle)
        setAccessibilityValue("Agent: \(item.agentState.accessibilityDescription)")
        setAccessibilityHelp("Activate this tab")
    }

    // MARK: - Stats Chips

    /// Configures inline stats chips (tools/errors/duration) when an agent is active.
    private func configureStatsChips(with item: TabDisplayItem) {
        // Remove previous chips.
        statsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let isAgentActive = item.agentState != .idle
        statsStack.isHidden = !isAgentActive

        guard isAgentActive else { return }

        if item.agentToolCount > 0 {
            statsStack.addArrangedSubview(
                makeStatChip(
                    icon: "bolt.fill",
                    value: "\(item.agentToolCount)",
                    color: CocxyColors.blue
                )
            )
        }
        if item.agentErrorCount > 0 {
            statsStack.addArrangedSubview(
                makeStatChip(
                    icon: "exclamationmark.triangle.fill",
                    value: "\(item.agentErrorCount)",
                    color: CocxyColors.red
                )
            )
        }
        if let duration = item.agentDurationText {
            statsStack.addArrangedSubview(
                makeStatChip(
                    icon: "clock",
                    value: duration,
                    color: CocxyColors.overlay1
                )
            )
        }
    }

    // MARK: - Multi-Agent Mini Pills (Fase B)

    /// Maximum number of mini pills rendered inline before collapsing
    /// the remainder into a `+N` overflow label. Kept at four because
    /// each pill now reserves ~30pt for the agent abbreviation, so the
    /// sidebar stays legible in narrow widths.
    private static let miniIndicatorsMaxInline = 4

    /// Populates the mini-pills stack from the tab's `perSurfaceAgents`
    /// snapshots.
    ///
    /// Each entry becomes a compact pill showing the agent's two-letter
    /// abbreviation (`Cl`, `Co`, `Ge`, `Ai`, ...) with a colored dot and
    /// an optional 1.5pt border when the split is focused. Clicking a
    /// pill invokes `onFocusSplit(surfaceID)` so the host can activate
    /// the tab (if needed) and route focus to the selected split. An
    /// overflow label appears when more snapshots are present than the
    /// inline budget allows.
    private func configureMiniIndicators(with item: TabDisplayItem) {
        miniIndicatorsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        guard !item.perSurfaceAgents.isEmpty else {
            miniIndicatorsStack.isHidden = true
            return
        }

        miniIndicatorsStack.isHidden = false

        let visible = item.perSurfaceAgents.prefix(Self.miniIndicatorsMaxInline)
        for snapshot in visible {
            miniIndicatorsStack.addArrangedSubview(
                makeMiniPill(
                    snapshot: snapshot,
                    color: stateNSColor(for: snapshot.state.agentState)
                )
            )
        }

        let overflow = item.perSurfaceAgents.count - Self.miniIndicatorsMaxInline
        if overflow > 0 {
            let overflowLabel = NSTextField(labelWithString: "+\(overflow)")
            overflowLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
            overflowLabel.textColor = CocxyColors.subtext1
            overflowLabel.translatesAutoresizingMaskIntoConstraints = false
            overflowLabel.setAccessibilityLabel("\(overflow) more active agents")
            miniIndicatorsStack.addArrangedSubview(overflowLabel)
        }
    }

    /// Builds a single mini-pill for one split snapshot, wiring the
    /// click handler through `onFocusSplit`.
    private func makeMiniPill(
        snapshot: SurfaceAgentSnapshot,
        color: NSColor
    ) -> NSView {
        let pill = MiniAgentPillView(
            snapshot: snapshot,
            stateColor: color
        )
        pill.onClick = { [weak self] surfaceID in
            self?.onFocusSplit?(surfaceID)
        }
        return pill
    }

    /// Creates a compact stat chip (icon + value) for the stats stack.
    private func makeStatChip(icon: String, value: String, color: NSColor) -> NSView {
        let container = NSStackView()
        container.orientation = .horizontal
        container.spacing = 2

        let iconView = NSImageView()
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            iconView.image = img.withSymbolConfiguration(.init(pointSize: 7, weight: .medium))
        }
        iconView.contentTintColor = color
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 10),
            iconView.heightAnchor.constraint(equalToConstant: 10),
        ])

        let label = NSTextField(labelWithString: value)
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        label.textColor = color

        container.addArrangedSubview(iconView)
        container.addArrangedSubview(label)
        return container
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

    /// Stored mouse-down location for drag detection.
    private var mouseDownLocation: NSPoint?

    /// Minimum distance (points) the mouse must travel before a drag starts.
    private static let dragThreshold: CGFloat = 5

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if closeButton.frame.contains(localPoint) { return }
        if isEditing { return }

        if event.clickCount >= 2 {
            startEditing()
            return
        }

        // Store for drag detection in mouseDragged.
        mouseDownLocation = event.locationInWindow

        // Select immediately on single click — no delay.
        // Double-click rename is handled above via clickCount.
        onSelect?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startLocation = mouseDownLocation else { return }

        // Only start a drag after the threshold is exceeded.
        let dx = event.locationInWindow.x - startLocation.x
        let dy = event.locationInWindow.y - startLocation.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance >= Self.dragThreshold else { return }

        // Clear to prevent re-triggering.
        mouseDownLocation = nil

        beginDragSession(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownLocation = nil
    }

    // MARK: - Drag Source

    /// Initiates an NSDraggingSession for cross-window tab transfer.
    private func beginDragSession(with event: NSEvent) {
        guard let dragData = onDragData?(),
              let jsonData = dragData.pasteboardData() else { return }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setData(jsonData, forType: .cocxySession)

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)

        // Create a snapshot of this view as the drag image.
        let snapshot = snapshotForDrag()
        draggingItem.setDraggingFrame(bounds, contents: snapshot)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    /// Creates a semi-transparent snapshot of this tab item for the drag image.
    private func snapshotForDrag() -> NSImage {
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.setAlpha(0.7)
            layer?.render(in: context)
        }
        image.unlockFocus()
        return image
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

// MARK: - NSDraggingSource Conformance

extension TabItemView: NSDraggingSource {
    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Allow move within the app (same or different window).
        context == .withinApplication ? .move : []
    }
}

// MARK: - Multi-Agent Mini Pill View

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
@MainActor
private final class MiniAgentPillView: NSView {

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

// MARK: - Flipped Views for Top-Aligned Scroll Content

/// Clip view with flipped coordinate system so content starts from the top.
final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

/// Document view with flipped coordinate system for top-aligned layout.
final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
