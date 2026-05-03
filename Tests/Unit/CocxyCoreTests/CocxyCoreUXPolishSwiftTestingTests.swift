// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
import CocxyCoreKit

@Suite("CocxyCore UX Polish")
struct CocxyCoreUXPolishSwiftTestingTests {

    @Test("vendored CocxyCore exposes CC-9 bell cursor paste and theme APIs")
    func vendoredCocxyCoreExposesCC9UXPolishAPIs() throws {
        let terminal = try #require(cocxycore_terminal_create(4, 40))
        defer { cocxycore_terminal_destroy(terminal) }

        #expect(cocxycore_terminal_bell_mode(terminal) == 0)
        cocxycore_terminal_set_bell_mode(terminal, 2)
        #expect(cocxycore_terminal_bell_mode(terminal) == 2)
        #expect(cocxycore_terminal_set_bell_audio_file(terminal, "/tmp/cocxy-bell.wav"))

        var bellPath = [UInt8](repeating: 0, count: 128)
        let bellPathLength = cocxycore_terminal_bell_audio_file(terminal, &bellPath, bellPath.count)
        #expect(String(decoding: bellPath.prefix(bellPathLength), as: UTF8.self) == "/tmp/cocxy-bell.wav")

        #expect(cocxycore_terminal_get_bracketed_paste_active(terminal) == false)
        feed("\u{001B}[?2004h", into: terminal)
        #expect(cocxycore_terminal_get_bracketed_paste_active(terminal))
        cocxycore_terminal_set_bracketed_paste_force(terminal, -1)
        #expect(cocxycore_terminal_mode_bracketed_paste(terminal))
        #expect(cocxycore_terminal_get_bracketed_paste_active(terminal) == false)

        #expect(cocxycore_terminal_cursor_blink_rate_ms(terminal) == 500)
        cocxycore_terminal_set_cursor_shape(terminal, 3)
        cocxycore_terminal_set_cursor_blink_rate_ms(terminal, 225)
        cocxycore_terminal_set_cursor_color_override(terminal, 0x10203040)
        #expect(cocxycore_terminal_cursor_shape(terminal) == 6)
        #expect(cocxycore_terminal_cursor_blink_rate_ms(terminal) == 225)

        var cursor = cocxycore_render_cursor()
        cocxycore_terminal_frame_cursor(terminal, &cursor)
        #expect(cursor.color.r == 0x10)
        #expect(cursor.color.g == 0x20)
        #expect(cursor.color.b == 0x30)
        #expect(cursor.color.a == 0x40)

        var theme = cocxycore_theme()
        theme.foreground = cocxycore_rgba(r: 10, g: 20, b: 30, a: 255)
        theme.background = cocxycore_rgba(r: 1, g: 2, b: 3, a: 255)
        theme.cursor = cocxycore_rgba(r: 40, g: 50, b: 60, a: 255)
        theme.selection = cocxycore_rgba(r: 70, g: 80, b: 90, a: 128)
        cocxycore_terminal_set_theme_with_transition_ms(terminal, &theme, 300)
        #expect(cocxycore_terminal_theme_transition_active(terminal))
        cocxycore_terminal_advance_theme_transition_ms(terminal, 300)
        #expect(cocxycore_terminal_theme_transition_active(terminal) == false)

        var foreground = cocxycore_rgba()
        cocxycore_terminal_resolve_cell_colors(terminal, 0, 0, &foreground, nil)
        #expect(foreground.r == 10)
        #expect(foreground.g == 20)
        #expect(foreground.b == 30)
    }
}

private func feed(_ text: String, into terminal: OpaquePointer) {
    let bytes = Array(text.utf8)
    cocxycore_terminal_feed(terminal, bytes, bytes.count)
}
