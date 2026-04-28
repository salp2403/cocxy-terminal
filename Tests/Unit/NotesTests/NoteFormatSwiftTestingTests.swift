// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Pin the `NoteFormat` contract: closed enum, tolerant parser, file
/// extension is uniform across formats. The `default` case is part of
/// the public API because the configuration parser surfaces it on every
/// missing or malformed key.
@Suite("NoteFormat")
struct NoteFormatSwiftTestingTests {

    @Test("rawValues match the documented config strings so TOML keys never drift from the enum")
    func rawValuesMatchConfigStrings() {
        #expect(NoteFormat.markdown.rawValue == "markdown")
        #expect(NoteFormat.markdownFrontmatter.rawValue == "markdown-frontmatter")
    }

    @Test("default format is markdown so users with no preference get the lightest variant")
    func defaultIsMarkdown() {
        #expect(NoteFormat.default == .markdown)
    }

    @Test("parse returns the matching case for known strings so explicit configuration honours user intent")
    func parseAcceptsKnownStrings() {
        #expect(NoteFormat.parse("markdown") == .markdown)
        #expect(NoteFormat.parse("markdown-frontmatter") == .markdownFrontmatter)
    }

    @Test("parse falls back to default for unknown strings so a typo never crashes the load path")
    func parseFallsBackForUnknownStrings() {
        #expect(NoteFormat.parse("yaml") == .default)
        #expect(NoteFormat.parse("MARKDOWN") == .default) // case-sensitive on purpose
        #expect(NoteFormat.parse("") == .default)
    }

    @Test("parse falls back to default for nil so a missing config key produces the documented value")
    func parseFallsBackForNil() {
        #expect(NoteFormat.parse(nil) == .default)
    }

    @Test("file extension is the same for every format so Finder and editors treat notes uniformly")
    func fileExtensionIsUniform() {
        for format in NoteFormat.allCases {
            #expect(format.fileExtension == "md")
        }
    }

    @Test("Codable round-trip preserves the case so persisted configs reload cleanly")
    func codableRoundTrip() throws {
        for format in NoteFormat.allCases {
            let encoded = try JSONEncoder().encode(format)
            let decoded = try JSONDecoder().decode(NoteFormat.self, from: encoded)
            #expect(format == decoded)
        }
    }

    @Test("allCases lists every variant so future enum additions surface a compile error in this test")
    func allCasesCount() {
        #expect(NoteFormat.allCases.count == 2)
    }
}
