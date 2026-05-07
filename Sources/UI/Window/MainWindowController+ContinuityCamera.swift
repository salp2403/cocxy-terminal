// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+ContinuityCamera.swift - Continuity Camera import routing.

import AppKit

@MainActor
extension MainWindowController {
    func handleContinuityCameraImportPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        let reader = AgentPromptAttachmentPasteboardReader()
        guard let payload = reader.payload(from: pasteboard) else {
            return false
        }

        let viewModel = resolveAgentPanelViewModel()
        do {
            switch payload {
            case .fileURLs(let fileURLs):
                guard !fileURLs.isEmpty else { return false }
                for fileURL in fileURLs {
                    try viewModel.attachImageFile(fileURL)
                }
            case .imageData(let data, let suggestedFilename):
                try viewModel.attachImageData(
                    data,
                    suggestedFilename: ContinuityCameraImportProvider
                        .suggestedFilename(for: suggestedFilename)
                )
            }
        } catch {
            viewModel.handleAttachmentError(error)
            if !isAgentModeVisible {
                showAgentModePanel()
            }
            return false
        }

        if !isAgentModeVisible {
            showAgentModePanel()
        }
        return true
    }
}
