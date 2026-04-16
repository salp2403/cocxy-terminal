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

    /// Debounce bucket recording the last transition seen for a given
    /// surface (or the legacy global bucket when the caller has not
    /// been migrated to per-surface routing).
    private struct DebounceBucket {
        var timestamp: Date
        var eventKey: String
    }

    /// Per-surface debounce state, keyed by the originating surface.
    ///
    /// The optional key preserves the legacy behavior of call sites that
    /// do not yet pass a surfaceID: all of those share the `nil` bucket,
    /// which reproduces the previous single global debounce exactly.
    /// Callers that thread a real surfaceID get an independent bucket,
    /// so an event on surface A never suppresses an identical event on
    /// surface B.
    private var debounceBuckets: [SurfaceID?: DebounceBucket] = [:]

    // MARK: - Testing Hooks (internal)

    /// Returns the number of distinct debounce buckets currently tracked.
    /// Exposed as `internal` for white-box tests of the per-surface
    /// debounce contract; not intended for production call sites.
    internal var _debounceBucketCountForTesting: Int {
        debounceBuckets.count
    }

    /// Returns the event key stored in the debounce bucket for a surface,
    /// or `nil` if the surface has never produced a transition. Exposed
    /// as `internal` for white-box tests.
    internal func _debounceEventKeyForTesting(
        surfaceID: SurfaceID?
    ) -> String? {
        debounceBuckets[surfaceID]?.eventKey
    }

    /// Returns the hook sessions currently active on a surface, or an
    /// empty set if the surface has no bucket. Exposed as `internal` for
    /// white-box tests of the per-surface hook-suppression contract.
    internal func _hookSessionsForTesting(
        surfaceID: SurfaceID?
    ) -> Set<String> {
        hookActiveSurfaces[surfaceID] ?? []
    }

    /// Cancellables for internal subscriptions.
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Hook Integration (Layer 0, ADR-008)

    /// Sessions that have active hook integration, keyed by the surface
    /// that owns them.
    ///
    /// When a surface has any active hook session in its bucket, its Layer
    /// 0 (hooks) signals take absolute priority over Layer 2 (pattern) and
    /// Layer 3 (timing) signals produced by the same surface. A surface
    /// without active hooks still accepts pattern/timing signals, even if
    /// some other surface has a hook session running — this is the key
    /// isolation property for multi-split terminals.
    ///
    /// Legacy call sites that do not thread a surfaceID share the `nil`
    /// bucket, which reproduces the previous global-suppression behavior
    /// for callers that have not been migrated yet.
    private(set) var hookActiveSurfaces: [SurfaceID?: Set<String>] = [:]

    /// Flat view over ``hookActiveSurfaces`` used by existing tests and
    /// external consumers that only need to know whether *any* hook
    /// session is alive anywhere in the engine. Preserved as a
    /// backward-compatible projection so the XCTest coverage of hook
    /// tracking keeps compiling unchanged.
    var hookActiveSessions: Set<String> {
        hookActiveSurfaces.values.reduce(into: Set<String>()) { $0.formUnion($1) }
    }

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
    /// dispatched to the main thread. The optional `surfaceID` is carried
    /// through to the emitted `StateContext` so subscribers can associate
    /// the transition with a specific terminal surface; callers that have
    /// not been migrated to per-surface routing pass `nil` (either
    /// directly or via the legacy `processTerminalOutput(_:)` overload
    /// provided by the `AgentDetecting` protocol extension).
    ///
    /// - Parameters:
    ///   - data: Raw bytes from the terminal.
    ///   - surfaceID: Surface whose output produced the bytes.
    nonisolated func processTerminalOutput(_ data: Data, surfaceID: SurfaceID?) {
        let oscSignals = oscDetector.processBytes(data)
        let patternSignals = patternDetector.processBytes(data)
        _ = timingDetector.processBytes(data)

        let allSignals = oscSignals + patternSignals

        guard !allSignals.isEmpty else { return }

        let resolved = resolveConflictingSignals(allSignals)

        DispatchQueue.main.async { [weak self] in
            self?.processResolvedSignal(resolved, surfaceID: surfaceID)
        }
    }

    /// Notifies the engine that the user typed input on a specific
    /// surface.
    ///
    /// Triggers the `waitingInput -> working` transition when applicable.
    /// The `surfaceID` is carried into the emitted `StateContext` so the
    /// resulting transition can be routed to the split that produced the
    /// input. Callers that have not been migrated to per-surface routing
    /// use the legacy `notifyUserInput()` overload provided by the
    /// `AgentDetecting` extension, which forwards `nil`.
    func notifyUserInput(surfaceID: SurfaceID?) {
        processResolvedSignal(
            DetectionSignal(
                event: .userInput,
                confidence: 1.0,
                source: .osc(code: 0)
            ),
            surfaceID: surfaceID
        )
    }

    /// Notifies the engine that the terminal process on a specific
    /// surface has exited.
    ///
    /// Transitions to idle regardless of current state. The `surfaceID`
    /// is carried into the emitted `StateContext` so the transition is
    /// associated with the surface whose process ended rather than with
    /// whichever split happens to be focused. Callers that have not been
    /// migrated to per-surface routing use the legacy
    /// `notifyProcessExited()` overload, which forwards `nil`.
    func notifyProcessExited(surfaceID: SurfaceID?) {
        processResolvedSignal(
            DetectionSignal(
                event: .agentExited,
                confidence: 1.0,
                source: .osc(code: 0)
            ),
            surfaceID: surfaceID
        )
    }

    /// Injects a signal directly into the engine.
    ///
    /// Used for testing and direct integration with detection layers.
    /// Must be called on the main thread.
    ///
    /// - Parameters:
    ///   - signal: The detection signal to process.
    ///   - surfaceID: Surface the signal is associated with, carried into
    ///     the emitted `StateContext`. Defaults to `nil` for backward
    ///     compatibility with legacy test call sites.
    func injectSignal(_ signal: DetectionSignal, surfaceID: SurfaceID? = nil) {
        processResolvedSignal(signal, surfaceID: surfaceID)
    }

    /// Injects multiple signals as a batch, resolving conflicts before applying.
    ///
    /// Simulates the behavior of `processTerminalOutput` where multiple
    /// layers produce signals from the same chunk of output. The winning
    /// signal is selected via confidence and source priority.
    ///
    /// - Parameters:
    ///   - signals: The batch of signals to resolve and apply.
    ///   - surfaceID: Surface the signals are associated with, carried
    ///     into the emitted `StateContext`. Defaults to `nil` for
    ///     backward compatibility with legacy test call sites.
    func injectSignalBatch(_ signals: [DetectionSignal], surfaceID: SurfaceID? = nil) {
        guard !signals.isEmpty else { return }
        let resolved = resolveConflictingSignals(signals)
        processResolvedSignal(resolved, surfaceID: surfaceID)
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
    /// Clears the state machine, every per-surface debounce bucket, and
    /// the agent name.
    func reset() {
        stateMachine.reset()
        currentState = .idle
        detectedAgentName = nil
        debounceBuckets.removeAll()
        hookActiveSurfaces.removeAll()
        oscDetector.reset()
        patternDetector.reset()
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
    /// - Parameters:
    ///   - event: The parsed hook event.
    ///   - surfaceID: Surface resolved from the event's `cwd`, when the
    ///     caller has already determined it. Defaults to `nil`; later
    ///     sub-phases of the per-surface migration will have the wiring
    ///     extension resolve the cwd to a surfaceID before dispatching.
    func processHookEvent(_ event: HookEvent, surfaceID: SurfaceID? = nil) {
        // Track active sessions per surface. Legacy call sites that pass
        // `nil` share the `nil` bucket, matching the previous
        // single-global-set behavior for untouched callers.
        switch event.type {
        case .sessionStart:
            hookActiveSurfaces[surfaceID, default: []].insert(event.sessionId)
        case .sessionEnd, .stop:
            hookActiveSurfaces[surfaceID]?.remove(event.sessionId)
            if hookActiveSurfaces[surfaceID]?.isEmpty == true {
                hookActiveSurfaces.removeValue(forKey: surfaceID)
            }
        default:
            break
        }

        // Convert hook event to detection signal
        guard let signal = mapHookEventToSignal(event) else {
            return
        }

        processResolvedSignal(
            signal,
            hookSessionId: event.sessionId,
            hookCwd: event.cwd,
            surfaceID: surfaceID
        )
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

        case .notification, .subagentStart, .subagentStop, .userPromptSubmit,
             .cwdChanged, .fileChanged:
            // These events are informational; they do not change agent state.
            // CwdChanged/FileChanged are consumed by TabManager and CodeReview
            // panels, not by the detection state machine.
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
        hookCwd: String? = nil,
        surfaceID: SurfaceID? = nil
    ) {
        // Suppress lower-layer signals when hook sessions are active on
        // the SAME surface (ADR-008). Hook signals (Layer 0) have absolute
        // priority over pattern (L2) and timing (L3) signals for the
        // surface they belong to, while other surfaces remain free to
        // produce pattern/timing transitions. When `surfaceID` is `nil`
        // (legacy callers), the `nil` bucket provides the historical
        // global-suppression behavior unchanged.
        let surfaceHasActiveHooks =
            !(hookActiveSurfaces[surfaceID]?.isEmpty ?? true)
        if surfaceHasActiveHooks {
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

        // Debounce: suppress if the same event fired on the same surface
        // within the debounce window. Callers with distinct surfaceIDs
        // have independent buckets, so a repeat event on surface A does
        // not mute a first-time event on surface B.
        if let bucket = debounceBuckets[surfaceID],
           bucket.eventKey == eventKey,
           now.timeIntervalSince(bucket.timestamp) < debounceInterval {
            return
        }

        let previousState = stateMachine.currentState
        stateMachine.processEvent(signal.event)
        let newState = stateMachine.currentState

        guard newState != previousState else {
            return
        }

        debounceBuckets[surfaceID] = DebounceBucket(
            timestamp: now,
            eventKey: eventKey
        )
        currentState = newState
        detectedAgentName = stateMachine.agentName

        timingDetector.notifyStateChanged(to: newState)
        if let agentName = stateMachine.agentName {
            timingDetector.notifyAgentChanged(to: agentName)
        }

        if let lastContext = stateMachine.transitionHistory.last {
            // Enrich with hook metadata so subscribers can identify the
            // session and tab without reading mutable receiver state. The
            // `surfaceID` passed by the caller replaces the state
            // machine's default of `nil` so downstream subscribers can
            // route the transition to the specific terminal surface that
            // produced it. When `surfaceID` is `nil` (legacy call sites),
            // subscribers fall back to tab-level resolution.
            let enriched = AgentStateMachine.StateContext(
                state: lastContext.state,
                previousState: lastContext.previousState,
                timestamp: lastContext.timestamp,
                agentName: lastContext.agentName,
                transitionEvent: lastContext.transitionEvent,
                metadata: lastContext.metadata,
                hookSessionId: hookSessionId,
                hookCwd: hookCwd,
                surfaceID: surfaceID
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
