// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentDashboardViewModel+FileChanged.swift
// Phase 3: canonical attribution of FileChanged lifecycle events to the
// owning session and (when uniquely identifiable) to its active subagent.
//
// FileChanged is the canonical filesystem signal regardless of whether it
// comes from the bounded Claude hook or Cocxy's native workspace monitor.
// Pre-Phase-3 the dashboard inferred file impacts from `tool_input.file_path`
// inside PostToolUse events. That inference is retained for backward
// compatibility but FileChanged now augments it with events emitted by the
// integration layer, including changes made by tools that do not surface a
// file_path in their PostToolUse payload.

import Foundation

struct PendingDashboardFileChange: Sendable {
    var operations: Set<FileImpact.FileOperation>
    var latestTimestamp: Date
    var attributedSubagentIDs: Set<String>
}

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
    /// - Events are coalesced for 250 ms by default. The burst produces one
    ///   immutable session snapshot and therefore one `@Published` emission.
    /// - Pending impacts are periodically compacted and committed impacts
    ///   retain only the 512 most recent paths per session.
    func handleFileChangedEvent(_ event: HookEvent) {
        guard case .fileChanged(let data) = event.data, !data.filePath.isEmpty else {
            return
        }
        guard let sessionData = sessionDataStore[event.sessionId] else {
            // Race: FileChanged before SessionStart, or session belongs to a
            // tab that is not in our store. Drop silently.
            return
        }

        let operation = Self.mapChangeType(data.changeType)
        let activeSubagentIDs = sessionData.subagents.filter(\.isActive).map(\.id)
        let attributedSubagentIDs: Set<String> = activeSubagentIDs.count == 1
            ? [activeSubagentIDs[0]]
            : []

        var pending = pendingFileChangesBySession[event.sessionId]?[data.filePath]
            ?? PendingDashboardFileChange(
            operations: [],
            latestTimestamp: event.timestamp,
            attributedSubagentIDs: []
        )
        pending.operations.insert(operation)
        pending.latestTimestamp = max(pending.latestTimestamp, event.timestamp)
        pending.attributedSubagentIDs.formUnion(attributedSubagentIDs)
        pendingFileChangesBySession[event.sessionId, default: [:]][data.filePath] = pending

        if let changes = pendingFileChangesBySession[event.sessionId],
           changes.count > Self.pendingFileChangeCompactionThreshold {
            pendingFileChangesBySession[event.sessionId] = Dictionary(
                uniqueKeysWithValues: changes.sorted(by: Self.isMoreRecentPendingChange)
                    .prefix(Self.retainedPendingFileChangesPerSession)
                    .map { ($0.key, $0.value) }
            )
        }
        scheduleFileChangeFlush()
    }

    func flushPendingFileChanges() {
        fileChangeFlushTimer?.cancel()
        fileChangeFlushTimer = nil
        applyPendingFileChanges()
    }

    func discardPendingFileChanges(for sessionId: String) {
        pendingFileChangesBySession.removeValue(forKey: sessionId)
        guard pendingFileChangesBySession.isEmpty else { return }
        fileChangeFlushTimer?.cancel()
        fileChangeFlushTimer = nil
    }

    /// Maps the canonical `event` field and legacy `change_type` values.
    ///
    /// Claude Code emits `change`, `add`, and `unlink`. Legacy producers used
    /// `write`, `edit`, and `delete`. Unknown or missing values default to
    /// `.write`, preserving the fact that the file was touched.
    static func mapChangeType(_ raw: String?) -> FileImpact.FileOperation {
        switch raw?.lowercased() {
        case "change", "edit":
            return .edit
        case "add", "create":
            return .create
        case "unlink", "delete":
            return .delete
        case "write", nil, "":
            return .write
        default:
            return .write
        }
    }

    private func scheduleFileChangeFlush() {
        let deadline: DispatchTime = fileChangeDebounceInterval > 0
            ? .now() + fileChangeDebounceInterval
            : .now()
        if let timer = fileChangeFlushTimer {
            timer.schedule(deadline: deadline)
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.fileChangeFlushTimer?.cancel()
            self.fileChangeFlushTimer = nil
            self.applyPendingFileChanges()
        }
        fileChangeFlushTimer = timer
        timer.schedule(deadline: deadline)
        timer.resume()
    }

    private func applyPendingFileChanges() {
        guard !pendingFileChangesBySession.isEmpty else { return }
        let pendingBySession = pendingFileChangesBySession
        pendingFileChangesBySession.removeAll(keepingCapacity: true)

        var didChange = false
        for sessionId in pendingBySession.keys.sorted() {
            guard var sessionData = sessionDataStore[sessionId],
                  let changes = pendingBySession[sessionId] else {
                continue
            }

            for filePath in changes.keys.sorted() {
                guard let change = changes[filePath] else { continue }
                var impact = sessionData.fileImpacts[filePath]
                    ?? FileImpact(path: filePath, lastChangedAt: change.latestTimestamp)
                impact.operations.formUnion(change.operations)
                impact.lastChangedAt = max(impact.lastChangedAt, change.latestTimestamp)
                sessionData.fileImpacts[filePath] = impact

                for subagentId in change.attributedSubagentIDs {
                    guard let index = sessionData.subagents.firstIndex(where: {
                        $0.id == subagentId
                    }) else {
                        continue
                    }
                    sessionData.subagents[index].touchedFilePaths.insert(filePath)
                    let previous = sessionData.subagents[index].lastActivityTime ?? .distantPast
                    sessionData.subagents[index].lastActivityTime = max(
                        previous,
                        change.latestTimestamp
                    )
                }

                let previousActivity = sessionData.lastActivityTime ?? .distantPast
                sessionData.lastActivityTime = max(previousActivity, change.latestTimestamp)
            }

            Self.pruneFileImpacts(&sessionData.fileImpacts)
            sessionDataStore[sessionId] = sessionData
            didChange = true
        }

        if didChange {
            rebuildSessions()
        }
    }

    private static func isMoreRecentPendingChange(
        _ lhs: Dictionary<String, PendingDashboardFileChange>.Element,
        _ rhs: Dictionary<String, PendingDashboardFileChange>.Element
    ) -> Bool {
        if lhs.value.latestTimestamp != rhs.value.latestTimestamp {
            return lhs.value.latestTimestamp > rhs.value.latestTimestamp
        }
        return lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
    }
}
