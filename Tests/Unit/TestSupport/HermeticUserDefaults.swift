// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HermeticUserDefaults.swift - UserDefaults suites that stay out of the user's preferences.

import Darwin
import Foundation

/// Names `UserDefaults` suites by absolute paths inside a temporary directory
/// that belongs to the test process.
///
/// cfprefsd stores a suite with a plain name in the user's real
/// `~/Library/Preferences`, and `removePersistentDomain(forName:)` still leaves
/// the emptied plist there. A suite named by an absolute path is stored at that
/// path instead, and the whole directory is deleted when the process exits.
enum HermeticUserDefaults {
    private static let root: URL = {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-test-defaults-\(UUID().uuidString)", isDirectory: true)
        atexit { try? FileManager.default.removeItem(at: HermeticUserDefaults.root) }
        return url
    }()

    /// A fresh suite name for `UserDefaults(suiteName:)`.
    static func suiteName() -> String {
        root.appendingPathComponent(UUID().uuidString, isDirectory: false).path
    }
}
