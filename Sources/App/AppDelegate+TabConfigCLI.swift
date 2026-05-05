// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+TabConfigCLI.swift - Reusable tab config CLI/UI integration.

import AppKit

extension AppDelegate {

    func saveFocusedTabConfigForCLI(
        name: String,
        command: String?,
        theme: String?,
        environment: [String: String]
    ) -> (name: String, path: String)? {
        guard let controller = focusedWindowController(),
              let tabID = controller.visibleTabID ?? controller.tabManager.activeTabID,
              let tab = controller.tabManager.tab(for: tabID) else {
            return nil
        }

        let store = TabConfigStore()
        let config = TabConfig(
            name: name,
            workingDirectory: tab.workingDirectory.standardizedFileURL.path,
            command: command,
            environment: environment,
            theme: theme ?? configService?.current.appearance.theme
        )

        do {
            try store.save(config)
            let path = try store.fileURL(forName: name).path
            return (name: name, path: path)
        } catch {
            NSLog("[AppDelegate] Failed to save tab config: %@", error.localizedDescription)
            return nil
        }
    }

    func openTabConfigForCLI(named name: String) -> (id: String, title: String, path: String)? {
        guard let controller = focusedWindowController() else { return nil }
        let store = TabConfigStore()

        do {
            let config = try store.load(named: name)
            let path = try store.fileURL(forName: name).path
            let directory = resolveTabConfigDirectory(config.workingDirectory)

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }

            let tabID = controller.createTab(workingDirectory: directory)
            controller.tabManager.renameTab(id: tabID, newTitle: config.name)
            controller.tabManager.setActive(id: tabID)

            applyTabConfigTheme(config.theme, to: tabID, in: controller)
            sendTabConfigStartupInput(config, to: tabID, in: controller)

            let title = controller.tabManager.tab(for: tabID)?.displayTitle ?? config.name
            return (id: tabID.rawValue.uuidString, title: title, path: path)
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
        destination: String,
        overwrite: Bool
    ) -> (name: String, path: String)? {
        do {
            let destinationURL = URL(fileURLWithPath: destination)
            let exported = try TabConfigStore().export(
                named: name,
                to: destinationURL,
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
              let surfaceID = controller.tabSurfaceMap[tabID],
              let engine = themeEngine,
              let theme = try? engine.themeByName(themeName) else {
            return
        }
        controller.terminalEngine(for: surfaceID).cocxyCoreBridge?
            .applyTheme(theme.palette, to: surfaceID)
    }

    private func sendTabConfigStartupInput(
        _ config: TabConfig,
        to tabID: TabID,
        in controller: MainWindowController
    ) {
        guard let input = startupInput(for: config) else { return }

        Task { @MainActor [weak controller] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let controller,
                  controller.tabManager.activeTabID == tabID,
                  let surfaceID = controller.tabSurfaceMap[tabID] else {
                return
            }
            controller.terminalEngine(for: surfaceID).sendText(input, to: surfaceID)
        }
    }

    private func startupInput(for config: TabConfig) -> String? {
        let assignments = config.environment
            .keys
            .sorted()
            .compactMap { key -> String? in
                guard let value = config.environment[key],
                      TabConfigTOMLCodec.isValidEnvironmentKey(key) else {
                    return nil
                }
                return "\(key)=\(shellSingleQuoted(value))"
            }

        if let command = config.command?.trimmingCharacters(in: .whitespacesAndNewlines),
           !command.isEmpty {
            return (assignments + [command]).joined(separator: " ") + "\r"
        }

        guard !assignments.isEmpty else { return nil }
        return "export \(assignments.joined(separator: " "))\r"
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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
