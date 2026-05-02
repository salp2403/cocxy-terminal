// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+Vim.swift - Wires editor-only Vim mode from config.

extension MainWindowController {
    func wireEditorVimMode(editorView: EditorView, tabID: TabID?) {
        guard let tabID else {
            editorView.setVimModeEnabled((configService?.current ?? .defaults).vim.enabled)
            return
        }
        editorView.setVimModeEnabled(effectiveConfig(for: tabID).vim.enabled)
    }
}
