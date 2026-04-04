// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// QuickTerminalPanel.swift - Global dropdown terminal panel.

import AppKit

// MARK: - Quick Terminal Panel

/// Floating NSPanel that provides a globally accessible dropdown terminal.
///
/// Activated by a global hotkey (default: Cmd+`), it slides in from a
/// configurable screen edge with animation. It maintains its own terminal
/// session independently of the main window.
///
/// ## Panel configuration
///
/// - Level: `.floating` (always above normal windows).
/// - Collection behavior: `.canJoinAllSpaces`, `.fullScreenAuxiliary`.
/// - Titlebar: transparent with hidden traffic lights.
/// - Style mask: `.nonactivatingPanel`, `.resizable`, `.closable`,
///   `.titled`, `.fullSizeContentView`.
///
/// ## Animation
///
/// Uses `NSAnimationContext.runAnimationGroup` with ease-in-out timing
/// (0.25s duration). Respects `NSWorkspace.shared
/// .accessibilityDisplayShouldReduceMotion` for instant transitions.
///
/// ## Frame calculation
///
/// - Top/Bottom: full screen width, height = screen.height * heightPercent.
/// - Left/Right: width = screen.width * heightPercent, full screen height.
///
/// - SeeAlso: `QuickTerminalController` for lifecycle management.
/// - SeeAlso: `QuickTerminalPosition` for edge enum.
@MainActor
final class QuickTerminalPanel: NSPanel {

    // MARK: - Constants

    /// Minimum height/width percent (20% of screen dimension).
    static let minimumPercent: CGFloat = 0.2

    /// Maximum height/width percent (90% of screen dimension).
    static let maximumPercent: CGFloat = 0.9

    /// Animation duration in seconds for slide-in/slide-out.
    static let animationDuration: TimeInterval = 0.25

    // MARK: - Configuration

    /// The edge from which the panel slides in.
    var slideEdge: QuickTerminalPosition = .top

    /// The panel size as a fraction of the relevant screen dimension.
    /// Clamped to [minimumPercent, maximumPercent] during frame calculation.
    var heightPercent: CGFloat = 0.4

    /// Whether the panel hides when the app loses focus.
    var hideOnDeactivate: Bool = true

    // MARK: - Initialization

    /// Creates a QuickTerminalPanel configured for floating dropdown behavior.
    convenience init() {
        let styleMask: NSWindow.StyleMask = [
            .nonactivatingPanel,
            .resizable,
            .closable,
            .titled,
            .fullSizeContentView,
        ]

        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: styleMask,
            backing: .buffered,
            defer: true
        )

        configurePanel()
    }

    // MARK: - Panel Configuration

    /// Applies the floating panel settings required for a dropdown terminal.
    private func configurePanel() {
        level = .floating
        isFloatingPanel = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isReleasedWhenClosed = false
        hidesOnDeactivate = false  // We control this ourselves in the controller.

        // Accessibility: label for VoiceOver identification.
        setAccessibilityLabel("Quick Terminal")

        // Hide the traffic light buttons.
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        // Background for the panel.
        isOpaque = false
        backgroundColor = CocxyColors.base.withAlphaComponent(0.98)
    }

    // MARK: - Frame Calculation

    /// Calculates the visible (on-screen) frame for the panel.
    ///
    /// - Parameters:
    ///   - edge: The screen edge to anchor the panel to.
    ///   - heightPercent: Fraction of the screen dimension (clamped to 0.2...0.9).
    ///   - screenFrame: The screen's visible frame.
    /// - Returns: The calculated frame rectangle.
    static func calculateFrame(
        for edge: QuickTerminalPosition,
        heightPercent: CGFloat,
        screenFrame: NSRect
    ) -> NSRect {
        let clampedPercent = max(minimumPercent, min(maximumPercent, heightPercent))

        switch edge {
        case .top:
            let panelHeight = screenFrame.height * clampedPercent
            return NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.maxY - panelHeight,
                width: screenFrame.width,
                height: panelHeight
            )

        case .bottom:
            let panelHeight = screenFrame.height * clampedPercent
            return NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.origin.y,
                width: screenFrame.width,
                height: panelHeight
            )

        case .left:
            let panelWidth = screenFrame.width * clampedPercent
            return NSRect(
                x: screenFrame.origin.x,
                y: screenFrame.origin.y,
                width: panelWidth,
                height: screenFrame.height
            )

        case .right:
            let panelWidth = screenFrame.width * clampedPercent
            return NSRect(
                x: screenFrame.maxX - panelWidth,
                y: screenFrame.origin.y,
                width: panelWidth,
                height: screenFrame.height
            )
        }
    }

    /// Calculates the off-screen frame for the panel (used as animation start/end).
    ///
    /// The off-screen frame has the same size as the visible frame but is
    /// positioned just outside the screen bounds on the relevant edge.
    ///
    /// - Parameters:
    ///   - edge: The screen edge the panel slides from.
    ///   - visibleFrame: The on-screen frame (from `calculateFrame`).
    /// - Returns: The off-screen frame rectangle.
    static func calculateOffScreenFrame(
        for edge: QuickTerminalPosition,
        visibleFrame: NSRect
    ) -> NSRect {
        switch edge {
        case .top:
            return NSRect(
                x: visibleFrame.origin.x,
                y: visibleFrame.origin.y + visibleFrame.height,
                width: visibleFrame.width,
                height: visibleFrame.height
            )

        case .bottom:
            return NSRect(
                x: visibleFrame.origin.x,
                y: visibleFrame.origin.y - visibleFrame.height,
                width: visibleFrame.width,
                height: visibleFrame.height
            )

        case .left:
            return NSRect(
                x: visibleFrame.origin.x - visibleFrame.width,
                y: visibleFrame.origin.y,
                width: visibleFrame.width,
                height: visibleFrame.height
            )

        case .right:
            return NSRect(
                x: visibleFrame.origin.x + visibleFrame.width,
                y: visibleFrame.origin.y,
                width: visibleFrame.width,
                height: visibleFrame.height
            )
        }
    }

    // MARK: - Animation

    /// Slides the panel in from the configured edge with animation.
    ///
    /// If the user has reduce-motion enabled, the panel appears instantly.
    ///
    /// - Parameter screenFrame: The screen frame to calculate position from.
    func slideIn(screenFrame: NSRect) {
        let visibleFrame = Self.calculateFrame(
            for: slideEdge,
            heightPercent: heightPercent,
            screenFrame: screenFrame
        )

        let shouldReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if shouldReduceMotion {
            setFrame(visibleFrame, display: true)
            makeKeyAndOrderFront(nil)
            return
        }

        // Start at off-screen position.
        let offScreenFrame = Self.calculateOffScreenFrame(
            for: slideEdge,
            visibleFrame: visibleFrame
        )
        setFrame(offScreenFrame, display: false)
        makeKeyAndOrderFront(nil)

        // Animate to visible position.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(visibleFrame, display: true)
        }
    }

    /// Slides the panel out to the configured edge with animation.
    ///
    /// If the user has reduce-motion enabled, the panel disappears instantly.
    ///
    /// - Parameters:
    ///   - screenFrame: The screen frame to calculate position from.
    ///   - completion: Called after the animation finishes.
    func slideOut(screenFrame: NSRect, completion: @escaping @Sendable () -> Void) {
        let visibleFrame = Self.calculateFrame(
            for: slideEdge,
            heightPercent: heightPercent,
            screenFrame: screenFrame
        )

        let shouldReduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if shouldReduceMotion {
            orderOut(nil)
            completion()
            return
        }

        let offScreenFrame = Self.calculateOffScreenFrame(
            for: slideEdge,
            visibleFrame: visibleFrame
        )

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.animator().setFrame(offScreenFrame, display: true)
        }, completionHandler: {
            MainActor.assumeIsolated {
                self.orderOut(nil)
            }
            completion()
        })
    }
}
