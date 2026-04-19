// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
import CocxyCoreKit
@testable import CocxyTerminal

/// Coverage for CocxyCore's Device Attributes responses through the Swift
/// C API boundary.
///
/// Primary DA (`CSI c`), Secondary DA (`CSI > c`), and Tertiary DA
/// (`CSI = c`) requests are sent by every modern Rust TUI (crossterm,
/// ratatui, tmux, mosh, Codex, Aider) at startup so the client can learn
/// the terminal's capabilities. When the terminal fails to answer, those
/// clients stall waiting — the Fase B smoke test surfaced this exact
/// deadlock with `codex` inside Cocxy. These tests pin the responses at
/// the bridge-visible layer so the regression stays caught even if the
/// Zig-side tests miss a C API change.
///
/// The tests exercise the same path the real PTY feed uses:
///   1. `cocxycore_terminal_feed` consumes the escape sequence.
///   2. `cocxycore_terminal_has_response` reports a pending reply.
///   3. `cocxycore_terminal_read_response` drains the reply into a buffer.
///
/// The production bridge wires the same three calls into its PTY read
/// source (see `CocxyCoreBridge.createReadSource`) so a green test here
/// mirrors runtime behaviour on a live terminal.
@Suite("CocxyCore Device Attributes")
struct CocxyCoreDeviceAttributesSwiftTestingTests {

    // MARK: - Helpers

    /// Spawns a scratch terminal (24×80) via the C API, feeds the given
    /// escape sequence, and returns any pending response as a UTF-8
    /// string. Always tears the terminal down so the test leaves no
    /// C-side state behind.
    private func response(for escape: String) -> String {
        let terminal = cocxycore_terminal_create(24, 80)
        defer { cocxycore_terminal_destroy(terminal) }
        #expect(terminal != nil, "cocxycore_terminal_create should succeed")
        guard let terminal else { return "" }

        let bytes = Array(escape.utf8)
        cocxycore_terminal_feed(terminal, bytes, bytes.count)

        guard cocxycore_terminal_has_response(terminal) else { return "" }

        var buf = [UInt8](repeating: 0, count: 256)
        let copied = cocxycore_terminal_read_response(terminal, &buf, buf.count)
        return String(decoding: buf.prefix(copied), as: UTF8.self)
    }

    // MARK: - Primary DA

    @Test("Primary DA (CSI c) returns VT220 with ANSI color")
    func primaryDARespondsWithVT220ColorIdentity() {
        // Crossterm / ratatui / tmux parse the `62;22` feature set to
        // enable the full interactive mode. Any drift in this answer
        // can silently regress support for those clients.
        #expect(response(for: "\u{001B}[c") == "\u{001B}[?62;22c")
    }

    @Test("Primary DA with explicit 0 param (CSI 0 c) responds identically")
    func primaryDAWithExplicitZeroResponds() {
        #expect(response(for: "\u{001B}[0c") == "\u{001B}[?62;22c")
    }

    @Test("Primary DA with non-zero param is silently ignored per ECMA-48")
    func primaryDAIgnoresReservedParams() {
        // Any `Ps` other than 0 is reserved. Terminals must not reply
        // so clients can distinguish "DA" from "private extension".
        #expect(response(for: "\u{001B}[5c").isEmpty)
    }

    // MARK: - Secondary DA

    @Test("Secondary DA (CSI > c) reports firmware in xterm format")
    func secondaryDARespondsWithFirmware() {
        // Format: `CSI > Pp ; Pv ; Pc c`
        //   Pp = 0    (xterm-compatible terminal type)
        //   Pv = 1304 (CocxyCore 0.13.4 encoded as major*100 + minor + patch)
        //   Pc = 0    (ROM cartridge — always 0)
        #expect(response(for: "\u{001B}[>c") == "\u{001B}[>0;1304;0c")
    }

    // MARK: - Tertiary DA

    @Test("Tertiary DA (CSI = c) returns DCS-wrapped unit id")
    func tertiaryDARespondsWithDCSPayload() {
        // VT420 tertiary DA response:
        //   DCS ! | <hex> ST  =  ESC P ! | 00000000 ESC \\
        // Clients that treat missing replies as a hard stall (tmux,
        // crossterm ≥ 0.27) unblock on any well-formed reply.
        #expect(response(for: "\u{001B}[=c") == "\u{001B}P!|00000000\u{001B}\\")
    }

    // MARK: - Regression: DSR still works

    @Test("DSR cursor position (CSI 6 n) continues to respond after DA additions")
    func dsrCursorPositionStillResponds() {
        // Sanity check that adding three DA cases did not shadow the
        // pre-existing `n` dispatch branch. Position the cursor
        // first so the response carries a non-trivial row/col pair.
        let combined = "\u{001B}[5;10H\u{001B}[6n"
        #expect(response(for: combined) == "\u{001B}[5;10R")
    }
}
