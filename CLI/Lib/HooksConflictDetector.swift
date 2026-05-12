// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HooksConflictDetector.swift - Detects existing non-Cocxy hook commands.

import Foundation

struct HookConfigurationConflict: Equatable {
    let eventType: String
    let command: String
}

enum HooksConflictDetector {
    static func detect(
        in settings: [String: Any],
        limitedTo eventTypes: [String]? = nil
    ) -> [HookConfigurationConflict] {
        guard let hooks = settings["hooks"] as? [String: Any] else {
            return []
        }

        let allowedEvents = eventTypes.map(Set.init)
        var conflicts: [HookConfigurationConflict] = []

        for eventType in hooks.keys.sorted() {
            if let allowedEvents, !allowedEvents.contains(eventType) {
                continue
            }

            guard let entries = hooks[eventType] as? [[String: Any]] else {
                continue
            }

            for entry in entries {
                conflicts.append(contentsOf: commandHooks(in: entry).filter { command in
                    !isCocxyHookCommand(command)
                }.map { command in
                    HookConfigurationConflict(eventType: eventType, command: command)
                })
            }
        }

        return conflicts
    }

    static func warning(for conflicts: [HookConfigurationConflict]) -> String? {
        guard !conflicts.isEmpty else { return nil }
        let eventSummary = Array(Set(conflicts.map(\.eventType))).sorted().joined(separator: ", ")
        return "Warning: existing non-Cocxy hooks detected for \(eventSummary); Cocxy will preserve them."
    }

    private static func commandHooks(in entry: [String: Any]) -> [String] {
        guard let hooks = entry["hooks"] as? [[String: Any]] else {
            return []
        }

        return hooks.compactMap { hook in
            guard hook["type"] as? String == "command" else { return nil }
            guard let command = hook["command"] as? String, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return command
        }
    }

    private static func isCocxyHookCommand(_ command: String) -> Bool {
        command.contains("cocxy") && command.contains("hook-handler")
    }
}
