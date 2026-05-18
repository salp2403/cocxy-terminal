// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyCoreMoatSmokeSwiftTestingTests.swift - Manual moat stress smoke for CocxyCore.

import Foundation
import Testing
import CocxyCoreKit

@Suite("CocxyCore moat smoke", .serialized)
struct CocxyCoreMoatSmokeSwiftTestingTests {

    @Test("deterministic parser and terminal fuzz runs without crashes")
    func deterministicParserAndTerminalFuzzRunsWithoutCrashes() throws {
        let cases = Self.envInt("COCXYCORE_MOAT_FUZZ_CASES", defaultValue: 10_000)
        let parser = try #require(cocxycore_parser_create())
        defer { cocxycore_parser_destroy(parser) }

        let terminal = try #require(cocxycore_terminal_create(12, 80))
        defer { cocxycore_terminal_destroy(terminal) }
        #expect(cocxycore_terminal_enable_scrollback(terminal, UInt32(max(cases / 2, 1_024))))

        var generator = SeededGenerator(seed: 0xC0C0_2026)
        for index in 0..<cases {
            let chunk = Self.fuzzChunk(index: index, generator: &generator)
            chunk.withUnsafeBytes { buffer in
                guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else { return }
                cocxycore_parser_feed(parser, base, chunk.count)
                cocxycore_terminal_feed(terminal, base, chunk.count)
            }

            if index > 0, index % 1_024 == 0 {
                let rows = UInt16(8 + (index % 8))
                let cols = UInt16(64 + (index % 32))
                #expect(cocxycore_terminal_resize(terminal, rows, cols))
            }
        }

        #expect(cocxycore_terminal_rows(terminal) >= 8)
        #expect(cocxycore_terminal_cols(terminal) >= 64)
        #expect(cocxycore_parser_get_state(parser) <= COCXYCORE_STATE_SOS_PM_APC_STRING.rawValue)
    }

    @Test("large scrollback search benchmark remains indexed and bounded")
    func largeScrollbackSearchBenchmarkRemainsIndexedAndBounded() throws {
        let rows = Self.envInt("COCXYCORE_MOAT_SEARCH_ROWS", defaultValue: 60_000)
        let maxElapsedMicros = UInt64(Self.envInt("COCXYCORE_MOAT_SEARCH_MAX_MICROS", defaultValue: 100_000))
        let markerRow = max(0, rows - 257)
        let marker = "COCXY_MOAT_MARKER_\(markerRow)"

        let terminal = try #require(cocxycore_terminal_create(16, 96))
        defer { cocxycore_terminal_destroy(terminal) }
        #expect(cocxycore_terminal_enable_scrollback(terminal, UInt32(rows + 512)))

        for index in 0..<rows {
            let suffix = index == markerRow ? " \(marker)" : ""
            feed("moat-row-\(String(format: "%07d", index))\(suffix)\r\n", into: terminal)
        }

        let engine = try #require(cocxycore_gpu_search_init(terminal))
        defer { cocxycore_gpu_search_destroy(engine) }
        cocxycore_gpu_search_sync(engine, terminal)

        #expect(cocxycore_gpu_search_indexed_rows(engine) >= UInt32(rows - 32))

        var matches = [cocxycore_search_match](
            repeating: cocxycore_search_match(row: 0, start_col: 0, end_col: 0),
            count: 8
        )
        var elapsedMicros: UInt64 = 0
        let count = marker.withCString { pattern in
            cocxycore_gpu_search_find(
                engine,
                terminal,
                pattern,
                UInt32(marker.utf8.count),
                false,
                false,
                0,
                0,
                0,
                UInt32(matches.count),
                &matches,
                &elapsedMicros
            )
        }

        #expect(count == 1)
        #expect(matches[0].row >= UInt32(markerRow - 32))
        #expect(matches[0].start_col == 17)
        #expect(matches[0].end_col == UInt16(16 + marker.utf8.count))
        #expect(elapsedMicros <= maxElapsedMicros)
    }

    @Test("large scrollback search pattern matrix remains bounded")
    func largeScrollbackSearchPatternMatrixRemainsBounded() throws {
        let rows = Self.envInt(
            "COCXYCORE_MOAT_PATTERN_ROWS",
            defaultValue: Self.envInt("COCXYCORE_MOAT_SEARCH_ROWS", defaultValue: 60_000)
        )
        let maxElapsedMicros = UInt64(Self.envInt("COCXYCORE_MOAT_SEARCH_MAX_MICROS", defaultValue: 100_000))
        let markerRows = Self.patternMarkerRows(rowCount: rows)
        let markers = [
            markerRows[0]: "COCXY_PATTERN_HEAD_\(markerRows[0])",
            markerRows[1]: "COCXY_PATTERN_MIDDLE_\(markerRows[1])",
            markerRows[2]: "COCXY_PATTERN_TAIL_\(markerRows[2])",
        ]

        let terminal = try #require(cocxycore_terminal_create(16, 112))
        defer { cocxycore_terminal_destroy(terminal) }
        #expect(cocxycore_terminal_enable_scrollback(terminal, UInt32(rows + 512)))

        for index in 0..<rows {
            let marker = markers[index].map { " \($0)" } ?? ""
            feed("moat-pattern-row-\(String(format: "%07d", index))\(marker)\r\n", into: terminal)
        }

        let engine = try #require(cocxycore_gpu_search_init(terminal))
        defer { cocxycore_gpu_search_destroy(engine) }
        cocxycore_gpu_search_sync(engine, terminal)

        #expect(cocxycore_gpu_search_indexed_rows(engine) >= UInt32(rows - 32))

        try assertPattern(
            markers[markerRows[0]]!,
            in: terminal,
            engine: engine,
            expectedStartColumn: 25,
            maxElapsedMicros: maxElapsedMicros
        )
        try assertPattern(
            markers[markerRows[1]]!.lowercased(),
            in: terminal,
            engine: engine,
            expectedStartColumn: 25,
            caseInsensitive: true,
            maxElapsedMicros: maxElapsedMicros
        )
        try assertPattern(
            markers[markerRows[2]]!,
            in: terminal,
            engine: engine,
            expectedStartColumn: 25,
            maxElapsedMicros: maxElapsedMicros
        )
    }

    @Test("session replay produces deterministic debug snapshot")
    func sessionReplayProducesDeterministicDebugSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxycore-moat-replay-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recordingURL = directory.appendingPathComponent("moat.cast")
        let source = try #require(cocxycore_terminal_create(5, 48))
        defer { cocxycore_terminal_destroy(source) }

        let recorder = try #require(recordingURL.path.withCString { path in
            "CocxyCore Moat Replay".withCString { title in
                cocxycore_session_recorder_start(source, path, title)
            }
        })
        feed("alpha\r\n", into: source)
        feed("beta COCXY_REPLAY_MARKER\r\n", into: source)
        feed("\u{001B}[3;8Hcursor\r\n", into: source)
        cocxycore_session_recorder_stop(recorder)
        #expect(cocxycore_session_recorder_is_active(recorder) == false)
        #expect(cocxycore_session_recorder_bytes_written(recorder) > 0)
        cocxycore_session_recorder_destroy(recorder)

        let target = try #require(cocxycore_terminal_create(5, 48))
        defer { cocxycore_terminal_destroy(target) }
        #expect(cocxycore_terminal_enable_scrollback(target, 64))

        let player = try #require(recordingURL.path.withCString { path in
            cocxycore_session_player_open(target, path)
        })
        defer { cocxycore_session_player_destroy(player) }

        cocxycore_session_player_seek_ns(player, 0)
        cocxycore_session_player_set_speed(player, 2.0)
        cocxycore_session_player_play(player)

        let snapshot = debugSnapshot(for: target, marker: "COCXY_REPLAY_MARKER")
        #expect(snapshot.rows == 5)
        #expect(snapshot.columns == 48)
        #expect(snapshot.visibleStart == cocxycore_terminal_history_visible_start(target))
        #expect(snapshot.historyRows >= 5)
        #expect(snapshot.lines[0] == "alpha")
        #expect(snapshot.lines[1] == "beta COCXY_REPLAY_MARKER")
        #expect(snapshot.lines[2].contains("cursor"))
        #expect(snapshot.markerRange?.start_col == 5)
        #expect(snapshot.markerRange?.end_col == 23)
        #expect(snapshot.cursorRow >= 2)
    }

    private static func envInt(_ key: String, defaultValue: Int) -> Int {
        guard let raw = ProcessInfo.processInfo.environment[key],
              let value = Int(raw),
              value > 0 else {
            return defaultValue
        }
        return value
    }

    private static func fuzzChunk(index: Int, generator: inout SeededGenerator) -> Data {
        switch index % 12 {
        case 0:
            return Data("plain-\(index)\r\n".utf8)
        case 1:
            return Data("\u{001B}[\(1 + index % 20);\(1 + index % 70)Hpos\(index)".utf8)
        case 2:
            return Data("\u{001B}[38;2;\(index % 255);\((index * 3) % 255);\((index * 7) % 255)mRGB\u{001B}[0m".utf8)
        case 3:
            return Data("\u{001B}]0;title-\(index)\u{0007}".utf8)
        case 4:
            return Data("\u{001B}[?2004hBRACKET\u{001B}[?2004l".utf8)
        case 5:
            return Data("\u{001B}[2J\u{001B}[Hclear-\(index)\r\n".utf8)
        case 6:
            return Data("\u{001B}P$qm\u{001B}\\".utf8)
        default:
            let length = 8 + (index % 48)
            var bytes: [UInt8] = []
            bytes.reserveCapacity(length + 1)
            for _ in 0..<length {
                let value = generator.nextByte()
                switch value % 16 {
                case 0: bytes.append(0x1B)
                case 1: bytes.append(0x0A)
                case 2: bytes.append(0x0D)
                default: bytes.append(0x20 + (value % 0x5F))
                }
            }
            bytes.append(0x0A)
            return Data(bytes)
        }
    }

    private static func patternMarkerRows(rowCount rows: Int) -> [Int] {
        [
            min(max(17, rows / 5), rows - 1),
            min(max(97, rows / 2), rows - 1),
            max(0, rows - 333),
        ]
    }
}

private struct SeededGenerator {
    var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func nextByte() -> UInt8 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return UInt8(truncatingIfNeeded: state >> 32)
    }
}

private func feed(_ text: String, into terminal: OpaquePointer) {
    let bytes = Array(text.utf8)
    cocxycore_terminal_feed(terminal, bytes, bytes.count)
}

private struct CocxyCoreDebugSnapshot {
    let rows: UInt16
    let columns: UInt16
    let visibleStart: UInt32
    let historyRows: UInt32
    let cursorRow: UInt16
    let cursorColumn: UInt16
    let lines: [String]
    let markerRange: cocxycore_buffer_range?
}

private func debugSnapshot(for terminal: OpaquePointer, marker: String) -> CocxyCoreDebugSnapshot {
    var range = cocxycore_buffer_range()
    let markerBytes = Array(marker.utf8)
    let foundMarker = markerBytes.withUnsafeBufferPointer { buffer in
        cocxycore_terminal_search_next(
            terminal,
            buffer.baseAddress,
            markerBytes.count,
            0,
            0,
            true,
            &range
        )
    }

    return CocxyCoreDebugSnapshot(
        rows: cocxycore_terminal_rows(terminal),
        columns: cocxycore_terminal_cols(terminal),
        visibleStart: cocxycore_terminal_history_visible_start(terminal),
        historyRows: cocxycore_terminal_history_rows(terminal),
        cursorRow: cocxycore_terminal_cursor_row(terminal),
        cursorColumn: cocxycore_terminal_cursor_col(terminal),
        lines: (0..<cocxycore_terminal_rows(terminal)).map { row in
            terminalLine(terminal, row: row, columns: cocxycore_terminal_cols(terminal))
        },
        markerRange: foundMarker ? range : nil
    )
}

private func terminalLine(_ terminal: OpaquePointer, row: UInt16, columns: UInt16) -> String {
    var scalars: [UnicodeScalar] = []
    for column in 0..<columns {
        let codepoint = cocxycore_terminal_cell_char(terminal, row, column)
        if let scalar = UnicodeScalar(codepoint), codepoint != 0 {
            scalars.append(scalar)
        } else {
            scalars.append(" ")
        }
    }
    return String(String.UnicodeScalarView(scalars))
        .trimmingCharacters(in: .whitespaces)
}

private func assertPattern(
    _ pattern: String,
    in terminal: OpaquePointer,
    engine: OpaquePointer,
    expectedStartColumn: UInt16,
    caseInsensitive: Bool = false,
    direction: UInt8 = 0,
    maxElapsedMicros: UInt64
) throws {
    var matches = [cocxycore_search_match](
        repeating: cocxycore_search_match(row: 0, start_col: 0, end_col: 0),
        count: 4
    )
    var elapsedMicros: UInt64 = 0
    let count = pattern.withCString { rawPattern in
        cocxycore_gpu_search_find(
            engine,
            terminal,
            rawPattern,
            UInt32(pattern.utf8.count),
            false,
            caseInsensitive,
            direction,
            0,
            0,
            UInt32(matches.count),
            &matches,
            &elapsedMicros
        )
    }

    #expect(count == 1)
    #expect(matches[0].start_col == expectedStartColumn)
    #expect(matches[0].end_col == UInt16(Int(expectedStartColumn) + pattern.utf8.count - 1))
    #expect(elapsedMicros <= maxElapsedMicros)
}
