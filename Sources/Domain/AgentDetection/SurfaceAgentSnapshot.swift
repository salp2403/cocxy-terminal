// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SurfaceAgentSnapshot.swift - Identity-aware snapshot of a surface's
// agent state. Carries the surface ID alongside the runtime state so
// consumers can route focus, attribute ownership, or label per-split
// UI without re-querying the store.

import Foundation

/// Snapshot bundling a `SurfaceAgentState` with identity and role flags
/// for the tab the surface belongs to.
///
/// Built by `SurfaceAgentStateResolver.additionalActiveSnapshots(...)` and
/// `SurfaceAgentStateResolver.allActiveSnapshots(...)` so consumers that
/// render per-split indicators (Fase B mini-pills, Fase C code-review
/// surface selector) can attach click handlers, draw focus borders, and
/// look up the detected agent without a second round-trip to the
/// per-surface store.
///
/// The existing `SurfaceAgentState` and `SurfaceAgentStateResolver.resolve`
/// remain the canonical entry points for consumers that only need a
/// single summary state (overlay, primary pill). Snapshots are additive:
/// they do not replace the priority-chain resolver, they enrich its
/// output so per-split features can share one source of truth.
///
/// `Equatable` supports publisher deduplication. `Sendable` keeps the
/// snapshot safe to move across actors. The struct is intentionally a
/// value type with no reference semantics so test fixtures remain simple.
struct SurfaceAgentSnapshot: Equatable, Sendable {

    /// Identifier of the surface this snapshot describes.
    ///
    /// Used by UI to route focus, select a split, or attribute a file
    /// touch to the right agent. Callers MUST treat this as opaque.
    let surfaceID: SurfaceID

    /// Runtime agent state captured at the moment the snapshot was built.
    ///
    /// This is a value copy; mutating the store after the snapshot was
    /// produced does not affect the snapshot.
    let state: SurfaceAgentState

    /// Whether the surface is currently the focused split of its tab.
    ///
    /// The focus flag reflects the user's typing target at snapshot time.
    /// It is only meaningful when the owning tab is displayed; for other
    /// tabs the flag is always `false`.
    let isFocused: Bool

    /// Whether the surface is the tab's primary (`tabSurfaceMap[tabID]`).
    ///
    /// A tab has exactly one primary surface. The primary is typically
    /// the first pane and the one that owns cross-split resources such
    /// as the SSH session or CWD reporter.
    let isPrimary: Bool

    init(
        surfaceID: SurfaceID,
        state: SurfaceAgentState,
        isFocused: Bool = false,
        isPrimary: Bool = false
    ) {
        self.surfaceID = surfaceID
        self.state = state
        self.isFocused = isFocused
        self.isPrimary = isPrimary
    }
}
