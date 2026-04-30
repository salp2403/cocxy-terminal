// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalEnginePreference.swift - Shared terminal engine selection.

import Foundation

/// User-facing engine preference for a terminal surface.
///
/// `.system` follows the global configuration and keeps today's default
/// behavior. `.inProcess` forces CocxyCore in-process for one tab, while
/// `.daemon` opts that tab into the experimental daemon path when the helper
/// passes readiness checks.
public enum TerminalEnginePreference: String, Codable, Equatable, Sendable, CaseIterable {
    case system
    case inProcess = "in-process"
    case daemon

    public init?(cliValue value: String) {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "system", "default", "auto":
            self = .system
        case "in-process", "inprocess", "cocxycore", "core":
            self = .inProcess
        case "daemon", "pty-daemon", "ptydaemon":
            self = .daemon
        default:
            return nil
        }
    }

    public var socketValue: String { rawValue }
}
