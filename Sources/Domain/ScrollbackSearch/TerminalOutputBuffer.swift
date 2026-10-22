// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalOutputBuffer.swift - Circular buffer for terminal output lines.

import Foundation

// MARK: - Terminal Output Buffer

/// Circular buffer that captures terminal output for scrollback search.
///
/// Receives raw `Data` from the PTY output handler, splits it into lines,
/// strips ANSI escape codes, and stores up to `maxLineCount` lines.
/// Older lines are discarded when the buffer is full.
///
/// ## Threading
///
/// This class is `@MainActor` because it is updated from the main-thread
/// wakeup callback and read from the search bar ViewModel (also on main).
///
/// ## Performance
///
/// Appending data is O(n) where n is the number of input bytes. Incomplete
/// lines retain only their most recent 64 KiB, so sustained output without a
/// newline cannot grow memory or per-chunk copy cost without bound. Trimming
/// old lines is O(k) where k is the number of lines to remove.
///
/// - SeeAlso: `ScrollbackSearchBarViewModel` (consumer of this buffer)
/// - SeeAlso: `MainWindowController` (wires output handler to this buffer)
@MainActor
final class TerminalOutputBuffer {

    // MARK: - Constants

    /// Default maximum number of lines to retain.
    static let defaultMaxLineCount = 10_000

    /// Maximum UTF-8 bytes retained for a line that has not terminated yet.
    static let maxPartialLineByteCount = 64 * 1_024

    // MARK: - State

    /// The maximum number of lines this buffer retains.
    let maxLineCount: Int

    /// The buffered lines, oldest first.
    private(set) var lines: [String] = []

    /// Tail of the partial line accumulated between newlines.
    private var partialLine = BoundedByteTail(capacity: maxPartialLineByteCount)

    /// Stateful scanner so escape sequences split across PTY chunks remain hidden.
    private var ansiScanner = ANSIByteScanner()

    // MARK: - Computed

    /// The current number of complete lines in the buffer.
    var lineCount: Int {
        lines.count
    }

    /// Retained bytes for the incomplete line, exposed for deterministic bounds tests.
    var retainedPartialLineByteCount: Int {
        partialLine.count
    }

    // MARK: - Initialization

    /// Creates a buffer with the given maximum line count.
    ///
    /// - Parameter maxLineCount: Maximum lines to retain. Defaults to 10,000.
    init(maxLineCount: Int = TerminalOutputBuffer.defaultMaxLineCount) {
        self.maxLineCount = maxLineCount
    }

    // MARK: - Append

    /// Appends raw terminal output data to the buffer.
    ///
    /// ANSI escape codes are stripped while scanning the raw bytes. Complete
    /// lines are decoded as UTF-8, while an unterminated line retains only its
    /// newest `maxPartialLineByteCount` bytes.
    ///
    /// - Parameter data: Raw bytes from the PTY output.
    func append(_ data: Data) {
        var newLines: [String] = []

        for byte in data {
            guard let visibleByte = ansiScanner.consume(byte) else { continue }

            switch visibleByte {
            case 0x0A:
                newLines.append(Self.decodeLine(partialLine.orderedBytes()))
                partialLine.removeAll()
            case 0x0D:
                // CR is cursor movement in terminal output, not searchable text.
                continue
            default:
                partialLine.append(visibleByte)
            }
        }

        lines.append(contentsOf: newLines)

        // Trim oldest lines if over capacity.
        if lines.count > maxLineCount {
            let excess = lines.count - maxLineCount
            lines.removeFirst(excess)
        }
    }

    // MARK: - Clear

    /// Removes all buffered lines and resets the partial line accumulator.
    func clear() {
        lines.removeAll()
        partialLine.removeAll()
        ansiScanner.reset()
    }

    // MARK: - ANSI Stripping

    /// Strips ANSI escape codes from the given string.
    ///
    /// - Parameter text: Raw terminal text potentially containing escape codes.
    /// - Returns: The text with all ANSI sequences removed.
    static func stripANSIEscapeCodes(_ text: String) -> String {
        var scanner = ANSIByteScanner()
        var visibleBytes: [UInt8] = []
        visibleBytes.reserveCapacity(text.utf8.count)

        for byte in text.utf8 {
            if let visibleByte = scanner.consume(byte) {
                visibleBytes.append(visibleByte)
            }
        }

        return String(decoding: visibleBytes, as: UTF8.self)
    }

    private static func decodeLine(_ bytes: [UInt8]) -> String {
        // Head truncation can land inside a multi-byte scalar. Dropping only
        // leading continuation bytes preserves valid UTF-8 for the retained tail.
        let firstScalarStart = bytes.firstIndex(where: { ($0 & 0xC0) != 0x80 }) ?? bytes.endIndex
        return String(decoding: bytes[firstScalarStart...], as: UTF8.self)
    }
}

// MARK: - Bounded Partial Line

private struct BoundedByteTail {
    private let capacity: Int
    private var storage: [UInt8] = []
    private var nextWriteIndex = 0

    var count: Int { storage.count }

    init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    mutating func append(_ byte: UInt8) {
        guard storage.count == capacity else {
            storage.append(byte)
            return
        }

        storage[nextWriteIndex] = byte
        nextWriteIndex = (nextWriteIndex + 1) % capacity
    }

    func orderedBytes() -> [UInt8] {
        guard storage.count == capacity, nextWriteIndex > 0 else {
            return storage
        }

        var ordered = Array(storage[nextWriteIndex...])
        ordered.append(contentsOf: storage[..<nextWriteIndex])
        return ordered
    }

    mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        nextWriteIndex = 0
    }
}

// MARK: - ANSI Scanner

private struct ANSIByteScanner {
    private enum State: Equatable {
        case text
        case escape
        case escapeIntermediate
        case controlSequence
        case operatingSystemCommand
        case operatingSystemCommandEscape
        case stringControl
        case stringControlEscape
    }

    /// Prevents malformed, unterminated controls from swallowing output forever.
    private static let maxControlSequenceByteCount = 64 * 1_024

    private var state: State = .text
    private var controlSequenceByteCount = 0

    mutating func consume(_ byte: UInt8) -> UInt8? {
        if state != .text {
            controlSequenceByteCount += 1
            if controlSequenceByteCount > Self.maxControlSequenceByteCount {
                reset()
                return consume(byte)
            }
        }

        switch state {
        case .text:
            if byte == 0x1B {
                begin(.escape)
                return nil
            }
            return byte

        case .escape:
            switch byte {
            case 0x1B:
                begin(.escape)
            case 0x5B:
                state = .controlSequence
            case 0x5D:
                state = .operatingSystemCommand
            case 0x50, 0x58, 0x5E, 0x5F:
                state = .stringControl
            case 0x20...0x2F:
                state = .escapeIntermediate
            default:
                reset()
            }
            return nil

        case .escapeIntermediate:
            switch byte {
            case 0x1B:
                begin(.escape)
                return nil
            case 0x20...0x2F:
                return nil
            case 0x30...0x7E:
                reset()
                return nil
            default:
                reset()
                return byte
            }

        case .controlSequence:
            switch byte {
            case 0x1B:
                begin(.escape)
                return nil
            case 0x20...0x3F:
                return nil
            case 0x40...0x7E:
                reset()
                return nil
            default:
                reset()
                return byte
            }

        case .operatingSystemCommand:
            switch byte {
            case 0x07:
                reset()
            case 0x1B:
                state = .operatingSystemCommandEscape
            default:
                break
            }
            return nil

        case .operatingSystemCommandEscape:
            switch byte {
            case 0x5C, 0x07:
                reset()
            case 0x1B:
                break
            default:
                state = .operatingSystemCommand
            }
            return nil

        case .stringControl:
            switch byte {
            case 0x1B:
                state = .stringControlEscape
            default:
                break
            }
            return nil

        case .stringControlEscape:
            switch byte {
            case 0x5C:
                reset()
            case 0x1B:
                break
            default:
                state = .stringControl
            }
            return nil
        }
    }

    mutating func reset() {
        state = .text
        controlSequenceByteCount = 0
    }

    private mutating func begin(_ newState: State) {
        state = newState
        controlSequenceByteCount = 1
    }
}
