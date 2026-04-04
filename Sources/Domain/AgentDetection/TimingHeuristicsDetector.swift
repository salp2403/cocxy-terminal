// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TimingHeuristicsDetector.swift - Detection layer 3: Timing-based heuristics.

import Foundation

// MARK: - Timing Heuristics Detector

/// Detection layer 3 (lowest confidence): Fallback timing-based heuristics.
///
/// Rules:
/// - If state is `working` and no output for > `idle_timeout` seconds -> `completionDetected`.
/// - If output is sustained for > `sustained_output_threshold` seconds -> `outputReceived`.
/// - Only acts as fallback: does NOT override OSC or pattern signals.
/// - Does NOT generate transitions from `idle` (inactive terminal stays idle).
/// - Resets timer on new output.
/// - Pauses when terminal loses focus.
///
/// Uses `DispatchSourceTimer` for efficient scheduling (not Foundation `Timer`).
///
/// - Thread safety: All mutable state is accessed on a dedicated serial queue.
/// - SeeAlso: ADR-004 (Agent detection strategy)
final class TimingHeuristicsDetector: DetectionLayer, @unchecked Sendable {

    private static let queueKey = DispatchSpecificKey<UUID>()

    // MARK: - Properties

    private let defaultIdleTimeout: TimeInterval
    private let sustainedOutputThreshold: TimeInterval
    private let queue: DispatchQueue
    private let queueID = UUID()
    private let outputStateLock = NSLock()

    /// Callback for async signal emission (timers fire outside processBytes).
    var onSignalEmitted: ((DetectionSignal) -> Void)?

    /// The current state of the state machine, as communicated by the engine.
    private var currentState: AgentStateMachine.State = .idle

    /// Name of the currently detected agent, for per-agent timeout lookup.
    private var currentAgentName: String?

    /// Per-agent idle timeout overrides.
    private var agentTimeouts: [String: TimeInterval] = [:]

    /// Timestamp of the most recent output received.
    private var lastOutputTimestamp: Date?

    /// Timestamp of when sustained output started.
    private var sustainedOutputStart: Date?

    /// Whether the detector is paused (terminal unfocused).
    private var isPaused: Bool = false

    /// Whether a sustained output signal has already been emitted for the current burst.
    private var sustainedOutputSignalEmitted: Bool = false

    /// The idle timer source.
    private var idleTimer: DispatchSourceTimer?

    /// Whether the detector has been stopped.
    private var isStopped: Bool = false

    /// Fast-path flag read from `processBytes` to avoid enqueuing work when
    /// the current state cannot emit any timing-based heuristics.
    private var acceptsOutput: Bool = false

    // MARK: - Initialization

    /// Creates a TimingHeuristicsDetector with configurable thresholds.
    ///
    /// - Parameters:
    ///   - defaultIdleTimeout: Seconds of no output before emitting completionDetected.
    ///     Default 5.0 seconds.
    ///   - sustainedOutputThreshold: Seconds of continuous output before confirming working.
    ///     Default 2.0 seconds.
    init(
        defaultIdleTimeout: TimeInterval = 5.0,
        sustainedOutputThreshold: TimeInterval = 2.0
    ) {
        self.defaultIdleTimeout = max(0.01, defaultIdleTimeout)
        self.sustainedOutputThreshold = max(0.01, sustainedOutputThreshold)
        self.queue = DispatchQueue(
            label: "com.cocxy.timing-heuristics",
            qos: .utility
        )
        self.queue.setSpecific(key: Self.queueKey, value: queueID)
    }

    deinit {
        performSynchronizedTeardown()
    }

    // MARK: - DetectionLayer

    /// Processes bytes and manages timers.
    ///
    /// Returns empty array synchronously. Signals are emitted asynchronously
    /// via the `onSignalEmitted` callback when timers fire.
    func processBytes(_ data: Data) -> [DetectionSignal] {
        outputStateLock.lock()
        let shouldHandleOutput = acceptsOutput
        outputStateLock.unlock()

        guard shouldHandleOutput else { return [] }

        queue.async { [weak self] in
            self?.handleNewOutput()
        }
        return []
    }

    // MARK: - State Notifications

    /// Called by the engine when the state machine transitions.
    ///
    /// The timing detector needs to know the current state to decide
    /// whether to start/stop/reset timers.
    func notifyStateChanged(to newState: AgentStateMachine.State) {
        setAcceptsOutput(shouldAcceptOutput(for: newState))
        queue.async { [weak self] in
            self?.currentState = newState
            self?.updateOutputAcceptance()
            self?.evaluateTimerState()
        }
    }

    /// Called when the detected agent changes.
    func notifyAgentChanged(to agentName: String?) {
        queue.async { [weak self] in
            self?.currentAgentName = agentName
        }
    }

    /// Sets a per-agent idle timeout override.
    func setAgentTimeout(agentName: String, timeout: TimeInterval) {
        queue.async { [weak self] in
            self?.agentTimeouts[agentName] = timeout
        }
    }

    // MARK: - Focus Control

    /// Pauses the detector (terminal lost focus).
    func pause() {
        setAcceptsOutput(false)
        queue.async { [weak self] in
            self?.isPaused = true
            self?.updateOutputAcceptance()
            self?.cancelIdleTimer()
        }
    }

    /// Resumes the detector (terminal gained focus).
    func resume() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.isPaused = false
            self.updateOutputAcceptance()
            // Restart timer if we were in a state that needs it
            if self.canEmitIdleTimeout() {
                self.lastOutputTimestamp = Date()
                self.startIdleTimer()
            }
        }
    }

    /// Stops the detector and cleans up all timers.
    ///
    /// After this call returns, no more signals will be emitted and all
    /// timers have been cancelled. Safe to call from any thread.
    ///
    /// Uses `queue.sync` to guarantee cleanup is complete before returning.
    /// This makes it safe to immediately nil the detector after calling stop().
    func stop() {
        performSynchronizedTeardown()
    }

    // MARK: - Private

    /// Handles new output arriving from the terminal.
    private func handleNewOutput() {
        guard !isStopped, !isPaused else { return }

        let now = Date()
        lastOutputTimestamp = now

        // Track sustained output for confirming working state
        if sustainedOutputStart == nil {
            sustainedOutputStart = now
            sustainedOutputSignalEmitted = false
        } else if !sustainedOutputSignalEmitted,
                  let start = sustainedOutputStart,
                  now.timeIntervalSince(start) >= sustainedOutputThreshold {
            // Sustained output threshold reached
            sustainedOutputSignalEmitted = true

            if currentState == .agentLaunched {
                emitSignal(DetectionSignal(
                    event: .outputReceived,
                    confidence: 0.3,
                    source: .timing,
                    timestamp: now
                ))
            }
        }

        // Restart idle timer on every new output
        if canEmitIdleTimeout() {
            startIdleTimer()
        }
    }

    /// Evaluates whether timers should be running based on current state.
    private func evaluateTimerState() {
        if canEmitIdleTimeout() {
            // If we have recent output, keep the timer running
            if lastOutputTimestamp != nil {
                startIdleTimer()
            }
        } else {
            cancelIdleTimer()
        }

        // Reset sustained output tracking on state change
        sustainedOutputStart = nil
        sustainedOutputSignalEmitted = false
    }

    /// Returns whether the current state allows idle timeout emission.
    ///
    /// States `working`, `waitingInput`, and `finished` can transition via idle
    /// timeout. The `finished + idleTimeout → idle` transition is needed to
    /// return to idle after an agent completes without an explicit exit signal.
    private func canEmitIdleTimeout() -> Bool {
        switch currentState {
        case .working, .waitingInput, .finished:
            return true
        case .idle, .agentLaunched, .error:
            return false
        }
    }

    /// Starts or restarts the idle timer.
    private func startIdleTimer() {
        cancelIdleTimer()

        guard !isPaused, !isStopped else { return }

        let timeout = effectiveIdleTimeout()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { [weak self] in
            self?.handleIdleTimerFired()
        }
        idleTimer = timer
        timer.resume()
    }

    /// Cancels the current idle timer.
    ///
    /// Must be called from within the detector's serial queue to avoid
    /// races with the timer's event handler.
    private func cancelIdleTimer() {
        idleTimer?.cancel()
        idleTimer = nil
    }

    /// Handles the idle timer firing.
    private func handleIdleTimerFired() {
        guard !isStopped, !isPaused else { return }
        guard canEmitIdleTimeout() else { return }

        // Verify that enough time has actually passed since last output
        let timeout = effectiveIdleTimeout()
        if let lastOutput = lastOutputTimestamp,
           Date().timeIntervalSince(lastOutput) >= timeout * 0.9 {
            emitSignal(DetectionSignal(
                event: .completionDetected,
                confidence: 0.3,
                source: .timing
            ))

            // Reset sustained output tracking
            sustainedOutputStart = nil
            sustainedOutputSignalEmitted = false
        }
    }

    /// Returns the effective idle timeout, considering per-agent overrides.
    private func effectiveIdleTimeout() -> TimeInterval {
        if let agentName = currentAgentName,
           let override = agentTimeouts[agentName] {
            return override
        }
        return defaultIdleTimeout
    }

    /// Emits a signal via the callback.
    private func emitSignal(_ signal: DetectionSignal) {
        onSignalEmitted?(signal)
    }

    private func performSynchronizedTeardown() {
        if DispatchQueue.getSpecific(key: Self.queueKey) == queueID {
            tearDownOnQueue()
            return
        }

        // Cleanup must run on the detector queue so the timer cannot outlive
        // teardown, but syncing from the same queue would trap. We detect that
        // case above and tear down inline instead.
        queue.sync {
            tearDownOnQueue()
        }
    }

    private func tearDownOnQueue() {
        isStopped = true
        updateOutputAcceptance()
        cancelIdleTimer()
        onSignalEmitted = nil
    }

    private func updateOutputAcceptance() {
        let shouldAcceptOutput = shouldAcceptOutput(for: currentState) && !isPaused && !isStopped
        setAcceptsOutput(shouldAcceptOutput)
    }

    private func shouldAcceptOutput(for state: AgentStateMachine.State) -> Bool {
        switch state {
        case .agentLaunched, .working, .waitingInput, .finished:
            return true
        case .idle, .error:
            return false
        }
    }

    private func setAcceptsOutput(_ newValue: Bool) {
        outputStateLock.lock()
        acceptsOutput = newValue
        outputStateLock.unlock()
    }
}
