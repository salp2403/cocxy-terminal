// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentDashboardSessionDeduplicator.swift - Removes hook/pattern mirror rows.

import Foundation

/// Removes synthetic pattern rows when a richer hook-native session owns the
/// same terminal surface. Sessions without a concrete surface stay distinct so
/// separate agents in the same tab are never collapsed by guesswork.
enum AgentDashboardSessionDeduplicator {
    static func deduplicate(
        _ sessions: [AgentSessionInfo],
        surfaceIDForHookSession: (String) -> SurfaceID?
    ) -> [AgentSessionInfo] {
        let hookSurfaceKeys = Set(sessions.compactMap { session -> SurfaceKey? in
            guard !isPatternSession(session),
                  let surfaceID = surfaceIDForHookSession(session.id) else {
                return nil
            }
            return SurfaceKey(tabID: session.tabId, surfaceID: surfaceID)
        })

        guard !hookSurfaceKeys.isEmpty else { return sessions }

        return sessions.filter { session in
            guard let surfaceID = patternSurfaceID(for: session) else {
                return true
            }
            return !hookSurfaceKeys.contains(
                SurfaceKey(tabID: session.tabId, surfaceID: surfaceID)
            )
        }
    }

    static func isPatternSession(_ session: AgentSessionInfo) -> Bool {
        let prefix = "pattern-\(session.tabId.uuidString)"
        return session.id == prefix || session.id.hasPrefix(prefix + "-")
    }

    static func patternSurfaceID(for session: AgentSessionInfo) -> SurfaceID? {
        let prefix = "pattern-\(session.tabId.uuidString)-"
        guard session.id.hasPrefix(prefix) else { return nil }

        let suffix = String(session.id.dropFirst(prefix.count))
        guard let uuid = UUID(uuidString: suffix) else { return nil }
        return SurfaceID(rawValue: uuid)
    }

    private struct SurfaceKey: Hashable {
        let tabID: UUID
        let surfaceID: SurfaceID
    }
}
