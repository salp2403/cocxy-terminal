// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentDashboardViewModel+FileChanged.swift
// Phase 3: canonical attribution of FileChanged lifecycle events to the
// owning session and (when uniquely identifiable) to its active subagent.
//
// FileChanged is the authoritative filesystem signal for Claude Code 2.1.83+.
// Pre-Phase-3 the dashboard inferred file impacts from `tool_input.file_path`
// inside PostToolUse events. That inference is retained for backward
// compatibility but FileChanged now augments it with events emitted by the
// CLI directly, including changes made by tools that do not surface a
// file_path in their PostToolUse payload.

import Foundation

extension AgentDashboardViewModel {

    /// Routes a `FileChanged` lifecycle event into session and subagent
    /// attribution maps.
    ///
    /// Invariants:
    /// - Decoded payload must contain a non-empty `filePath`.
    /// - Session lookup is by `event.sessionId` first (matches the rest of
    ///   the dashboard's contract); if the session does not exist yet the
    ///   event is dropped silently to avoid races during session bring-up.
    /// - When exactly one subagent in that session is active, the file path
    ///   is added to that subagent's `touchedFilePaths` set. With zero or
    ///   multiple active subagents we cannot attribute confidently, so the
    ///   change is recorded only at the session level.
    /// - The file impact is always recorded on the session, deduplicated via
    ///   the existing `Set<FileOperation>` semantics.
    /// - Updates `lastActivityTime` so the dashboard sort order surfaces the
    ///   busiest sessions on top.
    func handleFileChangedEvent(_ event: HookEvent) {
        guard case .fileChanged(let data) = event.data, !data.filePath.isEmpty else {
            return
        }
        guard sessionDataStore[event.sessionId] != nil else {
            // Race: FileChanged before SessionStart, or session belongs to a
            // tab that is not in our store. Drop silently.
            return
        }

        let operation = Self.mapChangeType(data.changeType)

        // Attribute to the single active subagent if exactly one is running.
        if let subagents = sessionDataStore[event.sessionId]?.subagents {
            let activeIndices = subagents.indices.filter { subagents[$0].isActive }
            if activeIndices.count == 1 {
                let idx = activeIndices[0]
                sessionDataStore[event.sessionId]?.subagents[idx]
                    .touchedFilePaths.insert(data.filePath)
                sessionDataStore[event.sessionId]?.subagents[idx]
                    .lastActivityTime = event.timestamp
            }
        }

        // Always record on the session as the canonical impact map. The set
        // semantics deduplicate repeated paths automatically.
        sessionDataStore[event.sessionId]?
            .fileImpacts[data.filePath, default: []]
            .insert(operation)
        sessionDataStore[event.sessionId]?.lastActivityTime = event.timestamp

        rebuildSessions()
    }

    /// Maps the optional `change_type` field to `FileImpact.FileOperation`.
    ///
    /// Claude Code currently emits `write`, `edit` and `delete`. We map
    /// `delete` to `.write` (treated as a mutating change) until a dedicated
    /// `.delete` case is added to `FileImpact.FileOperation`. Unknown or
    /// missing values default to `.write` — recording at least that the
    /// file was touched.
    static func mapChangeType(_ raw: String?) -> FileImpact.FileOperation {
        switch raw?.lowercased() {
        case "edit":
            return .edit
        case "write", "delete", nil, "":
            return .write
        default:
            return .write
        }
    }
}
