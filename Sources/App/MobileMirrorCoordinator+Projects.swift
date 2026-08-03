// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorCoordinator+Projects.swift - Authorized mobile project creation.

import AppKit
import Foundation

extension MobileMirrorCoordinator {
    func chooseProjectCreationRoot() {
        let panel = NSOpenPanel()
        let localizer = appDelegate?.appLocalizer()
            ?? AppLocalizer(languagePreference: .system)
        panel.title = localizer.string(
            "mobile.mirror.projectRoot.title",
            fallback: "Choose Project Creation Folder"
        )
        panel.prompt = localizer.string("common.choose", fallback: "Choose")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                do {
                    let root = try ProjectDirectoryRoot.open(url.standardizedFileURL)
                    self?.projectCreationRootHandle = root
                    self?.projectCreationRoot = try root.currentURL()
                    self?.refreshSnapshotAndPublish()
                } catch {
                    self?.projectCreationRootHandle = nil
                    self?.projectCreationRoot = nil
                    self?.refreshSnapshotAndPublish()
                    NSSound.beep()
                }
            }
        }
    }

    func createProject(
        named name: String,
        identity: MobileMirrorClientIdentity
    ) async throws {
        guard let root = projectCreationRootHandle else {
            throw MobileMirrorError.projectCreationUnavailable
        }
        guard await confirmProjectCreation(named: name, identity: identity) else {
            throw MobileMirrorError.authorizationDenied
        }
        let publication = try await projectService.createProject(named: name, in: root)
        let destination = try publication.verifiedURL()
        projectResolver.invalidate(directory: destination)
        let descriptor = projectResolver.resolveProject(for: destination)
        guard try publication.verifiedURL() == destination else {
            throw MobileMirrorError.projectCreationFailed(
                "the destination changed before registration"
            )
        }
        try projectRegistry.recordOpen(descriptor, incrementOpenCount: false)
        _ = try appDelegate?.activateProject(descriptor.groupingID)
        appDelegate?.windowEventBus?.broadcast(.custom(name: "project.changed", payload: [:]))
    }

    private func confirmProjectCreation(
        named name: String,
        identity: MobileMirrorClientIdentity
    ) async -> Bool {
        guard let appDelegate,
              let window = appDelegate.mobileMirrorWindowController?.window,
              window.attachedSheet == nil else {
            return false
        }
        window.makeKeyAndOrderFront(nil)
        let localizer = appDelegate.appLocalizer()
        let alert = NSAlert()
        alert.messageText = localizer.string(
            "mobile.mirror.projectConfirm.title",
            fallback: "Create Project from Phone?"
        )
        alert.informativeText = String(
            format: localizer.string(
                "mobile.mirror.projectConfirm.message",
                fallback: "Create %@ for the paired device at %@?"
            ),
            name,
            identity.remoteAddress
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: localizer.string("common.create", fallback: "Create"))
        alert.addButton(withTitle: localizer.string("common.cancel", fallback: "Cancel"))
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .alertFirstButtonReturn)
            }
        }
    }
}
