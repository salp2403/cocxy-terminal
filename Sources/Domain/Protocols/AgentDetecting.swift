// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentDetecting.swift - Contract for the agent detection engine.

import Foundation
import Combine

// MARK: - Agent Detection Protocol

/// Engine that detects AI agent state by analyzing terminal output.
///
/// The detection strategy is hybrid (ADR-004) with three layers ordered by
/// reliability:
///
/// 1. **OSC sequences** (high confidence) — explicit notifications from hooks.
/// 2. **Pattern matching** (medium confidence) — regex on terminal output.
/// 3. **Timing heuristics** (low confidence) — fallback based on output gaps.
///
/// OSC signals always override pattern and timing signals when they conflict.
///
/// State changes are published via Combine (`stateChanged` publisher) for
/// loose coupling with multiple consumers (Dashboard, Timeline, StatusBar).
///
/// - SeeAlso: ADR-004 (Agent detection strategy)
/// - SeeAlso: ARCHITECTURE.md Section 7.2
@MainActor
protocol AgentDetecting: AnyObject {

    /// Processes a chunk of raw output from the terminal PTY.
    ///
    /// Legacy entry point preserved for backward compatibility. The default
    /// implementation routes the call to the surfaceID-aware variant with
    /// `nil`, which makes the engine behave exactly as before (no
    /// surface-level routing).
    ///
    /// New call sites should prefer
    /// ``processTerminalOutput(_:surfaceID:)``.
    ///
    /// - Parameter data: Raw bytes from the terminal output.
    nonisolated func processTerminalOutput(_ data: Data)

    /// Processes a chunk of raw output from the terminal PTY, associating
    /// any resulting state transition with the originating surface.
    ///
    /// Thread-safe: can be called from any thread. Output is distributed
    /// to all three detection layers; resulting signals are resolved and
    /// dispatched to the main thread. When a non-nil `surfaceID` is
    /// provided, it is carried into `StateContext.surfaceID` so downstream
    /// subscribers can route the transition to a specific terminal
    /// surface instead of the focused tab.
    ///
    /// - Parameters:
    ///   - data: Raw bytes from the terminal output.
    ///   - surfaceID: Surface whose output produced the bytes, or `nil`
    ///     when the caller has not been migrated to per-surface routing.
    nonisolated func processTerminalOutput(_ data: Data, surfaceID: SurfaceID?)

    /// Notifies the engine that the user has submitted input (e.g.,
    /// pressed Enter).
    ///
    /// Legacy entry point preserved for backward compatibility. The
    /// default implementation routes to the surfaceID-aware variant with
    /// `nil`, which matches the previous behavior where the user-input
    /// signal was applied to the shared engine state without surface
    /// context.
    ///
    /// New call sites should prefer ``notifyUserInput(surfaceID:)``.
    func notifyUserInput()

    /// Notifies the engine that the user has submitted input, associating
    /// the resulting transition with the originating terminal surface.
    ///
    /// Triggers the `waitingInput -> working` transition when the surface
    /// was waiting for input. Carrying the surfaceID ensures the
    /// transition is attributed to the correct split once subscribers
    /// start routing per-surface.
    ///
    /// - Parameter surfaceID: Surface whose user submitted the input, or
    ///   `nil` when the caller has not been migrated to per-surface
    ///   routing.
    func notifyUserInput(surfaceID: SurfaceID?)

    /// Notifies the engine that the terminal process has exited.
    ///
    /// Legacy entry point preserved for backward compatibility. The
    /// default implementation routes to the surfaceID-aware variant with
    /// `nil`, which matches the previous behavior where process-exit
    /// signals affected the shared engine state.
    ///
    /// New call sites should prefer ``notifyProcessExited(surfaceID:)``.
    func notifyProcessExited()

    /// Notifies the engine that the terminal process for a specific
    /// surface has exited.
    ///
    /// Transitions to idle regardless of current state. Carrying the
    /// surfaceID ensures the transition is associated with the surface
    /// whose process ended, not with whichever split happens to be
    /// focused at the moment of emission.
    ///
    /// - Parameter surfaceID: Surface whose process exited, or `nil`
    ///   when the caller has not been migrated to per-surface routing.
    func notifyProcessExited(surfaceID: SurfaceID?)

    /// Pauses the timing detector when the terminal window loses focus.
    ///
    /// Prevents false idle timeout signals while the user is in another app.
    func pauseTimingDetector()

    /// Resumes the timing detector when the terminal window gains focus.
    ///
    /// Restarts idle timers if the agent is in a state that requires them.
    func resumeTimingDetector()

    /// Sets a per-agent idle timeout override on the timing detector.
    ///
    /// - Parameters:
    ///   - agentName: The agent identifier (e.g., "aider").
    ///   - timeout: The idle timeout in seconds.
    func setAgentTimeout(agentName: String, timeout: TimeInterval)

    /// Resets the engine to its initial state.
    ///
    /// Clears the state machine, debounce state, and the agent name.
    func reset()

    /// The current state of the agent lifecycle.
    var currentState: AgentStateMachine.State { get }

    /// Name of the currently detected agent, if any.
    var detectedAgentName: String? { get }

    /// Publisher that emits on every valid state transition.
    var stateChanged: AnyPublisher<AgentStateMachine.StateContext, Never> { get }
}

// MARK: - Backward-compatible Defaults

extension AgentDetecting {
    /// Default bridge from the legacy entry point to the surfaceID-aware
    /// variant. Existing callers that pass only `Data` continue to work
    /// unchanged and produce `nil` surfaceIDs in the emitted context.
    nonisolated func processTerminalOutput(_ data: Data) {
        processTerminalOutput(data, surfaceID: nil)
    }

    /// Default bridge from the legacy ``notifyUserInput()`` entry point
    /// to the surfaceID-aware variant, preserving behavior for callers
    /// that have not been migrated.
    func notifyUserInput() {
        notifyUserInput(surfaceID: nil)
    }

    /// Default bridge from the legacy ``notifyProcessExited()`` entry
    /// point to the surfaceID-aware variant, preserving behavior for
    /// callers that have not been migrated.
    func notifyProcessExited() {
        notifyProcessExited(surfaceID: nil)
    }
}

// MARK: - Agent State

/// Possible states of an AI agent in a terminal session.
///
/// State machine transitions (from ADR-004):
/// ```
/// Idle ──[agent command detected]──> Launched
/// Launched ──[first output]──> Working
/// Working ──[question pattern OR OSC notify]──> WaitingInput
/// Working ──[OSC 133 prompt OR idle timeout]──> Finished
/// Working ──[error pattern]──> Error
/// WaitingInput ──[user input]──> Working
/// Finished ──[new agent command]──> Working
/// Error ──[OSC 133 prompt]──> Idle
/// ```
enum AgentState: String, Codable, Sendable {
    /// No AI agent is active in this terminal.
    case idle
    /// An agent command was detected but has not produced output yet.
    case launched
    /// The agent is actively producing output.
    case working
    /// The agent is waiting for user input (e.g., a confirmation prompt).
    case waitingInput
    /// The agent has finished its task.
    case finished
    /// The agent encountered an error.
    case error
}

// MARK: - Detected Agent

/// Information about a detected AI agent.
struct DetectedAgent: Codable, Equatable, Sendable {
    /// Short identifier of the agent (e.g., "claude", "codex", "aider").
    let name: String
    /// Human-readable display name shown in the UI.
    let displayName: String
    /// The full command that launched the agent.
    let launchCommand: String
    /// Timestamp when the agent was first detected.
    let startedAt: Date

    init(
        name: String,
        displayName: String? = nil,
        launchCommand: String,
        startedAt: Date
    ) {
        self.name = name
        self.displayName = displayName ?? name
        self.launchCommand = launchCommand
        self.startedAt = startedAt
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case displayName
        case launchCommand
        case startedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? name
        let launchCommand = try container.decode(String.self, forKey: .launchCommand)
        let startedAt = try container.decode(Date.self, forKey: .startedAt)
        self.init(
            name: name,
            displayName: displayName,
            launchCommand: launchCommand,
            startedAt: startedAt
        )
    }
}
