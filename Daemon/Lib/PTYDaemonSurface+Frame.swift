// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonSurface+Frame.swift - Frame builder for the daemon surface.

import CocxyCoreKit
import CocxyShared
import Foundation

extension PTYDaemonSurface {
    /// Builds a fresh `PTYDaemonSurfaceFrame` for the surface, taking the
    /// terminal lock for the duration of the read.
    func makeFrame() -> PTYDaemonSurfaceFrame? {
        terminalLock.withLock {
            makeFrameLocked()
        }
    }

    /// Builds a frame assuming the caller already holds `terminalLock`.
    /// `readAvailablePTYBytes` calls this from within its own lock to avoid
    /// reacquiring the lock for each read tick.
    func makeFrameLocked() -> PTYDaemonSurfaceFrame? {
        guard cocxycore_terminal_build_frame(terminal) else { return nil }
        revision &+= 1
        let rows = cocxycore_terminal_rows(terminal)
        let columns = cocxycore_terminal_cols(terminal)
        let visibleStart = cocxycore_terminal_history_visible_start(terminal)
        var cells: [PTYDaemonGridCell] = []
        cells.reserveCapacity(Int(rows) * Int(columns))
        var wrappedRows: [UInt16] = []

        for row in 0..<rows {
            if cocxycore_terminal_row_wrapped(terminal, visibleStart + UInt32(row)) {
                wrappedRows.append(row)
            }
            for column in 0..<columns {
                var renderCell = cocxycore_render_cell()
                cocxycore_terminal_frame_cell(terminal, row, column, &renderCell)
                cells.append(
                    PTYDaemonGridCell(
                        row: row,
                        column: column,
                        glyph: renderCell.codepoint,
                        foregroundRGBA: Self.pack(renderCell.fg),
                        backgroundRGBA: Self.pack(renderCell.bg),
                        attributes: UInt16(renderCell.flags)
                    )
                )
            }
        }

        var renderCursor = cocxycore_render_cursor()
        cocxycore_terminal_frame_cursor(terminal, &renderCursor)
        let detectedContents = detectedContentsLocked(
            visibleStart: visibleStart,
            rows: rows,
            columns: columns
        )

        return PTYDaemonSurfaceFrame(
            surfaceID: surfaceID,
            revision: revision,
            timestamp: Date().timeIntervalSince1970,
            columns: columns,
            rows: rows,
            cells: cells,
            cursor: PTYDaemonCursor(
                row: renderCursor.row,
                column: renderCursor.col,
                visible: renderCursor.visible,
                style: Self.cursorStyle(renderCursor.shape)
            ),
            scrollbackTop: Int(visibleStart),
            historyMaxVisibleStart: Int(cocxycore_terminal_history_max_visible_start(terminal)),
            images: [],
            wrappedRows: wrappedRows,
            mouseTrackingMode: cocxycore_terminal_mode_mouse_tracking(terminal),
            mouseEncodingMode: cocxycore_terminal_mode_mouse_encoding(terminal),
            isAltScreen: cocxycore_terminal_is_alt_screen(terminal),
            bracketedPasteMode: cocxycore_terminal_mode_bracketed_paste(terminal),
            alternateScrollMode: cocxycore_terminal_mode_alternate_scroll(terminal),
            synchronizedOutput: cocxycore_terminal_mode_synchronized_output(terminal),
            detectedContents: detectedContents
        )
    }

    private func detectedContentsLocked(
        visibleStart: UInt32,
        rows: UInt16,
        columns: UInt16
    ) -> [PTYDaemonDetectedContent] {
        guard rows > 0, columns > 0 else { return [] }
        let (maxRow, overflowed) = visibleStart.addingReportingOverflow(UInt32(rows - 1))
        guard overflowed == false else { return [] }
        var fromRow = visibleStart
        var fromColumn: UInt16 = 0
        var contents: [PTYDaemonDetectedContent] = []
        contents.reserveCapacity(8)

        for _ in 0..<256 {
            var detected = cocxycore_detected_content()
            guard cocxycore_terminal_detect_content_next(
                terminal,
                fromRow,
                fromColumn,
                maxRow,
                &detected
            ), let content = Self.detectedContent(from: detected) else {
                break
            }
            guard detected.end_row >= fromRow,
                  detected.end_row <= maxRow,
                  detected.end_col < columns,
                  detected.end_row > fromRow || detected.end_col >= fromColumn else {
                break
            }
            let nextColumn = Int(detected.end_col) + 1
            contents.append(content)
            if nextColumn < Int(columns) {
                fromRow = detected.end_row
                fromColumn = UInt16(nextColumn)
            } else {
                guard detected.end_row < maxRow else { break }
                fromRow = detected.end_row + 1
                fromColumn = 0
            }
        }
        return contents
    }

    private static func detectedContent(
        from raw: cocxycore_detected_content
    ) -> PTYDaemonDetectedContent? {
        guard let kind = PTYDaemonDetectedContent.Kind(rawValue: raw.kind),
              let pointer = raw.text,
              raw.text_len > 0 else {
            return nil
        }
        let bytes = UnsafeBufferPointer(start: pointer, count: raw.text_len)
            .map { UInt8(bitPattern: $0) }
        let targetLength = min(raw.target_len, bytes.count)
        return PTYDaemonDetectedContent(
            kind: kind,
            text: String(decoding: bytes, as: UTF8.self),
            target: String(decoding: bytes.prefix(targetLength), as: UTF8.self),
            startRow: raw.start_row,
            startColumn: raw.start_col,
            endRow: raw.end_row,
            endColumn: raw.end_col,
            line: raw.line > 0 ? raw.line : nil,
            column: raw.column > 0 ? raw.column : nil,
            isExplicitHyperlink: raw.explicit_hyperlink
        )
    }

    static func pack(_ rgba: cocxycore_rgba) -> UInt32 {
        (UInt32(rgba.r) << 24) |
            (UInt32(rgba.g) << 16) |
            (UInt32(rgba.b) << 8) |
            UInt32(rgba.a)
    }

    static func cursorStyle(_ shape: UInt8) -> String {
        switch shape {
        case 2, 3: return "underline"
        case 4, 5: return "bar"
        default: return "block"
        }
    }
}
