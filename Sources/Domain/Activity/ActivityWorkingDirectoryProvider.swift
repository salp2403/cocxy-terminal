// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ActivityWorkingDirectoryProvider.swift - App-scoped working-directory snapshots.

import Foundation

@MainActor
final class ActivityWorkingDirectoryProvider {
    typealias SnapshotProvider = @MainActor () -> [URL]

    private let snapshotProvider: SnapshotProvider

    init(snapshotProvider: @escaping SnapshotProvider) {
        self.snapshotProvider = snapshotProvider
    }

    func directories() -> [URL] {
        var seen: Set<String> = []
        return snapshotProvider().compactMap { directory in
            let standardized = directory.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { return nil }
            return standardized
        }
    }
}
