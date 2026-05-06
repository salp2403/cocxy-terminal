// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NoteSpotlightScopePolicy.swift - Per-workspace privacy gate for
// Spotlight-backed note search.

import Foundation

/// Privacy policy for the opt-in Spotlight notes backend.
///
/// `[notes].search-engine = "spotlight"` is already off by default, but a
/// workspace can still opt out locally with `.cocxy-spotlight-ignore`.
/// The marker is checked at the project root resolved by
/// `NoteWorkspaceResolver`, not in Cocxy's hashed notes storage folder, so
/// the user keeps control in the same directory that owns the project.
struct NoteSpotlightScopePolicy: Sendable {

    static let ignoreFileName = ".cocxy-spotlight-ignore"

    private let fileExists: @Sendable (URL) -> Bool

    init() {
        self.fileExists = { url in
            FileManager.default.fileExists(atPath: url.path)
        }
    }

    init(fileExists: @escaping @Sendable (URL) -> Bool) {
        self.fileExists = fileExists
    }

    func allowsSpotlightSearch(in workspaceRoot: URL) -> Bool {
        let marker = workspaceRoot.standardizedFileURL
            .appendingPathComponent(Self.ignoreFileName, isDirectory: false)
        return !fileExists(marker)
    }

}
