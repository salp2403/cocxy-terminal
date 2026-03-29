// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentDetectionEngine.swift - Orchestrator for the 3-layer detection system.

import Foundation
import Combine

// MARK: - Agent Detection Engine

/// Orchestrator that combines the three detection layers into a unified engine.
///
/// Priority hierarchy: OSC (layer 1) > Patterns (layer 2) > Timing (layer 3).
///
/// This class:
/// - Maintains one `AgentStateMachine` instance.
/// - Routes terminal output to all three detection layers.
/// - Resolves conflicts between signals using confidence and source priority.
/// - Applies debounce to suppress rapid duplicate transitions.
/// - Publishes state changes on the main thread via Combine.
///
/// ## Threading Model
///
/// - `processTerminalOutput` is called from background threads (PTY reader).
/// - The three detection layers process on their own threads with locks.
/// - Resolved signals are dispatched to the main thread for state machine processing.
/// - All `@Published` properties and `stateChanged` emit on the main thread.
///
/// ## Conflict Resolution
///
/// When multiple signals arrive from different layers in the same output chunk:
/// 1. The signal with the highest confidence wins.
/// 2. At equal confidence, source priority applies: OSC > pattern > timing.
///
/// ## Debounce
///
/// If two consecutive signals would produce the same state transition
/// (same event type) within the debounce interval, the second is suppressed.
/// Signals that produce a different transition are always processed immediately.
///
/// - SeeAlso: ADR-004 (Agent detection strategy)
/// - SeeAlso: `AgentDetecting` protocol
@MainActor
final class AgentDetectionEngineImpl: ObservableObject, AgentDetecting {

    // MARK: - Published State

    /// The current state of the agent lifecycle.
    @Published private(set) var currentState: AgentStateMachine.State = .idle

    /// Name of the currently detected agent, if any.
    @Published private(set) var detectedAgentName: String?

    // MARK: - Publishers

    /// Publisher that emits on every valid state transition.
    var stateChanged: AnyPublisher<AgentStateMachine.StateContext, Never> {
        stateChangedSubject.eraseToAnyPublisher()
    }

    // MARK: - Private Properties

    private let stateMachine = AgentStateMachine()
    private let oscDetector = OSCSequenceDetector()
    private let patternDetector: PatternMatchingDetector
    private let timingDetector: TimingHeuristicsDetector
    private let stateChangedSubject = PassthroughSubject<AgentStateMachine.StateContext, Never>()

    /// The debounce interval in seconds. Duplicate transitions within this
    /// window are suppressed.
    private let debounceInterval: TimeInterval

    /// Timestamp of the last successful state transition.
    private var lastTransitionTimestamp: Date = .distantPast

    /// The event key that caused the last transition, for dedup comparison.
    private var lastTransitionEventKey: String?

    /// Cancellables for internal subscriptions.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Hook Integration (Layer 0, ADR-008)

    /// Sessions that have active hook integration.
    ///
    /// When a session is in this set, its signals come from Layer 0 (hooks)
    /// with absolute priority. Layers 1-3 remain operational for fallback
    /// and logging, but their signals are superseded by hook signals.
    private(set) var hookActiveSessions: Set<String> = []

    // MARK: - Initialization

    /// Creates an AgentDetectionEngineImpl with pre-compiled agent configurations.
    ///
    /// - Parameters:
    ///   - compiledConfigs: Pre-compiled agent detection configurations.
    ///   - debounceInterval: Minimum seconds between identical transitions. Default 0.2.
    init(
        compiledConfigs: [CompiledAgentConfig],
        debounceInterval: TimeInterval = 0.2
    ) {
        self.debounceInterval = debounceInterval
        self.patternDetector = PatternMatchingDetector(
            configs: compiledConfigs,
            requiredConsecutiveMatches: 2,
            cooldownInterval: 1.0,
            maxLineBuffer: 5
        )
        self.timingDetector = TimingHeuristicsDetector(
            defaultIdleTimeout: 5.0,
            sustainedOutputThreshold: 2.0
        )
        setupTimingDetectorCallback()
    }

    // MARK: - Public API

    /// Processes raw terminal output bytes from the PTY reader.
    ///
    /// Thread-safe: can be called from any thread. Output is distributed
    /// to all three detection layers. Resulting signals are resolved and
    /// dispatched to the main thread.
    ///
    /// - Parameter data: Raw bytes from the terminal.
    nonisolated func processTerminalOutput(_ data: Data) {
        let oscSignals = oscDetector.processBytes(data)
        let patternSignals = patternDetector.processBytes(data)
        _ = timingDetector.processBytes(data)

        let allSignals = oscSignals + patternSignals

        guard !allSignals.isEmpty else { return }

        let resolved = resolveConflictingSignals(allSignals)

        DispatchQueue.main.async { [weak self] in
            self?.processResolvedSignal(resolved)
        }
    }

    /// Notifies the engine that the user typed input.
    ///
    /// Triggers the `waitingInput -> working` transition when applicable.
    func notifyUserInput() {
        processResolvedSignal(DetectionSignal(
            event: .userInput,
            confidence: 1.0,
            source: .osc(code: 0)
        ))
    }

    /// Notifies the engine that the terminal process has exited.
    ///
    /// Transitions to idle regardless of current state.
    func notifyProcessExited() {
        processResolvedSignal(DetectionSignal(
            event: .agentExited,
            confidence: 1.0,
            source: .osc(code: 0)
        ))
    }

    /// Injects a signal directly into the engine.
    ///
    /// Used for testing and direct integration with detection layers.
    /// Must be called on the main thread.
    ///
    /// - Parameter signal: The detection signal to process.
    func injectSignal(_ signal: DetectionSignal) {
        processResolvedSignal(signal)
    }

    /// Injects multiple signals as a batch, resolving conflicts before applying.
    ///
    /// Simulates the behavior of `processTerminalOutput` where multiple
    /// layers produce signals from the same chunk of output. The winning
    /// signal is selected via confidence and source priority.
    ///
    /// - Parameter signals: The batch of signals to resolve and apply.
    func injectSignalBatch(_ signals: [DetectionSignal]) {
        guard !signals.isEmpty else { return }
        let resolved = resolveConflictingSignals(signals)
        processResolvedSignal(resolved)
    }

    /// Pauses the timing detector when the terminal window loses focus.
    ///
    /// Prevents false idle timeout signals while the user is in another app.
    func pauseTimingDetector() {
        timingDetector.pause()
    }

    /// Resumes the timing detector when the terminal window gains focus.
    ///
    /// Restarts idle timers if the agent is in a state that requires them.
    func resumeTimingDetector() {
        timingDetector.resume()
    }

    /// Sets a per-agent idle timeout override on the timing detector.
    ///
    /// Agents with slower response times (e.g., Aider, Gemini CLI) need
    /// longer timeouts to avoid false completion signals.
    ///
    /// - Parameters:
    ///   - agentName: The agent identifier (e.g., "aider").
    ///   - timeout: The idle timeout in seconds.
    func setAgentTimeout(agentName: String, timeout: TimeInterval) {
        timingDetector.setAgentTimeout(agentName: agentName, timeout: timeout)
    }

    /// Resets the engine to its initial state.
    ///
    /// Clears the state machine, debounce state, and the agent name.
    func reset() {
        stateMachine.reset()
        currentState = .idle
        detectedAgentName = nil
        lastTransitionTimestamp = .distantPast
        lastTransitionEventKey = nil
        oscDetector.reset()
        timingDetector.notifyStateChanged(to: .idle)
    }

    /// Updates the pattern detector with new compiled agent configurations.
    ///
    /// Called when `agents.toml` is hot-reloaded. The pattern detector resets
    /// its sliding window state to avoid matching stale patterns against the
    /// new config. Also updates per-agent idle timeout overrides on the
    /// timing detector.
    ///
    /// - Parameter configs: The newly compiled agent configurations.
    func updateAgentConfigs(_ configs: [CompiledAgentConfig]) {
        patternDetector.updateConfigs(configs)
        for compiled in configs {
            if let timeout = compiled.config.idleTimeoutOverride {
                timingDetector.setAgentTimeout(
                    agentName: compiled.config.name,
                    timeout: timeout
                )
            }
        }
    }

    // MARK: - Hook Event Processing (Layer 0)

    /// Processes a hook event from Claude Code, converting it to a detection signal.
    ///
    /// Hook events (Layer 0) have absolute priority over layers 1-3.
    /// The engine tracks which sessions have active hooks and uses that
    /// to suppress lower-layer signals for those sessions.
    ///
    /// Mapping (ADR-008):
    /// - SessionStart -> agentDetected (registers agent)
    /// - SessionEnd -> agentExited (deregisters agent)
    /// - Stop -> completionDetected (agent finished)
    /// - PreToolUse/PostToolUse -> outputReceived (agent working)
    /// - PostToolUseFailure -> errorDetected
    /// - TeammateIdle -> promptDetected (waiting for input)
    /// - TaskCompleted -> completionDetected
    /// - Notification/SubagentStart/SubagentStop/UserPromptSubmit -> no state change
    ///
    /// - Parameter event: The parsed hook event.
    func processHookEvent(_ event: HookEvent) {
        // Track active sessions
        switch event.type {
        case .sessionStart:
            hookActiveSessions.insert(event.sessionId)
        case .sessionEnd, .stop:
            hookActiveSessions.remove(event.sessionId)
        default:
            break
        }

        // Convert hook event to detection signal
        guard let signal = mapHookEventToSignal(event) else {
            return
        }

        processResolvedSignal(signal, hookSessionId: event.sessionId, hookCwd: event.cwd)
    }

    /// Maps a hook event type to the corresponding detection signal.
    ///
    /// Returns `nil` for event types that do not trigger state transitions
    /// (e.g., Notification, SubagentStart/Stop, UserPromptSubmit).
    private func mapHookEventToSignal(_ event: HookEvent) -> DetectionSignal? {
        let source = DetectionSource.hook(event: event.type.rawValue)
        let confidence: Double = 1.0

        switch event.type {
        case .sessionStart:
            let agentName: String
            if case .sessionStart(let data) = event.data {
                agentName = data.agentType ?? "claude-code"
            } else {
                agentName = "claude-code"
            }
            return DetectionSignal(
                event: .agentDetected(name: agentName),
                confidence: confidence,
                source: source
            )

        case .sessionEnd:
            return DetectionSignal(
                event: .agentExited,
                confidence: confidence,
                source: source
            )

        case .stop:
            return DetectionSignal(
                event: .completionDetected,
                confidence: confidence,
                source: source
            )

        case .preToolUse, .postToolUse:
            return DetectionSignal(
                event: .outputReceived,
                confidence: confidence,
                source: source
            )

        case .postToolUseFailure:
            let errorMessage: String
            if case .toolUse(let data) = event.data {
                errorMessage = data.error ?? "Tool use failed"
            } else {
                errorMessage = "Tool use failed"
            }
            return DetectionSignal(
                event: .errorDetected(message: errorMessage),
                confidence: confidence,
                source: source
            )

        case .teammateIdle:
            return DetectionSignal(
                event: .promptDetected,
                confidence: confidence,
                source: source
            )

        case .taskCompleted:
            return DetectionSignal(
                event: .completionDetected,
                confidence: confidence,
                source: source
            )

        case .notification, .subagentStart, .subagentStop, .userPromptSubmit:
            // These events are informational; they do not change agent state.
            return nil
        }
    }

    // MARK: - Signal Processing

    /// Processes a resolved signal through debounce and state machine.
    ///
    /// The debounce logic suppresses duplicate events (same event key)
    /// arriving within the debounce interval. Different events always
    /// pass through immediately.
    private func processResolvedSignal(
        _ signal: DetectionSignal,
        hookSessionId: String? = nil,
        hookCwd: String? = nil
    ) {
        // Suppress lower-layer signals when hook sessions are active (ADR-008).
        // Hook signals (Layer 0) have absolute priority over pattern (L2) and
        // timing (L3) detections to prevent conflicting state transitions.
        if !hookActiveSessions.isEmpty {
            switch signal.source {
            case .hook:
                break
            case .osc:
                break // OSC signals are terminal-level, not agent-specific
            case .pattern, .timing:
                return
            }
        }

        let eventKey = Self.eventKey(for: signal.event)
        let now = Date()
        let timeSinceLastTransition = now.timeIntervalSince(lastTransitionTimestamp)

        // Debounce: suppress if same event within interval
        if eventKey == lastTransitionEventKey
            && timeSinceLastTransition < debounceInterval {
            return
        }

        let previousState = stateMachine.currentState
        stateMachine.processEvent(signal.event)
        let newState = stateMachine.currentState

        guard newState != previousState else { return }

        lastTransitionTimestamp = now
        lastTransitionEventKey = eventKey
        currentState = newState
        detectedAgentName = stateMachine.agentName

        timingDetector.notifyStateChanged(to: newState)
        if let agentName = stateMachine.agentName {
            timingDetector.notifyAgentChanged(to: agentName)
        }

        if let lastContext = stateMachine.transitionHistory.last {
            // Enrich with hook metadata so subscribers can identify the
            // session and tab without reading mutable receiver state.
            let enriched = AgentStateMachine.StateContext(
                state: lastContext.state,
                previousState: lastContext.previousState,
                timestamp: lastContext.timestamp,
                agentName: lastContext.agentName,
                transitionEvent: lastContext.transitionEvent,
                metadata: lastContext.metadata,
                hookSessionId: hookSessionId,
                hookCwd: hookCwd
            )
            stateChangedSubject.send(enriched)
        }
    }

    // MARK: - Conflict Resolution

    /// Resolves conflicting signals by selecting the winner.
    ///
    /// Rules:
    /// 1. Highest confidence wins.
    /// 2. At equal confidence, source priority: OSC > pattern > timing.
    ///
    /// - Parameter signals: The competing signals.
    /// - Returns: The winning signal.
    nonisolated private func resolveConflictingSignals(_ signals: [DetectionSignal]) -> DetectionSignal {
        guard let first = signals.first else {
            preconditionFailure("resolveConflictingSignals called with empty array")
        }
        guard signals.count > 1 else { return first }

        return signals.max(by: { lhs, rhs in
            if lhs.confidence != rhs.confidence {
                return lhs.confidence < rhs.confidence
            }
            return sourcePriority(lhs.source) < sourcePriority(rhs.source)
        }) ?? first
    }

    /// Returns a numeric priority for a detection source.
    /// Higher value = higher priority.
    /// Layer 0 (hook) has absolute priority per ADR-008.
    nonisolated private func sourcePriority(_ source: DetectionSource) -> Int {
        switch source {
        case .hook:
            return 4
        case .osc:
            return 3
        case .pattern:
            return 2
        case .timing:
            return 1
        }
    }

    /// Returns a stable string key for an event, used for debounce comparison.
    ///
    /// Events with the same key are considered duplicates for debounce purposes.
    /// The key strips variable data (error messages, agent names) to group
    /// logically identical events together.
    private static func eventKey(for event: AgentStateMachine.Event) -> String {
        switch event {
        case .agentDetected:
            return "agentDetected"
        case .outputReceived:
            return "outputReceived"
        case .promptDetected:
            return "promptDetected"
        case .completionDetected:
            return "completionDetected"
        case .errorDetected:
            return "errorDetected"
        case .idleTimeout:
            return "idleTimeout"
        case .userInput:
            return "userInput"
        case .agentExited:
            return "agentExited"
        }
    }

    // MARK: - Internal Setup

    /// Configures the timing detector's async callback to feed signals
    /// back into the engine on the main thread.
    private func setupTimingDetectorCallback() {
        timingDetector.onSignalEmitted = { [weak self] signal in
            DispatchQueue.main.async { [weak self] in
                self?.processResolvedSignal(signal)
            }
        }
    }
}
