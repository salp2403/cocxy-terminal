// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraChromeController.swift - Integration seam between the live
// production domain (TabManager + AgentStatePerSurfaceStore) and the
// Aurora presentation module.
//
// This is the only file in `Sources/UI/Design/` that imports AppKit and
// domain types. The rest of the design module stays presentation-only;
// here we bridge the two without leaking SwiftUI internals into the
// domain or AppKit mount points into the views.
//
// Responsibilities:
//   - Own the `@ObservableObject` state consumed by Aurora views.
//   - Build the Aurora input list through `AuroraSourceBuilder` and feed
//     the adapter so the sidebar/status bar always reflect live data.
//   - Hand the host view controller ready-to-mount `NSHostingView`
//     instances for sidebar, status bar and palette overlay.
//   - Route SwiftUI callbacks (activate session, create tab, execute
//     palette action) to injectable closures so the host stays in
//     control of every mutation.
//
// The controller is additive: while the feature flag is off it is never
// instantiated, so the classic chrome path stays bit-for-bit unchanged.

import AppKit
import Combine
import SwiftUI

@MainActor
final class AuroraChromeController: ObservableObject {

    // MARK: - Published state

    /// Aurora workspace tree consumed by the sidebar and the status-bar
    /// agent matrix. Rebuilt on every snapshot update.
    @Published var workspaces: [Design.AuroraWorkspace] = []

    /// Session id matching `Tab.id.uuidString`, used by the sidebar to
    /// highlight the active row.
    @Published var activeSessionID: String?

    /// Port bindings surfaced on the Aurora status bar. Kept empty until
    /// a future release wires the port scanner through.
    @Published var ports: [Design.AuroraPortBinding] = []

    /// Timeline scrubber snapshot. Default "live / now" until the
    /// command-duration store feeds a real replay window.
    @Published var timeline: Design.AuroraTimelineState = .init(progress: 1)

    /// Clock label rendered at the far right of the Aurora status bar.
    /// Updated once per second by the integration layer.
    @Published var clockLabel: String = ""

    /// Palette data mirrored from the production engine.
    @Published var paletteActions: [Design.AuroraPaletteAction] = []
    @Published var isPaletteVisible: Bool = false
    @Published var paletteQuery: String = ""
    @Published var paletteSelectedIndex: Int = 0

    /// Pretty shortcut labels shown on the Aurora sidebar tray. The
    /// integration layer refreshes these from the live keybindings so
    /// edits to `window.commandPalette` / `tab.new` reach the header
    /// (and stay aligned with the menu bar glyphs rendered by
    /// `MenuKeybindingsBinder`). Defaults match the catalog baselines
    /// using the macOS-canonical modifier order
    /// (`⌃⌥⇧⌘<key>`) that `KeybindingShortcut.prettyLabel` emits, so
    /// previews and tests render without depending on the binder.
    @Published var paletteShortcutLabel: String = "⇧⌘P"
    @Published var newTabShortcutLabel: String = "⌘T"

    // MARK: - Dependencies (weak)

    private weak var tabManager: TabManager?
    private weak var store: AgentStatePerSurfaceStore?

    // MARK: - Host callbacks

    /// Invoked when the user picks a session row in the Aurora sidebar.
    /// The host resolves the session id back to the owning tab and
    /// activates it through the existing focus path.
    var onActivateSession: ((TabID) -> Void)?

    /// Invoked when the user taps the "+" button in the Aurora sidebar
    /// header. Wired to the controller's `createTab()` path so the new
    /// tab goes through the standard lifecycle hooks.
    var onCreateTab: (() -> Void)?

    /// Invoked when the user presses the palette hotkey inside an
    /// Aurora view (sidebar header button, palette-trigger keyboard
    /// shortcut). Delegates to `toggleCommandPalette()` on the host.
    var onTogglePalette: (() -> Void)?

    /// Invoked when a palette action is executed. Uses the action id
    /// so the host can forward to the shared engine without leaking
    /// engine types into the design module.
    var onExecutePaletteAction: ((String) -> Void)?

    /// Invoked when the palette overlay is dismissed without picking
    /// an action (escape key, backdrop tap).
    var onDismissPalette: (() -> Void)?

    // MARK: - Data providers

    /// Caller-provided snapshot of the surfaces each tab owns, in the
    /// order the sidebar should show them. Typically filled from the
    /// host's `splitManager` + `tabSurfaceMap` + `splitSurfaceViews`.
    var surfaceIDsByTabProvider: (() -> [TabID: [SurfaceID]])?

    // MARK: - Hosting views

    private(set) var sidebarHost: AuroraHostingView<AuroraSidebarHost>?
    private(set) var statusBarHost: AuroraHostingView<AuroraStatusBarHost>?
    private(set) var paletteHost: AuroraHostingView<AuroraPaletteHost>?

    // MARK: - Private state

    private var cancellables: Set<AnyCancellable> = []
    private var clockTimerCancellable: AnyCancellable?

    // MARK: - Init

    init(
        tabManager: TabManager,
        store: AgentStatePerSurfaceStore
    ) {
        self.tabManager = tabManager
        self.store = store
        updateClockLabel()
    }

    // MARK: - Subscriptions

    /// Starts observing domain changes. Called by the host after the
    /// controller is installed. Safe to call multiple times; prior
    /// subscriptions are dropped so reinstalls do not accumulate sinks.
    func beginObservingDomain() {
        cancellables.removeAll()

        guard let tabManager, let store else { return }

        tabManager.$tabs
            .sink { [weak self] _ in self?.refreshSources() }
            .store(in: &cancellables)

        tabManager.$activeTabID
            .sink { [weak self] _ in self?.refreshSources() }
            .store(in: &cancellables)

        store.$states
            .sink { [weak self] _ in self?.refreshSources() }
            .store(in: &cancellables)

        startClockTimer()
        refreshSources()
    }

    /// Stops observing and cancels the clock timer. Called when the
    /// controller is torn down or the Aurora flag is flipped off.
    func stopObserving() {
        cancellables.removeAll()
        clockTimerCancellable?.cancel()
        clockTimerCancellable = nil
    }

    // MARK: - Snapshot refresh

    /// Rebuilds the workspace tree from the current domain snapshot.
    /// Exposed as `internal` so the host can force a refresh after
    /// lifecycle events the subscriptions do not catch (split creation,
    /// session restore, surface teardown).
    func refreshSources() {
        guard let tabManager, let store else { return }

        let surfaceMap = surfaceIDsByTabProvider?() ?? [:]
        let sources = AuroraSourceBuilder.buildSources(
            tabs: tabManager.tabs,
            surfaceIDsByTab: surfaceMap,
            store: store
        )
        workspaces = Design.AuroraWorkspaceAdapter.workspaces(from: sources)
        activeSessionID = tabManager.activeTab?.id.rawValue.uuidString
    }

    // MARK: - Palette

    /// Replaces the palette action catalogue. Called by the host after
    /// rebuilding shortcut labels (post config reload) or when actions
    /// are added or removed (feature flag toggles).
    func setPaletteActions(_ actions: [Design.AuroraPaletteAction]) {
        paletteActions = actions
        if paletteSelectedIndex >= actions.count {
            paletteSelectedIndex = max(0, actions.count - 1)
        }
    }

    /// Shows the palette overlay and resets selection/query so the user
    /// starts with an empty matcher every time.
    ///
    /// The hosting `NSHostingView` is un-hidden alongside the published
    /// flag so hit-testing reaches the SwiftUI overlay. While the flag
    /// is off the view renders as empty but the hosting view still
    /// intercepts hit-tests; keeping it hidden until the palette is
    /// requested preserves input routing for the surfaces underneath.
    func showPalette() {
        paletteQuery = ""
        paletteSelectedIndex = 0
        isPaletteVisible = true
        paletteHost?.isHidden = false
    }

    /// Hides the palette overlay and notifies the host so it can
    /// restore first-responder on the terminal surface. Also hides the
    /// hosting view so clicks fall through to the terminal again.
    func hidePalette() {
        isPaletteVisible = false
        paletteHost?.isHidden = true
        onDismissPalette?()
    }

    /// Toggles between showing and hiding the palette overlay. Used by
    /// the integration layer when the palette shortcut fires while the
    /// Aurora chrome is active so the same keyboard binding drives the
    /// right overlay regardless of which chrome is mounted.
    func togglePalette() {
        if isPaletteVisible {
            hidePalette()
        } else {
            showPalette()
        }
    }

    // MARK: - Hosting view factories

    /// Builds (or returns the cached) sidebar hosting view. The wrapper
    /// holds a strong reference to `self` so Combine-driven updates on
    /// `workspaces` / `activeSessionID` keep the view in sync.
    func makeSidebarHost() -> AuroraHostingView<AuroraSidebarHost> {
        if let cached = sidebarHost { return cached }
        let host = AuroraHostingView(rootView: AuroraSidebarHost(controller: self))
        host.translatesAutoresizingMaskIntoConstraints = true
        sidebarHost = host
        return host
    }

    /// Builds (or returns the cached) status-bar hosting view.
    func makeStatusBarHost() -> AuroraHostingView<AuroraStatusBarHost> {
        if let cached = statusBarHost { return cached }
        let host = AuroraHostingView(rootView: AuroraStatusBarHost(controller: self))
        host.translatesAutoresizingMaskIntoConstraints = true
        statusBarHost = host
        return host
    }

    /// Builds (or returns the cached) command-palette hosting view.
    /// The wrapper is always mounted — it decides whether to render via
    /// its own `isPaletteVisible` binding so the host doesn't need to
    /// toggle `isHidden` on every open/close cycle.
    func makePaletteHost() -> AuroraHostingView<AuroraPaletteHost> {
        if let cached = paletteHost { return cached }
        let host = AuroraHostingView(rootView: AuroraPaletteHost(controller: self))
        host.translatesAutoresizingMaskIntoConstraints = true
        paletteHost = host
        return host
    }

    // MARK: - Clock

    private func startClockTimer() {
        clockTimerCancellable?.cancel()
        updateClockLabel()
        clockTimerCancellable = Timer
            .publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.updateClockLabel() }
    }

    private func updateClockLabel() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        clockLabel = formatter.string(from: Date())
    }

    // MARK: - Session id lookup

    /// Resolves a session id back to the owning `TabID` so the host
    /// can reuse its existing focus handlers.
    func tabID(forSessionID sessionID: String) -> TabID? {
        guard let tabManager else { return nil }
        return tabManager.tabs.first {
            $0.id.rawValue.uuidString == sessionID
        }?.id
    }
}

// MARK: - SwiftUI host wrappers

/// Wrapper view that observes the controller so SwiftUI re-renders when
/// any published property changes. Using a dedicated wrapper avoids
/// stashing Combine bindings on NSHostingView (which would break
/// reactive updates) and keeps the design-module view contracts intact.
struct AuroraSidebarHost: View {

    @ObservedObject var controller: AuroraChromeController

    var body: some View {
        Design.AuroraSidebarView(
            workspaces: Binding(
                get: { controller.workspaces },
                set: { controller.workspaces = $0 }
            ),
            activeSessionID: Binding(
                get: { controller.activeSessionID },
                set: { controller.activeSessionID = $0 }
            ),
            onTogglePalette: { controller.onTogglePalette?() },
            onCreateTab: { controller.onCreateTab?() },
            onActivateSession: { sessionID in
                if let tabID = controller.tabID(forSessionID: sessionID) {
                    controller.onActivateSession?(tabID)
                }
            },
            paletteShortcutLabel: controller.paletteShortcutLabel,
            newTabShortcutLabel: controller.newTabShortcutLabel
        )
    }
}

struct AuroraStatusBarHost: View {

    @ObservedObject var controller: AuroraChromeController

    var body: some View {
        Design.AuroraStatusBarView(
            workspaces: controller.workspaces,
            ports: controller.ports,
            timeline: Binding(
                get: { controller.timeline },
                set: { controller.timeline = $0 }
            ),
            clockLabel: controller.clockLabel,
            onReplay: { /* Reserved for a future timeline replay hook. */ }
        )
    }
}

struct AuroraPaletteHost: View {

    @ObservedObject var controller: AuroraChromeController

    var body: some View {
        Design.AuroraCommandPaletteView(
            isVisible: Binding(
                get: { controller.isPaletteVisible },
                set: { newValue in
                    if newValue {
                        controller.showPalette()
                    } else {
                        controller.hidePalette()
                    }
                }
            ),
            query: Binding(
                get: { controller.paletteQuery },
                set: { controller.paletteQuery = $0 }
            ),
            selectedIndex: Binding(
                get: { controller.paletteSelectedIndex },
                set: { controller.paletteSelectedIndex = $0 }
            ),
            actions: Design.AuroraPaletteFilter.filter(
                controller.paletteActions,
                by: controller.paletteQuery
            ),
            onSelect: { action in
                controller.onExecutePaletteAction?(action.id)
                controller.hidePalette()
            },
            onDismiss: { controller.hidePalette() }
        )
    }
}

// MARK: - Hosting view subclass

/// `NSHostingView` subclass used exclusively by the Aurora chrome.
///
/// Overrides `mouseDownCanMoveWindow` to return `false`. Without this
/// override the main window (`isMovableByWindowBackground = true`)
/// interprets any click that lands on a "non-interactive" area of the
/// SwiftUI overlay as a window-drag gesture, swallowing taps on
/// session rows, workspace collapse toggles and tray buttons. Setting
/// it to `false` matches what `NonDraggableView` and the classic
/// `MiniAgentPillView` / tab-bar containers already do — the rule is
/// documented in `feedback_mousedown_movable_window`.
///
/// Also accepts first responder so the palette overlay can receive
/// keyboard input without another wrapper layer.
final class AuroraHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func becomeFirstResponder() -> Bool { true }
}
