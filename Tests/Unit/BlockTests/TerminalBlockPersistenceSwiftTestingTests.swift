// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Terminal block persistence")
struct TerminalBlockPersistenceSwiftTestingTests {

    @Test("JSONL serializer round-trips a command block")
    func jsonlSerializerRoundTripsCommandBlock() throws {
        let block = sampleBlock(id: 42)

        let line = try TerminalBlockSerializer.encodeLine(block)
        let decoded = try TerminalBlockSerializer.decodeLine(line)

        #expect(line.hasSuffix("\n"))
        #expect(decoded == block)
        #expect(decoded.schemaVersion == TerminalCommandBlock.currentSchemaVersion)
        #expect(decoded.isBookmarked == false)
    }

    @Test("JSONL serializer decodes legacy unversioned records")
    func jsonlSerializerDecodesLegacyUnversionedRecords() throws {
        let legacyLine = """
        {"blockType":2,"command":"echo legacy","durationNs":150,"endRow":4,"endTimeNs":250,"exitCode":0,"id":42,"output":"legacy\\n","pwd":"/Users/example/project","startRow":3,"startTimeNs":100,"streamID":0}
        """

        let decoded = try TerminalBlockSerializer.decodeLine(legacyLine)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.command == "echo legacy")
        #expect(decoded.output == "legacy\n")
        #expect(decoded.isBookmarked == false)
    }

    @Test("JSONL serializer rejects future schema versions")
    func jsonlSerializerRejectsFutureSchemaVersions() throws {
        let futureLine = """
        {"schemaVersion":99,"blockType":2,"command":"echo future","durationNs":150,"endRow":4,"endTimeNs":250,"exitCode":0,"id":42,"isBookmarked":false,"output":"future\\n","pwd":"/Users/example/project","startRow":3,"startTimeNs":100,"streamID":0}
        """

        #expect(throws: DecodingError.self) {
            _ = try TerminalBlockSerializer.decodeLine(futureLine)
        }
    }

    @Test("JSONL serializer preserves multiline command and output")
    func jsonlSerializerPreservesMultilineCommandAndOutput() throws {
        let block = sampleBlock(
            id: 51,
            command: "cat <<'EOF'\nhello\nEOF",
            output: "hello\nsecond line\n"
        )

        let decoded = try TerminalBlockSerializer.decodeLine(
            try TerminalBlockSerializer.encodeLine(block)
        )

        #expect(decoded.command == "cat <<'EOF'\nhello\nEOF")
        #expect(decoded.output == "hello\nsecond line\n")
    }

    @Test("store appends and loads blocks for one session")
    func storeAppendsAndLoadsBlocksForOneSession() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TerminalBlockStore(rootDirectory: root)

        try store.append(sampleBlock(id: 1, command: "echo one"), sessionID: "tab-1")
        try store.append(sampleBlock(id: 2, command: "echo two"), sessionID: "tab-1")

        #expect(try store.load(sessionID: "tab-1").map(\.command) == ["echo one", "echo two"])
    }

    @Test("store lists only regular JSONL session files")
    func storeListsOnlyRegularJSONLSessionFiles() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TerminalBlockStore(rootDirectory: root)

        try store.append(sampleBlock(id: 1, command: "echo one"), sessionID: "tab-1")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("not-a-session.jsonl", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "ignored".write(to: root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        #expect(try store.sessionIDs() == ["tab-1"])
    }

    @Test("store skips corrupt JSONL lines without losing valid blocks")
    func storeSkipsCorruptJSONLLinesWithoutLosingValidBlocks() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TerminalBlockStore(rootDirectory: root)
        let block = sampleBlock(id: 7)
        let fileURL = store.fileURL(forSessionID: "session")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let content = "not-json\n" + (try TerminalBlockSerializer.encodeLine(block))
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        #expect(try store.load(sessionID: "session") == [block])
    }

    @Test("session filenames are sanitized before persistence")
    func sessionFilenamesAreSanitizedBeforePersistence() {
        let root = URL(fileURLWithPath: "/tmp/cocxy-block-test")
        let store = TerminalBlockStore(rootDirectory: root)

        #expect(store.fileURL(forSessionID: "tab/one:danger uuid").lastPathComponent == "tab-one-danger-uuid.jsonl")
        #expect(store.fileURL(forSessionID: "").lastPathComponent == "default.jsonl")
    }

    @Test("restoration supplies persisted blocks only until live blocks exist")
    func restorationSuppliesPersistedBlocksOnlyUntilLiveBlocksExist() {
        let restored = [sampleBlock(id: 1, command: "echo restored")]
        let live = [sampleBlock(id: 2, command: "echo live")]

        #expect(
            TerminalBlockRestoration.blocksForDisplay(
                live: [],
                restored: restored,
                limit: 32
            ) == restored
        )
        #expect(
            TerminalBlockRestoration.blocksForDisplay(
                live: live,
                restored: restored,
                limit: 32
            ) == live
        )
    }

    @Test("restoration keeps the most recent blocks when applying limits")
    func restorationKeepsMostRecentBlocksWhenApplyingLimits() {
        let restored = (1...5).map { sampleBlock(id: UInt64($0)) }

        let limited = TerminalBlockRestoration.blocksForDisplay(
            live: [],
            restored: restored,
            limit: 3
        )

        #expect(limited.map(\.id) == [3, 4, 5])
    }

    @Test("restoration deduplicates persisted block IDs without changing chronology")
    func restorationDeduplicatesPersistedBlockIDsWithoutChangingChronology() {
        let restored = [
            sampleBlock(id: 1, command: "echo first", startTimeNs: 100),
            sampleBlock(id: 2, command: "echo second", startTimeNs: 200),
            sampleBlock(id: 1, command: "echo newest", startTimeNs: 100).withBookmark(true)
        ]

        let blocks = TerminalBlockRestoration.blocksForDisplay(
            live: [],
            restored: restored,
            limit: 32
        )

        #expect(blocks.map(\.id) == [1, 2])
        #expect(blocks.first?.command == "echo newest")
        #expect(blocks.first?.isBookmarked == true)
        #expect(
            TerminalBlockRestoration.block(
                id: 1,
                live: nil,
                restored: restored
            )?.command == "echo newest"
        )
    }

    @Test("restoration merges bookmark metadata into live blocks")
    func restorationMergesBookmarkMetadataIntoLiveBlocks() {
        let live = [
            sampleBlock(id: 1, command: "echo live"),
            sampleBlock(id: 2, command: "echo plain")
        ]
        let restored = [
            sampleBlock(id: 1, command: "echo old").withBookmark(true)
        ]

        let blocks = TerminalBlockRestoration.blocksForDisplay(
            live: live,
            restored: restored,
            limit: 32
        )

        #expect(blocks.map(\.id) == [1, 2])
        #expect(blocks[0].command == "echo live")
        #expect(blocks[0].isBookmarked == true)
        #expect(blocks[1].isBookmarked == false)
    }

    @Test("store keeps newest bookmark update for restored blocks")
    func storeKeepsNewestBookmarkUpdateForRestoredBlocks() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = TerminalBlockStore(rootDirectory: root)

        try store.append(sampleBlock(id: 8, command: "echo item"), sessionID: "tab-1")
        try store.append(sampleBlock(id: 8, command: "echo item").withBookmark(true), sessionID: "tab-1")

        let restored = try store.load(sessionID: "tab-1")
        let blocks = TerminalBlockRestoration.blocksForDisplay(
            live: [],
            restored: restored,
            limit: 32
        )

        #expect(blocks.count == 1)
        #expect(blocks.first?.isBookmarked == true)
    }

    @Test("restoration lookup falls back to persisted blocks")
    func restorationLookupFallsBackToPersistedBlocks() {
        let restored = [sampleBlock(id: 10), sampleBlock(id: 11)]
        let live = sampleBlock(id: 11, command: "echo live")

        #expect(
            TerminalBlockRestoration.block(
                id: 11,
                live: nil,
                restored: restored
            )?.id == 11
        )
        #expect(
            TerminalBlockRestoration.block(
                id: 11,
                live: live,
                restored: restored
            )?.command == "echo live"
        )
        #expect(
            TerminalBlockRestoration.block(
                id: 99,
                live: nil,
                restored: restored
            ) == nil
        )
    }

    @Test("share formatter includes command output and exit code")
    func shareFormatterIncludesCommandOutputAndExitCode() {
        let text = TerminalBlockShareFormatter.text(for: sampleBlock(id: 4, command: "pwd", output: "/tmp\n"))

        #expect(text.contains("$ pwd"))
        #expect(text.contains("/tmp"))
        #expect(text.contains("exit_code=0"))
    }

    @Test("output context formatter joins clean block outputs chronologically")
    func outputContextFormatterJoinsCleanBlockOutputsChronologically() {
        let text = TerminalBlockOutputContextFormatter.text(
            for: [
                sampleBlock(id: 1, output: "one\n"),
                sampleBlock(id: 2, output: "two-a\ntwo-b\n")
            ]
        )

        #expect(text == "one\ntwo-a\ntwo-b")
    }

    @Test("output context formatter skips empty outputs without trimming content spaces")
    func outputContextFormatterSkipsEmptyOutputsWithoutTrimmingContentSpaces() {
        let text = TerminalBlockOutputContextFormatter.text(
            for: [
                sampleBlock(id: 1, output: "\n"),
                sampleBlock(id: 2, output: "  spaced output  \n")
            ]
        )

        #expect(text == "  spaced output  ")
    }

    private func sampleBlock(
        id: UInt64,
        command: String = "echo hi",
        output: String = "hi\n",
        startTimeNs: UInt64 = 100
    ) -> TerminalCommandBlock {
        TerminalCommandBlock(
            id: id,
            command: command,
            output: output,
            exitCode: 0,
            pwd: "/Users/example/project",
            startTimeNs: startTimeNs,
            endTimeNs: startTimeNs + 150,
            durationNs: 150,
            startRow: 3,
            endRow: 4,
            streamID: 0,
            blockType: 2
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-blocks-\(UUID().uuidString)", isDirectory: true)
    }
}
