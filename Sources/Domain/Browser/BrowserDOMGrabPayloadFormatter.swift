// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserDOMGrabPayloadFormatter.swift - Pure helper that renders a
// `BrowserDOMGrabPayload` for explicit review in Rich Input.

import Foundation

/// Renders a captured `BrowserDOMGrabPayload` as multi-line review text.
///
/// The format is intentionally line-addressable so users and terminal-aware
/// CLIs can identify the selector, URL, and screenshot path
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

    /// Renders the payload as multi-line text for the Rich Input composer.
    /// The output always ends with a trailing newline so an eventual user
    /// submission reaches the terminal as a complete line block.
    ///
    /// - Parameter payload: Captured grab to format.
    /// - Returns: Sanitized multi-line text ready for explicit review.
    static func format(_ payload: BrowserDOMGrabPayload) -> String {
        var lines: [String] = []
        lines.append("--- Browser DOM grab ---")
        lines.append("Page: \(singleLine(payload.pageTitle))")
        lines.append("URL: \(singleLine(payload.pageURL.absoluteString))")
        lines.append("Selector: \(singleLine(payload.selector))")

        let trimmed = sanitizedText(
            payload.visibleText,
            preservingLineBreaks: true
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            lines.append("Text: \(truncated(trimmed))")
        }

        if let screenshot = payload.screenshotPath {
            lines.append("Screenshot: \(singleLine(screenshot.path))")
        }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Private helpers

    /// Collapses any embedded newline into a single space so the
    /// formatter's line-addressable contract holds even when a page
    /// title or selector contains a literal `\n`.
    private static func singleLine(_ value: String) -> String {
        sanitizedText(value, preservingLineBreaks: false)
    }

    /// Removes terminal controls and directional formatting before untrusted
    /// page text reaches a native review surface. Newlines remain only in the
    /// visible-text field; all other fields stay line-addressable.
    private static func sanitizedText(
        _ value: String,
        preservingLineBreaks: Bool
    ) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(normalized.unicodeScalars.count)
        for scalar in normalized.unicodeScalars {
            switch scalar.value {
            case 0x09:
                scalars.append(" ")
            case 0x0A, 0x2028, 0x2029:
                scalars.append(preservingLineBreaks ? "\n" : " ")
            case 0x00...0x1F, 0x7F...0x9F:
                continue
            case 0x061C, 0x200E...0x200F, 0x202A...0x202E, 0x2066...0x2069:
                continue
            default:
                scalars.append(scalar)
            }
        }
        return String(scalars)
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
