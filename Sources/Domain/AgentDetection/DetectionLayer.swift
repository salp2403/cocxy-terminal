// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DetectionLayer.swift - Shared protocol and types for the 3-layer detection system.

import Foundation

// MARK: - Detection Layer Protocol

/// Contract for each of the three detection layers (OSC, patterns, timing).
///
/// Each layer processes raw bytes from terminal output and produces
/// zero or more `DetectionSignal` values that the engine uses to
/// drive the `AgentStateMachine`.
///
/// - SeeAlso: ADR-004 (Agent detection strategy)
protocol DetectionLayer: AnyObject, Sendable {
    /// Processes a chunk of raw terminal output and returns detection signals.
    ///
    /// Implementations must be safe to call from background threads.
    /// - Parameter data: Raw bytes from the terminal.
    /// - Returns: Zero or more detection signals, ordered by occurrence.
    func processBytes(_ data: Data) -> [DetectionSignal]
}

// MARK: - Detection Signal

/// A signal emitted by a detection layer when it identifies a state-relevant event.
///
/// Signals carry the event to feed into the state machine, a confidence score,
/// the source that generated the signal, and a timestamp.
struct DetectionSignal: Sendable {
    /// The event to feed into the `AgentStateMachine`.
    let event: AgentStateMachine.Event
    /// Confidence score from 0.0 (no confidence) to 1.0 (certain).
    let confidence: Double
    /// Which detection subsystem generated this signal.
    let source: DetectionSource
    /// When this signal was generated.
    let timestamp: Date

    init(
        event: AgentStateMachine.Event,
        confidence: Double,
        source: DetectionSource,
        timestamp: Date = Date()
    ) {
        self.event = event
        self.confidence = min(max(confidence, 0.0), 1.0)
        self.source = source
        self.timestamp = timestamp
    }
}

// MARK: - Detection Source

/// Identifies which detection subsystem generated a `DetectionSignal`.
///
/// Priority order (highest first): hook > osc > pattern > timing.
/// Added `.hook` case in v2.0 (ADR-008) for Layer 0.
enum DetectionSource: Sendable, Equatable {
    /// Signal from Claude Code hook events (Layer 0, highest priority).
    /// Carries the hook event type name.
    case hook(event: String)
    /// Signal from OSC sequence parsing. Carries the OSC code number.
    case osc(code: Int)
    /// Signal from regex pattern matching. Carries the pattern name.
    case pattern(name: String)
    /// Signal from timing heuristics.
    case timing
}
