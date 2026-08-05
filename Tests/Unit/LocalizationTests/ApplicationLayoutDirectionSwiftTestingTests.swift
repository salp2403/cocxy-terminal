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
        #expect(richInputPanel.identifier == ApplicationLayoutDirectionCoordinator.managedWindowIdentifier)
        #expect(richInputHost.userInterfaceLayoutDirection == .rightToLeft)
        #expect(renamePanel.identifier == ApplicationLayoutDirectionCoordinator.managedWindowIdentifier)
        #expect(renamePanel.contentView?.userInterfaceLayoutDirection == .rightToLeft)
        richInputPanel.close()
        renamePanel.close()
        parentWindow.close()
    }

    @Test("directional panel geometry uses fixed logical-edge coordinates")
    func directionalPanelGeometryUsesFixedOracles() {
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
        let root = NSView(frame: window.contentView?.bounds ?? .zero)
        root.addSubview(NSHostingView(rootView: Text("Direction")))
        window.contentView = root
        return window
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
