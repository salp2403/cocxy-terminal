// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentDashboardViewModel+FileChanged.swift
// Phase 1 stub for the FileChanged lifecycle event handler.
//
// The full attribution logic — linking FileChanged events to the active
// subagent or to the owning session's file impact map — is added in Phase 3
// (ADR-012). Phase 1 ships this empty dispatch so the exhaustive switch in
// `processHookEvent` compiles cleanly while the rest of the pipeline is built.

import Foundation

extension AgentDashboardViewModel {

    /// Handles a Claude Code `FileChanged` lifecycle event.
    ///
    /// No-op in Phase 1. Phase 3 will replace this implementation with the
    /// attribution logic that:
    /// 1. Locates the session whose `cwd` exactly matches `event.cwd`.
    /// 2. Adds `event.filePath` to the active subagent's `touchedFilePaths`
    ///    set, or to the session's `fileImpacts` map when no subagent is
    ///    active.
    /// 3. Deduplicates repeated paths.
    ///
    /// Keeping the method visible at Phase 1 lets the exhaustive switch in
    /// `processHookEvent(_:)` call it safely before the real logic lands,
    /// avoiding a temporary `break` that would need rewiring later.
    func handleFileChangedEvent(_ event: HookEvent) {
        // Intentionally empty until Phase 3. The helper is kept public to
        // the module so future tests can exercise the dispatch path.
        _ = event
    }
}
