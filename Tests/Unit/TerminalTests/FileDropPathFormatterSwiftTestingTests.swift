// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Unit coverage for `FileDropPathFormatter`, the pure helper that turns
/// dropped file URLs into the shell-safe text payload the terminal pane
/// injects into the active PTY.
///
/// The contract the formatter must honour mirrors the canonical macOS
/// drag-and-drop shell-escape convention, so terminal-aware CLIs detect
/// the dropped item as a single argument and run their image / file
/// recognition logic against it. Without escaping, a path containing
/// spaces splits into multiple words at the shell level and the CLI sees
/// fragments instead of the full file.
@Suite("FileDropPathFormatter")
struct FileDropPathFormatterSwiftTestingTests {

    // MARK: - Empty input

    @Test("empty input produces an empty string")
    func emptyInputProducesEmptyString() {
        let result = FileDropPathFormatter.format([])

        #expect(result == "")
    }

    // MARK: - Single path, no metacharacters

    @Test("a single path without shell metacharacters is left untouched")
    func plainPathIsUntouched() {
        let url = URL(fileURLWithPath: "/Users/dev/Documents/notes.md")

        let result = FileDropPathFormatter.format([url])

        #expect(result == "/Users/dev/Documents/notes.md")
    }

    // MARK: - Whitespace escaping

    @Test("spaces in a path are backslash-escaped")
    func spacesAreEscaped() {
        let url = URL(fileURLWithPath: "/Users/dev/Screenshots/Screenshot 2026-04-27 at 8.41.00 AM.png")

        let result = FileDropPathFormatter.format([url])

        #expect(result == "/Users/dev/Screenshots/Screenshot\\ 2026-04-27\\ at\\ 8.41.00\\ AM.png")
    }

    @Test("tab characters in a path are backslash-escaped")
    func tabsAreEscaped() {
        // A literal tab in a filename is rare but legal on macOS, and
        // unescaped tabs split arguments in zsh/bash exactly like spaces.
        let url = URL(fileURLWithPath: "/tmp/odd\tname.txt")

        let result = FileDropPathFormatter.format([url])

        #expect(result == "/tmp/odd\\\tname.txt")
    }

    // MARK: - Backslash precedence

    @Test("backslashes are escaped before any other metacharacter so we do not double-escape what we add")
    func backslashesAreEscapedFirst() {
        // The formatter must replace `\` with `\\` BEFORE prepending
        // backslashes for other characters; otherwise the very escapes
        // the formatter writes for spaces/parens would themselves be
        // re-escaped on a second pass and the output would no longer
        // round-trip through the shell.
        let url = URL(fileURLWithPath: "/tmp/path with\\backslash.txt")

        let result = FileDropPathFormatter.format([url])

        #expect(result == "/tmp/path\\ with\\\\backslash.txt")
    }

    // MARK: - Shell metacharacters

    @Test("shell metacharacters are backslash-escaped")
    func shellMetacharactersAreEscaped() {
        let url = URL(fileURLWithPath: "/tmp/(weird)[name]{here}.txt")

        let result = FileDropPathFormatter.format([url])

        #expect(result == "/tmp/\\(weird\\)\\[name\\]\\{here\\}.txt")
    }

    @Test("redirection and pipe characters are escaped")
    func redirectionCharactersAreEscaped() {
        let url = URL(fileURLWithPath: "/tmp/redir<in>out|pipe&bg;sep.txt")

        let result = FileDropPathFormatter.format([url])

        #expect(result == "/tmp/redir\\<in\\>out\\|pipe\\&bg\\;sep.txt")
    }

    @Test("expansion characters dollar and backtick are escaped")
    func expansionCharactersAreEscaped() {
        let url = URL(fileURLWithPath: "/tmp/$VAR-`cmd`.txt")

        let result = FileDropPathFormatter.format([url])

        #expect(result == "/tmp/\\$VAR-\\`cmd\\`.txt")
    }

    @Test("quote characters are escaped")
    func quoteCharactersAreEscaped() {
        let url = URL(fileURLWithPath: "/tmp/it's-\"quoted\".txt")

        let result = FileDropPathFormatter.format([url])

        #expect(result == "/tmp/it\\'s-\\\"quoted\\\".txt")
    }

    @Test("glob characters and history hash and exclamation are escaped")
    func globAndHistoryCharactersAreEscaped() {
        let url = URL(fileURLWithPath: "/tmp/*-?-#-!.txt")

        let result = FileDropPathFormatter.format([url])

        #expect(result == "/tmp/\\*-\\?-\\#-\\!.txt")
    }

    // MARK: - Unicode preservation

    @Test("non-ASCII characters such as accents and emoji are preserved verbatim")
    func unicodeCharactersArePreserved() {
        // Accented characters and emoji are valid on HFS+/APFS and must
        // not be escaped — they are not shell metacharacters and any
        // backslash injected before them would corrupt the path.
        let url = URL(fileURLWithPath: "/Users/José/Documents/Resumé 📄.pdf")

        let result = FileDropPathFormatter.format([url])

        #expect(result == "/Users/José/Documents/Resumé\\ 📄.pdf")
    }

    // MARK: - Multiple paths

    @Test("multiple paths are joined by a single space and each is escaped independently")
    func multiplePathsAreJoinedAndEscapedIndependently() {
        let urls = [
            URL(fileURLWithPath: "/tmp/file one.txt"),
            URL(fileURLWithPath: "/tmp/file(two).txt"),
            URL(fileURLWithPath: "/tmp/plain.txt"),
        ]

        let result = FileDropPathFormatter.format(urls)

        #expect(result == "/tmp/file\\ one.txt /tmp/file\\(two\\).txt /tmp/plain.txt")
    }

    // MARK: - Real-world Screenshot example

    @Test("matches the canonical shell-escape produced for a typical macOS Screenshot path")
    func realWorldScreenshotPath() {
        // This path is exactly the form macOS produces under the
        // default Screenshots Capture preferences.
        let url = URL(fileURLWithPath: "/Users/example/Screenshots/Screenshot 2026-04-27 at 8.41.00 AM.png")

        let result = FileDropPathFormatter.format([url])

        #expect(result == "/Users/example/Screenshots/Screenshot\\ 2026-04-27\\ at\\ 8.41.00\\ AM.png")
    }
}
