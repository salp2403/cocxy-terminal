// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SurfaceInputDropMonitor.swift - Detects repeated PTY input drops on
// a per-surface basis so the user can be notified about a stuck pane.

import Foundation

// MARK: - Input delivery event

/// Outcome of a single PTY-input call (`sendKeyEvent` / `sendText`).
///
/// The bridge emits one of these values for every keystroke or injected
/// text packet. Consumers use the stream to decide whether a surface is
/// currently accepting input.
enum InputDeliveryEvent: Sendable, Equatable {
    /// Byte payload was written through the surface's PTY.
    case delivered

    /// The byte payload was dropped. `reason` helps diagnose whether the
    /// surface is unknown to the bridge (teardown race) or whether the
    /// PTY itself rejected the write (fd closed, process gone).
    case dropped(InputDropReason)
}

/// Why a keystroke / text injection did not reach the PTY.
///
/// Kept as a distinct enum (rather than piggybacking onto
/// `AgentStateResetReason`) so the monitor's telemetry can stay focused
/// on the input hot path without pulling in agent-lifecycle concepts.
enum InputDropReason: String, Sendable, Equatable, CaseIterable {
    /// `CocxyCoreBridge.surfaces[surfaceID]` did not contain an entry
    /// for the target surface. Usually indicates that the surface was
    /// torn down while the caller still held the `SurfaceID` (rare,
    /// observed during Fase B smoke after an agent-lifecycle recovery
    /// interacted badly with a zsh autocorrect prompt).
    case surfaceMissing

    /// The C-side PTY write call returned zero bytes written. The
    /// bridge still has the surface, but the kernel rejected the write
    /// (file descriptor closed, child process exited, etc.).
    case ptyWriteFailed
}

// MARK: - Monitor

/// Per-surface tracker that raises an alert when a pane silently drops
/// multiple keystrokes in a row.
///
/// `CocxyCoreBridge.sendKeyEvent` / `sendText` sometimes return without
/// delivering bytes to the PTY — either because the surface entry is
/// missing from the bridge map or because the PTY write itself failed.
/// The Fase B smoke test surfaced a scenario where those drops stack
/// up silently: the user keeps typing, the terminal stays visually
/// focused, but nothing reaches the shell. Rather than leaving the user
/// guessing, the monitor counts consecutive drops and invokes its
/// handler once a configurable threshold is reached, so the caller can
/// pop a lightweight banner guiding the user to close the stuck pane
/// with Cmd+Shift+W.
///
/// ## Threading
///
/// The monitor is isolated to the main actor because the observed input
/// path (`TerminalEngine.sendKeyEvent` / `sendText`) already runs on
/// the main actor, and because the handler needs to touch UI state.
/// That keeps the implementation free of locks.
///
/// ## State shape
///
/// Each surface owns a single `DropState` entry that tracks the current
/// consecutive drop count, the last observed reason (for diagnostics),
/// and a `notified` flag so the handler fires **once** per stuck
/// episode. A successful delivery (`.delivered`) resets both fields so
/// a second stuck episode can still surface a notification.
///
/// ## Cancellation
///
/// `clear(surfaceID:)` removes the entry entirely. Teardown paths in
/// `MainWindowController+SurfaceLifecycle` and `SplitActions` call it
/// alongside the watchdog / probe cancellation so the next surface
/// assigned that ID (rare, UUID-based) starts from a clean slate.
///
/// - SeeAlso: `CocxyCoreBridge.sendKeyEvent(_:to:)`
/// - SeeAlso: `CocxyCoreBridge.sendText(_:to:)`
@MainActor
final class SurfaceInputDropMonitor {

    /// Default consecutive-drop threshold. Chosen at 3 because the
    /// user typically pressing a key twice without seeing output still
    /// feels normal (a slow PTY, a modifier-only combo). Three in a
    /// row is strong enough evidence to surface the notification.
    static let defaultThreshold: Int = 3

    /// Per-surface tracker. A nil entry means "no drops observed since
    /// the last successful delivery (or since the surface was cleared)".
    private struct DropState {
        var consecutiveDrops: Int = 0
        var lastReason: InputDropReason?
        var notified: Bool = false
    }

    private var states: [SurfaceID: DropState] = [:]

    /// Upper bound on consecutive drops before the handler fires.
    /// Immutable after init so tests can pin specific thresholds and
    /// production callers rely on the default.
    let threshold: Int

    /// Handler invoked when `threshold` consecutive drops have been
    /// recorded for a surface and the monitor has not yet notified for
    /// this episode. Runs on the main actor.
    var onStuckPane: (@MainActor (SurfaceID, InputDropReason) -> Void)?

    init(
        threshold: Int = SurfaceInputDropMonitor.defaultThreshold,
        onStuckPane: (@MainActor (SurfaceID, InputDropReason) -> Void)? = nil
    ) {
        precondition(threshold > 0, "threshold must be positive")
        self.threshold = threshold
        self.onStuckPane = onStuckPane
    }

    // MARK: - Recording

    /// Records a drop for a surface. Increments the consecutive count
    /// and, when the threshold is reached for the first time in the
    /// current episode, invokes `onStuckPane` with the triggering
    /// reason.
    ///
    /// Subsequent drops within the same episode are tracked (the count
    /// keeps climbing) but do **not** re-fire the handler. A
    /// `recordDelivery(...)` call ends the episode, clears the counter,
    /// and allows the next stuck run to notify again.
    func recordDrop(surfaceID: SurfaceID, reason: InputDropReason) {
        var state = states[surfaceID] ?? DropState()
        state.consecutiveDrops += 1
        state.lastReason = reason
        states[surfaceID] = state

        guard state.consecutiveDrops >= threshold, !state.notified else { return }
        states[surfaceID]?.notified = true
        onStuckPane?(surfaceID, reason)
    }

    /// Records a successful PTY delivery for a surface. Resets the
    /// consecutive drop counter and clears the `notified` flag so a
    /// fresh stuck episode can still fire the handler.
    ///
    /// Cheap in the common case: if the surface has no tracker entry,
    /// this is a dictionary lookup and a no-op.
    func recordDelivery(surfaceID: SurfaceID) {
        guard states[surfaceID] != nil else { return }
        states.removeValue(forKey: surfaceID)
    }

    // MARK: - Cleanup

    /// Removes the tracker entry for a surface. Called from teardown
    /// paths so a recycled `SurfaceID` cannot inherit stale drop state.
    func clear(surfaceID: SurfaceID) {
        states.removeValue(forKey: surfaceID)
    }

    /// Removes every tracker entry. Called during full window teardown.
    func clearAll() {
        states.removeAll()
    }

    // MARK: - Introspection

    /// Consecutive drops currently recorded for a surface. Returns `0`
    /// when no entry exists.
    func consecutiveDrops(for surfaceID: SurfaceID) -> Int {
        states[surfaceID]?.consecutiveDrops ?? 0
    }

    /// Whether the monitor has already notified for the current stuck
    /// episode on the given surface. Intended for tests.
    func hasNotified(for surfaceID: SurfaceID) -> Bool {
        states[surfaceID]?.notified ?? false
    }

    /// Number of surfaces currently being tracked. Intended for tests.
    var trackedCount: Int { states.count }
}
