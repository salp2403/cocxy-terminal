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
        let copy = Self.localizedSaveTabConfigCopy(localizer: appLocalizer())
        alert.messageText = copy.messageText
        alert.informativeText = copy.informativeText
        alert.accessoryView = field
        alert.addButton(withTitle: copy.primaryButton)
        alert.addButton(withTitle: copy.secondaryButton)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard appDelegate.saveFocusedTabConfigForCLI(
            name: name,
            command: nil,
            theme: nil,
            environment: [:]
        ) != nil else {
            showTabConfigError(Self.localizedTabConfigSaveFailureMessage(localizer: appLocalizer()))
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
        let copy = Self.localizedOpenTabConfigCopy(localizer: appLocalizer())
        alert.messageText = copy.messageText
        alert.informativeText = copy.informativeText
        alert.accessoryView = field
        alert.addButton(withTitle: copy.primaryButton)
        alert.addButton(withTitle: copy.secondaryButton)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard appDelegate.openTabConfigForCLI(named: name) != nil else {
            showTabConfigError(Self.localizedTabConfigOpenFailureMessage(localizer: appLocalizer()))
            return
        }
    }

    private func showTabConfigError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.addButton(withTitle: appLocalizer().string("common.ok", fallback: "OK"))
        alert.runModal()
    }
}
