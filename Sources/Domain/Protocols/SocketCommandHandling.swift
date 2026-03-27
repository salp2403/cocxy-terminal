// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SocketCommandHandling.swift - Protocol for dispatching socket commands.

import Foundation

// MARK: - Socket Command Handling

/// Protocol for objects that can process CLI socket commands.
///
/// The `SocketServerImpl` delegates command processing to a handler
/// conforming to this protocol. This decouples the socket transport
/// layer from the domain logic (TabManager, SplitManager, etc.).
///
/// The handler is called from a background thread (the socket connection
/// queue). If the concrete implementation needs main-thread access
/// (e.g., to read from TabManager), it is responsible for dispatching
/// internally.
///
/// - SeeAlso: `SocketRequest` for the incoming message format.
/// - SeeAlso: `SocketResponse` for the reply format.
/// - SeeAlso: `CLICommandName` for the closed set of valid commands.
protocol SocketCommandHandling: AnyObject, Sendable {
    /// Processes a CLI command and returns a response.
    ///
    /// Called from a background thread. Implementations that need
    /// main-actor access must dispatch internally.
    ///
    /// Unknown commands produce an error response, never a crash.
    ///
    /// - Parameter request: The incoming CLI request.
    /// - Returns: A `SocketResponse` with the result of the command.
    func handleCommand(_ request: SocketRequest) -> SocketResponse
}
