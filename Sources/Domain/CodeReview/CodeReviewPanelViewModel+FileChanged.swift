// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewPanelViewModel+FileChanged.swift
// Auto-refreshes the agent code review panel when Claude Code 2.1.83+ emits
// a FileChanged lifecycle event, debounced to collapse rapid edits into a
// single git diff invocation.

import Foundation

extension CodeReviewPanelViewModel {

    /// Reacts to a FileChanged lifecycle event by debouncing a diff refresh.
    ///
    /// The handler errs on the side of doing nothing when the event cannot be
    /// matched against the active tab's CWD or when the panel is hidden, so
    /// background mutations from other tabs or terminals never trigger a
    /// redundant git diff invocation.
    ///
    /// Invariants:
    /// - The event must carry both `cwd` and a non-empty `filePath`.
    /// - The event's `cwd` must exactly match `activeTabCwdProvider?()`
    ///   (`feedback_hook_matching_exact`). Parent or fuzzy matches would
    ///   reintroduce the cross-terminal contamination bug from session 9.
    /// - The reported file must live inside that CWD (boundary check, even
    ///   though Claude Code already scopes events to `cwd`).
    /// - The panel must currently be visible (`isVisible == true`); hidden
    ///   panels skip refreshes to avoid wasted git invocations.
    /// - A pending refresh is replaced by the latest event, collapsing a
    ///   burst of edits into a single refresh after the debounce window.
    func handleFileChangedHook(_ event: HookEvent) {
        guard case .fileChanged(let data) = event.data, !data.filePath.isEmpty else {
            return
        }
        guard let eventCwd = event.cwd, !eventCwd.isEmpty,
              let activeCwdURL = activeTabCwdProvider?() else {
            return
        }
        let eventCwdPath = HookPathNormalizer.normalize(eventCwd)
        let activeCwdPath = HookPathNormalizer.normalize(activeCwdURL.path)
        guard eventCwdPath == activeCwdPath else {
            return
        }
        let filePath = HookPathNormalizer.normalize(data.filePath)
        guard filePath == activeCwdPath || filePath.hasPrefix(activeCwdPath + "/") else {
            return
        }

        guard isVisible else {
            // Hidden panels should still be discoverable: a real FileChanged
            // hook is the strongest signal that the agent is modifying this
            // workspace, so ask the user whether they want to open review.
            requestReviewSuggestionIfNeeded(key: "\(event.sessionId):\(filePath)")
            cancelPendingFileChangeRefresh()
            return
        }

        scheduleFileChangeRefresh()
    }

    /// Schedules a single debounced `refreshDiffs()` call. Cancelling the
    /// pending work item before re-arming ensures rapid bursts collapse into
    /// exactly one refresh after the debounce window elapses.
    func scheduleFileChangeRefresh() {
        cancelPendingFileChangeRefresh()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.fileChangeRefreshWorkItem = nil
            // Re-check visibility at fire time: the panel may have been
            // hidden during the debounce window.
            guard self.isVisible else { return }
            self.refreshDiffs()
        }
        fileChangeRefreshWorkItem = workItem
        let deadline: DispatchTime = fileChangeRefreshDebounce > 0
            ? .now() + fileChangeRefreshDebounce
            : .now()
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: workItem)
    }

    /// Cancels and clears the pending FileChanged refresh, if any. Safe to
    /// call when nothing is pending.
    func cancelPendingFileChangeRefresh() {
        fileChangeRefreshWorkItem?.cancel()
        fileChangeRefreshWorkItem = nil
    }
}
