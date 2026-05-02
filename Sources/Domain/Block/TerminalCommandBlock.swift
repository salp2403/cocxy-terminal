// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalCommandBlock.swift - Value model for command-scoped terminal blocks.

import Foundation

struct TerminalCommandBlock: Codable, Equatable, Sendable, Identifiable {
    let id: UInt64
    let command: String
    let output: String
    let exitCode: Int32?
    let pwd: String?
    let startTimeNs: UInt64
    let endTimeNs: UInt64
    let durationNs: UInt64
    let startRow: UInt32
    let endRow: UInt32
    let streamID: UInt32
    let blockType: UInt8

    init(
        id: UInt64,
        command: String,
        output: String,
        exitCode: Int32?,
        pwd: String?,
        startTimeNs: UInt64,
        endTimeNs: UInt64,
        durationNs: UInt64,
        startRow: UInt32,
        endRow: UInt32,
        streamID: UInt32,
        blockType: UInt8
    ) {
        self.id = id
        self.command = command
        self.output = output
        self.exitCode = exitCode
        self.pwd = pwd
        self.startTimeNs = startTimeNs
        self.endTimeNs = endTimeNs
        self.durationNs = durationNs
        self.startRow = startRow
        self.endRow = endRow
        self.streamID = streamID
        self.blockType = blockType
    }
}

enum TerminalBlockSerializer {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    static func encodeLine(_ block: TerminalCommandBlock) throws -> String {
        let data = try encoder.encode(block)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    static func decodeLine(_ line: String) throws -> TerminalCommandBlock {
        let data = Data(line.trimmingCharacters(in: .newlines).utf8)
        return try decoder.decode(TerminalCommandBlock.self, from: data)
    }
}

enum TerminalBlockRestoration {
    static func blocksForDisplay(
        live: [TerminalCommandBlock],
        restored: [TerminalCommandBlock],
        limit: Int
    ) -> [TerminalCommandBlock] {
        guard limit > 0 else { return [] }

        let source = live.isEmpty ? newestRestoredBlocksByID(restored) : live
        guard source.count > limit else { return source }
        return Array(source.suffix(limit))
    }

    static func block(
        id: UInt64,
        live: TerminalCommandBlock?,
        restored: [TerminalCommandBlock]
    ) -> TerminalCommandBlock? {
        if let live { return live }
        return restored.last { $0.id == id }
    }

    private static func newestRestoredBlocksByID(
        _ restored: [TerminalCommandBlock]
    ) -> [TerminalCommandBlock] {
        var seenIDs = Set<UInt64>()
        var newestReversed: [TerminalCommandBlock] = []

        for block in restored.reversed() where seenIDs.insert(block.id).inserted {
            newestReversed.append(block)
        }

        return newestReversed.reversed()
    }
}
