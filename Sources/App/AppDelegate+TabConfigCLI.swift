// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+TabConfigCLI.swift - Reusable tab config CLI/UI integration.

import AppKit

extension AppDelegate {

    func saveFocusedTabConfigForCLI(
        name: String,
        command: String?,
        theme: String?,
        environment: [String: String],
        store: TabConfigStore = TabConfigStore()
    ) -> (name: String, path: String, warning: String?)? {
        guard let controller = focusedWindowController(),
              let tabID = controller.visibleTabID ?? controller.tabManager.activeTabID,
              controller.tabManager.tab(for: tabID) != nil,
              let projectDirectory = controller.tabConfigProjectDirectory(for: tabID) else {
            return nil
        }

        let layout: TabConfigLayout?
        let layoutWarning: String?
        let localizer = appLocalizer()
        do {
            layout = try controller.captureTabConfigLayout(
                for: tabID,
                projectDirectory: projectDirectory
            )
            layoutWarning = nil
        } catch {
            layout = nil
            layoutWarning = localizer.string(
                "tabConfig.warning.save.layoutOmitted",
                fallback: "Warning: The tab config was saved without its pane layout."
            )
            NSLog(
                "[AppDelegate] Saving tab config without pane layout: %@",
                error.localizedDescription
            )
        }

        do {
            let config = TabConfig(
                name: name,
                workingDirectory: ProjectPathCanonicalizer.canonicalURL(projectDirectory).path,
                command: command,
                environment: environment,
                theme: theme ?? configService?.current.appearance.theme,
                layout: layout
            )
            try store.save(config)
            let path = try store.fileURL(forName: name).path
            return (name: name, path: path, warning: layoutWarning)
        } catch {
            NSLog("[AppDelegate] Failed to save tab config: %@", error.localizedDescription)
            return nil
        }
    }

    func openTabConfigForCLI(
        named name: String,
        store: TabConfigStore = TabConfigStore()
    ) -> (id: String, title: String, path: String, warning: String?)? {
        openTabConfig(named: name, launchOrigin: .localSocket, store: store)
    }

    func openTabConfigFromUserInterface(
        named name: String,
        store: TabConfigStore = TabConfigStore()
    ) -> (id: String, title: String, path: String, warning: String?)? {
        openTabConfig(named: name, launchOrigin: .userInterface, store: store)
    }

    private func openTabConfig(
        named name: String,
        launchOrigin: TabConfigLaunchOrigin,
        store: TabConfigStore
    ) -> (id: String, title: String, path: String, warning: String?)? {
        guard let controller = focusedWindowController() else { return nil }
        let localizer = appLocalizer()

        do {
            let snapshot = try store.loadSnapshot(named: name)
            let config = snapshot.config
            let path = try store.fileURL(forName: name).path
            let requestedDirectory = resolveTabConfigDirectory(config.workingDirectory)
            let resolver = TabConfigLayoutRuntimeResolver()
            let projectDirectory = try resolver.canonicalProjectDirectory(requestedDirectory)
            let resolvedReport = try config.layout.map {
                try resolver.resolveBestEffort($0, projectDirectory: projectDirectory)
            }
            let resolvedLayout = resolvedReport?.layout
            let primaryDirectory = resolvedLayout?.firstPane.workingDirectory ?? projectDirectory

            let tabID = controller.createTab(workingDirectory: primaryDirectory)
            guard controller.tabSurfaceMap[tabID] != nil else {
                controller.performCloseTab(tabID)
                throw TabConfigLayoutRuntimeError.inconsistentLayout("primary terminal could not be created")
            }
            do {
                if let resolvedLayout {
                    try controller.installTabConfigLayout(resolvedLayout, in: tabID)
                }
            } catch {
                controller.performCloseTab(tabID)
                throw error
            }
            controller.bindTabConfigProjectDirectory(projectDirectory, to: tabID)
            controller.tabManager.renameTab(id: tabID, newTitle: config.name)
            _ = controller.focusTab(id: tabID)

            applyTabConfigTheme(config.theme, to: tabID, in: controller)
            if let authorization = TabConfigStartupSecurity.makeAuthorizationRequest(
                snapshot: snapshot,
                workingDirectory: primaryDirectory,
                destinationTabID: tabID,
                launchOrigin: launchOrigin
            ),
               controller.authorizeTabConfigStartup(authorization) {
                sendTabConfigStartupInput(authorization, in: controller)
            }

            let title = controller.tabManager.tab(for: tabID)?.displayTitle ?? config.name
            let warning: String? = resolvedReport.flatMap { report -> String? in
                guard !report.warnings.isEmpty else { return nil }
                let key = report.warnings.count == 1
                    ? "tabConfig.warning.open.paneReplaced.one"
                    : "tabConfig.warning.open.paneReplaced.other"
                let fallback = report.warnings.count == 1
                    ? "Warning: One unavailable pane was replaced with a terminal at the project root."
                    : "Warning: %d unavailable panes were replaced with terminals at the project root."
                return String(
                    format: localizer.string(key, fallback: fallback),
                    locale: localizer.locale,
                    report.warnings.count
                )
            }
            return (id: tabID.rawValue.uuidString, title: title, path: path, warning: warning)
        } catch {
            NSLog("[AppDelegate] Failed to open tab config: %@", error.localizedDescription)
            return nil
        }
    }

    func listTabConfigsForCLI() -> [String]? {
        do {
            return try TabConfigStore().listNames()
        } catch {
            NSLog("[AppDelegate] Failed to list tab configs: %@", error.localizedDescription)
            return nil
        }
    }

    func tabConfigPathForCLI(named name: String) -> String? {
        do {
            return try TabConfigStore().fileURL(forName: name).path
        } catch {
            return nil
        }
    }

    func exportTabConfigForCLI(
        named name: String,
        fileName: String,
        overwrite: Bool
    ) -> (name: String, path: String)? {
        do {
            let exported = try TabConfigStore().exportForSocket(
                named: name,
                fileName: fileName,
                overwrite: overwrite
            )
            return (name: name, path: exported.path)
        } catch {
            NSLog("[AppDelegate] Failed to export tab config: %@", error.localizedDescription)
            return nil
        }
    }

    private func applyTabConfigTheme(
        _ themeName: String?,
        to tabID: TabID,
        in controller: MainWindowController
    ) {
        guard let themeName,
              let engine = themeEngine,
              let theme = try? engine.themeByName(themeName) else {
            return
        }
        for surfaceID in controller.surfaceIDs(for: tabID) {
            controller.terminalEngine(for: surfaceID).cocxyCoreBridge?
                .applyTheme(theme.palette, to: surfaceID)
        }
    }

    private func sendTabConfigStartupInput(
        _ authorization: TabConfigStartupAuthorizationRequest,
        in controller: MainWindowController
    ) {
        Task { @MainActor [weak controller] in
            try? await Task.sleep(for: .milliseconds(500))
            let authorizedWorkingDirectory = ProjectPathCanonicalizer.canonicalURL(
                URL(fileURLWithPath: authorization.workingDirectory)
            )
            guard let controller,
                  Date() < authorization.expiresAt,
                  controller.tabManager.activeTabID == authorization.destinationTabID,
                  let currentWorkingDirectory = controller.tabConfigAuthorizationWorkingDirectory(
                    for: authorization.destinationTabID
                  ),
                  ProjectPathCanonicalizer.canonicalURL(currentWorkingDirectory).path
                    == authorizedWorkingDirectory.path,
                  let surfaceID = controller.tabSurfaceMap[authorization.destinationTabID] else {
                return
            }
            controller.terminalEngine(for: surfaceID).sendText(
                authorization.startupInput,
                to: surfaceID
            )
        }
    }

    private func resolveTabConfigDirectory(_ path: String) -> URL {
        if path == "~" {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        if path.hasPrefix("~/") {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(path.dropFirst(2)))
                .standardizedFileURL
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }
}
