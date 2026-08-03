// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+Projects.swift - App-wide project change propagation.

import AppKit
import Combine

enum ProjectActivationError: Error, LocalizedError {
    case unavailable(String)
    case noWindow
    case projectHomeUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable(let path):
            return "The project folder is unavailable: \(path)"
        case .noWindow:
            return "Cocxy could not create a window for this project."
        case .projectHomeUnavailable:
            return "Cocxy could not open Project Home in a readable pane."
        }
    }
}

extension NSUserInterfaceItemIdentifier {
    static let projectOpenRecentMenu = NSUserInterfaceItemIdentifier(
        "dev.cocxy.menu.project-open-recent"
    )
}

extension AppDelegate {
    func startProjectChangeBroadcasting() {
        projectRegistryChangeCancellable?.cancel()
        var changes: [AnyPublisher<Void, Never>] = [
            projectRegistry.recordsDidChange.map { _ in () }.eraseToAnyPublisher(),
            auroraWorkspaceTitleStore.$revision.dropFirst().map { _ in () }.eraseToAnyPublisher(),
        ]
        if let sessionRegistry {
            changes.append(sessionRegistry.sessionAdded.map { _ in () }.eraseToAnyPublisher())
            changes.append(sessionRegistry.sessionRemoved.map { _ in () }.eraseToAnyPublisher())
            changes.append(sessionRegistry.sessionUpdated.compactMap { event -> Void? in
                guard case .workingDirectoryChanged = event.change else { return nil }
                return ()
            }.eraseToAnyPublisher())
        }
        projectRegistryChangeCancellable = Publishers.MergeMany(changes)
            .sink { [weak self] in
                self?.windowEventBus?.broadcast(
                    .custom(name: "project.changed", payload: [:])
                )
            }
    }

    func liveProjectIDs() -> Set<String> {
        guard let sessionRegistry else { return [] }
        return Set(sessionRegistry.allSessions.map {
            projectResolver.resolveProject(for: $0.workingDirectory).groupingID.rawValue
        })
    }

    func setProjectAlias(
        _ title: String?,
        for projectID: ProjectID,
        requestedDirectory: URL? = nil
    ) {
        let directories = allWindowControllers.flatMap { controller in
            controller.tabManager.tabs.map(\.workingDirectory)
        }
        let legacyIdentities = ProjectAliasMigrationPlanner.legacyIdentities(
            for: projectID,
            directories: directories,
            requestedDirectory: requestedDirectory,
            projectResolver: projectResolver
        )
        auroraWorkspaceTitleStore.setTitle(
            title,
            for: projectID.rawValue,
            migrating: legacyIdentities
        )
    }

    @discardableResult
    func activateProject(_ projectID: ProjectID) throws -> TabID {
        let rootURL = URL(fileURLWithPath: projectID.rawValue, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ProjectActivationError.unavailable(rootURL.path)
        }

        let focused = focusedWindowController()
        let controllers = ([focused].compactMap { $0 } + allWindowControllers)
            .reduce(into: [MainWindowController]()) { result, controller in
                if !result.contains(where: { $0 === controller }) {
                    result.append(controller)
                }
            }
        for controller in controllers {
            let activeTabID = controller.tabManager.activeTabID
            let tabs = controller.tabManager.tabs.sorted { lhs, rhs in
                (lhs.id == activeTabID ? 0 : 1) < (rhs.id == activeTabID ? 0 : 1)
            }
            if let tab = tabs.first(where: {
                projectResolver.resolveProject(for: $0.workingDirectory).groupingID == projectID
            }) {
                if let windowTabRouter {
                    windowTabRouter.activateTab(id: tab.id)
                } else {
                    controller.tabManager.setActive(id: tab.id)
                    controller.window?.makeKeyAndOrderFront(nil)
                }
                return tab.id
            }
        }

        if let controller = focused ?? windowController {
            let tabID = controller.createTab(workingDirectory: rootURL)
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
            return tabID
        }

        guard let controller = makeWindowController(registerInitialSession: false),
              let tabID = controller.tabManager.activeTabID else {
            throw ProjectActivationError.noWindow
        }
        controller.tabManager.updateTab(id: tabID) { $0.workingDirectory = rootURL }
        controller.observeProjectDirectory(rootURL)
        if let tab = controller.tabManager.tab(for: tabID) {
            registerSession(for: tab, in: controller)
        }
        controller.showWindow(nil)
        controller.window?.center()
        controller.createTerminalSurface()
        controller.window?.makeKeyAndOrderFront(nil)
        additionalWindowControllers.append(controller)
        return tabID
    }

    func activateProjectForUser(_ projectID: ProjectID) {
        do {
            _ = try showProjectHome(projectID)
        } catch {
            presentProjectError(error)
        }
    }

    @objc func openProjectMenuAction(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = appLocalizer().string("project.open.title", fallback: "Open Project")
        panel.prompt = appLocalizer().string("project.open.button", fallback: "Open")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        presentOpenPanel(panel) { [weak self] response in
            guard response == .OK, let directory = panel.url, let self else { return }
            let projectID = projectResolver.resolveProject(for: directory).groupingID
            activateProjectForUser(projectID)
        }
    }

    @objc func openRecentProjectMenuAction(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        activateProjectForUser(ProjectID(rawValue: path))
    }

    @objc func cloneProjectMenuAction(_ sender: Any?) {
        let localizer = appLocalizer()
        let alert = NSAlert()
        alert.messageText = localizer.string("project.clone.title", fallback: "Clone Project")
        alert.informativeText = localizer.string(
            "project.clone.remote.prompt",
            fallback: "Enter an HTTPS or SSH Git URL."
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: localizer.string("common.continue", fallback: "Continue"))
        alert.addButton(withTitle: localizer.string("common.cancel", fallback: "Cancel"))
        let remoteField = NSTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 24))
        remoteField.placeholderString = "https://example.com/team/project.git"
        remoteField.setAccessibilityLabel(alert.informativeText)
        alert.accessoryView = remoteField

        presentAlert(alert) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            do {
                _ = try ProjectCloneService.validatedRemote(remoteField.stringValue)
                chooseProjectCloneDestination(remote: remoteField.stringValue)
            } catch {
                presentProjectError(error)
            }
        }
    }

    func updateProjectMenus(in menu: NSMenu) {
        if menu.identifier == .projectOpenRecentMenu {
            populateOpenRecentMenu(menu)
        }
        for item in menu.items where item.submenu?.identifier == .projectOpenRecentMenu {
            if let submenu = item.submenu {
                populateOpenRecentMenu(submenu)
            }
        }
    }

    private func populateOpenRecentMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let localizer = appLocalizer()
        guard projectRegistry.persistenceErrorDescription == nil else {
            let item = NSMenuItem(
                title: localizer.string(
                    "project.registry.unavailable",
                    fallback: "Project list unavailable"
                ),
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
            return
        }
        guard !projectRegistry.recent.isEmpty else {
            let item = NSMenuItem(
                title: localizer.string("project.recent.empty", fallback: "No Recent Projects"),
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
            return
        }

        for record in projectRegistry.recent.prefix(12) {
            let root = URL(fileURLWithPath: record.id.rawValue, isDirectory: true)
            let name = auroraWorkspaceTitleStore.title(for: record.id.rawValue)
                ?? ProjectDescriptor.automaticName(for: root)
            let item = NSMenuItem(
                title: "\(name) - \(root.deletingLastPathComponent().path)",
                action: #selector(openRecentProjectMenuAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = record.id.rawValue
            item.image = NSImage(systemSymbolName: record.isPinned ? "pin.fill" : "folder", accessibilityDescription: nil)
            var isDirectory: ObjCBool = false
            item.isEnabled = FileManager.default.fileExists(
                atPath: root.path,
                isDirectory: &isDirectory
            ) && isDirectory.boolValue
            menu.addItem(item)
        }
    }

    private func chooseProjectCloneDestination(remote: String) {
        let panel = NSOpenPanel()
        panel.title = appLocalizer().string(
            "project.clone.destination.title",
            fallback: "Choose Clone Destination"
        )
        panel.prompt = appLocalizer().string("project.clone.button", fallback: "Clone")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        presentOpenPanel(panel) { [weak self] response in
            guard response == .OK, let parent = panel.url, let self else { return }
            performProjectClone(remote: remote, parentDirectory: parent)
        }
    }

    private func performProjectClone(remote: String, parentDirectory: URL) {
        let parentRoot: ProjectDirectoryRoot
        do {
            parentRoot = try ProjectDirectoryRoot.open(parentDirectory)
        } catch {
            presentProjectError(error)
            return
        }
        let progress = NSAlert()
        progress.messageText = appLocalizer().string(
            "project.clone.progress",
            fallback: "Cloning project..."
        )
        let spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 320, height: 20))
        spinner.style = .bar
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        progress.accessoryView = spinner
        let parentWindow = focusedWindowController()?.window
        if let parentWindow {
            parentWindow.beginSheet(progress.window)
        } else {
            progress.window.orderFront(nil)
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try ProjectCloneService().clone(
                        remote: remote,
                        in: parentRoot
                    )
                }.value
                dismissProgressAlert(progress, parentWindow: parentWindow)
                finishProjectClone(result)
            } catch {
                dismissProgressAlert(progress, parentWindow: parentWindow)
                presentProjectError(error)
            }
        }
    }

    private func finishProjectClone(_ result: ProjectCloneResult) {
        let rootURL: URL
        do {
            rootURL = try result.verifiedRootURL()
        } catch {
            presentProjectError(error)
            return
        }
        projectResolver.invalidate(directory: rootURL)
        gitInfoProvider.invalidateCache(for: rootURL)
        let descriptor = projectResolver.resolveProject(for: rootURL)
        do {
            guard try result.verifiedRootURL() == rootURL else {
                throw ProjectCloneError.destinationChanged(rootURL.path)
            }
        } catch {
            presentProjectError(error)
            return
        }
        var metadataError: Error?
        do {
            try projectRegistry.recordOpen(
                descriptor,
                incrementOpenCount: false,
                remoteOrigin: result.remoteOrigin
            )
        } catch {
            metadataError = error
        }

        do {
            _ = try activateProject(descriptor.groupingID)
        } catch {
            presentProjectError(error)
            return
        }
        if let metadataError {
            presentProjectMetadataWarning(metadataError)
        }
    }

    private func dismissProgressAlert(_ alert: NSAlert, parentWindow: NSWindow?) {
        if let parentWindow, alert.window.sheetParent === parentWindow {
            parentWindow.endSheet(alert.window)
        } else {
            alert.window.orderOut(nil)
        }
    }

    private func presentOpenPanel(
        _ panel: NSOpenPanel,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        if let window = focusedWindowController()?.window {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }

    private func presentAlert(
        _ alert: NSAlert,
        completion: @escaping (NSApplication.ModalResponse) -> Void
    ) {
        if let window = focusedWindowController()?.window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    private func presentProjectError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = appLocalizer().string(
            "project.error.title",
            fallback: "Project action failed"
        )
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: appLocalizer().string("common.ok", fallback: "OK"))
        presentAlert(alert) { _ in }
    }

    private func presentProjectMetadataWarning(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = appLocalizer().string(
            "project.metadata.warning.title",
            fallback: "Project cloned with a warning"
        )
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: appLocalizer().string("common.ok", fallback: "OK"))
        presentAlert(alert) { _ in }
    }
}
