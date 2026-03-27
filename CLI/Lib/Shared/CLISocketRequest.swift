// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CLISocketRequest.swift - Lightweight copy of SocketRequest for CLI companion.

import Foundation

// MARK: - CLI Socket Request

/// A command request sent from the CLI companion to the Cocxy Terminal app.
///
/// Wire format: 4 bytes big-endian payload length + JSON payload.
///
/// This is a standalone copy of the app's `SocketRequest` type.
/// The CLI must not import the main app module.
public struct CLISocketRequest: Codable, Equatable {
    /// Unique identifier for this request. Used to match responses.
    public let id: String

    /// The command to execute (e.g., "notify", "new-tab", "status").
    public let command: String

    /// Command-specific parameters. Nil when the command takes no arguments.
    public let params: [String: String]?

    public init(id: String, command: String, params: [String: String]?) {
        self.id = id
        self.command = command
        self.params = params
    }
}
