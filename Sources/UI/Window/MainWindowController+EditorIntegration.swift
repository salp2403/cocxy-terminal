// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+EditorIntegration.swift - External editor command palette actions.

import AppKit
import CocxyShared
import Foundation

extension MainWindowController {
    func commandPaletteEditorActions() -> [CommandAction] {
        var actions: [CommandAction] = [
            CommandAction(
                id: "editor.openDefault",
                name: "Open Workspace in Default Editor",
                description: "Open the active tab's workspace with the system default editor",
                shortcut: nil,
                category: .editor,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in self?.openActiveWorkspaceInEditor(editorID: nil) }
                }
            )
        ]

        for launcher in EditorRegistry.builtIn where isEditorAvailable(launcher) && launcher.style == .gui {
            actions.append(
                CommandAction(
                    id: "editor.open.\(launcher.id)",
                    name: "Open Workspace in \(launcher.displayName)",
                    description: "Open the active tab's workspace using \(launcher.displayName)",
                    shortcut: nil,
                    category: .editor,
                    handler: { [weak self, editorID = launcher.id] in
                        self?.dismissCommandPalette()
                        Task { @MainActor in self?.openActiveWorkspaceInEditor(editorID: editorID) }
                    }
                )
            )
        }

        return actions
    }

    func openActiveWorkspaceInEditor(editorID: String?) {
        let workspace = tabManager.activeTab
            .map { $0.worktreeRoot ?? $0.workingDirectory }
            ?? FileManager.default.homeDirectoryForCurrentUser
        openURLInEditor(workspace, editorID: editorID)
    }

    func codeReviewExternalEditorActions(workingDirectory: URL?) -> [CodeReviewExternalEditorAction] {
        guard let workingDirectory else { return [] }
        let localizer = appLocalizer()

        var actions: [CodeReviewExternalEditorAction] = [
            CodeReviewExternalEditorAction(
                id: "system",
                title: Self.localizedOpenInDefaultEditorTitle(localizer: localizer),
                systemImage: "arrow.up.right.square"
            ) { [weak self] relativePath in
                self?.openReviewFileInEditor(relativePath, workingDirectory: workingDirectory, editorID: nil)
            }
        ]

        for launcher in EditorRegistry.builtIn where isEditorAvailable(launcher) && launcher.style == .gui {
            actions.append(
                CodeReviewExternalEditorAction(
                    id: launcher.id,
                    title: Self.localizedOpenInEditorTitle(launcher.displayName, localizer: localizer),
                    systemImage: "square.and.pencil"
                ) { [weak self, editorID = launcher.id] relativePath in
                    self?.openReviewFileInEditor(relativePath, workingDirectory: workingDirectory, editorID: editorID)
                }
            )
        }

        return actions
    }

    func openURLInEditor(_ url: URL, editorID: String?) {
        let request = EditorOpenRequest(filePath: url.path, editorID: editorID)
        let launcher = EditorRegistry.launcher(matching: editorID)
        let executablePath = launcher?.executableNames.lazy.compactMap { Self.resolveEditorExecutable(named: $0) }.first
        let bundleIdentifier = launcher?.bundleIdentifiers.first(where: {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        })
        let plan = EditorLaunchPlanner.plan(
            request: request,
            launcher: launcher,
            executablePath: executablePath,
            bundleIdentifier: bundleIdentifier
        )
        runEditorLaunchPlan(plan)
    }

    private func openReviewFileInEditor(_ relativePath: String, workingDirectory: URL, editorID: String?) {
        guard let fileURL = resolvedReviewFileURL(relativePath, workingDirectory: workingDirectory) else {
            NSLog("[EditorIntegration] Refused to open review path outside working directory: %@", relativePath)
            return
        }
        openURLInEditor(fileURL, editorID: editorID)
    }

    private func resolvedReviewFileURL(_ relativePath: String, workingDirectory: URL) -> URL? {
        let base = workingDirectory.standardizedFileURL
        let candidate = URL(fileURLWithPath: relativePath, relativeTo: base).standardizedFileURL
        guard candidate.path == base.path || candidate.path.hasPrefix(base.path + "/") else {
            return nil
        }
        return candidate
    }

    private func isEditorAvailable(_ launcher: EditorLauncher) -> Bool {
        launcher.executableNames.contains { Self.resolveEditorExecutable(named: $0) != nil }
            || launcher.bundleIdentifiers.contains {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
            }
    }

    private static func resolveEditorExecutable(named name: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"]
            ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for directory in path.split(separator: ":").map(String.init) {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func runEditorLaunchPlan(_ plan: EditorLaunchPlan) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: plan.executablePath)
        process.arguments = plan.arguments

        do {
            try process.run()
        } catch {
            NSLog("[EditorIntegration] Failed to launch %@: %@", plan.displayName, String(describing: error))
        }
    }
}
