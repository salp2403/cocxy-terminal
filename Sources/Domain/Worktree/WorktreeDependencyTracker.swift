// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeDependencyTracker.swift - Conservative branch dependency inference.

import Foundation

struct WorktreeDependencyGraph: Sendable, Equatable {
    let dependentsByEntryID: [String: [String]]

    func dependents(of entryID: String) -> [String] {
        dependentsByEntryID[entryID] ?? []
    }
}

struct WorktreeDependencyTracker: Sendable {
    func graph(
        for entries: [WorktreeManifest.WorktreeEntry]
    ) -> WorktreeDependencyGraph {
        var dependentsByEntryID: [String: [String]] = [:]
        for parent in entries {
            let slashPrefix = parent.branch + "/"
            let dashPrefix = parent.branch + "-"
            let dependents = entries
                .filter { child in
                    child.id != parent.id
                        && child.createdAt >= parent.createdAt
                        && (
                            child.branch.hasPrefix(slashPrefix)
                                || child.branch.hasPrefix(dashPrefix)
                        )
                }
                .map(\.id)
                .sorted()
            if !dependents.isEmpty {
                dependentsByEntryID[parent.id] = dependents
            }
        }
        return WorktreeDependencyGraph(dependentsByEntryID: dependentsByEntryID)
    }
}
