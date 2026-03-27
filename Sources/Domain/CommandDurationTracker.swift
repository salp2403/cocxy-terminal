// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CommandDurationTracker.swift - Extracts OSC 133 command lifecycle events from terminal output.

import Foundation

// MARK: - Command Duration Tracker

/// Lightweight incremental parser that detects OSC 133 ;B (command start)
/// and OSC 133 ;D (command finished) in raw terminal output bytes.
///
/// Unlike `OSCSequenceDetector` (which maps OSC 133 to generic detection signals
/// for the agent system), this tracker emits specific `OSCNotification` values
/// for command lifecycle tracking.
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

    // MARK: - Parser State

    private enum ParserState {
        case normal
        case escapeReceived
        case readingOSC
        case oscEscapeReceived
    }

    // MARK: - Properties

    private var parserState: ParserState = .normal
    private var oscBuffer: [UInt8] = []
    private let lock = NSLock()
    private let onNotification: @Sendable (OSCNotification) -> Void

    /// Maximum OSC payload size to prevent unbounded memory growth.
    private static let maxOSCBufferSize = 256

    // MARK: - Initialization

    /// Creates a tracker that invokes the handler for each command lifecycle event.
    ///
    /// - Parameter onNotification: Called with `.commandStarted` or `.commandFinished`
    ///   when the corresponding OSC 133 sequence is detected.
    init(onNotification: @escaping @Sendable (OSCNotification) -> Void) {
        self.onNotification = onNotification
    }

    // MARK: - Processing

    /// Processes raw terminal output bytes, looking for OSC 133 ;B and ;D sequences.
    ///
    /// - Parameter data: Raw bytes from the PTY output.
    func processBytes(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        for byte in data {
            switch parserState {
            case .normal:
                if byte == 0x1B {
                    parserState = .escapeReceived
                }

            case .escapeReceived:
                if byte == 0x5D {
                    parserState = .readingOSC
                    oscBuffer.removeAll(keepingCapacity: true)
                } else if byte == 0x1B {
                    // Double ESC: stay in escapeReceived.
                } else {
                    parserState = .normal
                }

            case .readingOSC:
                if byte == 0x07 {
                    handleOSCPayload()
                    oscBuffer.removeAll(keepingCapacity: true)
                    parserState = .normal
                } else if byte == 0x1B {
                    parserState = .oscEscapeReceived
                } else {
                    oscBuffer.append(byte)
                    if oscBuffer.count > Self.maxOSCBufferSize {
                        oscBuffer.removeAll(keepingCapacity: true)
                        parserState = .normal
                    }
                }

            case .oscEscapeReceived:
                if byte == 0x5C {
                    handleOSCPayload()
                    oscBuffer.removeAll(keepingCapacity: true)
                    parserState = .normal
                } else if byte == 0x5D {
                    oscBuffer.removeAll(keepingCapacity: true)
                    parserState = .readingOSC
                } else if byte == 0x1B {
                    // Another ESC: stay waiting.
                } else {
                    oscBuffer.removeAll(keepingCapacity: true)
                    parserState = .normal
                }
            }
        }
    }

    // MARK: - Private

    /// Parses the accumulated OSC buffer and emits a notification if it matches 133;B or 133;D.
    private func handleOSCPayload() {
        guard let semicolonIndex = oscBuffer.firstIndex(of: 0x3B) else { return }

        let codeBytes = Array(oscBuffer[oscBuffer.startIndex..<semicolonIndex])
        guard let codeString = String(bytes: codeBytes, encoding: .utf8),
              codeString == "133" else {
            return
        }

        let payloadBytes = Array(oscBuffer[oscBuffer.index(after: semicolonIndex)...])
        guard let payload = String(bytes: payloadBytes, encoding: .utf8),
              !payload.isEmpty else {
            return
        }

        let subCommand = payload.prefix(1)

        switch subCommand {
        case "B":
            onNotification(.commandStarted)

        case "D":
            let exitCode = parseExitCode(from: payload)
            onNotification(.commandFinished(exitCode: exitCode))

        default:
            break
        }
    }

    /// Extracts the exit code from an OSC 133;D payload (e.g., "D;127" -> 127).
    private func parseExitCode(from payload: String) -> Int? {
        let parts = payload.split(separator: ";", maxSplits: 2)
        guard parts.count >= 2, let code = Int(parts[1]) else {
            return nil
        }
        return code
    }
}
