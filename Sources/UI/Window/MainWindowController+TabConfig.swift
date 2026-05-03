// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+TabConfig.swift - UI affordances for reusable tab configs.

import AppKit

extension MainWindowController {

    @objc func saveCurrentTabConfigAction(_ sender: Any?) {
        promptAndSaveCurrentTabConfig()
    }

    @objc func openTabConfigAction(_ sender: Any?) {
        promptAndOpenTabConfig()
    }

    func promptAndSaveCurrentTabConfig() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let activeTitle = tabManager.activeTab?.displayTitle ?? "tab"
        let field = NSTextField(string: TabConfigStore.suggestedName(from: activeTitle))
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)

        let alert = NSAlert()
        alert.messageText = "Save Current Tab as Config"
        alert.informativeText = "Saved configs live locally as TOML and can be edited before opening."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard appDelegate.saveFocusedTabConfigForCLI(
            name: name,
            command: nil,
            theme: nil,
            environment: [:]
        ) != nil else {
            showTabConfigError("Unable to save tab config.")
            return
        }
    }

    func promptAndOpenTabConfig() {
        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let names = appDelegate.listTabConfigsForCLI() ?? []
        let field = NSComboBox(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        field.completes = true
        field.addItems(withObjectValues: names)
        field.stringValue = names.first ?? ""

        let alert = NSAlert()
        alert.messageText = "Open Tab from Config"
        alert.informativeText = "The TOML file is reloaded from disk before the tab opens."
        alert.accessoryView = field
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard appDelegate.openTabConfigForCLI(named: name) != nil else {
            showTabConfigError("Unable to open tab config.")
            return
        }
    }

    private func showTabConfigError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
