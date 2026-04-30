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
        var cells: [PTYDaemonGridCell] = []
        cells.reserveCapacity(Int(rows) * Int(columns))

        for row in 0..<rows {
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
            scrollbackTop: Int(cocxycore_terminal_history_visible_start(terminal)),
            images: []
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
