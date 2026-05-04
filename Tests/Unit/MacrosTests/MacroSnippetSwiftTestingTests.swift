// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MacroSnippetSwiftTestingTests.swift - Macros and snippets foundation coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Macros and snippets foundation")
struct MacroSnippetSwiftTestingTests {
    @Test("recorder captures events and returns immutable macro")
    func recorderCapturesEventsAndReturnsMacro() throws {
        var recorder = MacroRecorder()
        let start = Date(timeIntervalSince1970: 100)
        let stop = Date(timeIntervalSince1970: 120)

        try recorder.start(id: "build", name: "Build", at: start)
        try recorder.record(.text("swift build"))
        try recorder.record(.key("return"))
        let macro = try recorder.stop(at: stop)

        #expect(macro.id == "build")
        #expect(macro.name == "Build")
        #expect(macro.events == [.text("swift build"), .key("return")])
        #expect(macro.createdAt == start)
        #expect(macro.updatedAt == stop)
        #expect(recorder.isRecording == false)
    }

    @Test("recorder rejects invalid lifecycle transitions")
    func recorderRejectsInvalidLifecycleTransitions() throws {
        var recorder = MacroRecorder()

        #expect(throws: MacroRecorderError.notRecording) {
            try recorder.record(.key("return"))
        }
        try recorder.start(name: "Empty")
        #expect(throws: MacroRecorderError.alreadyRecording) {
            try recorder.start(name: "Nested")
        }
        #expect(throws: MacroRecorderError.emptyMacro) {
            _ = try recorder.stop()
        }
    }

    @Test("player repeats macro events deterministically")
    func playerRepeatsMacroEventsDeterministically() throws {
        let macro = TerminalMacro(
            id: "ship",
            name: "Ship",
            events: [.command("git status"), .key("return")]
        )

        let plan = try MacroPlayer().playback(macro, repeatCount: 3)

        #expect(plan.macroID == "ship")
        #expect(plan.events == [
            .command("git status"), .key("return"),
            .command("git status"), .key("return"),
            .command("git status"), .key("return"),
        ])
    }

    @Test("terminal input replayer maps macro events to PTY text")
    @MainActor
    func terminalInputReplayerMapsMacroEventsToPTYText() throws {
        let plan = MacroPlaybackPlan(
            macroID: "build",
            events: [
                .text("swift build"),
                .key("return"),
                .command("git status"),
                .key("ctrl-c"),
            ]
        )
        var sentText: [String] = []
        let replayer = MacroTerminalInputReplayer { text in
            sentText.append(text)
        }

        let replayedCount = try replayer.replay(plan)

        #expect(replayedCount == 4)
        #expect(sentText == ["swift build", "\r", "git status\r", "\u{03}"])
    }

    @Test("terminal input replayer rejects unsupported keys")
    @MainActor
    func terminalInputReplayerRejectsUnsupportedKeys() throws {
        let plan = MacroPlaybackPlan(macroID: "bad", events: [.key("hyper-space")])
        let replayer = MacroTerminalInputReplayer { _ in }

        #expect(throws: MacroTerminalInputReplayError.unsupportedKey("hyper-space")) {
            _ = try replayer.replay(plan)
        }
    }

    @Test("player rejects empty macros and invalid repeat counts")
    func playerRejectsEmptyMacrosAndInvalidRepeatCounts() throws {
        let empty = TerminalMacro(id: "empty", name: "Empty", events: [])
        let macro = TerminalMacro(id: "ok", name: "OK", events: [.key("x")])

        #expect(throws: MacroPlayerError.emptyMacro("empty")) {
            _ = try MacroPlayer().playback(empty)
        }
        #expect(throws: MacroPlayerError.invalidRepeatCount(0)) {
            _ = try MacroPlayer().playback(macro, repeatCount: 0)
        }
    }

    @Test("snippet parser expands numbered placeholders and tab order")
    func snippetParserExpandsNumberedPlaceholdersAndTabOrder() throws {
        let expansion = try SnippetParser().expand("func ${1:name}(${2:value}) {\n\t$0\n}")

        #expect(expansion.renderedText == "func name(value) {\n\t\n}")
        #expect(expansion.orderedTabStops.map(\.index) == [1, 2, 0])
        #expect(expansion.orderedTabStops.map(\.placeholder) == ["name", "value", ""])
        #expect(expansion.nextTabStop(after: nil)?.index == 1)
        #expect(expansion.nextTabStop(after: 1)?.index == 2)
        #expect(expansion.nextTabStop(after: 2)?.index == 0)
    }

    @Test("snippet parser supports bare stops escaped dollars and repeated positions")
    func snippetParserSupportsBareStopsEscapedDollarsAndRepeatedPositions() throws {
        let expansion = try SnippetParser().expand("\\$ ${1:first} $2 ${1:again}")

        #expect(expansion.renderedText == "$ first  again")
        #expect(expansion.orderedTabStops.map(\.index) == [1, 1, 2])
        #expect(expansion.orderedTabStops[0].range == SnippetTextRange(location: 2, length: 5))
        #expect(expansion.orderedTabStops[1].range == SnippetTextRange(location: 9, length: 5))
        #expect(expansion.orderedTabStops[2].range == SnippetTextRange(location: 8, length: 0))
    }

    @Test("snippet parser rejects malformed placeholders")
    func snippetParserRejectsMalformedPlaceholders() throws {
        #expect(throws: SnippetParserError.unterminatedPlaceholder("${1:name")) {
            _ = try SnippetParser().expand("${1:name")
        }
        #expect(throws: SnippetParserError.invalidPlaceholder("name")) {
            _ = try SnippetParser().expand("${name}")
        }
    }

    @Test("snippet manager persists upserts expands and removes snippets")
    func snippetManagerPersistsUpsertsExpandsAndRemovesSnippets() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SnippetStore(fileURL: root.appendingPathComponent("snippets.json"))
        let manager = SnippetManager(store: store)
        let snippet = Snippet(
            id: "swift-func",
            name: "Swift Function",
            trigger: "fn",
            body: "func ${1:name}() {\n\t$0\n}",
            scope: "swift",
            updatedAt: Date(timeIntervalSince1970: 100)
        )

        try manager.upsert(snippet)
        let loaded = try manager.list()
        let expansion = try manager.expand(trigger: "fn", scope: "swift")

        #expect(loaded == [snippet])
        #expect(expansion.renderedText == "func name() {\n\t\n}")
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        try manager.remove(id: "swift-func")
        #expect(try manager.list().isEmpty)
    }

    @Test("snippet manager validates identifiers triggers and scope matching")
    func snippetManagerValidatesIdentifiersTriggersAndScopeMatching() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = SnippetManager(
            store: SnippetStore(fileURL: root.appendingPathComponent("snippets.json"))
        )
        try manager.upsert(Snippet(id: "shared", name: "Shared", trigger: "mk", body: "mkdir $0"))
        try manager.upsert(Snippet(id: "swift", name: "Swift", trigger: "mk", body: "let $0", scope: "swift"))

        #expect(try manager.snippet(trigger: "mk", scope: "swift")?.id == "swift")
        #expect(try manager.snippet(trigger: "mk", scope: "python")?.id == "shared")
        #expect(throws: SnippetManagerError.invalidIdentifier("../bad")) {
            try manager.upsert(Snippet(id: "../bad", name: "Bad", trigger: "bad", body: "x"))
        }
        #expect(throws: SnippetManagerError.invalidTrigger("\n")) {
            try manager.upsert(Snippet(id: "bad-trigger", name: "Bad", trigger: "\n", body: "x"))
        }
    }

    @Test("alias manager renders shell-specific blocks in stable order")
    func aliasManagerRendersShellSpecificBlocksInStableOrder() throws {
        let aliases = [
            ShellAlias(name: "gs", value: "git status"),
            ShellAlias(name: "quote", value: "printf 'ok'"),
        ]

        let zsh = try AliasManager().renderBlock(aliases: aliases, shell: .zsh)
        let fish = try AliasManager().renderBlock(aliases: aliases, shell: .fish)

        #expect(zsh.contains("alias gs='git status'"))
        #expect(zsh.contains("alias quote='printf '\\''ok'\\'''"))
        #expect(fish.contains("alias gs 'git status'"))
        #expect(zsh.hasPrefix("# Cocxy aliases begin\nalias gs="))
        #expect(zsh.hasSuffix("# Cocxy aliases end\n"))
    }

    @Test("alias manager rejects unsafe alias definitions")
    func aliasManagerRejectsUnsafeAliasDefinitions() throws {
        #expect(throws: AliasManagerError.invalidName("bad name")) {
            try AliasManager().validate(ShellAlias(name: "bad name", value: "ls"))
        }
        #expect(throws: AliasManagerError.unsafeValue("echo one\necho two")) {
            try AliasManager().validate(ShellAlias(name: "multi", value: "echo one\necho two"))
        }
    }

    @Test("clipboard history deduplicates trims searches and enforces limit")
    func clipboardHistoryDeduplicatesTrimsSearchesAndEnforcesLimit() {
        var store = ClipboardHistoryStore(limit: 3)

        #expect(store.record(text: "   ") == nil)
        _ = store.record(text: "alpha", at: Date(timeIntervalSince1970: 1))
        _ = store.record(text: "beta", at: Date(timeIntervalSince1970: 2))
        _ = store.record(text: "alpha", at: Date(timeIntervalSince1970: 3))
        _ = store.record(text: "gamma", at: Date(timeIntervalSince1970: 4))
        _ = store.record(text: "delta", at: Date(timeIntervalSince1970: 5))

        #expect(store.items.map(\.text) == ["delta", "gamma", "alpha"])
        #expect(store.search("alp").map(\.text) == ["alpha"])
        #expect(store.search("").map(\.text) == ["delta", "gamma", "alpha"])

        store.clear()
        #expect(store.items.isEmpty)
    }

    @Test("macro event payloads codable round-trip")
    func macroEventPayloadsCodableRoundTrip() throws {
        let macro = TerminalMacro(
            id: "roundtrip",
            name: "Roundtrip",
            events: [.text("abc"), .key("return"), .command("clear"), .delay(milliseconds: 150)],
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let data = try JSONEncoder().encode(macro)
        let decoded = try JSONDecoder().decode(TerminalMacro.self, from: data)

        #expect(decoded == macro)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-macros-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
