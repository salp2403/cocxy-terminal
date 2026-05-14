// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+CodexAccount.swift - Command palette actions for safe Codex account selection.

import CocxyShared
import Foundation

extension MainWindowController {
    func commandPaletteCodexAccountActions(
        accounts: [CodexAccount] = CodexAccountScanner.accounts(),
        selectionURL: URL = MainWindowController.codexAccountSelectionURL()
    ) -> [CommandAction] {
        guard !accounts.isEmpty else { return [] }

        let selectedID = CodexAccountSelectionStore.load(from: selectionURL).selectedAccountID

        return accounts.enumerated().map { index, account in
            let suffix = account.id == selectedID ? " (Active)" : ""
            let accountLabel = "Codex Account \(index + 1)"
            return CommandAction(
                id: "codex.account.switch.\(account.id)",
                name: "Switch Codex Account: \(accountLabel)\(suffix)",
                description: "Use this local Codex account for Cocxy integrations",
                shortcut: nil,
                category: .agent,
                handler: { [weak self, accountID = account.id, selectionURL] in
                    self?.dismissCommandPalette()
                    self?.activateCodexAccount(accountID: accountID, selectionURL: selectionURL)
                }
            )
        }
    }

    func activateCodexAccount(accountID: String, selectionURL: URL = MainWindowController.codexAccountSelectionURL()) {
        do {
            try CodexAccountSelectionStore.save(
                CodexAccountSelection(selectedAccountID: accountID),
                to: selectionURL
            )
            refreshCodexAccountIntegrations()
        } catch {
            NSLog("[CodexAccount] Failed to save selected account: %@", String(describing: error))
        }
    }

    func refreshCodexAccountIntegrations() {
        refreshStatusBar()
        guard rateLimitProbeService.currentAgent == .codex else { return }
        Task { [weak self] in
            await self?.rateLimitProbeService.refresh()
        }
    }

    static func codexAccountSelectionURL() -> URL {
        CodexAccountSelectionStore.defaultSelectionURL()
    }
}
