// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TabConfigProjectContextStore.swift - App-scoped project roots for reusable layouts.

import Foundation

@MainActor
final class TabConfigProjectContextStore {
    static let shared = TabConfigProjectContextStore()

    private var projectRoots: [TabID: URL] = [:]

    private init() {}

    func setProjectRoot(_ projectRoot: URL, for tabID: TabID) {
        projectRoots[tabID] = projectRoot.standardizedFileURL
    }

    func projectRoot(for tabID: TabID) -> URL? {
        projectRoots[tabID]
    }

    func removeProjectRoot(for tabID: TabID) {
        projectRoots.removeValue(forKey: tabID)
    }
}
