// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// QuickTerminalController.swift - Lifecycle controller for the Quick Terminal.

import AppKit

// MARK: - Quick Terminal Controller

/// Controls the QuickTerminal lifecycle: hotkey registration, show/hide
/// animations, and terminal management.
///
/// ## Responsibilities
///
/// 1. Create and configure the `QuickTerminalPanel`.
/// 2. Register global and local hotkey monitors for Cmd+`.
/// 3. Toggle the panel visibility on hotkey press.
/// 4. Manage the terminal surface inside the panel.
///
/// ## Hotkey strategy
///
/// Uses `NSEvent.addGlobalMonitorForEvents` (app not focused) combined with
/// `NSEvent.addLocalMonitorForEvents` (app focused). This avoids requiring
/// Accessibility permissions that `CGEvent.tapCreate` needs.
///
/// ## Usage
///
/// ```swift
/// let controller = QuickTerminalController()
/// controller.setup(bridge: bridge, config: config)
/// controller.registerHotkey()
/// ```
///
/// - SeeAlso: `QuickTerminalPanel` for the floating panel.
/// - SeeAlso: `QuickTerminalPosition` for edge configuration.
@MainActor
final class QuickTerminalController {

    // MARK: - Constants

    /// Keycode for the grave accent (`) key on a US keyboard layout.
    static let graveAccentKeyCode: UInt16 = 50

    // MARK: - State

    /// Whether the quick terminal panel is currently visible.
    private(set) var isVisible: Bool = false

    /// The floating panel, or nil before `setup()` is called.
    private var panel: QuickTerminalPanel?

    /// The terminal surface view hosted inside the panel.
    private var terminalView: TerminalHostView?

    /// View model retained for the lifetime of the quick terminal surface.
    private var terminalViewModel: TerminalViewModel?

    /// Reference to the terminal engine for surface creation.
    private weak var bridge: (any TerminalEngine)?

    /// The current slide edge, read from config.
    private(set) var currentSlideEdge: QuickTerminalPosition = .top

    /// The current height percent (0.0-1.0), read from config.
    private(set) var currentHeightPercent: CGFloat = 0.4

    /// Working directory used when the quick terminal surface is first spawned.
    private var workingDirectory = FileManager.default.homeDirectoryForCurrentUser

    /// Global event monitor handle (for when app is not focused).
    private var globalMonitor: Any?

    /// Local event monitor handle (for when app is focused).
    private var localMonitor: Any?

    // MARK: - Test Helpers

    /// Whether the panel has been created. Used in tests.
    var isPanelNil: Bool { panel == nil }

    // MARK: - Setup

    /// Creates the panel and applies configuration.
    ///
    /// Can be called multiple times safely. A previous panel is closed and
    /// replaced.
    ///
    /// - Parameters:
    ///   - bridge: The terminal engine bridge for surface creation. Can be nil
    ///     for testing.
    ///   - config: The application configuration to read quick terminal settings from.
    func setup(bridge: (any TerminalEngine)?, config: CocxyConfig) {
        // Tear down previous panel if any.
        destroySurfaceIfNeeded()
        panel?.close()
        panel = nil
        terminalView = nil
        terminalViewModel = nil
        isVisible = false

        self.bridge = bridge

        // Read config values.
        let qtConfig = config.quickTerminal
        currentSlideEdge = qtConfig.position
        currentHeightPercent = CGFloat(qtConfig.heightPercentage) / 100.0
        workingDirectory = Self.resolveWorkingDirectory(from: config)

        // Create the panel.
        let newPanel = QuickTerminalPanel()
        newPanel.slideEdge = currentSlideEdge
        newPanel.heightPercent = currentHeightPercent
        self.panel = newPanel

        // Create the terminal view inside the panel.
        let terminalViewModel = TerminalViewModel(engine: bridge)
        terminalViewModel.setDefaultFontSize(config.appearance.fontSize)
        self.terminalViewModel = terminalViewModel
        let surfaceView = CocxyCoreView(viewModel: terminalViewModel)
        surfaceView.translatesAutoresizingMaskIntoConstraints = false

        newPanel.contentView = surfaceView
        self.terminalView = surfaceView
    }

    // MARK: - Visibility

    /// Toggles the quick terminal: shows if hidden, hides if visible.
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Shows the quick terminal panel with a slide-in animation.
    ///
    /// If already visible, this is a no-op.
    func show() {
        guard !isVisible, let panel = panel else { return }

        let screenFrame = currentScreenFrame()
        panel.slideIn(screenFrame: screenFrame)
        ensureSurfaceCreated()
        terminalView?.syncSizeWithTerminal()
        if let terminalView {
            panel.makeFirstResponder(terminalView)
        }
        isVisible = true
    }

    /// Hides the quick terminal panel with a slide-out animation.
    ///
    /// If already hidden, this is a no-op.
    func hide() {
        guard isVisible, let panel = panel else { return }

        // Set state immediately to prevent re-entrant toggles during animation.
        isVisible = false

        let screenFrame = currentScreenFrame()
        panel.slideOut(screenFrame: screenFrame) {}
    }

    // MARK: - Hotkey Registration

    /// Registers global and local hotkey monitors for Cmd+`.
    ///
    /// Global monitor: fires when the app is NOT focused.
    /// Local monitor: fires when the app IS focused.
    ///
    /// Both filter for keycode 50 (grave accent) + Command modifier.
    func registerHotkey() {
        // Global monitor: app not focused.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard Self.isQuickTerminalHotkey(event) else { return }
            Task { @MainActor [weak self] in
                self?.toggle()
            }
        }

        // Local monitor: app focused.
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { [weak self] event in
            guard Self.isQuickTerminalHotkey(event) else { return event }
            Task { @MainActor [weak self] in
                self?.toggle()
            }
            return nil  // Consume the event.
        }
    }

    /// Unregisters hotkey monitors and cleans up the panel.
    func tearDown() {
        if let globalMonitor = globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor = localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        destroySurfaceIfNeeded()
        panel?.close()
        panel = nil
        terminalView = nil
        terminalViewModel = nil
        isVisible = false
    }

    // MARK: - Private Helpers

    /// Returns the current screen's visible frame for panel positioning.
    private func currentScreenFrame() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
    }

    private func ensureSurfaceCreated() {
        guard let bridge,
              let terminalView,
              terminalViewModel?.surfaceID == nil else { return }

        do {
            let surfaceID = try bridge.createSurface(
                in: terminalView,
                workingDirectory: workingDirectory,
                command: nil
            )
            terminalViewModel?.markRunning(surfaceID: surfaceID)
            terminalView.configureSurfaceIfNeeded(bridge: bridge, surfaceID: surfaceID)
            terminalView.syncSizeWithTerminal()
        } catch {
            NSLog(
                "[QuickTerminalController] Failed to create quick terminal surface: %@",
                String(describing: error)
            )
        }
    }

    private func destroySurfaceIfNeeded() {
        guard let bridge,
              let surfaceID = terminalViewModel?.surfaceID else { return }
        bridge.destroySurface(surfaceID)
        terminalViewModel?.markStopped()
    }

    private static func resolveWorkingDirectory(from config: CocxyConfig) -> URL {
        let rawPath = config.quickTerminal.workingDirectory.isEmpty
            ? config.general.workingDirectory
            : config.quickTerminal.workingDirectory
        let expandedPath = (rawPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath, isDirectory: true)
    }

    /// Checks if a keyboard event matches the quick terminal hotkey (Cmd+`).
    ///
    /// - Parameter event: The keyboard event to check.
    /// - Returns: `true` if the event is Cmd+` (keycode 50 + Command flag).
    private static func isQuickTerminalHotkey(_ event: NSEvent) -> Bool {
        return event.keyCode == graveAccentKeyCode
            && event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.shift)
            && !event.modifierFlags.contains(.option)
            && !event.modifierFlags.contains(.control)
    }
}
