// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// InlineImageOSCDetector.swift - Dedicated OSC 1337 parser for large image payloads.

import Foundation

// MARK: - Inline Image OSC Detector

/// Dedicated parser for OSC 1337 inline image sequences.
///
/// Runs in parallel with `OSCSequenceDetector` but handles only OSC 1337.
/// Has a 16MB buffer (vs 4KB in the general detector) to accommodate
/// base64-encoded images from `imgcat` and similar tools.
///
/// The general `OSCSequenceDetector` discards any OSC payload exceeding
/// 4KB (`maxOSCBufferSize = 4096`). This detector intercepts OSC 1337
/// specifically and accumulates the full payload before passing it to
/// `OSC1337Parser`.
///
/// Thread safety: Uses NSLock for buffer access. Called from the PTY
/// output thread.
///
/// - SeeAlso: `OSC1337Parser` for payload parsing.
/// - SeeAlso: `InlineImageRenderer` for rendering.
/// - SeeAlso: `OSCSequenceDetector` for the general OSC parser.
final class InlineImageOSCDetector: @unchecked Sendable {

    // MARK: - Types

    /// Callback invoked when a complete OSC 1337 image payload is received.
    typealias ImageHandler = @Sendable (String) -> Void

    // MARK: - Constants

    /// Maximum payload size: 16 MB (sufficient for most inline images).
    static let maxPayloadSize = 16 * 1024 * 1024

    // MARK: - Parser State

    /// States of the incremental OSC 1337 parser.
    private enum State {
        /// Scanning for ESC byte (0x1B).
        case normal
        /// Received ESC, waiting for ] (0x5D) to start OSC.
        case escapeReceived
        /// Reading the numeric OSC code before the semicolon.
        case readingOSCCode
        /// Accumulating OSC 1337 payload after the semicolon.
        case readingPayload
        /// Received ESC inside payload, waiting for \ (ST terminator).
        case payloadEscapeReceived
    }

    // MARK: - Properties

    private var state: State = .normal
    private var codeBuffer: [UInt8] = []
    private var payloadBuffer: [UInt8] = []
    private let lock = NSLock()
    private let imageHandler: ImageHandler

    // MARK: - Initialization

    /// Creates a detector with the given image handler.
    ///
    /// - Parameter imageHandler: Called on the I/O thread when a complete
    ///   OSC 1337 payload is received. The string contains the full payload
    ///   after the "1337;" prefix (e.g., "File=inline=1:base64data").
    init(imageHandler: @escaping ImageHandler) {
        self.imageHandler = imageHandler
    }

    // MARK: - Processing

    /// Processes raw terminal output bytes looking for OSC 1337 sequences.
    ///
    /// Can be called with arbitrarily sized chunks. The parser maintains
    /// state between calls to handle sequences split across chunks.
    ///
    /// - Parameter data: Raw bytes from the PTY output.
    func processBytes(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }

        for byte in data {
            switch state {
            case .normal:
                if byte == 0x1B {
                    state = .escapeReceived
                }

            case .escapeReceived:
                if byte == 0x5D { // ]
                    state = .readingOSCCode
                    codeBuffer.removeAll(keepingCapacity: true)
                } else {
                    state = .normal
                }

            case .readingOSCCode:
                if byte == 0x3B { // ;
                    let isOSC1337 = codeBuffer == [0x31, 0x33, 0x33, 0x37]
                    if isOSC1337 {
                        state = .readingPayload
                        payloadBuffer.removeAll(keepingCapacity: true)
                    } else {
                        state = .normal
                        codeBuffer.removeAll(keepingCapacity: true)
                    }
                } else if byte >= 0x30 && byte <= 0x39 { // ASCII digit
                    codeBuffer.append(byte)
                    // "1337" is 4 digits; allow up to 5 to detect non-matching codes.
                    if codeBuffer.count > 5 {
                        state = .normal
                        codeBuffer.removeAll(keepingCapacity: true)
                    }
                } else {
                    // Non-digit, non-semicolon: not a valid OSC code.
                    state = .normal
                    codeBuffer.removeAll(keepingCapacity: true)
                }

            case .readingPayload:
                if byte == 0x07 { // BEL terminator
                    emitPayload()
                    state = .normal
                } else if byte == 0x1B {
                    state = .payloadEscapeReceived
                } else {
                    payloadBuffer.append(byte)
                    if payloadBuffer.count > Self.maxPayloadSize {
                        payloadBuffer.removeAll(keepingCapacity: true)
                        state = .normal
                    }
                }

            case .payloadEscapeReceived:
                if byte == 0x5C { // \ -> ST terminator (ESC \)
                    emitPayload()
                    state = .normal
                } else {
                    // Not ST: the ESC was part of the payload data.
                    payloadBuffer.append(0x1B)
                    payloadBuffer.append(byte)
                    state = .readingPayload
                }
            }
        }
    }

    /// Resets parser state and clears all buffers.
    ///
    /// Called when the associated tab is destroyed or during error recovery.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        state = .normal
        codeBuffer.removeAll(keepingCapacity: true)
        payloadBuffer.removeAll(keepingCapacity: true)
    }

    // MARK: - Private

    /// Converts the accumulated payload buffer to a string and invokes
    /// the image handler. Clears the buffer afterwards.
    ///
    /// Empty payloads are silently discarded.
    private func emitPayload() {
        guard !payloadBuffer.isEmpty,
              let payloadString = String(bytes: payloadBuffer, encoding: .utf8) else {
            payloadBuffer.removeAll(keepingCapacity: true)
            return
        }
        payloadBuffer.removeAll(keepingCapacity: true)
        imageHandler(payloadString)
    }
}
