// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandDurationTracker.swift - Extracts OSC 133 command lifecycle events from terminal output.

import Foundation

// MARK: - Command Duration Tracker

/// Lightweight adapter that maps OSC 133 ;B (command start) and
/// OSC 133 ;D (command finished) block events into host notifications.
///
/// Unlike `OSCSequenceDetector` (which maps OSC 133 to generic detection signals
/// for the agent system), this tracker emits specific `OSCNotification` values.
/// The underlying parser lives in `BlockOSCDetector` so command-block boundary
/// handling has one dedicated implementation.
///
/// ## Usage
///
/// Wire the tracker into the terminal output handler:
/// ```swift
/// let tracker = CommandDurationTracker { notification in
///     handleOSCNotification(notification)
/// }
/// bridge.setOutputHandler(for: surfaceID) { data in
///     tracker.processBytes(data)
/// }
/// ```
///
/// ## Threading
///
/// `processBytes` is called from background threads (PTY reader).
/// The notification handler is invoked on the caller's thread.
/// The consumer is responsible for dispatching to the main thread.
///
/// - SeeAlso: `OSCSequenceDetector` (agent detection layer)
final class CommandDurationTracker: @unchecked Sendable {
    private let detector: BlockOSCDetector

    // MARK: - Initialization

    /// Creates a tracker that invokes the handler for each command lifecycle event.
    ///
    /// - Parameter onNotification: Called with `.commandStarted` or `.commandFinished`
    ///   when the corresponding OSC 133 sequence is detected.
    init(onNotification: @escaping @Sendable (OSCNotification) -> Void) {
        self.detector = BlockOSCDetector { event in
            switch event {
            case .commandStarted:
                onNotification(.commandStarted)
            case .commandFinished(let exitCode):
                onNotification(.commandFinished(exitCode: exitCode))
            case .promptStarted, .commandExecuted:
                break
            }
        }
    }

    // MARK: - Processing

    /// Processes raw terminal output bytes, looking for OSC 133 ;B and ;D sequences.
    ///
    /// - Parameter data: Raw bytes from the PTY output.
    func processBytes(_ data: Data) {
        detector.processBytes(data)
    }
}
