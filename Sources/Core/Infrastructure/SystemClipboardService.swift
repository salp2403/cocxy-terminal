// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SystemClipboardService.swift - NSPasteboard-backed clipboard service.

import AppKit

// MARK: - System Clipboard Service

/// Production implementation of `ClipboardServiceProtocol` backed by `NSPasteboard.general`.
///
/// All operations target the general pasteboard (system clipboard).
/// This service is `@MainActor` because `NSPasteboard` must be accessed from the main thread.
@MainActor
final class SystemClipboardService: ClipboardServiceProtocol {

    /// Reads the current string from the system clipboard.
    ///
    /// - Returns: The clipboard text, or `nil` if empty or not plain text.
    func read() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    /// Writes text to the system clipboard.
    ///
    /// Clears existing content before writing the new text.
    /// - Parameter text: The text to write to the clipboard.
    func write(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    /// Clears all content from the system clipboard.
    func clear() {
        NSPasteboard.general.clearContents()
    }
}
