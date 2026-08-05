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
            windowProvider: { [existing] }
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
        let coordinator = ApplicationLayoutDirectionCoordinator(windowProvider: { [window] })

        coordinator.start(localizer: AppLocalizer(languagePreference: .arabic))

        #expect(window.contentView?.userInterfaceLayoutDirection == .rightToLeft)
        #expect(terminal.userInterfaceLayoutDirection == .leftToRight)
        coordinator.stop()
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
