// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+CellsCommands.swift - Command Palette actions for Cocxy Cells.

import AppKit
import Foundation

extension MainWindowController {
    func commandPaletteCellsActions() -> [CommandAction] {
        let cli = Self.cellsCLICommandPrefix()
        return [
            CommandAction(
                id: "cells.list",
                name: "Cells: List Cells",
                description: "List local and user-owned compute cells",
                shortcut: nil,
                category: .cli,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in
                        self?.openCellsCommandTab(command: "\(cli) cell list", execute: true)
                    }
                }
            ),
            CommandAction(
                id: "cells.createDocker",
                name: "Cells: Create Docker Cell",
                description: "Prepare a local Docker cell creation command",
                shortcut: nil,
                category: .cli,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in
                        self?.openCellsCommandTab(
                            command: "\(cli) cell create --provider docker --image alpine:3.20",
                            execute: false
                        )
                    }
                }
            ),
            CommandAction(
                id: "cells.createSSH",
                name: "Cells: Create SSH Cell",
                description: "Prepare a user-owned SSH cell creation command",
                shortcut: nil,
                category: .cli,
                handler: { [weak self] in
                    self?.dismissCommandPalette()
                    Task { @MainActor in
                        self?.openCellsCommandTab(
                            command: "\(cli) cell create --provider ssh --host your-host --user \(NSUserName())",
                            execute: false
                        )
                    }
                }
            ),
        ]
    }

    private func openCellsCommandTab(command: String, execute: Bool) {
        let workingDirectory = tabManager.activeTab?.workingDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
        let tabID = createTab(workingDirectory: workingDirectory)
        tabManager.renameTab(id: tabID, newTitle: "Cells")
        guard let surfaceID = tabSurfaceMap[tabID] else { return }
        terminalEngine(for: surfaceID).sendText(command + (execute ? "\r" : ""), to: surfaceID)
        window?.makeKeyAndOrderFront(nil)
        focusActiveTerminalSurface()
    }

    private static func cellsCLICommandPrefix() -> String {
        let candidates = [
            Bundle.main.url(forResource: "cocxy", withExtension: nil)?.path,
            "/usr/local/bin/cocxy",
            "/opt/homebrew/bin/cocxy",
        ].compactMap { $0 }

        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return "cocxy"
        }
        return cellsShellQuoted(path)
    }

    private static func cellsShellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
