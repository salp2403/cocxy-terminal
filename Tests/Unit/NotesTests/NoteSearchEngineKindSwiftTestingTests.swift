// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Pin the `NoteSearchEngineKind` config contract: closed enum,
/// tolerant parser, default value matches the documented one. Locked
/// down here so the TOML key surface cannot drift from the runtime
/// matching in the factory.
@Suite("NoteSearchEngineKind")
struct NoteSearchEngineKindSwiftTestingTests {

    @Test("rawValues match the documented config strings so TOML keys stay stable across versions")
    func rawValuesMatchConfigStrings() {
        #expect(NoteSearchEngineKind.grep.rawValue == "grep")
        #expect(NoteSearchEngineKind.fts5.rawValue == "fts5")
        #expect(NoteSearchEngineKind.spotlight.rawValue == "spotlight")
    }

    @Test("default kind is grep so users with no preference get the zero-dependency backend")
    func defaultIsGrep() {
        #expect(NoteSearchEngineKind.default == .grep)
    }

    @Test("parse returns the matching case for known strings so explicit configuration honours user intent")
    func parseAcceptsKnownStrings() {
        #expect(NoteSearchEngineKind.parse("grep") == .grep)
        #expect(NoteSearchEngineKind.parse("fts5") == .fts5)
        #expect(NoteSearchEngineKind.parse("spotlight") == .spotlight)
    }

    @Test("parse falls back to default for unknown strings so a typo never blocks the load path")
    func parseFallsBackForUnknownStrings() {
        #expect(NoteSearchEngineKind.parse("ripgrep") == .default)
        #expect(NoteSearchEngineKind.parse("FTS5") == .default) // case-sensitive on purpose
        #expect(NoteSearchEngineKind.parse("") == .default)
    }

    @Test("parse falls back to default for nil so a missing config key produces the documented value")
    func parseFallsBackForNil() {
        #expect(NoteSearchEngineKind.parse(nil) == .default)
    }

    @Test("allCases lists every backend so adding a new engine forces this test to update")
    func allCasesCount() {
        #expect(NoteSearchEngineKind.allCases.count == 3)
    }

    @Test("Codable round-trip preserves the case so persisted configs reload cleanly")
    func codableRoundTrip() throws {
        for kind in NoteSearchEngineKind.allCases {
            let encoded = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(NoteSearchEngineKind.self, from: encoded)
            #expect(kind == decoded)
        }
    }
}
