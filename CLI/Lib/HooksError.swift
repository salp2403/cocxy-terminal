// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HooksError.swift - Error types for hooks install/uninstall/status operations.

import Foundation

// MARK: - Hooks Error

/// Errors that can occur during hooks management operations.
///
/// These cover file system errors, JSON parsing errors, and
/// hook-handler input validation errors.
public enum HooksError: Error, Equatable {
    /// The `~/.claude/settings.json` file exists but contains invalid JSON.
    case malformedSettingsFile(path: String)

    /// The hook-handler received invalid JSON on stdin.
    case invalidHookJSON(reason: String)

    /// The hook-handler received empty input on stdin.
    case emptyInput

    /// A file system operation failed.
    case fileSystemError(reason: String)
}
