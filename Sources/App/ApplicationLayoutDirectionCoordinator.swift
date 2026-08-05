// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ApplicationLayoutDirectionCoordinator.swift - App-wide shell direction.

import AppKit

@MainActor
final class ApplicationLayoutDirectionCoordinator: NSObject {
    private let notificationCenter: NotificationCenter
    private let windowProvider: @MainActor () -> [NSWindow]
    private var isObservingWindows = false
    private(set) var direction: NSUserInterfaceLayoutDirection = .leftToRight

    init(
        notificationCenter: NotificationCenter = .default,
        windowProvider: @escaping @MainActor () -> [NSWindow] = { NSApp.windows }
    ) {
        self.notificationCenter = notificationCenter
        self.windowProvider = windowProvider
        super.init()
    }

    func start(localizer: AppLocalizer) {
        update(localizer: localizer)
        guard !isObservingWindows else { return }
        notificationCenter.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        isObservingWindows = true
    }

    func update(localizer: AppLocalizer) {
        direction = Self.resolvedDirection(for: localizer)
        windowProvider().forEach(apply)
    }

    func apply(to window: NSWindow) {
        guard let contentView = window.contentView else { return }
        apply(direction, to: contentView)
    }

    func stop() {
        guard isObservingWindows else { return }
        notificationCenter.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        isObservingWindows = false
    }

    static func resolvedDirection(for localizer: AppLocalizer) -> NSUserInterfaceLayoutDirection {
        localizer.isRightToLeft ? .rightToLeft : .leftToRight
    }

    private func apply(_ direction: NSUserInterfaceLayoutDirection, to view: NSView) {
        guard !(view is any TerminalHostingView) else {
            view.userInterfaceLayoutDirection = .leftToRight
            return
        }
        view.userInterfaceLayoutDirection = direction
        view.subviews.forEach { apply(direction, to: $0) }
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        apply(to: window)
    }
}
