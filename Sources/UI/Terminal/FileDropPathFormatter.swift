// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// FileDropPathFormatter.swift - Pure helper that formats dropped file
// URLs as the shell-safe text payload `CocxyCoreView.performDragOperation`
// injects into the active PTY.

import Foundation

/// Formats one or more dropped file URLs into a shell-safe payload string
/// suitable for PTY injection.
///
/// macOS's canonical drag-and-drop shell convention prefixes whitespace
/// and shell metacharacters with a backslash. Terminal-aware CLIs rely
/// on that convention to recognise the dropped item as a single
/// argument: an unescaped path containing spaces splits at the shell
/// level into multiple words and path-detection logic only ever sees the
/// first fragment.
///
/// The formatter is a pure value type so it stays trivially testable in
/// isolation from AppKit, NSPasteboard, or the bridge.
enum FileDropPathFormatter {

    /// Builds the shell-safe payload string for the given drop. Empty
    /// input returns an empty string so the caller can early-out without
    /// reaching the PTY.
    ///
    /// Multiple URLs are joined by a single space; each path is escaped
    /// independently so a space in one path cannot leak into the next.
    static func format(_ urls: [URL]) -> String {
        urls.map { escape($0.path) }.joined(separator: " ")
    }

    /// Backslash-escapes whitespace and shell metacharacters in a single
    /// path using the canonical macOS shell-escape convention. Backslashes
    /// themselves are escaped FIRST so the prefixes the formatter writes
    /// for the remaining characters do not get re-escaped on a later pass.
    static func escape(_ path: String) -> String {
        // The order matters: replace `\` with `\\` BEFORE prepending a
        // backslash to any other character. Otherwise the escapes the
        // formatter writes for spaces / parens / quotes would themselves
        // be matched by a later backslash-escape pass and the output
        // would no longer round-trip through the shell.
        var escaped = path.replacingOccurrences(of: "\\", with: "\\\\")
        for character in shellMetacharacters {
            escaped = escaped.replacingOccurrences(
                of: String(character),
                with: "\\" + String(character)
            )
        }
        return escaped
    }

    /// Characters that change shell parsing when present without a
    /// backslash. Captures the full set so a user dragging a file into
    /// Cocxy sees byte-for-byte the same payload they would receive from
    /// any other native macOS terminal.
    private static let shellMetacharacters: [Character] = [
        " ", "\t",
        "(", ")",
        "[", "]",
        "{", "}",
        "<", ">",
        "|", "&", ";",
        "$", "`",
        "'", "\"",
        "*", "?",
        "#", "!",
    ]
}
