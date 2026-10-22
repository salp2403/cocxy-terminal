// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MobileMirrorCoordinator+Projects.swift - Authorized mobile project creation.

import AppKit
import Foundation
import os.log

private let mobileMirrorProjectLogger = Logger(
    subsystem: "dev.cocxy.terminal",
    category: "MobileProject"
)

extension MobileMirrorCoordinator {
    func prepareProjectCreation(
        named rawName: String,
        identity: MobileMirrorClientIdentity,
        cookie: String,
        channelID: UUID
    ) throws -> @MainActor () async throws -> Void {
        guard let root = projectCreationRootHandle else {
            throw MobileMirrorError.projectCreationUnavailable
        }
        let name = try MobileMirrorProjectService.normalizedProjectName(rawName)
        return { [weak self] in
            guard let self else { throw MobileMirrorError.projectCreationUnavailable }
            try await self.createProject(
                named: name,
                identity: identity,
                cookie: cookie,
                channelID: channelID,
                root: root
            )
        }
    }

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
        identity: MobileMirrorClientIdentity,
        cookie: String,
        channelID: UUID,
        root: ProjectDirectoryRoot
    ) async throws {
        try requireActivePairing(cookie: cookie, channelID: channelID, identity: identity)
        try Task.checkCancellation()
        guard await projectCreationConfirmation(name, identity) else {
            try Task.checkCancellation()
            throw MobileMirrorError.authorizationDenied
        }
        try Task.checkCancellation()
        let publication = try await projectService.createProject(named: name, in: root)
        var activatedTab: (delegate: AppDelegate, id: TabID)?
        do {
            try requireActivePairing(cookie: cookie, channelID: channelID, identity: identity)
            try Task.checkCancellation()
            guard let appDelegate else {
                throw MobileMirrorError.projectCreationUnavailable
            }
            let verifiedDirectory = try publication.openVerifiedDirectory()
            let destination = try publication.verifiedURL(for: verifiedDirectory)
            projectResolver.invalidate(directory: destination)
            let descriptor = try ProjectDescriptor.verifiedStandalone(verifiedDirectory)
            guard try publication.verifiedURL(for: verifiedDirectory) == destination else {
                throw MobileMirrorError.projectCreationFailed(
                    "the destination changed before registration"
                )
            }
            let tabID = try appDelegate.activateProject(
                descriptor.groupingID,
                verifiedDirectory: verifiedDirectory
            )
            activatedTab = (appDelegate, tabID)
            guard try publication.verifiedURL(for: verifiedDirectory) == destination else {
                throw MobileMirrorError.projectCreationFailed(
                    "the destination changed during activation"
                )
            }
            try projectRegistry.recordOpen(descriptor, incrementOpenCount: false)
            appDelegate.windowEventBus?.broadcast(.custom(name: "project.changed", payload: [:]))
        } catch let originalError {
            if let activatedTab {
                activatedTab.delegate.controllerContainingTab(activatedTab.id)?
                    .performCloseTab(activatedTab.id)
            }
            do {
                try publication.rollback()
            } catch {
                mobileMirrorProjectLogger.error(
                    "Mobile project rollback failed: \(String(describing: error), privacy: .private)"
                )
            }
            throw originalError
        }
    }

    private func requireActivePairing(
        cookie: String,
        channelID: UUID,
        identity: MobileMirrorClientIdentity
    ) throws {
        guard let active = authority.activePairing(cookie: cookie),
              active.channelID == channelID,
              active.identity.fingerprint == identity.fingerprint else {
            throw MobileMirrorError.sessionExpired
        }
    }

}

@MainActor
enum MobileMirrorProjectConfirmationPresenter {
    static func confirm(
        named name: String,
        identity: MobileMirrorClientIdentity,
        appDelegate: AppDelegate?
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
        let resolution = MobileMirrorProjectConfirmationResolution()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard resolution.install(continuation) else { return }
                alert.beginSheetModal(for: window) { response in
                    resolution.resolve(response == .alertFirstButtonReturn)
                }
            }
        } onCancel: {
            resolution.resolve(false)
            Task { @MainActor in
                if window.attachedSheet === alert.window {
                    window.endSheet(alert.window, returnCode: .cancel)
                }
            }
        }
    }
}

private final class MobileMirrorProjectConfirmationResolution: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var result: Bool?

    func install(_ continuation: CheckedContinuation<Bool, Never>) -> Bool {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(returning: result)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func resolve(_ result: Bool) {
        let continuation: CheckedContinuation<Bool, Never>?
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}
