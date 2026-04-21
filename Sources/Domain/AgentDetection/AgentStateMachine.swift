// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentStateMachine.swift - State machine for agent lifecycle tracking.

import Foundation
import Combine

// MARK: - Agent State Machine

/// Finite state machine that tracks the lifecycle of an AI agent in a terminal.
///
/// Each terminal surface owns one instance. The machine processes events and
/// transitions between states according to ADR-004. Invalid transitions are
/// silently ignored (logged at debug level).
///
/// Transition table (from ADR-004):
/// ```
/// idle           + agentDetected    -> agentLaunched
/// agentLaunched  + outputReceived   -> working
/// agentLaunched  + errorDetected    -> error
/// agentLaunched  + agentExited      -> idle
/// working        + promptDetected   -> waitingInput
/// working        + completionDetected -> finished
/// working        + errorDetected    -> error
/// working        + agentExited      -> idle
/// waitingInput   + userInput        -> working
/// waitingInput   + completionDetected -> finished
/// waitingInput   + errorDetected    -> error
/// waitingInput   + agentExited      -> idle
/// finished       + outputReceived   -> working
/// finished       + idleTimeout      -> idle
/// finished       + agentExited      -> idle
/// error          + outputReceived   -> working
/// error          + agentExited      -> idle
/// error          + idleTimeout      -> idle
/// ```
///
/// - SeeAlso: ADR-004 (Agent detection strategy)
@MainActor
final class AgentStateMachine: ObservableObject {

    // MARK: - State

    /// Possible states of an AI agent in a terminal session.
    enum State: String, CaseIterable, Codable, Sendable {
        /// No agent detected.
        case idle
        /// Agent binary detected but no output yet.
        case agentLaunched
        /// Agent is generating output.
        case working
        /// Agent is waiting for user input.
        case waitingInput
        /// Agent completed its task.
        case finished
        /// Agent encountered an error.
        case error
    }

    // MARK: - Event

    /// Events that can trigger state transitions.
    enum Event: Sendable {
        /// Agent binary was launched.
        case agentDetected(name: String)
        /// Terminal output was received from the agent.
        case outputReceived
        /// An input prompt was detected (e.g., "? Y/n").
        case promptDetected
        /// A task completion signal was detected.
        case completionDetected
        /// An error was detected in the agent output.
        case errorDetected(message: String)
        /// No output for the configured idle timeout.
        case idleTimeout
        /// The user typed something while agent was waiting.
        case userInput
        /// The agent process terminated.
        case agentExited
    }

    // MARK: - State Context

    /// Snapshot of a state transition, used for history and publisher emissions.
    struct StateContext {
        /// The new state after the transition.
        let state: State
        /// The state before the transition.
        let previousState: State
        /// When the transition occurred.
        let timestamp: Date
        /// Name of the detected agent, if any.
        let agentName: String?
        /// The event that caused this transition.
        let transitionEvent: Event
        /// Additional metadata (e.g., error messages).
        let metadata: [String: String]
        /// Hook session ID that triggered this transition (nil for pattern/timing).
        /// Carried per-context to avoid race conditions with receiver state.
        let hookSessionId: String?
        /// Working directory from the hook event (nil for pattern/timing).
        let hookCwd: String?
        /// Terminal surface that originated this transition, when known.
        ///
        /// Pattern and timing detectors populate this from the surface whose
        /// output produced the signal; hook-based transitions populate it
        /// after resolving the hook's `cwd` to a live surface. Remains `nil`
        /// for call sites that have not been migrated to the per-surface
        /// API (backward compatibility during the v0.1.71 transition).
        let surfaceID: SurfaceID?
    }

    // MARK: - Properties

    /// The current state of the machine.
    @Published private(set) var currentState: State = .idle

    /// Name of the currently detected agent.
    private(set) var agentName: String?

    /// History of the last transitions (capped at `maxHistoryCount`).
    private(set) var transitionHistory: [StateContext] = []

    /// Publisher that emits on every valid state transition.
    var stateChanged: AnyPublisher<StateContext, Never> {
        stateChangedSubject.eraseToAnyPublisher()
    }

    // MARK: - Private

    private let stateChangedSubject = PassthroughSubject<StateContext, Never>()
    private static let maxHistoryCount = 50

    // MARK: - Transition Table

    /// Returns the next state for a given (currentState, event) pair, or `nil`
    /// if the transition is not valid.
    private static func nextState(from state: State, on event: Event) -> State? {
        switch (state, event) {
        // idle
        case (.idle, .agentDetected):
            return .agentLaunched

        // agentLaunched
        case (.agentLaunched, .outputReceived):
            return .working
        case (.agentLaunched, .errorDetected):
            return .error
        case (.agentLaunched, .agentExited):
            return .idle

        // working
        case (.working, .promptDetected):
            return .waitingInput
        case (.working, .completionDetected):
            return .finished
        case (.working, .errorDetected):
            return .error
        case (.working, .agentExited):
            return .idle

        // waitingInput
        case (.waitingInput, .userInput):
            return .working
        case (.waitingInput, .completionDetected):
            return .finished
        case (.waitingInput, .errorDetected):
            return .error
        case (.waitingInput, .agentExited):
            return .idle

        // finished
        case (.finished, .outputReceived):
            return .working
        case (.finished, .idleTimeout):
            return .idle
        case (.finished, .agentExited):
            return .idle

        // error
        case (.error, .outputReceived):
            return .working
        case (.error, .agentExited):
            return .idle
        case (.error, .idleTimeout):
            return .idle

        default:
            return nil
        }
    }

    // MARK: - Public API

    /// Processes an event, transitioning to a new state if the transition is valid.
    ///
    /// Invalid transitions are silently ignored.
    /// - Parameter event: The event to process.
    func processEvent(_ event: Event) {
        let newState: State

        if case .agentDetected(let name) = event,
           currentState != .idle {
            // A terminal pane can legitimately start a new agent after the
            // previous one returned to the shell but before slower recovery
            // paths cleared our cached state. Treat a fresh launch banner as
            // a new session instead of preserving the stale agent identity.
            if agentName == name,
               currentState == .agentLaunched || currentState == .working || currentState == .waitingInput {
                return
            }
            newState = .agentLaunched
        } else if let next = Self.nextState(from: currentState, on: event) {
            newState = next
        } else {
            return
        }

        let previousState = currentState

        // Extract metadata from the event.
        var metadata: [String: String] = [:]
        if case .errorDetected(let message) = event {
            metadata["errorMessage"] = message
        }

        // Update agent name.
        if case .agentDetected(let name) = event {
            agentName = name
        }

        // Clear agent name when returning to idle.
        if newState == .idle {
            agentName = nil
        }

        // Transition.
        currentState = newState

        // Build context (hook metadata and surfaceID are injected by the
        // engine after transition, since the state machine itself does not
        // know which surface produced the event).
        let context = StateContext(
            state: newState,
            previousState: previousState,
            timestamp: Date(),
            agentName: agentName,
            transitionEvent: event,
            metadata: metadata,
            hookSessionId: nil,
            hookCwd: nil,
            surfaceID: nil
        )

        // Record in history (capped).
        transitionHistory.append(context)
        if transitionHistory.count > Self.maxHistoryCount {
            transitionHistory.removeFirst(transitionHistory.count - Self.maxHistoryCount)
        }

        // Emit to publisher.
        stateChangedSubject.send(context)
    }

    /// Resets the machine to idle, clearing agent name and history.
    func reset() {
        currentState = .idle
        agentName = nil
        transitionHistory.removeAll()
    }
}

// MARK: - Tab.AgentState Mapping

extension AgentStateMachine.State {

    /// Maps this state machine state to the corresponding `AgentState` used by
    /// `Tab` and the rest of the domain layer.
    ///
    /// The mapping is direct for all states. `agentLaunched` maps to
    /// `AgentState.launched` which already exists in the domain model.
    var toTabAgentState: AgentState {
        switch self {
        case .idle:
            return .idle
        case .agentLaunched:
            return .launched
        case .working:
            return .working
        case .waitingInput:
            return .waitingInput
        case .finished:
            return .finished
        case .error:
            return .error
        }
    }
}
