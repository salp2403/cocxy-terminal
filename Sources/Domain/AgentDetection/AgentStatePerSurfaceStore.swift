// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentStatePerSurfaceStore.swift - Per-surface agent state source of truth.

import Combine
import Foundation

/// Main-actor store that tracks the agent-detection state of each
/// terminal surface independently.
///
/// **Current rollout state (v0.1.71 Fase 2 landed).** The store is
/// live as a shadow source of truth: `AppDelegate+AgentWiring`
/// dual-writes every tab-level agent mutation onto it (see
/// ``wireAgentDetectionToTabs`` and ``wireHookReceiverToEngine``), the
/// surface lifecycle (`destroyTerminalSurface`, `destroyAllSurfaces`,
/// `performCloseTab`, `closeSplitAction`) resets its entries alongside
/// the engine's debounce and hook-session buckets, and the detection
/// engine carries `surfaceID` through every public entry point so each
/// emitted `StateContext` can be routed per split. `Tab` is still the
/// field UI consumers read — the store shadows it so Fase 3 can flip
/// readers one component at a time while the tab-level fallback stays
/// available as a safety net.
///
/// Migration roadmap:
/// - **Fase 1 (done)**: this store plus `SurfaceAgentState` are in
///   tree and unit-tested (`AgentStatePerSurfaceStoreSwiftTestingTests`).
/// - **Fase 2 (done)**: the engine threads `surfaceID` through its
///   entry points, debounce, and hook-session tracking; the bridge
///   exposes `resolveSurfaceID(matchingCwd:)`; the AgentWiring sink
///   dual-writes every transition onto Tab and the store; surface
///   teardown resets both the engine's per-surface buckets and this
///   store's entry. End-to-end coverage lives in
///   `AgentWiringDualWriteSwiftTestingTests`.
/// - **Fase 3 (pending)**: UI consumers (sidebar pills, status bar,
///   notification rings, dashboard) subscribe to this store instead of
///   reading `Tab`. Dual-write stays in place as a safety net during
///   and after the flip.
/// - **Fase 4 (pending)**: the forwarding fields on `Tab` are removed
///   and this store becomes the sole source of truth.
///
/// Treat this type as a shadow source of truth until Fase 4 ships.
/// Production writers (AgentWiring) and teardown paths
/// (MainWindowController extensions) are already aligned with it, so
/// new writers should mirror the same dual-write pattern. Readers
/// migrating over should keep a Tab-based fallback until Fase 3 is
/// complete for that consumer.
///
/// The store runs on the main actor to align with the existing agent
/// infrastructure (`AgentStateAggregator`, `AgentDashboardViewModel`)
/// which already expects main-actor isolation. All publishers emit on
/// the main thread.
@MainActor
final class AgentStatePerSurfaceStore: ObservableObject {

    /// Current per-surface states.
    ///
    /// Views should prefer `state(for:)` and `publisher(for:)` for safe
    /// access. The published dictionary is exposed for SwiftUI views that
    /// need to observe the whole map (e.g., sidebar pills showing every
    /// active agent across splits).
    @Published private(set) var states: [SurfaceID: SurfaceAgentState] = [:]

    // MARK: - Reads

    /// Returns the state for the surface, or `.idle` if the surface has
    /// never been tracked.
    func state(for surfaceID: SurfaceID) -> SurfaceAgentState {
        states[surfaceID] ?? .idle
    }

    /// Combine publisher emitting the state for a specific surface.
    ///
    /// Emits the current state synchronously on subscribe, then on every
    /// subsequent change. Duplicate states are filtered via `removeDuplicates`
    /// to avoid redundant view updates; an unchanged mutation (e.g., setting
    /// `agentToolCount` to the same value) produces no downstream emission.
    func publisher(for surfaceID: SurfaceID) -> AnyPublisher<SurfaceAgentState, Never> {
        $states
            .map { $0[surfaceID] ?? .idle }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Returns all surface IDs that currently have either an active state
    /// (`isActive == true`) or an attached detected agent.
    ///
    /// Used by the sidebar to show mini-pills for every active agent across
    /// splits of the same tab. Results are sorted deterministically by
    /// surface UUID to avoid UI reordering flicker.
    func activeSurfaceIDs() -> [SurfaceID] {
        states
            .filter { $0.value.isActive || $0.value.hasAgent }
            .keys
            .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
    }

    // MARK: - Writes

    /// Atomically mutates the state of one surface.
    ///
    /// If the surface has no entry yet, the mutation starts from `.idle`.
    /// After the closure returns, the new state is stored. Equal states
    /// still trigger a `@Published` emission, but the publisher's
    /// `removeDuplicates` operator filters them out downstream.
    func update(
        surfaceID: SurfaceID,
        mutation: (inout SurfaceAgentState) -> Void
    ) {
        var current = states[surfaceID] ?? .idle
        mutation(&current)
        states[surfaceID] = current
    }

    /// Replaces the state of a surface wholesale.
    ///
    /// Prefer `update(surfaceID:mutation:)` when only a few fields change —
    /// it preserves correctness of unchanged fields even if the caller's
    /// snapshot is stale.
    func set(surfaceID: SurfaceID, state: SurfaceAgentState) {
        states[surfaceID] = state
    }

    /// Removes a surface's state entirely.
    ///
    /// Equivalent to setting it to `.idle` for reads, but also frees the
    /// dictionary slot. Called when a surface is destroyed so stale entries
    /// do not accumulate.
    func reset(surfaceID: SurfaceID) {
        states.removeValue(forKey: surfaceID)
    }

    /// Prunes states for surfaces that are no longer alive.
    ///
    /// Typically called from the surface lifecycle (after `destroySurface`
    /// or after session restore) to avoid leaking entries for destroyed
    /// surfaces. Surfaces in `alive` are kept; all others are removed.
    func prune(alive: Set<SurfaceID>) {
        states = states.filter { alive.contains($0.key) }
    }

    /// Removes all state. Used on full reset (e.g., window close or session
    /// wipe).
    func clearAll() {
        states.removeAll()
    }
}
