// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeSessionRestore.swift - Helpers for per-worktree session continuity.

import Foundation

enum WorktreeSessionRestore {
    static func matchingTabs(
        worktreeID: String,
        worktreeRoot: URL,
        in tabs: [TabState]
    ) -> [TabState] {
        let normalizedRoot = worktreeRoot.standardizedFileURL
        return tabs.filter { tab in
            if tab.worktreeID == worktreeID { return true }
            return tab.worktreeRoot?.standardizedFileURL == normalizedRoot
        }
    }
}
