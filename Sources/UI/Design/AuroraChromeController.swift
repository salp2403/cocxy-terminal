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

    /// Port bindings surfaced on the Aurora status bar. Mirrored from the
    /// live `PortScannerImpl` whenever the integration layer wires one in.
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

    /// Live Aurora visual theme. The host keeps this aligned with the
    /// terminal theme so the sidebar/status/palette do not stay dark when
    /// the user switches the shell to a light palette.
    @Published var themeIdentity: Design.ThemeIdentity = .aurora

    /// Sidebar hover inspector rendered by a separate passthrough host
    /// on the window overlay layer. Keeping it outside the sidebar's
    /// hosting view prevents the card from covering rows while the user
    /// navigates or opens context menus.
    @Published var sidebarTooltip: Design.AuroraSidebarTooltipSnapshot?
    @Published var sidebarTooltipSidebarFrameInOverlay: CGRect = .zero

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

    /// Invoked when the user clicks a session-row close affordance in
    /// the Aurora sidebar. The host routes this through the same
    /// `closeTab(_:)` lifecycle as the classic tab strip, including
    /// pinned-tab guards, close confirmation, split teardown and store
    /// cleanup.
    var onCloseSession: ((TabID) -> Void)?

    /// Context-menu parity with the classic sidebar. Aurora rows are
    /// SwiftUI, not `TabItemView`, so pinning / close-others / movement
    /// are routed through explicit callbacks instead of reusing AppKit's
    /// `NSMenuItem` target-action handlers.
    var onTogglePinSession: ((TabID) -> Void)?
    var onCloseOtherSessions: ((TabID) -> Void)?
    var onMoveSessionUp: ((TabID) -> Void)?
    var onMoveSessionDown: ((TabID) -> Void)?

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

    /// Invoked when the user clicks the bell glyph in the Aurora
    /// sidebar tray. The host wires this to the existing
    /// `toggleNotificationPanel()` so the classic and Aurora chromes
    /// open the same overlay.
    var onToggleNotifications: (() -> Void)?

    // MARK: - Data providers

    /// Caller-provided snapshot of the surfaces each tab owns, in the
    /// order the sidebar should show them. Typically filled from the
    /// host's `splitManager` + `tabSurfaceMap` + `splitSurfaceViews`.
    var surfaceIDsByTabProvider: (() -> [TabID: [SurfaceID]])?

    // MARK: - Hosting views

    private(set) var sidebarHost: AuroraHostingView<AuroraSidebarHost>?
    private(set) var statusBarHost: AuroraHostingView<AuroraStatusBarHost>?
    private(set) var paletteHost: AuroraHostingView<AuroraPaletteHost>?
    private(set) var sidebarTooltipHost: AuroraPassthroughHostingView<AuroraSidebarTooltipHost>?

    // MARK: - Private state

    private var cancellables: Set<AnyCancellable> = []
    private var clockTimerCancellable: AnyCancellable?
    private var portsCancellable: AnyCancellable?

    /// Live provider for the `[worktree].show-badge` config flag. The
    /// controller reads it on every refresh so toggling the flag in the
    /// user's TOML takes effect at the next sidebar update without
    /// touching persisted tab state. Defaults to `true` so
    /// environments that never wire the provider (tests, legacy paths)
    /// keep rendering the badge.
    var worktreeBadgeVisibleProvider: @MainActor () -> Bool = { true }

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
            .sink { [weak self] tabs in
                self?.refreshSources(tabsSnapshot: tabs)
            }
            .store(in: &cancellables)

        tabManager.$activeTabID
            .sink { [weak self] activeTabID in
                self?.refreshSources(activeTabID: activeTabID)
            }
            .store(in: &cancellables)

        store.$states
            .sink { [weak self] states in
                self?.refreshSources(stateSnapshot: states)
            }
            .store(in: &cancellables)

        startClockTimer()
        refreshSources()
    }

    /// Subscribes to a port scanner and mirrors its active ports onto
    /// the Aurora status-bar view. Idempotent — calling it again with
    /// a different scanner drops the previous subscription. Pass `nil`
    /// to clear the live wiring (e.g. when the Aurora chrome is torn
    /// down while the scanner continues running for the classic
    /// status bar).
    func wirePortScanner(_ scanner: PortScannerImpl?) {
        portsCancellable?.cancel()
        portsCancellable = nil
        guard let scanner else {
            ports = []
            return
        }
        ports = Self.mapPorts(scanner.activePorts)
        portsCancellable = scanner.$activePorts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] latest in
                self?.ports = AuroraChromeController.mapPorts(latest)
            }
    }

    /// Pure mapper from the domain's `DetectedPort` list to the
    /// presentation-only `AuroraPortBinding` list the status bar
    /// consumes. Exposed as `static` so tests can exercise the
    /// translation without touching the @Published pipeline.
    static func mapPorts(_ detected: [DetectedPort]) -> [Design.AuroraPortBinding] {
        detected.map { entry in
            Design.AuroraPortBinding(
                port: Int(entry.port),
                name: entry.processName ?? String(entry.port),
                health: .ok
            )
        }
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
        refreshSources(
            tabsSnapshot: tabManager?.tabs,
            activeTabID: tabManager?.activeTabID,
            stateSnapshot: store?.states
        )
    }

    /// Rebuilds the workspace tree while using an explicit active tab
    /// and domain snapshots. `@Published` emits during `willSet`, so
    /// sinks must use the value Combine just delivered instead of
    /// reading the source object again. Otherwise the terminal/agent can
    /// update correctly while Aurora repaints from the previous tab list,
    /// previous active tab, or previous per-surface agent state until
    /// some unrelated refresh happens.
    private func refreshSources(
        tabsSnapshot: [Tab]? = nil,
        activeTabID: TabID? = nil,
        stateSnapshot: [SurfaceID: SurfaceAgentState]? = nil
    ) {
        guard let tabManager, let store else { return }

        let tabs = tabsSnapshot ?? tabManager.tabs
        let surfaceMap = surfaceIDsByTabProvider?() ?? [:]
        let sources = AuroraSourceBuilder.buildSources(
            tabs: tabs,
            surfaceIDsByTab: surfaceMap,
            store: store,
            stateSnapshot: stateSnapshot,
            worktreeBadgeVisible: worktreeBadgeVisibleProvider()
        )
        let resolvedActiveTabID = activeTabID ?? tabManager.activeTabID
        activeSessionID = resolvedActiveTabID?.rawValue.uuidString
        workspaces = Design.AuroraWorkspaceAdapter.workspaces(from: sources)
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

    /// Builds (or returns the cached) sidebar tooltip overlay host. This
    /// host is mounted over the full window overlay layer and is fully
    /// passthrough at the AppKit hit-test level.
    func makeSidebarTooltipHost() -> AuroraPassthroughHostingView<AuroraSidebarTooltipHost> {
        if let cached = sidebarTooltipHost { return cached }
        let host = AuroraPassthroughHostingView(rootView: AuroraSidebarTooltipHost(controller: self))
        host.translatesAutoresizingMaskIntoConstraints = true
        sidebarTooltipHost = host
        return host
    }

    func updateSidebarTooltipSidebarFrameInOverlay(_ frame: CGRect) {
        sidebarTooltipSidebarFrameInOverlay = frame
    }

    // MARK: - Clock

    private func startClockTimer() {
        clockTimerCancellable?.cancel()
        updateClockLabel()
        // `Timer.publish(on: .main, in: .common).autoconnect()` keeps the
        // main run loop alive until its subscriber is cancelled. In GUI
        // sessions ARC releases the controller when its host window closes,
        // so the timer stops. Under `xctest` test cases often create Aurora
        // controllers and never tear them down, leaving the clock timer
        // subscribed on the main run loop; the xctest process then never
        // returns after the last test case. Production keeps the live
        // clock; tests skip it — the label is already populated by the
        // `updateClockLabel()` call above, so the first render still shows
        // the right value.
        guard !Self.isRunningUnderXCTest else { return }
        clockTimerCancellable = Timer
            .publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.updateClockLabel() }
    }

    /// True when the current process is any test runner (XCTest or Swift
    /// Testing). Mirrors the gate used by
    /// `MainWindowController+AuroraIntegration` so every Aurora-wired
    /// `Timer.publish` subscribes only in production. Keep this narrowly
    /// scoped to known test runners; raw debug launches outside a `.app`
    /// bundle should still behave like the app and keep the live clock.
    private static var isRunningUnderXCTest: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return true }
        if Bundle.main.bundlePath.hasSuffix(".xctest") { return true }
        let names = [
            ProcessInfo.processInfo.processName,
            URL(fileURLWithPath: CommandLine.arguments.first ?? "").lastPathComponent,
        ].map { $0.lowercased() }
        if names.contains(where: { name in
            name.contains("xctest")
                || name.contains("swiftpm-testing")
                || name.contains("swift-testing")
        }) { return true }
        return NSClassFromString("XCTestCase") != nil
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
        // The sidebar mutates only workspace collapse state, so keep
        // `workspaces` as a real projected binding and pass the active
        // session as a read-only snapshot. The controller owns active
        // selection because it is derived from `TabManager`.
        Design.AuroraSidebarView(
            workspaces: $controller.workspaces,
            activeSessionID: controller.activeSessionID,
            onTogglePalette: { controller.onTogglePalette?() },
            onCreateTab: { controller.onCreateTab?() },
            onActivateSession: { sessionID in
                if let tabID = controller.tabID(forSessionID: sessionID) {
                    controller.onActivateSession?(tabID)
                }
            },
            onCloseSession: { sessionID in
                if let tabID = controller.tabID(forSessionID: sessionID) {
                    controller.onCloseSession?(tabID)
                }
            },
            onTogglePinSession: { sessionID in
                if let tabID = controller.tabID(forSessionID: sessionID) {
                    controller.onTogglePinSession?(tabID)
                }
            },
            onCloseOtherSessions: { sessionID in
                if let tabID = controller.tabID(forSessionID: sessionID) {
                    controller.onCloseOtherSessions?(tabID)
                }
            },
            onMoveSessionUp: { sessionID in
                if let tabID = controller.tabID(forSessionID: sessionID) {
                    controller.onMoveSessionUp?(tabID)
                }
            },
            onMoveSessionDown: { sessionID in
                if let tabID = controller.tabID(forSessionID: sessionID) {
                    controller.onMoveSessionDown?(tabID)
                }
            },
            onToggleNotifications: controller.onToggleNotifications.map { handler in
                { handler() }
            },
            onHoverSession: { snapshot in
                controller.sidebarTooltip = snapshot
            },
            paletteShortcutLabel: controller.paletteShortcutLabel,
            newTabShortcutLabel: controller.newTabShortcutLabel
        )
        .designThemePalette(Design.palette(for: controller.themeIdentity))
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
            onReplay: { /* Reserved for a future timeline replay hook. */ },
            onCopyPort: { port in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(port.localhostURLString, forType: .string)
            },
            onOpenPort: { port in
                guard let url = URL(string: port.localhostURLString) else { return }
                NSWorkspace.shared.open(url)
            }
        )
        .designThemePalette(Design.palette(for: controller.themeIdentity))
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
        .designThemePalette(Design.palette(for: controller.themeIdentity))
    }
}

struct AuroraSidebarTooltipHost: View {

    @ObservedObject var controller: AuroraChromeController

    var body: some View {
        GeometryReader { proxy in
            if let tooltip = controller.sidebarTooltip {
                let placement = placement(
                    for: tooltip,
                    sidebarFrame: controller.sidebarTooltipSidebarFrameInOverlay,
                    containerSize: proxy.size
                )
                Design.AuroraSessionTooltipCard(
                    session: tooltip.session,
                    workspaceName: tooltip.workspaceName,
                    workspaceBranch: tooltip.workspaceBranch
                )
                .frame(width: placement.width)
                .allowsHitTesting(false)
                .position(x: placement.x, y: placement.y)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .leading)))
            }
        }
        .allowsHitTesting(false)
        .designThemePalette(Design.palette(for: controller.themeIdentity))
    }

    private func placement(
        for tooltip: Design.AuroraSidebarTooltipSnapshot,
        sidebarFrame: CGRect,
        containerSize: CGSize
    ) -> (x: CGFloat, y: CGFloat, width: CGFloat) {
        let rightSpace = max(0, containerSize.width - sidebarFrame.maxX - 18)
        let width = min(360, max(260, rightSpace - 18))
        let x = min(
            containerSize.width - width * 0.5 - 12,
            sidebarFrame.maxX + 18 + width * 0.5
        )
        let sidebarTopY = max(0, containerSize.height - sidebarFrame.maxY)
        let rawY = sidebarTopY + tooltip.rowFrame.midY
        let approximateHalfHeight: CGFloat = 158
        let y = min(
            max(rawY, approximateHalfHeight + 12),
            max(approximateHalfHeight + 12, containerSize.height - approximateHalfHeight - 12)
        )
        return (x, y, width)
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

/// Window-overlay host for hover inspectors. Returning `nil` from
/// `hitTest` means terminal clicks, sidebar clicks and context menus pass
/// through exactly as if the tooltip layer did not exist.
final class AuroraPassthroughHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
