// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectPresentation.swift - Pure project registry presentation mapping.

import Foundation

struct ProjectPresentationItem: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let parentPath: String
    let isPinned: Bool
    let isLive: Bool
    let isAvailable: Bool
    let lastOpenedAt: Date
}

enum ProjectPresentationBuilder {
    static func makeItems(
        records: [ProjectRecord],
        aliases: [String: String],
        liveProjectIDs: Set<String>,
        availability: (URL) -> Bool
    ) -> [ProjectPresentationItem] {
        records.map { record in
            let root = URL(fileURLWithPath: record.id.rawValue, isDirectory: true)
            let alias = AuroraWorkspacePlanner.normalizedTitle(aliases[record.id.rawValue])
            let automaticName = ProjectDescriptor.automaticName(for: root)
            return ProjectPresentationItem(
                id: record.id.rawValue,
                name: alias ?? automaticName,
                parentPath: root.deletingLastPathComponent().path,
                isPinned: record.isPinned,
                isLive: liveProjectIDs.contains(record.id.rawValue),
                isAvailable: availability(root),
                lastOpenedAt: record.lastOpenedAt
            )
        }
    }
}
