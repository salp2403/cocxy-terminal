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
/// Appending data is O(n) where n is the number of new lines. Trimming
/// old lines is O(k) where k is the number of lines to remove.
///
/// - SeeAlso: `ScrollbackSearchBarViewModel` (consumer of this buffer)
/// - SeeAlso: `MainWindowController` (wires output handler to this buffer)
@MainActor
final class TerminalOutputBuffer {

    // MARK: - Constants

    /// Default maximum number of lines to retain.
    static let defaultMaxLineCount = 10_000

    // MARK: - State

    /// The maximum number of lines this buffer retains.
    let maxLineCount: Int

    /// The buffered lines, oldest first.
    private(set) var lines: [String] = []

    /// Partial line data accumulated between newlines.
    private var partialLine: String = ""

    // MARK: - Computed

    /// The current number of complete lines in the buffer.
    var lineCount: Int {
        lines.count
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
    /// The data is decoded as UTF-8, split on newlines, and ANSI escape
    /// codes are stripped. Partial lines (data not ending with a newline)
    /// are accumulated until the next newline arrives.
    ///
    /// - Parameter data: Raw bytes from the PTY output.
    func append(_ data: Data) {
        guard let rawText = String(data: data, encoding: .utf8) else { return }

        let cleanedText = Self.stripANSIEscapeCodes(rawText)
        let combined = partialLine + cleanedText

        var newLines = combined.components(separatedBy: "\n")

        // The last element is either empty (if data ended with \n)
        // or a partial line that needs to be accumulated.
        partialLine = newLines.removeLast()

        // Strip carriage returns from each line.
        let trimmedLines = newLines.map { line in
            line.replacingOccurrences(of: "\r", with: "")
        }

        lines.append(contentsOf: trimmedLines)

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
        partialLine = ""
    }

    // MARK: - ANSI Stripping

    /// Regex pattern matching ANSI escape sequences.
    ///
    /// Covers CSI sequences (ESC[...X), OSC sequences (ESC]...BEL/ST),
    /// and simple two-byte sequences (ESC + single char).
    private static let ansiPattern = #"\x1B(?:\[[0-9;?]*[A-Za-z]|\][^\x07\x1B]*(?:\x07|\x1B\\)|[A-Za-z])"#

    private static let ansiRegex: NSRegularExpression? = try? NSRegularExpression(pattern: ansiPattern)

    /// Strips ANSI escape codes from the given string.
    ///
    /// - Parameter text: Raw terminal text potentially containing escape codes.
    /// - Returns: The text with all ANSI sequences removed.
    static func stripANSIEscapeCodes(_ text: String) -> String {
        guard let regex = ansiRegex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
