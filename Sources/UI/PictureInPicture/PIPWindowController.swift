// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PIPWindowController.swift - Floating terminal Picture-in-Picture panel.

import AppKit

/// Owns a floating `NSPanel` that temporarily reparents one terminal
/// host view out of the main window.
///
/// The controller deliberately does not create or duplicate a PTY. It
/// moves the existing `NSView` into a panel and returns that same view
/// to the host on close, preserving renderer state, scrollback, focus
/// and input routing.
@MainActor
final class PIPWindowController: NSObject, NSWindowDelegate {
    let tabID: TabID
    let detachedView: NSView
    private let onRestore: (TabID, NSView) -> Void
    private(set) var didRestore = false

    init(tabID: TabID, title: String, detachedView: NSView, onRestore: @escaping (TabID, NSView) -> Void) {
        self.tabID = tabID
        self.detachedView = detachedView
        self.onRestore = onRestore

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.titleVisibility = .visible
        panel.contentView = NSView(frame: panel.contentRect(forFrameRect: panel.frame))

        super.init()

        panel.delegate = self
        if let screen = NSScreen.main {
            panel.setFrame(
                NSRect(
                    x: screen.visibleFrame.maxX - 760,
                    y: screen.visibleFrame.maxY - 460,
                    width: 720,
                    height: 420
                ),
                display: false
            )
        }
        panel.contentView?.addSubview(detachedView)
        detachedView.frame = panel.contentView?.bounds ?? panel.contentRect(forFrameRect: panel.frame)
        detachedView.autoresizingMask = [.width, .height]
        self.window = panel
    }

    private(set) var window: NSPanel?

    func show() {
        window?.makeKeyAndOrderFront(nil)
    }

    func restore() {
        guard !didRestore else { return }
        didRestore = true
        detachedView.removeFromSuperview()
        onRestore(tabID, detachedView)
    }

    func windowWillClose(_ notification: Notification) {
        restore()
    }
}
