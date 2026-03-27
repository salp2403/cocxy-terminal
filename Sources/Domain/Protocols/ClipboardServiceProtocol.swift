// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ClipboardServiceProtocol.swift - Abstraction for clipboard read/write operations.

import Foundation

// MARK: - Clipboard Service Protocol

/// Abstraction for clipboard operations.
///
/// Decouples terminal clipboard operations from `NSPasteboard` so the domain
/// layer remains testable without AppKit. The system implementation wraps
/// `NSPasteboard.general`; tests use `MockClipboardService`.
///
/// - SeeAlso: `SystemClipboardService` (production implementation)
/// - SeeAlso: `MockClipboardService` (test double)
@MainActor protocol ClipboardServiceProtocol: AnyObject {

    /// Reads the current text content from the clipboard.
    ///
    /// - Returns: The clipboard text, or `nil` if the clipboard is empty or
    ///   does not contain plain text.
    func read() -> String?

    /// Writes text to the clipboard, replacing any existing content.
    ///
    /// - Parameter text: The text to write.
    func write(_ text: String)

    /// Clears all content from the clipboard.
    func clear()
}

// MARK: - Mock Clipboard Service

/// In-memory clipboard for testing. Thread-safe is not needed because tests
/// run on a single thread.
final class MockClipboardService: ClipboardServiceProtocol {

    private var content: String?

    func read() -> String? {
        content
    }

    func write(_ text: String) {
        content = text
    }

    func clear() {
        content = nil
    }
}
