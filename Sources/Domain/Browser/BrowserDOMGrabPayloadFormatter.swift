// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserDOMGrabPayloadFormatter.swift - Pure helper that renders a
// `BrowserDOMGrabPayload` as the multi-line text injected into the
// active terminal pane.

import Foundation

/// Renders a captured `BrowserDOMGrabPayload` as the multi-line text
/// the surface lifecycle pastes into the active terminal pane.
///
/// The format is intentionally line-addressable so a receiving
/// terminal-aware CLI can pick up the selector / URL / screenshot path
/// with simple prefix matches (`Page:`, `URL:`, `Selector:`, `Text:`,
/// `Screenshot:`). Optional fields are omitted from the output rather
/// than left blank — a blank line in the middle of the payload would
/// break the line-prefix detection on the receiving end.
///
/// The formatter is a pure value type so the rendering logic stays
/// trivially unit-testable in isolation from AppKit, WebKit, and the
/// PTY bridge.
enum BrowserDOMGrabPayloadFormatter {

    /// Maximum number of characters of `visibleText` rendered before
    /// the formatter truncates with an ellipsis. Sized so a paste-like
    /// dump of a long article body cannot blow past a typical agent
    /// prompt's context window in a single grab.
    static let maxVisibleTextLength: Int = 500

    /// Renders the payload as the multi-line text the terminal pane
    /// receives. The output always ends with a trailing newline so
    /// the agent prompter sees the message as a complete line block.
    ///
    /// - Parameter payload: Captured grab to format.
    /// - Returns: Multi-line text ready for `bridge.writeBytes`.
    static func format(_ payload: BrowserDOMGrabPayload) -> String {
        var lines: [String] = []
        lines.append("--- Browser DOM grab ---")
        lines.append("Page: \(singleLine(payload.pageTitle))")
        lines.append("URL: \(payload.pageURL.absoluteString)")
        lines.append("Selector: \(singleLine(payload.selector))")

        let trimmed = payload.visibleText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if !trimmed.isEmpty {
            lines.append("Text: \(truncated(trimmed))")
        }

        if let screenshot = payload.screenshotPath {
            lines.append("Screenshot: \(screenshot.path)")
        }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Private helpers

    /// Collapses any embedded newline into a single space so the
    /// formatter's line-addressable contract holds even when a page
    /// title or selector contains a literal `\n`.
    private static func singleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    /// Truncates the trimmed visible text above the limit and appends
    /// an ellipsis marker so the consumer can tell the value was cut.
    /// Leaves shorter values untouched so equality with the original
    /// text is preserved when no truncation was needed.
    private static func truncated(_ trimmed: String) -> String {
        guard trimmed.count > maxVisibleTextLength else { return trimmed }
        return trimmed.prefix(maxVisibleTextLength) + "..."
    }
}
