// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PreferencesWindowDelegate.swift - Intercepts preferences window close for unsaved changes.

import AppKit

// MARK: - Preferences Window Delegate

/// Intercepts the preferences window close event to prompt the user
/// when there are unsaved changes.
///
/// Presents a modal alert with three options:
/// - **Save**: Persists changes to disk and closes the window.
/// - **Discard**: Reverts all changes and closes the window.
/// - **Cancel**: Keeps the window open for further editing.
///
/// This delegate is retained by the window controller (via `preferencesWindowDelegate`)
/// to prevent premature deallocation.
@MainActor
final class PreferencesWindowDelegate: NSObject, NSWindowDelegate {

    /// The view model to check for unsaved changes and to trigger save/discard.
    private let viewModel: PreferencesViewModel

    /// Callback fired when the preferences window is about to close.
    /// Used by MainWindowController to restore terminal focus.
    var onClose: (() -> Void)?

    init(viewModel: PreferencesViewModel) {
        self.viewModel = viewModel
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard viewModel.hasUnsavedChanges else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "Unsaved Changes"
        alert.informativeText = "You have unsaved settings. Would you like to save them before closing?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: sender) { [weak self] response in
            guard let self else { return }
            switch response {
            case .alertFirstButtonReturn:
                // Save and close.
                do {
                    try self.viewModel.save()
                } catch {
                    NSLog("[PreferencesWindowDelegate] Failed to save: %@",
                          String(describing: error))
                }
                sender.close()

            case .alertSecondButtonReturn:
                // Discard changes and close.
                self.viewModel.discardChanges()
                sender.close()

            default:
                // Cancel — keep window open. No action needed.
                break
            }
        }

        // Return false to prevent immediate close; the sheet handler closes if needed.
        return false
    }
}
