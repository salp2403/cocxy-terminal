// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
import CocxyCoreKit

@Suite("CocxyCore conformance matrix", .serialized)
struct CocxyCoreConformanceMatrixSwiftTestingTests {

    @Test("versioned VT OSC conformance matrix meets 95 percent target")
    func versionedVTOSCConformanceMatrixMeetsTarget() throws {
        let cases = Self.versionedConformanceCases()
        var passed: [String] = []
        var failed: [String] = []

        for conformanceCase in cases {
            do {
                if try conformanceCase.run() {
                    passed.append(conformanceCase.id)
                } else {
                    failed.append(conformanceCase.id)
                }
            } catch {
                failed.append("\(conformanceCase.id): \(error)")
            }
        }

        let score = Double(passed.count) / Double(cases.count)
        let scoreText = "\(passed.count)/\(cases.count)"
        #expect(
            score >= 0.95,
            "CocxyCore VT/OSC conformance score \(scoreText) is below 95%; failed=\(failed.joined(separator: ","))"
        )
        #expect(failed.isEmpty, "CocxyCore VT/OSC conformance failed cases: \(failed.joined(separator: ","))")
    }

    @Test("VT editing truecolor and private mode sequences stay compatible")
    func vtEditingTruecolorAndPrivateModesStayCompatible() throws {
        let terminal = try #require(cocxycore_terminal_create(6, 32))
        defer { cocxycore_terminal_destroy(terminal) }

        feed("hello\u{001B}[2DXY\r\n", into: terminal)
        #expect(screenLine(terminal, row: 0, columns: 32) == "helXY")

        feed("\u{001B}[38;2;12;34;56mRGB\u{001B}[0m", into: terminal)
        #expect(screenLine(terminal, row: 1, columns: 32) == "RGB")
        #expect(cocxycore_terminal_cell_fg_type(terminal, 1, 0) == COCXYCORE_COLOR_RGB.rawValue)

        var red: UInt8 = 0
        var green: UInt8 = 0
        var blue: UInt8 = 0
        cocxycore_terminal_cell_fg_rgb(terminal, 1, 0, &red, &green, &blue)
        #expect(red == 12)
        #expect(green == 34)
        #expect(blue == 56)

        feed("\u{001B}[2;10Hpos", into: terminal)
        #expect(screenLine(terminal, row: 1, columns: 32) == "RGB      pos")

        feed("\u{001B}[?2004h", into: terminal)
        #expect(cocxycore_terminal_get_bracketed_paste_active(terminal))
        feed("\u{001B}[?2004l", into: terminal)
        #expect(cocxycore_terminal_get_bracketed_paste_active(terminal) == false)
    }

    @Test("DSR and DECRQSS response matrix stays stable")
    func responseMatrixStaysStable() throws {
        let terminal = try #require(cocxycore_terminal_create(24, 80))
        defer { cocxycore_terminal_destroy(terminal) }

        feed("\u{001B}[5;10H\u{001B}[6n", into: terminal)
        #expect(readResponse(from: terminal) == "\u{001B}[5;10R")

        feed("\u{001B}[1;31m\u{001B}P$qm\u{001B}\\", into: terminal)
        #expect(readResponse(from: terminal) == "\u{001B}P1$r0;1;31m\u{001B}\\")

        feed("\u{001B}[5;20r\u{001B}P$qr\u{001B}\\", into: terminal)
        #expect(readResponse(from: terminal) == "\u{001B}P1$r5;20r\u{001B}\\")
    }

    @Test("scrollback search indexes large terminal history with stable coordinates")
    func scrollbackSearchIndexesLargeHistory() throws {
        let terminal = try #require(cocxycore_terminal_create(8, 48))
        defer { cocxycore_terminal_destroy(terminal) }

        #expect(cocxycore_terminal_enable_scrollback(terminal, 8_192))

        for index in 0..<4_096 {
            let marker = index == 3_777 ? " COCXY_MATCH_3777" : ""
            feed("row-\(String(format: "%04d", index))\(marker)\r\n", into: terminal)
        }

        let engine = try #require(cocxycore_gpu_search_init(terminal))
        defer { cocxycore_gpu_search_destroy(engine) }
        cocxycore_gpu_search_sync(engine, terminal)

        #expect(cocxycore_gpu_search_indexed_rows(engine) >= 4_000)

        var matches = [cocxycore_search_match](
            repeating: cocxycore_search_match(row: 0, start_col: 0, end_col: 0),
            count: 4
        )
        var elapsedMicros: UInt64 = 0
        let count = "COCXY_MATCH_3777".withCString { pattern in
            cocxycore_gpu_search_find(
                engine,
                terminal,
                pattern,
                UInt32("COCXY_MATCH_3777".utf8.count),
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
        #expect(matches[0].row >= 3_700)
        #expect(matches[0].start_col == 9)
        #expect(matches[0].end_col == 24)
    }

    private static func versionedConformanceCases() -> [VersionedConformanceCase] {
        [
            VersionedConformanceCase(id: "VT-PRINT-001", category: "VT") {
                try terminalCase(input: "plain") {
                    screenLine($0, row: 0, columns: 48) == "plain"
                }
            },
            VersionedConformanceCase(id: "VT-CRLF-002", category: "VT") {
                try terminalCase(input: "one\r\ntwo") {
                    screenLine($0, row: 0, columns: 48) == "one"
                        && screenLine($0, row: 1, columns: 48) == "two"
                }
            },
            VersionedConformanceCase(id: "VT-BS-003", category: "VT") {
                try terminalCase(input: "abc\u{0008}Z") {
                    screenLine($0, row: 0, columns: 48) == "abZ"
                }
            },
            VersionedConformanceCase(id: "CSI-CUP-004", category: "CSI") {
                try terminalCase(input: "\u{001B}[3;5HXY") {
                    cell($0, row: 2, col: 4) == "X"
                        && cell($0, row: 2, col: 5) == "Y"
                        && cocxycore_terminal_cursor_row($0) == 2
                        && cocxycore_terminal_cursor_col($0) == 6
                }
            },
            VersionedConformanceCase(id: "CSI-HVP-005", category: "CSI") {
                try terminalCase(input: "\u{001B}[4;7fP") {
                    cell($0, row: 3, col: 6) == "P"
                }
            },
            VersionedConformanceCase(id: "CSI-MOVE-006", category: "CSI") {
                try terminalCase(input: "\u{001B}[5;5H\u{001B}[2A\u{001B}[3CX") {
                    cell($0, row: 2, col: 7) == "X"
                }
            },
            VersionedConformanceCase(id: "CSI-ED-007", category: "CSI") {
                try terminalCase(input: "abc\u{001B}[H\u{001B}[2JZ") {
                    screenLine($0, row: 0, columns: 48) == "Z"
                }
            },
            VersionedConformanceCase(id: "CSI-EL-008", category: "CSI") {
                try terminalCase(input: "abcdef\u{001B}[1;3H\u{001B}[K") {
                    screenLine($0, row: 0, columns: 48) == "ab"
                }
            },
            VersionedConformanceCase(id: "SGR-BOLD-009", category: "SGR") {
                try terminalCase(input: "\u{001B}[1mB") {
                    cocxycore_terminal_cell_style($0, 0, 0) & 0b0000_0001 != 0
                }
            },
            VersionedConformanceCase(id: "SGR-MIXED-010", category: "SGR") {
                try terminalCase(input: "\u{001B}[1;3;4mM") {
                    let style = cocxycore_terminal_cell_style($0, 0, 0)
                    return style & 0b0000_0001 != 0
                        && style & 0b0000_0100 != 0
                        && style & 0b0000_1000 != 0
                }
            },
            VersionedConformanceCase(id: "SGR-FG-INDEXED-011", category: "SGR") {
                try terminalCase(input: "\u{001B}[31mR") {
                    cocxycore_terminal_cell_fg_type($0, 0, 0) == COCXYCORE_COLOR_INDEXED.rawValue
                        && cocxycore_terminal_cell_fg_index($0, 0, 0) == 1
                }
            },
            VersionedConformanceCase(id: "SGR-BG-INDEXED-012", category: "SGR") {
                try terminalCase(input: "\u{001B}[42mG") {
                    cocxycore_terminal_cell_bg_type($0, 0, 0) == COCXYCORE_COLOR_INDEXED.rawValue
                        && cocxycore_terminal_cell_bg_index($0, 0, 0) == 2
                }
            },
            VersionedConformanceCase(id: "SGR-FG-256-013", category: "SGR") {
                try terminalCase(input: "\u{001B}[38;5;196mX") {
                    cocxycore_terminal_cell_fg_type($0, 0, 0) == COCXYCORE_COLOR_INDEXED.rawValue
                        && cocxycore_terminal_cell_fg_index($0, 0, 0) == 196
                }
            },
            VersionedConformanceCase(id: "SGR-BG-TRUECOLOR-014", category: "SGR") {
                try terminalCase(input: "\u{001B}[48;2;10;20;30mB") {
                    guard cocxycore_terminal_cell_bg_type($0, 0, 0) == COCXYCORE_COLOR_RGB.rawValue else {
                        return false
                    }
                    var red: UInt8 = 0
                    var green: UInt8 = 0
                    var blue: UInt8 = 0
                    cocxycore_terminal_cell_bg_rgb($0, 0, 0, &red, &green, &blue)
                    return red == 10 && green == 20 && blue == 30
                }
            },
            VersionedConformanceCase(id: "SGR-RESET-015", category: "SGR") {
                try terminalCase(input: "\u{001B}[1;31mA\u{001B}[0mB") {
                    cocxycore_terminal_cell_style($0, 0, 1) == 0
                        && cocxycore_terminal_cell_fg_type($0, 0, 1) == COCXYCORE_COLOR_DEFAULT.rawValue
                }
            },
            VersionedConformanceCase(id: "MODE-APPCURSOR-016", category: "Mode") {
                try terminalCase(input: "\u{001B}[?1h\u{001B}[?1l") {
                    cocxycore_terminal_mode_app_cursor($0) == false
                }
            },
            VersionedConformanceCase(id: "MODE-BRACKETED-PASTE-017", category: "Mode") {
                try terminalCase(input: "\u{001B}[?2004h") {
                    cocxycore_terminal_mode_bracketed_paste($0)
                        && cocxycore_terminal_get_bracketed_paste_active($0)
                }
            },
            VersionedConformanceCase(id: "MODE-MOUSE-SGR-018", category: "Mode") {
                try terminalCase(input: "\u{001B}[?1006h") {
                    cocxycore_terminal_mode_mouse($0) == 6
                }
            },
            VersionedConformanceCase(id: "MODE-ALT-SCREEN-019", category: "Mode") {
                try terminalCase(input: "Main\u{001B}[?1049hAlt\u{001B}[?1049l") {
                    cocxycore_terminal_is_alt_screen($0) == false
                        && cell($0, row: 0, col: 0) == "M"
                }
            },
            VersionedConformanceCase(id: "CURSOR-VISIBLE-020", category: "Cursor") {
                try terminalCase(input: "\u{001B}[?25l\u{001B}[?25h") {
                    cocxycore_terminal_cursor_visible($0)
                }
            },
            VersionedConformanceCase(id: "CURSOR-SHAPE-021", category: "Cursor") {
                try terminalCase(input: "\u{001B}[2 q") {
                    cocxycore_terminal_cursor_shape($0) == 1
                }
            },
            VersionedConformanceCase(id: "RESPONSE-DSR-022", category: "Response") {
                try terminalCase(input: "\u{001B}[5;10H\u{001B}[6n") {
                    readResponse(from: $0) == "\u{001B}[5;10R"
                }
            },
            VersionedConformanceCase(id: "RESPONSE-DECRQSS-SGR-023", category: "Response") {
                try terminalCase(input: "\u{001B}[1;31m\u{001B}P$qm\u{001B}\\") {
                    readResponse(from: $0) == "\u{001B}P1$r0;1;31m\u{001B}\\"
                }
            },
            VersionedConformanceCase(id: "RESPONSE-DECRQSS-MARGIN-024", category: "Response") {
                try terminalCase(rows: 24, columns: 80, input: "\u{001B}[5;20r\u{001B}P$qr\u{001B}\\") {
                    readResponse(from: $0) == "\u{001B}P1$r5;20r\u{001B}\\"
                }
            },
            VersionedConformanceCase(id: "OSC-HYPERLINK-025", category: "OSC") {
                try terminalCase(input: "\u{001B}]8;id=docs;https://cocxy.dev/docs\u{0007}Click\u{001B}]8;;\u{0007}") {
                    var metadata = cocxycore_hyperlink_metadata()
                    guard cocxycore_terminal_get_hyperlink_at($0, 0, 0, &metadata) else {
                        return false
                    }
                    return string(from: metadata.uri, length: metadata.uri_len) == "https://cocxy.dev/docs"
                        && string(from: metadata.params, length: metadata.params_len) == "id=docs"
                        && metadata.length == 5
                }
            },
            VersionedConformanceCase(id: "UTF8-COMBINING-026", category: "UTF8") {
                try terminalCase(input: "e\u{0301}") {
                    cocxycore_terminal_cell_char($0, 0, 0) == UInt32(UInt8(ascii: "e"))
                        && cocxycore_terminal_cell_combining_count($0, 0, 0) == 1
                        && cocxycore_terminal_cell_combining($0, 0, 0, 0) == 0x0301
                }
            },
            VersionedConformanceCase(id: "SCROLLBACK-HISTORY-027", category: "Scrollback") {
                try terminalCase(rows: 3, columns: 24, input: "") { terminal in
                    guard cocxycore_terminal_enable_scrollback(terminal, 16) else { return false }
                    for index in 0..<8 {
                        feed("row-\(index)\r\n", into: terminal)
                    }
                    return cocxycore_terminal_scrollback_len(terminal) >= 5
                        && cocxycore_terminal_history_rows(terminal) >= 8
                }
            },
            VersionedConformanceCase(id: "SEARCH-NEXT-028", category: "Search") {
                try terminalCase(rows: 4, columns: 32, input: "alpha\r\nneedle\r\nomega") { terminal in
                    var range = cocxycore_buffer_range()
                    let query = Array("needle".utf8)
                    return query.withUnsafeBufferPointer { buffer in
                        cocxycore_terminal_search_next(
                            terminal,
                            buffer.baseAddress,
                            query.count,
                            0,
                            0,
                            true,
                            &range
                        )
                    } && range.start_col == 0 && range.end_col == 5
                }
            },
        ]
    }
}

private struct VersionedConformanceCase {
    let id: String
    let category: String
    let run: () throws -> Bool
}

private func terminalCase(
    rows: UInt16 = 8,
    columns: UInt16 = 48,
    input: String,
    verify: (OpaquePointer) throws -> Bool
) throws -> Bool {
    let terminal = try #require(cocxycore_terminal_create(rows, columns))
    defer { cocxycore_terminal_destroy(terminal) }
    feed(input, into: terminal)
    return try verify(terminal)
}

private func feed(_ text: String, into terminal: OpaquePointer) {
    let bytes = Array(text.utf8)
    cocxycore_terminal_feed(terminal, bytes, bytes.count)
}

private func cell(_ terminal: OpaquePointer, row: UInt16, col: UInt16) -> Character? {
    let codepoint = cocxycore_terminal_cell_char(terminal, row, col)
    guard let scalar = UnicodeScalar(codepoint), codepoint != 0 else {
        return nil
    }
    return Character(scalar)
}

private func screenLine(_ terminal: OpaquePointer, row: UInt16, columns: UInt16) -> String {
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

private func readResponse(from terminal: OpaquePointer) -> String {
    guard cocxycore_terminal_has_response(terminal) else { return "" }
    var buffer = [UInt8](repeating: 0, count: 128)
    let length = cocxycore_terminal_read_response(terminal, &buffer, buffer.count)
    return String(decoding: buffer.prefix(length), as: UTF8.self)
}

private func string(from pointer: UnsafePointer<CChar>?, length: Int) -> String {
    guard let pointer, length > 0 else { return "" }
    let buffer = UnsafeBufferPointer(start: pointer, count: length)
    return String(decoding: buffer.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
