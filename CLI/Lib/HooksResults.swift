// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HooksResults.swift - Result types for hooks operations.

import Foundation

// MARK: - Install Result

/// The result of a `hooks install` operation.
///
/// Communicates whether hooks were installed, or if they were already present.
public struct HooksInstallResult: Equatable {
    /// Whether hooks were newly installed in this operation.
    public let installed: Bool

    /// Whether hooks were already installed (idempotent detection).
    public let alreadyInstalled: Bool

    /// The list of hook event types that were installed.
    public let hookEvents: [String]

    public init(installed: Bool, alreadyInstalled: Bool, hookEvents: [String]) {
        self.installed = installed
        self.alreadyInstalled = alreadyInstalled
        self.hookEvents = hookEvents
    }
}

// MARK: - Uninstall Result

/// The result of a `hooks uninstall` operation.
///
/// Communicates whether hooks were removed, and which events were affected.
public struct HooksUninstallResult: Equatable {
    /// Whether any cocxy hooks were removed.
    public let uninstalled: Bool

    /// Whether there was nothing to remove (no cocxy hooks found).
    public let nothingToRemove: Bool

    /// The list of event types from which cocxy hooks were removed.
    public let removedEvents: [String]

    public init(uninstalled: Bool, nothingToRemove: Bool, removedEvents: [String]) {
        self.uninstalled = uninstalled
        self.nothingToRemove = nothingToRemove
        self.removedEvents = removedEvents
    }
}

// MARK: - Status Result

/// The result of a `hooks status` query.
///
/// Reports which hook events have cocxy hooks installed.
public struct HooksStatusResult: Equatable {
    /// Whether cocxy hooks are currently installed.
    public let installed: Bool

    /// The list of event types that have cocxy hooks.
    public let installedEvents: [String]

    public init(installed: Bool, installedEvents: [String]) {
        self.installed = installed
        self.installedEvents = installedEvents
    }
}
