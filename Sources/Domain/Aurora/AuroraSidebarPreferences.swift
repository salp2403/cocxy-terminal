// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AuroraSidebarPreferences.swift - Persisted Aurora vertical sidebar choices.

import Foundation

/// Density/layout mode for the Aurora vertical workspace sidebar.
///
/// This lives in the domain layer because the choice is persisted in
/// `[appearance]`, mirrored through Preferences, and consumed by the
/// Aurora UI. Keeping one enum avoids stringly typed conversions between
/// config, controller, and view.
enum AuroraSidebarDisplayMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case detailed
    case summary
    case compact

    static var defaults: AuroraSidebarDisplayMode { .detailed }

    var showsPrimaryMetadata: Bool {
        switch self {
        case .detailed, .summary: return true
        case .compact: return false
        }
    }

    var showsPaneMatrix: Bool {
        switch self {
        case .detailed, .summary: return true
        case .compact: return false
        }
    }

    var showsCloseButton: Bool {
        switch self {
        case .detailed, .summary: return true
        case .compact: return false
        }
    }

    var verticalPadding: Double {
        switch self {
        case .detailed: return 8
        case .summary: return 6
        case .compact: return 4
        }
    }
}

/// Which signal should be promoted into the Aurora session row's primary
/// metadata line. The hover inspector still shows every signal; this only
/// controls the always-visible row summary.
enum AuroraSidebarPrimaryInfo: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case state
    case directory
    case process
    case command

    static var defaults: AuroraSidebarPrimaryInfo { .state }
}
