// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CLISocketResponse.swift - Lightweight copy of SocketResponse for CLI companion.

import Foundation

// MARK: - CLI Socket Response

/// A response received from the Cocxy Terminal app after processing a command.
///
/// Wire format: 4 bytes big-endian payload length + JSON payload.
///
/// This is a standalone copy of the app's `SocketResponse` type.
/// The CLI must not import the main app module.
public struct CLISocketResponse: Codable, Equatable {
    /// Matches the `id` of the originating request.
    public let id: String

    /// Whether the command was executed successfully.
    public let success: Bool

    /// Command-specific response data. Nil on error.
    public let data: [String: String]?

    /// Error message when `success` is `false`. Nil on success.
    public let error: String?

    public init(id: String, success: Bool, data: [String: String]?, error: String?) {
        self.id = id
        self.success = success
        self.data = data
        self.error = error
    }
}
