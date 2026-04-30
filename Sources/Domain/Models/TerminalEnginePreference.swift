// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalEnginePreference.swift - Per-tab terminal engine selection.

import Foundation

/// User-facing engine preference for a tab.
///
/// `.system` follows the global configuration and keeps today's default
/// behaviour. `.inProcess` forces CocxyCore in-process for one tab, while
/// `.daemon` opts that tab into the experimental daemon path when the helper
/// passes readiness checks.
enum TerminalEnginePreference: String, Codable, Equatable, Sendable, CaseIterable {
    case system
    case inProcess = "in-process"
    case daemon

    init?(cliValue value: String) {
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

    var socketValue: String { rawValue }
}
