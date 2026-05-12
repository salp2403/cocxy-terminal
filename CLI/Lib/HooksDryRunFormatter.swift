// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HooksDryRunFormatter.swift - Human-readable hook setup previews.

import Foundation

struct HooksDryRunFormatter {
    static func header() -> String {
        "Dry run: no hook files will be modified."
    }

    static func line(
        for source: AgentSource,
        settingsFilePath: String,
        hookEvents: [String],
        remove: Bool
    ) -> String {
        let action = remove ? "would remove" : "would install"
        return "\(source.displayName): \(action) Cocxy hooks in \(settingsFilePath) for \(hookEvents.joined(separator: ", "))."
    }
}
