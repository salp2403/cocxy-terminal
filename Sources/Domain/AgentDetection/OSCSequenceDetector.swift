// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// OSCSequenceDetector.swift - Detection layer 1: OSC sequence analysis.

import Foundation

// MARK: - OSC Sequence Detector

/// Detection layer 1 (highest confidence): Incremental parser for OSC sequences.
///
/// Processes raw terminal bytes one by one in streaming fashion. Detects
/// OSC sequences delimited by ESC ] ... BEL or ESC ] ... ESC \.
///
/// Supported sequences:
/// - **OSC 133**: Shell integration prompt marking (;A, ;B, ;C, ;D).
/// - **OSC 9**: Desktop notification (maps to completionDetected).
/// - **OSC 99**: Claude Code agent hook (maps to appropriate event).
/// - **OSC 777**: Generic notification (maps to completionDetected).
///
/// This layer has the highest priority in the detection hierarchy.
/// When an OSC signal conflicts with a pattern match or timing heuristic,
/// the OSC signal always wins.
///
/// - Performance: < 5ms latency from byte received to signal emitted.
/// - Thread safety: Uses a lock for internal buffer access.
/// - SeeAlso: ADR-004 (Agent detection strategy)
final class OSCSequenceDetector: DetectionLayer, @unchecked Sendable {

    // MARK: - Parser State

    /// States of the incremental OSC parser.
    private enum ParserState {
        /// Normal mode: scanning for ESC byte.
        case normal
        /// Received ESC (0x1B) outside an OSC, waiting for ] (0x5D).
        case escapeReceived
        /// Inside an OSC sequence, accumulating code + payload bytes.
        case readingOSC
        /// Received ESC (0x1B) while inside an OSC, waiting for \ (ST terminator).
        case oscEscapeReceived
    }

    // MARK: - Properties

    private var parserState: ParserState = .normal
    private var oscBuffer: [UInt8] = []
    private let lock = NSLock()

    /// Maximum OSC payload size to prevent unbounded memory growth.
    private static let maxOSCBufferSize = 4096

    // MARK: - DetectionLayer

    func processBytes(_ data: Data) -> [DetectionSignal] {
        lock.lock()
        defer { lock.unlock() }

        var signals: [DetectionSignal] = []

        for byte in data {
            switch parserState {
            case .normal:
                if byte == 0x1B { // ESC
                    parserState = .escapeReceived
                }

            case .escapeReceived:
                if byte == 0x5D { // ] -> start of OSC
                    parserState = .readingOSC
                    oscBuffer.removeAll(keepingCapacity: true)
                } else if byte == 0x1B {
                    // Double ESC: stay in escapeReceived
                } else {
                    parserState = .normal
                }

            case .readingOSC:
                if byte == 0x07 { // BEL terminator
                    if let signal = parseOSCPayload(oscBuffer) {
                        signals.append(signal)
                    }
                    oscBuffer.removeAll(keepingCapacity: true)
                    parserState = .normal
                } else if byte == 0x1B { // Potential ST start
                    parserState = .oscEscapeReceived
                } else {
                    oscBuffer.append(byte)
                    if oscBuffer.count > Self.maxOSCBufferSize {
                        oscBuffer.removeAll(keepingCapacity: true)
                        parserState = .normal
                    }
                }

            case .oscEscapeReceived:
                if byte == 0x5C { // backslash -> ST terminator (ESC \)
                    if let signal = parseOSCPayload(oscBuffer) {
                        signals.append(signal)
                    }
                    oscBuffer.removeAll(keepingCapacity: true)
                    parserState = .normal
                } else if byte == 0x5D { // ] -> new OSC start (previous malformed)
                    oscBuffer.removeAll(keepingCapacity: true)
                    parserState = .readingOSC
                } else if byte == 0x1B {
                    // Another ESC: stay waiting
                } else {
                    // Malformed: discard and return to normal
                    oscBuffer.removeAll(keepingCapacity: true)
                    parserState = .normal
                }
            }
        }

        return signals
    }

    // MARK: - Reset

    /// Resets the parser state and clears any partial buffer.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        parserState = .normal
        oscBuffer.removeAll(keepingCapacity: true)
    }

    // MARK: - OSC Payload Parsing

    /// Parses the accumulated OSC buffer into a `DetectionSignal`, if recognized.
    ///
    /// The buffer contains everything between ESC ] and the terminator,
    /// i.e., the numeric code and the payload separated by ;.
    private func parseOSCPayload(_ buffer: [UInt8]) -> DetectionSignal? {
        guard let semicolonIndex = buffer.firstIndex(of: 0x3B) else {
            // No semicolon: try to parse as code-only (some OSCs have no payload)
            let codeString = String(bytes: buffer, encoding: .utf8) ?? ""
            guard let code = Int(codeString) else { return nil }
            return mapOSCCodeToSignal(code: code, payload: "")
        }

        let codeBytes = Array(buffer[buffer.startIndex..<semicolonIndex])
        let payloadBytes = Array(buffer[buffer.index(after: semicolonIndex)...])

        guard let codeString = String(bytes: codeBytes, encoding: .utf8),
              let code = Int(codeString) else {
            return nil
        }

        let payload = String(bytes: payloadBytes, encoding: .utf8) ?? ""
        return mapOSCCodeToSignal(code: code, payload: payload)
    }

    /// Maps an OSC code + payload to a `DetectionSignal`.
    private func mapOSCCodeToSignal(code: Int, payload: String) -> DetectionSignal? {
        switch code {
        case 133:
            return mapOSC133(payload: payload)
        case 9:
            return DetectionSignal(
                event: .completionDetected,
                confidence: 0.9,
                source: .osc(code: 9)
            )
        case 99:
            return mapOSC99(payload: payload)
        case 777:
            return DetectionSignal(
                event: .completionDetected,
                confidence: 0.9,
                source: .osc(code: 777)
            )
        default:
            return nil
        }
    }

    /// Maps OSC 133 sub-commands to detection signals.
    ///
    /// - `;A` -> prompt start -> completionDetected (shell is showing prompt).
    /// - `;B` -> command start -> outputReceived (user executed something).
    /// - `;C` -> command output start -> outputReceived.
    /// - `;D` -> command finished -> completionDetected (or errorDetected with exit code).
    private func mapOSC133(payload: String) -> DetectionSignal? {
        let subCommand = payload.prefix(1)

        switch subCommand {
        case "A":
            return DetectionSignal(
                event: .completionDetected,
                confidence: 1.0,
                source: .osc(code: 133)
            )
        case "B", "C":
            // B = command start, C = command output start. Both indicate output.
            return DetectionSignal(
                event: .outputReceived,
                confidence: 1.0,
                source: .osc(code: 133)
            )
        case "D":
            return mapOSC133D(payload: payload)
        default:
            return nil
        }
    }

    /// Maps OSC 133;D with optional exit code.
    ///
    /// - `;D` or `;D;0` -> completionDetected.
    /// - `;D;N` (N > 0) -> errorDetected with exit code in message.
    private func mapOSC133D(payload: String) -> DetectionSignal {
        let parts = payload.split(separator: ";", maxSplits: 2)

        if parts.count >= 2, let exitCode = Int(parts[1]), exitCode != 0 {
            return DetectionSignal(
                event: .errorDetected(message: "Process exited with code \(exitCode)"),
                confidence: 1.0,
                source: .osc(code: 133)
            )
        }

        return DetectionSignal(
            event: .completionDetected,
            confidence: 1.0,
            source: .osc(code: 133)
        )
    }

    /// Maps OSC 99 (agent hook) payload to a detection signal.
    ///
    /// Expected payload: "agent-status;state" where state is:
    /// working, waiting, finished, error.
    private func mapOSC99(payload: String) -> DetectionSignal {
        let parts = payload.split(separator: ";", maxSplits: 2)

        if parts.count >= 2 {
            let status = parts[1].lowercased()
            switch status {
            case "working":
                return DetectionSignal(
                    event: .outputReceived,
                    confidence: 1.0,
                    source: .osc(code: 99)
                )
            case "waiting":
                return DetectionSignal(
                    event: .promptDetected,
                    confidence: 1.0,
                    source: .osc(code: 99)
                )
            case "finished":
                return DetectionSignal(
                    event: .completionDetected,
                    confidence: 1.0,
                    source: .osc(code: 99)
                )
            case "error":
                return DetectionSignal(
                    event: .errorDetected(message: "Agent reported error via OSC 99"),
                    confidence: 1.0,
                    source: .osc(code: 99)
                )
            default:
                break
            }
        }

        // Default: treat as completion notification
        return DetectionSignal(
            event: .completionDetected,
            confidence: 1.0,
            source: .osc(code: 99)
        )
    }
}
