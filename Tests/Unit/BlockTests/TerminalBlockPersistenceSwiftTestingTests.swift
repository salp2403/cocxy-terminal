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

    @Test("restoration deduplicates persisted block IDs using the newest record")
    func restorationDeduplicatesPersistedBlockIDsUsingNewestRecord() {
        let restored = [
            sampleBlock(id: 1, command: "echo first"),
            sampleBlock(id: 2, command: "echo second"),
            sampleBlock(id: 1, command: "echo newest")
        ]

        let blocks = TerminalBlockRestoration.blocksForDisplay(
            live: [],
            restored: restored,
            limit: 32
        )

        #expect(blocks.map(\.id) == [2, 1])
        #expect(blocks.last?.command == "echo newest")
        #expect(
            TerminalBlockRestoration.block(
                id: 1,
                live: nil,
                restored: restored
            )?.command == "echo newest"
        )
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

    private func sampleBlock(
        id: UInt64,
        command: String = "echo hi",
        output: String = "hi\n"
    ) -> TerminalCommandBlock {
        TerminalCommandBlock(
            id: id,
            command: command,
            output: output,
            exitCode: 0,
            pwd: "/Users/Galf/project",
            startTimeNs: 100,
            endTimeNs: 250,
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
