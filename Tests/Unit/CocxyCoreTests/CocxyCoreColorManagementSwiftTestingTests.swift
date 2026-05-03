// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
import CocxyCoreKit

@Suite("CocxyCore Color Management")
struct CocxyCoreColorManagementSwiftTestingTests {

    @Test("vendored CocxyCore exposes color space, ICC path, and managed output")
    func vendoredCocxyCoreExposesColorManagementAPIs() throws {
        let terminal = try #require(cocxycore_terminal_create(4, 40))
        defer { cocxycore_terminal_destroy(terminal) }

        #expect(cocxycore_terminal_get_color_space(terminal) == COCXYCORE_COLOR_SPACE_SRGB)
        #expect(cocxycore_terminal_set_icc_profile_path(terminal, "/tmp/cocxy-display.icc"))
        var profilePath = [UInt8](repeating: 0, count: 128)
        let copied = cocxycore_terminal_icc_profile_path(terminal, &profilePath, profilePath.count)
        #expect(String(decoding: profilePath.prefix(copied), as: UTF8.self) == "/tmp/cocxy-display.icc")
        #expect(cocxycore_terminal_set_icc_profile_path(terminal, "/tmp/not-a-profile.txt") == false)
        #expect(cocxycore_terminal_supports_wide_gamut(terminal))

        feed("x", into: terminal)
        cocxycore_terminal_set_theme(terminal, 255, 0, 0, 0, 0, 0, 255, 0, 0)

        var foreground = cocxycore_rgba()
        cocxycore_terminal_resolve_cell_colors(terminal, 0, 0, &foreground, nil)
        #expect(foreground.r == 255)
        #expect(foreground.g == 0)
        #expect(foreground.b == 0)

        cocxycore_terminal_set_color_space(terminal, COCXYCORE_COLOR_SPACE_DISPLAY_P3)
        #expect(cocxycore_terminal_get_color_space(terminal) == COCXYCORE_COLOR_SPACE_DISPLAY_P3)
        cocxycore_terminal_set_color_space(terminal, cocxycore_color_space(rawValue: 99))
        #expect(cocxycore_terminal_get_color_space(terminal) == COCXYCORE_COLOR_SPACE_DISPLAY_P3)

        cocxycore_terminal_resolve_cell_colors(terminal, 0, 0, &foreground, nil)
        #expect(foreground.r == 234)
        #expect(foreground.g == 51)
        #expect(foreground.b == 35)

        #expect(cocxycore_terminal_set_font(terminal, nil, 14.0, 2.0, false))
        #expect(cocxycore_terminal_build_frame(terminal))
        var frameCell = cocxycore_render_cell()
        cocxycore_terminal_frame_cell(terminal, 0, 0, &frameCell)
        #expect(frameCell.fg.r == 234)
        #expect(frameCell.fg.g == 51)
        #expect(frameCell.fg.b == 35)
    }
}

private func feed(_ text: String, into terminal: OpaquePointer) {
    let bytes = Array(text.utf8)
    cocxycore_terminal_feed(terminal, bytes, bytes.count)
}
