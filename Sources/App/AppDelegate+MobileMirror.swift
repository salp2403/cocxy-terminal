// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+MobileMirror.swift - App lifecycle and menu wiring for phone pairing.

import AppKit

extension AppDelegate {
    func setupMobileMirror() {
        guard mobileMirrorCoordinator == nil, let sessionRegistry else { return }
        mobileMirrorCoordinator = MobileMirrorCoordinator(
            appDelegate: self,
            projectRegistry: projectRegistry,
            projectResolver: projectResolver,
            titleStore: auroraWorkspaceTitleStore,
            sessionRegistry: sessionRegistry,
            auditLog: relayAuditLog
        )
    }

    @objc func showMobileMirrorAction(_ sender: Any?) {
        setupMobileMirror()
        guard let coordinator = mobileMirrorCoordinator else { return }
        if mobileMirrorWindowController == nil {
            mobileMirrorWindowController = MobileMirrorWindowController(
                coordinator: coordinator,
                localizer: appLocalizer()
            )
        }
        mobileMirrorWindowController?.showWindow(sender)
        mobileMirrorWindowController?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    func shutdownMobileMirror() {
        mobileMirrorCoordinator?.shutdown()
        mobileMirrorWindowController?.close()
        mobileMirrorWindowController = nil
        mobileMirrorCoordinator = nil
    }
}
