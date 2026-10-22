// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

extension Design.AuroraWorkspace {
    func aggregatedNotesSummary(
        from summaries: [String: Design.AuroraWorkspaceNotesSummary],
        recentLimit: Int = 5
    ) -> Design.AuroraNotesSectionSummary? {
        let relevant = notesWorkspaceIDs.compactMap { summaries[$0] }
        let count = relevant.reduce(0) { $0 + $1.count }
        guard count > 0 else { return nil }
        let recent = relevant
            .flatMap(\.recentNotes)
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                if $0.workspaceID != $1.workspaceID { return $0.workspaceID < $1.workspaceID }
                return $0.id < $1.id
            }
        return Design.AuroraNotesSectionSummary(
            count: count,
            recentNotes: Array(recent.prefix(max(0, recentLimit)))
        )
    }

    static func uniqueNotesWorkspaceIDs(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

extension Design {
    struct AuroraNoteRow: Identifiable, Equatable, Hashable, Sendable {
        let id: String
        let workspaceID: String
        let title: String
        let updatedAt: Date

        init(id: String, workspaceID: String, title: String, updatedAt: Date) {
            self.id = id
            self.workspaceID = workspaceID
            self.title = title
            self.updatedAt = updatedAt
        }
    }

    struct AuroraNotesSectionSummary: Equatable, Hashable, Sendable {
        let count: Int
        let recentNotes: [AuroraNoteRow]
    }

    struct AuroraWorkspaceNotesSummary: Equatable, Hashable, Sendable {
        let workspaceID: String
        let count: Int
        let recentNotes: [AuroraNoteRow]

        init(workspaceID: String, count: Int, recentNotes: [AuroraNoteRow]) {
            self.workspaceID = workspaceID
            self.count = count
            self.recentNotes = recentNotes
        }
    }
}
