// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CLIError.swift - Error types for the CLI companion.

import Foundation

// MARK: - CLI Error

/// Errors that can occur during CLI operations.
///
/// Each error produces a clear, actionable message for the user.
public enum CLIError: Error, Equatable {
    /// The Cocxy Terminal app is not running (connection refused).
    case appNotRunning

    /// Permission denied when connecting to the socket.
    case permissionDenied

    /// The connection timed out waiting for a response.
    case timeout

    /// An unknown command was provided.
    case unknownCommand(String)

    /// A required argument is missing.
    case missingArgument(command: String, argument: String)

    /// An invalid argument was provided.
    case invalidArgument(command: String, argument: String, reason: String)

    /// The server returned an error response.
    case serverError(String)

    /// The response payload is too large.
    case payloadTooLarge(size: Int, maximum: Int)

    /// The response could not be parsed.
    case malformedResponse(reason: String)

    /// The socket connection failed for an unexpected reason.
    case connectionFailed(reason: String)

    /// User-facing error message for terminal output.
    public var userMessage: String {
        switch self {
        case .appNotRunning:
            return "Error: Cocxy Terminal is not running. Start the app first."
        case .permissionDenied:
            return "Error: Permission denied connecting to Cocxy Terminal socket."
        case .timeout:
            return "Error: Connection timed out waiting for Cocxy Terminal response."
        case .unknownCommand(let command):
            return "Error: Unknown command '\(command)'. Run 'cocxy --help' for usage."
        case .missingArgument(let command, let argument):
            return "Error: Command '\(command)' requires argument <\(argument)>."
        case .invalidArgument(let command, let argument, let reason):
            return "Error: Invalid argument '\(argument)' for command '\(command)': \(reason)."
        case .serverError(let message):
            return "Error: \(message)"
        case .payloadTooLarge(let size, let maximum):
            return "Error: Payload size \(size) bytes exceeds maximum \(maximum) bytes."
        case .malformedResponse(let reason):
            return "Error: Malformed response from Cocxy Terminal: \(reason)."
        case .connectionFailed(let reason):
            return "Error: Connection failed: \(reason)."
        }
    }
}
