// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import SwiftUI
import Testing
@testable import CocxyTerminal

@Suite("Application layout direction", .serialized)
@MainActor
struct ApplicationLayoutDirectionSwiftTestingTests {
    @Test("Arabic direction reaches existing and newly visible AppKit and SwiftUI roots")
    func arabicDirectionPropagatesAcrossWindowRoots() {
        let notificationCenter = NotificationCenter()
        let existing = makeWindow()
        let coordinator = ApplicationLayoutDirectionCoordinator(
            notificationCenter: notificationCenter,
            windowProvider: { [existing] },
            isManagedWindow: { _ in true }
        )

        coordinator.start(localizer: AppLocalizer(languagePreference: .arabic))

        #expect(existing.contentView?.userInterfaceLayoutDirection == .rightToLeft)
        #expect(existing.contentView?.subviews.first?.userInterfaceLayoutDirection == .rightToLeft)

        let later = makeWindow()
        notificationCenter.post(name: NSWindow.didBecomeKeyNotification, object: later)
        #expect(later.contentView?.userInterfaceLayoutDirection == .rightToLeft)

        coordinator.update(localizer: AppLocalizer(languagePreference: .english))
        #expect(existing.contentView?.userInterfaceLayoutDirection == .leftToRight)
        coordinator.stop()
    }

    @Test("terminal rendering remains left to right inside an RTL shell")
    func terminalRenderingStaysLeftToRight() {
        let terminal = TerminalHostViewFactory.make(
            viewModel: TerminalViewModel(engine: MockTerminalEngine()),
            engine: MockTerminalEngine(),
            localizer: AppLocalizer(languagePreference: .arabic)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(terminal)
        let coordinator = ApplicationLayoutDirectionCoordinator(
            windowProvider: { [window] },
            isManagedWindow: { _ in true }
        )

        coordinator.start(localizer: AppLocalizer(languagePreference: .arabic))

        #expect(window.contentView?.userInterfaceLayoutDirection == .rightToLeft)
        #expect(terminal.userInterfaceLayoutDirection == .leftToRight)
        coordinator.stop()
    }

    @Test("unchanged direction skips sweeps and unmanaged windows stay untouched")
    func unchangedDirectionAndUnmanagedWindowsAreExcluded() {
        let managed = makeWindow()
        let external = makeWindow()
        var providerCalls = 0
        let coordinator = ApplicationLayoutDirectionCoordinator(
            windowProvider: {
                providerCalls += 1
                return [managed, external]
            },
            isManagedWindow: { $0 === managed }
        )

        coordinator.start(localizer: AppLocalizer(languagePreference: .arabic))
        coordinator.update(localizer: AppLocalizer(languagePreference: .arabic))

        #expect(providerCalls == 1)
        #expect(managed.contentView?.userInterfaceLayoutDirection == .rightToLeft)
        #expect(external.contentView?.userInterfaceLayoutDirection == .leftToRight)
        coordinator.stop()
    }

    @Test("default window policy includes Cocxy controllers and excludes external windows")
    func defaultWindowPolicyUsesApplicationOwnership() {
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let ownedSheet = makeWindow()
        let originalIdentifier = NSUserInterfaceItemIdentifier("owned-sheet")
        ownedSheet.identifier = originalIdentifier
        ApplicationLayoutDirectionCoordinator.markAsApplicationManaged(ownedSheet)
        let external = makeWindow()
        let coordinator = ApplicationLayoutDirectionCoordinator(
            windowProvider: { [weak controller] in
                [controller?.window, ownedSheet, external].compactMap { $0 }
            }
        )

        coordinator.start(localizer: AppLocalizer(languagePreference: .arabic))

        #expect(controller.window?.contentView?.userInterfaceLayoutDirection == .rightToLeft)
        #expect(ownedSheet.contentView?.userInterfaceLayoutDirection == .rightToLeft)
        #expect(ownedSheet.identifier == originalIdentifier)
        #expect(ApplicationLayoutDirectionCoordinator.isApplicationManagedWindow(ownedSheet))
        #expect(external.contentView?.userInterfaceLayoutDirection == .leftToRight)
        coordinator.stop()
        controller.close()
    }

    @Test("AppKit direction reaches the hosted SwiftUI environment")
    func swiftUIEnvironmentReceivesStampedDirection() {
        let recorder = LayoutDirectionRecorder()
        let hostingView = NSHostingView(rootView: LayoutDirectionProbe { direction in
            recorder.direction = direction
        })
        hostingView.frame = NSRect(x: 0, y: 0, width: 120, height: 80)

        ApplicationLayoutDirectionCoordinator.apply(.rightToLeft, to: hostingView)
        _ = hostingView.fittingSize
        hostingView.layoutSubtreeIfNeeded()

        #expect(hostingView.userInterfaceLayoutDirection == .rightToLeft)
        #expect(recorder.direction == .rightToLeft)
    }

    @Test("a trailing panel created after an Arabic sweep opens on the left")
    func newlyCreatedPanelUsesCurrentLogicalEdge() throws {
        let provider = LayoutDirectionConfigProvider(language: .english)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: service
        )
        controller.showWindow(nil)
        controller.window?.setContentSize(NSSize(width: 1_000, height: 700))
        let coordinator = ApplicationLayoutDirectionCoordinator(
            windowProvider: { [weak controller] in controller?.window.map { [$0] } ?? [] },
            isManagedWindow: { _ in true }
        )
        coordinator.start(localizer: AppLocalizer(languagePreference: .english))

        provider.language = .arabic
        try service.reload()
        coordinator.update(localizer: AppLocalizer(languagePreference: .arabic))
        controller.applyConfig(service.current)
        controller.showDashboardPanel()

        let panel = try #require(controller.dashboardHostingView)
        #expect(panel.frame.minX == 0)
        #expect(panel.autoresizingMask.contains(.maxXMargin))
        #expect(!panel.autoresizingMask.contains(.minXMargin))
        #expect(panel.userInterfaceLayoutDirection == .rightToLeft)
        coordinator.stop()
        controller.close()
    }

    @Test("native surfaces created after an Arabic sweep inherit RTL")
    func dynamicallyCreatedNativeSurfacesUseLocalizedDirection() {
        let localizer = AppLocalizer(languagePreference: .arabic)
        let tabItem = TabItemView(
            displayItem: TabDisplayItem(
                id: TabID(),
                displayTitle: "Terminal",
                subtitle: nil,
                statusColorName: "gray",
                badgeText: nil,
                isActive: false,
                hasUnreadNotification: false,
                agentState: .idle
            ),
            localizer: localizer
        )
        let richInputHost = FocusableHostingView(rootView: RichInputComposerView(
            viewModel: RichInputComposerViewModel(),
            localizer: localizer,
            panelWidth: 320
        ))
        let richInputPanel = RichInputPanel(
            hostedView: richInputHost,
            frame: NSRect(x: 0, y: 0, width: 320, height: 220),
            localizer: localizer
        )
        let parentWindow = makeWindow()
        let renamePanel = RenameSheetController.present(
            on: parentWindow,
            currentName: "Terminal",
            localizer: localizer,
            onComplete: { _ in }
        )

        #expect(tabItem.userInterfaceLayoutDirection == .rightToLeft)
        #expect(ApplicationLayoutDirectionCoordinator.isApplicationManagedWindow(richInputPanel))
        #expect(richInputHost.userInterfaceLayoutDirection == .rightToLeft)
        #expect(ApplicationLayoutDirectionCoordinator.isApplicationManagedWindow(renamePanel))
        #expect(renamePanel.contentView?.userInterfaceLayoutDirection == .rightToLeft)
        richInputPanel.close()
        renamePanel.close()
        parentWindow.close()
    }

    @Test("late-created shell surface trees follow Arabic and LTR changes")
    func lateCreatedShellSurfaceTreesFollowCurrentDirection() throws {
        let provider = LayoutDirectionConfigProvider(language: .english)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: service
        )
        controller.showWindow(nil)
        let coordinator = ApplicationLayoutDirectionCoordinator(
            windowProvider: { [weak controller] in controller?.window.map { [$0] } ?? [] },
            isManagedWindow: { _ in true }
        )
        coordinator.start(localizer: AppLocalizer(languagePreference: .english))
        defer {
            coordinator.stop()
            controller.close()
        }

        try applyLanguage(
            .arabic,
            provider: provider,
            service: service,
            controller: controller,
            coordinator: coordinator
        )
        try expectLateCreatedSurfaceTrees(
            direction: .rightToLeft,
            controller: controller
        )

        try applyLanguage(
            .english,
            provider: provider,
            service: service,
            controller: controller,
            coordinator: coordinator
        )
        controller.dismissCommandPalette()
        controller.dismissSmartRouting()
        try expectLateCreatedSurfaceTrees(
            direction: .leftToRight,
            controller: controller
        )
    }

    @Test("tab item restamps dynamic children after every update")
    func tabItemRestampsRebuiltChildren() {
        var initialItem = makeActiveTabDisplayItem(title: "Initial")
        initialItem.agentToolCount = 1
        initialItem.perSurfaceAgents = [
            SurfaceAgentSnapshot(
                surfaceID: SurfaceID(),
                state: SurfaceAgentState(agentState: .working)
            ),
        ]
        let tabItem = TabItemView(
            displayItem: initialItem,
            localizer: AppLocalizer(languagePreference: .arabic)
        )
        expectDirection(.rightToLeft, in: tabItem, label: "initial Arabic tab item")
        expectMiniPillGeometry(.rightToLeft, in: tabItem)
        expectAccentStripGeometry(.rightToLeft, in: tabItem)
        let initialViewIDs = Set(viewTree(rootedAt: tabItem).map(ObjectIdentifier.init))

        var updatedItem = makeActiveTabDisplayItem(title: "Updated")
        updatedItem.agentToolCount = 2
        updatedItem.agentErrorCount = 1
        updatedItem.agentDurationText = "2m"
        updatedItem.perSurfaceAgents = [
            SurfaceAgentSnapshot(
                surfaceID: SurfaceID(),
                state: SurfaceAgentState(agentState: .waitingInput),
                isFocused: true
            ),
            SurfaceAgentSnapshot(
                surfaceID: SurfaceID(),
                state: SurfaceAgentState(agentState: .working)
            ),
        ]
        tabItem.update(with: updatedItem)

        let updatedTree = viewTree(rootedAt: tabItem)
        #expect(!Set(updatedTree.map(ObjectIdentifier.init)).subtracting(initialViewIDs).isEmpty)
        expectDirection(.rightToLeft, in: tabItem, label: "updated Arabic tab item")
        expectMiniPillGeometry(.rightToLeft, in: tabItem)

        tabItem.updateLocalizer(AppLocalizer(languagePreference: .english))
        tabItem.update(with: initialItem)
        expectDirection(.leftToRight, in: tabItem, label: "updated LTR tab item")
        expectMiniPillGeometry(.leftToRight, in: tabItem)
        expectAccentStripGeometry(.leftToRight, in: tabItem)
    }

    @Test("directional panel geometry uses fixed logical-edge coordinates")
    func directionalPanelGeometryUsesFixedOracles() {
        let paneFrame = NSRect(x: 100, y: 0, width: 600, height: 500)
        #expect(DirectionalPanelGeometry.paneTrailingOrigin(
            paneFrame: paneFrame,
            panelWidth: 280,
            direction: .leftToRight
        ) == 404)
        #expect(DirectionalPanelGeometry.paneTrailingOrigin(
            paneFrame: paneFrame,
            panelWidth: 280,
            direction: .rightToLeft
        ) == 116)
        #expect(DirectionalPanelGeometry.logicalLeadingOrigin(
            containerWidth: 1_000,
            panelWidth: 200,
            inset: 18,
            direction: .rightToLeft
        ) == 782)
        #expect(DirectionalPanelGeometry.trailingOrigin(
            containerWidth: 1_000,
            panelWidth: 320,
            direction: .leftToRight
        ) == 680)
        #expect(DirectionalPanelGeometry.trailingOrigin(
            containerWidth: 1_000,
            panelWidth: 320,
            occupiedWidth: 320,
            direction: .rightToLeft
        ) == 320)
        #expect(DirectionalPanelGeometry.trailingExitOrigin(
            containerWidth: 1_000,
            panelWidth: 320,
            direction: .rightToLeft
        ) == -320)

        let rtlVisible = DirectionalPanelGeometry.terminalVisibleFrame(
            terminalBounds: NSRect(x: 0, y: 0, width: 1_000, height: 700),
            terminalFrameInOverlay: NSRect(x: 0, y: 0, width: 1_000, height: 700),
            overlayWidth: 1_000,
            dockedWidth: 320,
            direction: .rightToLeft
        )
        #expect(rtlVisible == NSRect(x: 320, y: 0, width: 680, height: 700))
    }

    @Test("AppDelegate config sink applies a changed application language")
    func appDelegateLanguageSinkUpdatesDirection() async throws {
        let previousMenu = NSApp.mainMenu
        let provider = LayoutDirectionConfigProvider(language: .english)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        let delegate = AppDelegate()
        delegate.installConfigServiceForTesting(service)
        delegate.applicationLayoutDirectionCoordinator.start(
            localizer: AppLocalizer(languagePreference: .english)
        )
        delegate.startMenuKeybindingsObserver()
        defer {
            delegate.applicationLayoutDirectionCoordinator.stop()
            NSApp.mainMenu = previousMenu
        }

        provider.language = .arabic
        try service.reload()
        for _ in 0..<20 {
            if delegate.applicationLayoutDirectionCoordinator.direction == .rightToLeft { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(delegate.applicationLayoutDirectionCoordinator.direction == .rightToLeft)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        // A standalone window releases itself on close() by default, which
        // under ARC over-releases it and crashes the process later.
        window.isReleasedWhenClosed = false
        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        root.addSubview(NSHostingView(rootView: Text("Direction")))
        window.contentView = root
        return window
    }

    private func applyLanguage(
        _ language: AppLanguage,
        provider: LayoutDirectionConfigProvider,
        service: ConfigService,
        controller: MainWindowController,
        coordinator: ApplicationLayoutDirectionCoordinator
    ) throws {
        provider.language = language
        try service.reload()
        let localizer = AppLocalizer(languagePreference: language)
        coordinator.update(localizer: localizer)
        controller.applyConfig(service.current)
    }

    private func expectLateCreatedSurfaceTrees(
        direction: NSUserInterfaceLayoutDirection,
        controller: MainWindowController
    ) throws {
        controller.showTransientCommandPaletteOverlay(
            engine: StaticCommandPaletteEngine(actions: [])
        )
        let palette = try #require(controller.commandPaletteHostingView)
        expectDirection(direction, in: palette, label: "unified quick switch")

        controller.showSmartRouting()
        let smartRouting = try #require(controller.smartRoutingHostingView)
        expectDirection(direction, in: smartRouting, label: "smart routing")

        controller.tabBarView?.frame.size.width = 360
        controller.refreshShortcutHintsOverlay(
            config: UXPolishConfig(
                alwaysShowShortcutHints: true,
                shortcutHintDebugOverlay: true,
                shortcutHintOffsetX: 0,
                shortcutHintOffsetY: 0,
                shortcutHintScale: 1
            ),
            keybindings: .defaults
        )
        #expect(!controller.shortcutHintOverlayHosts.isEmpty)
        for (placement, host) in controller.shortcutHintOverlayHosts {
            expectDirection(direction, in: host, label: "shortcut hint \(placement)")
        }
        let overlay = try #require(controller.overlayContainerView)
        let debugFrame = try #require(controller.shortcutHintOverlayHosts[.debug]).frame
        if direction == .rightToLeft {
            #expect(debugFrame.maxX == overlay.bounds.width - 18)
        } else {
            #expect(debugFrame.minX == 18)
        }
        let sidebarHost = try #require(controller.shortcutHintOverlayHosts[.sidebar])
        let sidebarFrame = controller.tabBarView.map { $0.convert($0.bounds, to: overlay) }
            ?? overlay.bounds
        let sidebarInset: CGFloat = controller.tabBarView == nil ? 14 : 12
        if direction == .rightToLeft {
            #expect(sidebarFrame.maxX - sidebarHost.frame.maxX == sidebarInset)
        } else {
            #expect(sidebarHost.frame.minX - sidebarFrame.minX == sidebarInset)
        }
        let paneHost = try #require(controller.shortcutHintOverlayHosts[.pane])
        let paneAnchor = controller.focusedPaneView()
            ?? controller.terminalSurfaceView
            ?? controller.terminalContainerView
            ?? overlay
        let paneFrame = paneAnchor.convert(paneAnchor.bounds, to: overlay)
        let paneWidth = min(280, max(120, paneFrame.width - 24))
        let expectedPaneX = direction == .rightToLeft
            ? min(paneFrame.maxX - paneWidth - 12, paneFrame.minX + 16)
            : max(paneFrame.minX + 12, paneFrame.maxX - paneWidth - 16)
        #expect(paneHost.frame.minX == expectedPaneX)

        let firstPane = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 240))
        firstPane.addSubview(NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40)))
        let secondPane = NSView(frame: NSRect(x: 200, y: 0, width: 200, height: 240))
        secondPane.addSubview(NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40)))
        let splitView = controller.createSplitView(
            isVertical: true,
            frame: NSRect(x: 0, y: 0, width: 400, height: 240),
            first: firstPane,
            second: secondPane
        )
        expectDirection(direction, in: splitView, label: "split view")
    }

    private func expectDirection(
        _ expected: NSUserInterfaceLayoutDirection,
        in root: NSView,
        label: String
    ) {
        for view in viewTree(rootedAt: root) {
            #expect(
                view.userInterfaceLayoutDirection == expected,
                "\(label) contains a child with the wrong layout direction"
            )
        }
    }

    private func expectMiniPillGeometry(
        _ direction: NSUserInterfaceLayoutDirection,
        in root: NSView
    ) {
        let pill = viewTree(rootedAt: root).compactMap { $0 as? MiniAgentPillView }.first
        guard let pill else {
            Issue.record("Tab item did not contain a mini agent pill")
            return
        }
        pill.frame = NSRect(x: 0, y: 0, width: 30, height: 14)
        pill.userInterfaceLayoutDirection = direction
        pill.layoutSubtreeIfNeeded()
        pill.layout()
        guard let label = pill.subviews.compactMap({ $0 as? NSTextField }).first,
              let dot = pill.layer?.sublayers?.first(where: {
                  $0.frame.width == 6 && $0.frame.height == 6
              }) else {
            Issue.record("Mini agent pill did not expose its visual components")
            return
        }
        #expect(label.frame.width > 0)
        #expect(dot.frame.minX == (direction == .rightToLeft ? 19 : 5))
        #expect(!dot.frame.intersects(label.frame))
    }

    private func expectAccentStripGeometry(
        _ direction: NSUserInterfaceLayoutDirection,
        in tabItem: TabItemView
    ) {
        tabItem.frame = NSRect(x: 0, y: 0, width: 240, height: 56)
        tabItem.layout()
        guard let strip = tabItem.layer?.sublayers?.first(where: {
            $0.frame.height == 40 && [2, 5].contains($0.frame.width)
        }) else {
            Issue.record("Tab item did not expose its accent strip")
            return
        }
        if direction == .rightToLeft {
            #expect(strip.frame.maxX == tabItem.bounds.maxX)
        } else {
            #expect(strip.frame.minX == tabItem.bounds.minX)
        }
    }

    private func viewTree(rootedAt root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap(viewTree(rootedAt:))
    }

    private func makeActiveTabDisplayItem(title: String) -> TabDisplayItem {
        TabDisplayItem(
            id: TabID(),
            displayTitle: title,
            subtitle: nil,
            statusColorName: "blue",
            badgeText: nil,
            isActive: true,
            hasUnreadNotification: false,
            agentState: .working
        )
    }
}

@MainActor
private final class LayoutDirectionRecorder {
    var direction: LayoutDirection?
}

private struct LayoutDirectionProbe: NSViewRepresentable {
    let report: @MainActor (LayoutDirection) -> Void

    func makeNSView(context: Context) -> NSView {
        report(context.environment.layoutDirection)
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        report(context.environment.layoutDirection)
    }
}

private final class LayoutDirectionConfigProvider: ConfigFileProviding, @unchecked Sendable {
    var language: AppLanguage

    init(language: AppLanguage) {
        self.language = language
    }

    func readConfigFile() -> String? {
        """
        [appearance]
        app-language = "\(language.rawValue)"
        """
    }

    func writeConfigFile(_ content: String) throws {}
}
