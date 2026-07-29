// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MenuBarAgentSummary.swift - Pure menu bar agent counts and rows.

import Foundation

/// Immutable menu bar presentation derived from dashboard sessions.
struct MenuBarAgentSummary: Equatable, Sendable {
    static let visibleRowLimit = 5

    struct Row: Equatable, Sendable {
        let sessionID: String
        let tabID: UUID
        let name: String
        let state: AgentDashboardState
        let activity: String?
    }

    let working: Int
    let waiting: Int
    let errors: Int
    let rows: [Row]
    let overflowCount: Int

    static let empty = MenuBarAgentSummary(
        working: 0,
        waiting: 0,
        errors: 0,
        rows: [],
        overflowCount: 0
    )

    var badgeTitle: String {
        var parts: [String] = []
        if working > 0 { parts.append("\(working)↻") }
        if waiting > 0 { parts.append("\(waiting)⏳") }
        if errors > 0 { parts.append("\(errors)⚠") }
        return parts.isEmpty ? "" : " " + parts.joined(separator: " ")
    }

    static func summarize(
        _ sessions: [AgentSessionInfo],
        surfaceIDForHookSession: (String) -> SurfaceID? = { _ in nil },
        visibleRowLimit: Int = MenuBarAgentSummary.visibleRowLimit
    ) -> MenuBarAgentSummary {
        let deduplicated = AgentDashboardSessionDeduplicator.deduplicate(
            sessions,
            surfaceIDForHookSession: surfaceIDForHookSession
        )
        let attachedSessions = deduplicated.filter { $0.state != .idle }

        var working = 0
        var waiting = 0
        var errors = 0

        for session in attachedSessions {
            switch AgentStatusTextFormatter.counterBucket(for: session.state) {
            case .working?:
                working += 1
            case .waiting?:
                waiting += 1
            case .errors?:
                errors += 1
            case .finished?, nil:
                break
            }
        }

        let rowLimit = max(0, visibleRowLimit)
        let rows = attachedSessions.prefix(rowLimit).map { session in
            Row(
                sessionID: session.id,
                tabID: session.tabId,
                name: session.projectName,
                state: session.state,
                activity: normalizedActivity(session.lastActivity)
            )
        }

        return MenuBarAgentSummary(
            working: working,
            waiting: waiting,
            errors: errors,
            rows: rows,
            overflowCount: max(0, attachedSessions.count - rows.count)
        )
    }

    private static func normalizedActivity(_ activity: String?) -> String? {
        let trimmed = activity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
