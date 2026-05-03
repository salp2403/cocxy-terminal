// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TerminalCommandBlock.swift - Value model for command-scoped terminal blocks.

import Foundation

struct TerminalCommandBlock: Codable, Equatable, Sendable, Identifiable {
    static let currentSchemaVersion: UInt8 = 2

    let schemaVersion: UInt8
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
    let isBookmarked: Bool

    init(
        schemaVersion: UInt8 = TerminalCommandBlock.currentSchemaVersion,
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
        blockType: UInt8,
        isBookmarked: Bool = false
    ) {
        self.schemaVersion = schemaVersion
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
        self.isBookmarked = isBookmarked
    }

    func withBookmark(_ isBookmarked: Bool) -> TerminalCommandBlock {
        TerminalCommandBlock(
            schemaVersion: Self.currentSchemaVersion,
            id: id,
            command: command,
            output: output,
            exitCode: exitCode,
            pwd: pwd,
            startTimeNs: startTimeNs,
            endTimeNs: endTimeNs,
            durationNs: durationNs,
            startRow: startRow,
            endRow: endRow,
            streamID: streamID,
            blockType: blockType,
            isBookmarked: isBookmarked
        )
    }

    func mergingRestoredMetadata(from restored: TerminalCommandBlock) -> TerminalCommandBlock {
        withBookmark(restored.isBookmarked)
    }
}

extension TerminalCommandBlock {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case command
        case output
        case exitCode
        case pwd
        case startTimeNs
        case endTimeNs
        case durationNs
        case startRow
        case endRow
        case streamID
        case blockType
        case isBookmarked
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSchemaVersion = try container.decodeIfPresent(
            UInt8.self,
            forKey: .schemaVersion
        ) ?? 1
        guard decodedSchemaVersion <= Self.currentSchemaVersion else {
            throw DecodingError.dataCorruptedError(
                forKey: .schemaVersion,
                in: container,
                debugDescription: "Unsupported terminal command block schema version"
            )
        }

        self.init(
            schemaVersion: decodedSchemaVersion,
            id: try container.decode(UInt64.self, forKey: .id),
            command: try container.decode(String.self, forKey: .command),
            output: try container.decode(String.self, forKey: .output),
            exitCode: try container.decodeIfPresent(Int32.self, forKey: .exitCode),
            pwd: try container.decodeIfPresent(String.self, forKey: .pwd),
            startTimeNs: try container.decode(UInt64.self, forKey: .startTimeNs),
            endTimeNs: try container.decode(UInt64.self, forKey: .endTimeNs),
            durationNs: try container.decode(UInt64.self, forKey: .durationNs),
            startRow: try container.decode(UInt32.self, forKey: .startRow),
            endRow: try container.decode(UInt32.self, forKey: .endRow),
            streamID: try container.decode(UInt32.self, forKey: .streamID),
            blockType: try container.decode(UInt8.self, forKey: .blockType),
            isBookmarked: try container.decodeIfPresent(Bool.self, forKey: .isBookmarked) ?? false
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(id, forKey: .id)
        try container.encode(command, forKey: .command)
        try container.encode(output, forKey: .output)
        try container.encodeIfPresent(exitCode, forKey: .exitCode)
        try container.encodeIfPresent(pwd, forKey: .pwd)
        try container.encode(startTimeNs, forKey: .startTimeNs)
        try container.encode(endTimeNs, forKey: .endTimeNs)
        try container.encode(durationNs, forKey: .durationNs)
        try container.encode(startRow, forKey: .startRow)
        try container.encode(endRow, forKey: .endRow)
        try container.encode(streamID, forKey: .streamID)
        try container.encode(blockType, forKey: .blockType)
        try container.encode(isBookmarked, forKey: .isBookmarked)
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

enum TerminalBlockShareFormatter {
    static func text(for block: TerminalCommandBlock) -> String {
        var sections = ["$ \(block.command)"]
        if !block.output.isEmpty {
            sections.append(block.output)
        }
        if let exitCode = block.exitCode {
            sections.append("exit_code=\(exitCode)")
        }
        return sections.joined(separator: "\n\n")
    }
}

enum TerminalBlockRestoration {
    static func blocksForDisplay(
        live: [TerminalCommandBlock],
        restored: [TerminalCommandBlock],
        limit: Int
    ) -> [TerminalCommandBlock] {
        guard limit > 0 else { return [] }

        let source: [TerminalCommandBlock]
        if live.isEmpty {
            source = newestRestoredBlocksByID(restored)
        } else {
            let restoredByID = newestRestoredBlockMapByID(restored)
            source = live.map { block in
                guard let restoredBlock = restoredByID[block.id] else { return block }
                return block.mergingRestoredMetadata(from: restoredBlock)
            }
        }
        guard source.count > limit else { return source }
        return Array(source.suffix(limit))
    }

    static func block(
        id: UInt64,
        live: TerminalCommandBlock?,
        restored: [TerminalCommandBlock]
    ) -> TerminalCommandBlock? {
        if let live {
            guard let restored = newestRestoredBlockMapByID(restored)[id] else { return live }
            return live.mergingRestoredMetadata(from: restored)
        }
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

    private static func newestRestoredBlockMapByID(
        _ restored: [TerminalCommandBlock]
    ) -> [UInt64: TerminalCommandBlock] {
        var blocksByID: [UInt64: TerminalCommandBlock] = [:]
        for block in restored {
            blocksByID[block.id] = block
        }
        return blocksByID
    }
}
