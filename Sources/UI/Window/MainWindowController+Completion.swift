// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+Completion.swift - Wires inline completions into editor panels.

import Foundation

extension MainWindowController {
    func wireEditorCompletionIfNeeded(editorView: EditorView, fileURL: URL?, tabID: TabID?) {
        guard let tabID else {
            wireEditorCompletion(editorView, config: (configService?.current ?? .defaults).completions)
            return
        }
        wireEditorCompletion(editorView, config: effectiveConfig(for: tabID).completions)
    }

    func closeEditorCompletionIfNeeded(editorView: EditorView) {
        editorView.setInlineCompletionEngine(nil)
    }

    func rewireVisibleEditorCompletions() {
        let tabID = visibleTabID ?? tabManager.activeTabID
        for view in panelContentViews.values {
            guard let editorView = view as? EditorView else { continue }
            wireEditorCompletionIfNeeded(
                editorView: editorView,
                fileURL: editorView.fileURL,
                tabID: tabID
            )
        }
    }

    private func wireEditorCompletion(_ editorView: EditorView, config: CompletionConfig) {
        guard config.inlineAIEnabled,
              config.provider == .foundationModelsOnDevice
        else {
            editorView.setInlineCompletionEngine(nil)
            return
        }

        editorView.setInlineCompletionEngine(CompletionEngine(
            provider: FoundationModelsInlineCompletionProvider(),
            config: config
        ))
    }
}
