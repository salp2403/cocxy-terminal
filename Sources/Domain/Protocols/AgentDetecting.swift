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
    /// Thread-safe: can be called from any thread. Output is distributed
    /// to all three detection layers. Resulting signals are resolved and
    /// dispatched to the main thread.
    ///
    /// - Parameter data: Raw bytes from the terminal output.
    nonisolated func processTerminalOutput(_ data: Data)

    /// Notifies the engine that the user has submitted input (e.g., pressed Enter).
    ///
    /// Triggers the `waitingInput -> working` transition when the
    /// agent was waiting for user input.
    func notifyUserInput()

    /// Notifies the engine that the terminal process has exited.
    ///
    /// Transitions to idle regardless of current state.
    func notifyProcessExited()

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
    /// The full command that launched the agent.
    let launchCommand: String
    /// Timestamp when the agent was first detected.
    let startedAt: Date
}
