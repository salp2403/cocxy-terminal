// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+MobileMirror.swift - App lifecycle and menu wiring for phone pairing.

import AppKit

extension AppDelegate {
    func setupMobileMirror() {
        guard mobileMirrorCoordinator == nil,
              let sessionRegistry,
              let remoteConnectionManager,
              let remoteProfileStore,
              let tunnelManager,
              let relayManager else { return }
        let tunnelController = MobileMirrorSSHTunnelController(
            connectionManager: remoteConnectionManager,
            profileStore: remoteProfileStore,
            tunnelManager: tunnelManager
        )
        mobileMirrorCoordinator = MobileMirrorCoordinator(
            appDelegate: self,
            projectRegistry: projectRegistry,
            projectResolver: projectResolver,
            titleStore: auroraWorkspaceTitleStore,
            sessionRegistry: sessionRegistry,
            approvalRegistry: mobileMirrorApprovalRegistry,
            auditLog: relayAuditLog,
            relayManager: relayManager,
            tunnelController: tunnelController
        )
    }

    @objc func showMobileMirrorAction(_ sender: Any?) {
        setupMobileMirror()
        guard let coordinator = mobileMirrorCoordinator else {
            presentMobileMirrorUnavailableAlert()
            return
        }
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

    func updateMobileMirrorLocalization(_ localizer: AppLocalizer) {
        mobileMirrorWindowController?.updateLocalizer(localizer)
        mobileMirrorCoordinator?.updateLocalization(localizer)
    }

    private func presentMobileMirrorUnavailableAlert() {
        NSSound.beep()
        let localizer = appLocalizer()
        let alert = NSAlert()
        alert.messageText = localizer.string(
            "mobile.mirror.title",
            fallback: "Pair Phone"
        )
        alert.informativeText = localizer.string(
            "mobile.web.status.unavailable",
            fallback: "Mobile pairing is unavailable."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: localizer.string("common.ok", fallback: "OK"))
        if let window = focusedWindowController()?.window, window.attachedSheet == nil {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
