// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionDragData.swift - Pasteboard payload for cross-window tab drag-and-drop.

import AppKit

// MARK: - UTI

/// Custom UTI for Cocxy Terminal session drag-and-drop.
///
/// Registered as a pasteboard type so AppKit can identify Cocxy drag
/// operations and distinguish them from external drops.
extension NSPasteboard.PasteboardType {
    static let cocxySession = NSPasteboard.PasteboardType("dev.cocxy.terminal.session")
}

// MARK: - Session Drag Data

/// Lightweight payload written to the pasteboard when dragging a tab.
///
/// Contains only identifiers — the session registry holds all metadata.
/// This keeps the pasteboard payload small and avoids serializing heavy
/// state like scrollback or view hierarchies.
///
/// ## Flow
///
/// 1. Drag starts: `TabItemView` writes `SessionDragData` to pasteboard.
/// 2. Drag enters another window: `TabBarView` reads and validates.
/// 3. Drop: `MainWindowController` performs the transfer via the registry.
struct SessionDragData: Codable, Sendable {
    /// The session being dragged.
    let sessionID: SessionID

    /// The tab ID in the source window (used to locate the tab).
    let tabID: TabID

    /// The window the drag originated from.
    let sourceWindowID: WindowID

    // MARK: - Pasteboard Serialization

    /// Encodes this drag data as JSON for the pasteboard.
    ///
    /// - Returns: The JSON data, or `nil` if encoding fails.
    func pasteboardData() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Decodes drag data from a pasteboard item.
    ///
    /// - Parameter pasteboard: The pasteboard to read from.
    /// - Returns: The decoded drag data, or `nil` if the pasteboard
    ///   does not contain a valid Cocxy session payload.
    static func from(pasteboard: NSPasteboard) -> SessionDragData? {
        guard let data = pasteboard.data(forType: .cocxySession) else {
            return nil
        }
        return try? JSONDecoder().decode(SessionDragData.self, from: data)
    }
}
