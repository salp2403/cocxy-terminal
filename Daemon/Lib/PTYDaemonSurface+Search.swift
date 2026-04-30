// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonSurface+Search.swift - Literal and regex search over scrollback.

import CocxyCoreKit
import CocxyShared
import Foundation

extension PTYDaemonSurface {
    /// Linear scan of the scrollback using CocxyCore's built-in matcher.
    /// Caller must hold `terminalLock`.
    func literalSearch(
        query: String,
        caseSensitive: Bool,
        maxResults: Int
    ) -> [PTYDaemonSearchResult] {
        let capped = max(1, min(maxResults, 200))
        var results: [PTYDaemonSearchResult] = []
        var fromRow: UInt32 = 0
        var fromColumn: UInt16 = 0
        let queryBytes = Array(query.utf8)
        let maxRows = cocxycore_terminal_history_rows(terminal)

        while results.count < capped {
            var range = cocxycore_buffer_range()
            let found = queryBytes.withUnsafeBufferPointer { pointer in
                cocxycore_terminal_search_next(
                    terminal,
                    pointer.baseAddress,
                    queryBytes.count,
                    fromRow,
                    fromColumn,
                    caseSensitive,
                    &range
                )
            }
            guard found else { break }
            results.append(
                PTYDaemonSearchResult(
                    id: UUID().uuidString,
                    lineNumber: Int(range.start_row),
                    column: Int(range.start_col),
                    matchText: query,
                    contextBefore: nil,
                    contextAfter: lineText(row: range.start_row)
                )
            )

            fromRow = range.end_row
            fromColumn = range.end_col &+ 1
            if fromColumn >= cocxycore_terminal_cols(terminal) {
                fromRow &+= 1
                fromColumn = 0
            }
            if fromRow >= maxRows { break }
        }
        return results
    }

    /// Regex search via the GPU search engine, used when the caller passes
    /// `useRegex: true`. Returns `nil` to signal the caller should fall back
    /// to the literal matcher.
    func regexSearch(
        query: String,
        caseSensitive: Bool,
        maxResults: Int
    ) -> [PTYDaemonSearchResult]? {
        guard let engine = cocxycore_gpu_search_init(terminal) else { return nil }
        defer { cocxycore_gpu_search_destroy(engine) }
        cocxycore_gpu_search_sync(engine, terminal)

        let capped = max(1, min(maxResults, 200))
        var matches = Array(
            repeating: cocxycore_search_match(row: 0, start_col: 0, end_col: 0),
            count: capped
        )
        var elapsed: UInt64 = 0
        let found = query.withCString { queryPtr in
            matches.withUnsafeMutableBufferPointer { buffer -> UInt32 in
                guard let baseAddress = buffer.baseAddress else { return 0 }
                return cocxycore_gpu_search_find(
                    engine,
                    terminal,
                    queryPtr,
                    UInt32(query.utf8.count),
                    true,
                    !caseSensitive,
                    0,
                    0,
                    0,
                    UInt32(capped),
                    baseAddress,
                    &elapsed
                )
            }
        }

        guard found > 0 else { return [] }
        return matches.prefix(Int(found)).map { match in
            PTYDaemonSearchResult(
                id: UUID().uuidString,
                lineNumber: Int(match.row),
                column: Int(match.start_col),
                matchText: query,
                contextBefore: nil,
                contextAfter: lineText(row: match.row)
            )
        }
    }

    /// Reads the row's visible text and trims surrounding whitespace.
    /// Caller must hold `terminalLock`.
    func lineText(row: UInt32) -> String {
        let columns = cocxycore_terminal_cols(terminal)
        var scalars = String.UnicodeScalarView()
        for column in 0..<columns {
            let codepoint = cocxycore_terminal_history_cell_char(terminal, row, column)
            guard codepoint != 0, let scalar = UnicodeScalar(codepoint) else { continue }
            scalars.append(scalar)
        }
        return String(scalars).trimmingCharacters(in: .whitespaces)
    }
}
