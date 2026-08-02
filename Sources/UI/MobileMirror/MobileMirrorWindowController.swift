// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorWindowController.swift - Retained native pairing panel.

import AppKit
import SwiftUI

@MainActor
final class MobileMirrorWindowController: NSWindowController, NSWindowDelegate {
    init(coordinator: MobileMirrorCoordinator, localizer: AppLocalizer) {
        let view = MobileMirrorView(coordinator: coordinator, localizer: localizer)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.title = localizer.string("mobile.mirror.title", fallback: "Pair Phone")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.minSize = NSSize(width: 480, height: 540)
        window.setContentSize(NSSize(width: 520, height: 650))
        window.center()
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("MobileMirrorWindow")
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }
}
