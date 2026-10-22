// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ApplicationLayoutDirectionCoordinator.swift - App-wide shell direction.

import AppKit
import ObjectiveC

@MainActor
protocol ApplicationLayoutDirectionManagedWindowController: AnyObject {}

@MainActor
final class ApplicationLayoutDirectionCoordinator: NSObject {
    private static var managedWindowAssociationKey: UInt8 = 0

    private let notificationCenter: NotificationCenter
    private let windowProvider: @MainActor () -> [NSWindow]
    private let isManagedWindow: @MainActor (NSWindow) -> Bool
    private var isObservingWindows = false
    private var hasAppliedDirection = false
    private(set) var direction: NSUserInterfaceLayoutDirection = .leftToRight

    init(
        notificationCenter: NotificationCenter = .default,
        windowProvider: @escaping @MainActor () -> [NSWindow] = { NSApp.windows },
        isManagedWindow: @escaping @MainActor (NSWindow) -> Bool =
            ApplicationLayoutDirectionCoordinator.isApplicationManagedWindow
    ) {
        self.notificationCenter = notificationCenter
        self.windowProvider = windowProvider
        self.isManagedWindow = isManagedWindow
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
        let resolvedDirection = Self.resolvedDirection(for: localizer)
        guard !hasAppliedDirection || resolvedDirection != direction else { return }
        direction = resolvedDirection
        hasAppliedDirection = true
        windowProvider().filter(isManagedWindow).forEach(apply)
    }

    func apply(to window: NSWindow) {
        guard isManagedWindow(window) else { return }
        guard let contentView = window.contentView else { return }
        applyCurrentDirection(to: contentView)
    }

    func applyCurrentDirection(to view: NSView) {
        Self.apply(direction, to: view)
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

    static func markAsApplicationManaged(_ window: NSWindow) {
        objc_setAssociatedObject(
            window,
            &managedWindowAssociationKey,
            true,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
    }

    static func isApplicationManagedWindow(_ window: NSWindow) -> Bool {
        (objc_getAssociatedObject(window, &managedWindowAssociationKey) as? Bool == true)
            || window.windowController is any ApplicationLayoutDirectionManagedWindowController
    }

    static func apply(_ direction: NSUserInterfaceLayoutDirection, to view: NSView) {
        // Terminal cells retain their logical column order inside the mirrored app shell.
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

extension MainWindowController: ApplicationLayoutDirectionManagedWindowController {}
extension MobileMirrorWindowController: ApplicationLayoutDirectionManagedWindowController {}
extension CrashRecoveryOfferWindowController: ApplicationLayoutDirectionManagedWindowController {}

enum DirectionalPanelGeometry {
    static func paneTrailingOrigin(
        paneFrame: NSRect,
        panelWidth: CGFloat,
        direction: NSUserInterfaceLayoutDirection
    ) -> CGFloat {
        if direction == .rightToLeft {
            return min(paneFrame.maxX - panelWidth - 12, paneFrame.minX + 16)
        }
        return max(paneFrame.minX + 12, paneFrame.maxX - panelWidth - 16)
    }

    static func logicalLeadingOrigin(
        containerWidth: CGFloat,
        panelWidth: CGFloat,
        inset: CGFloat,
        direction: NSUserInterfaceLayoutDirection
    ) -> CGFloat {
        direction == .rightToLeft
            ? containerWidth - panelWidth - inset
            : inset
    }

    static func trailingOrigin(
        containerWidth: CGFloat,
        panelWidth: CGFloat,
        occupiedWidth: CGFloat = 0,
        direction: NSUserInterfaceLayoutDirection
    ) -> CGFloat {
        switch direction {
        case .rightToLeft:
            return occupiedWidth
        default:
            return containerWidth - occupiedWidth - panelWidth
        }
    }

    static func trailingExitOrigin(
        containerWidth: CGFloat,
        panelWidth: CGFloat,
        direction: NSUserInterfaceLayoutDirection
    ) -> CGFloat {
        direction == .rightToLeft ? -panelWidth : containerWidth
    }

    static func terminalVisibleFrame(
        terminalBounds: NSRect,
        terminalFrameInOverlay: NSRect,
        overlayWidth: CGFloat,
        dockedWidth: CGFloat,
        direction: NSUserInterfaceLayoutDirection
    ) -> NSRect {
        let dockedFrame: NSRect
        if direction == .rightToLeft {
            dockedFrame = NSRect(x: 0, y: 0, width: dockedWidth, height: 1)
        } else {
            dockedFrame = NSRect(
                x: overlayWidth - dockedWidth,
                y: 0,
                width: dockedWidth,
                height: 1
            )
        }
        let overlap = max(
            0,
            min(terminalFrameInOverlay.maxX, dockedFrame.maxX)
                - max(terminalFrameInOverlay.minX, dockedFrame.minX)
        )
        let reservedWidth = min(terminalBounds.width, overlap)
        return NSRect(
            x: direction == .rightToLeft ? reservedWidth : 0,
            y: 0,
            width: max(0, terminalBounds.width - reservedWidth),
            height: terminalBounds.height
        )
    }
}
