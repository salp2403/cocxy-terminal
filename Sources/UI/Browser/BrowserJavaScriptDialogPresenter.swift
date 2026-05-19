// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserJavaScriptDialogPresenter.swift - Native fallback UI for captured WebKit dialogs.

import AppKit

@MainActor
enum BrowserJavaScriptDialogPresenter {
    private static let automationGraceNanoseconds: UInt64 = 750_000_000

    static func scheduleFallbackPresentation(
        dialog: BrowserDialogItem,
        viewModel: BrowserViewModel,
        window: NSWindow?,
        localizer: AppLocalizer
    ) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: automationGraceNanoseconds)
            guard viewModel.isJavaScriptDialogPending(dialog.id) else { return }
            present(dialog: dialog, viewModel: viewModel, window: window, localizer: localizer)
        }
    }

    private static func present(
        dialog: BrowserDialogItem,
        viewModel: BrowserViewModel,
        window: NSWindow?,
        localizer: AppLocalizer
    ) {
        let alert = NSAlert()
        alert.messageText = title(for: dialog.kind, localizer: localizer)
        alert.informativeText = dialog.message
        alert.alertStyle = .informational
        alert.addButton(withTitle: localizer.string("browser.dialog.ok", fallback: "OK"))

        let promptField: NSTextField?
        switch dialog.kind {
        case .alert:
            promptField = nil
        case .confirm:
            alert.addButton(withTitle: localizer.string("browser.dialog.cancel", fallback: "Cancel"))
            promptField = nil
        case .prompt:
            alert.addButton(withTitle: localizer.string("browser.dialog.cancel", fallback: "Cancel"))
            let field = NSTextField(string: dialog.defaultText ?? "")
            field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
            alert.accessoryView = field
            promptField = field
        }

        let resolver: (NSApplication.ModalResponse) -> Void = { response in
            let resolution: BrowserDialogResolution
            switch dialog.kind {
            case .alert:
                resolution = response == .alertFirstButtonReturn ? .accept(promptText: nil) : .dismiss
            case .confirm:
                resolution = response == .alertFirstButtonReturn ? .accept(promptText: nil) : .dismiss
            case .prompt:
                resolution = response == .alertFirstButtonReturn
                    ? .accept(promptText: promptField?.stringValue ?? dialog.defaultText)
                    : .dismiss
            }
            _ = viewModel.resolveJavaScriptDialog(id: dialog.id.uuidString, resolution: resolution)
        }

        if let window {
            alert.beginSheetModal(for: window, completionHandler: resolver)
        } else {
            resolver(alert.runModal())
        }
    }

    private static func title(for kind: BrowserDialogKind, localizer: AppLocalizer) -> String {
        switch kind {
        case .alert:
            return localizer.string("browser.dialog.alert.title", fallback: "JavaScript Alert")
        case .confirm:
            return localizer.string("browser.dialog.confirm.title", fallback: "JavaScript Confirm")
        case .prompt:
            return localizer.string("browser.dialog.prompt.title", fallback: "JavaScript Prompt")
        }
    }
}
