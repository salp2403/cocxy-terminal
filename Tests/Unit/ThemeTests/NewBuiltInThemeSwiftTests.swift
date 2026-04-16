// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("Built-in themes — Catppuccin Frappe")
@MainActor
struct CatppuccinFrappeTests {

    let palette: ThemePalette

    init() throws {
        let engine = ThemeEngineImpl()
        palette = try engine.themeByName("Catppuccin Frappe").palette
    }

    @Test func backgroundIsBase() {
        #expect(palette.background == "#303446")
    }

    @Test func foregroundIsText() {
        #expect(palette.foreground == "#c6d0f5")
    }

    @Test func cursorIsRosewater() {
        #expect(palette.cursor == "#f2d5cf")
    }

    @Test func ansiRedIsRed() {
        #expect(palette.ansiColors[1] == "#e78284")
    }

    @Test func ansiGreenIsGreen() {
        #expect(palette.ansiColors[2] == "#a6d189")
    }

    @Test func ansiBlueIsBlue() {
        #expect(palette.ansiColors[4] == "#8caaee")
    }

    @Test func brightBlackIsSurface1() {
        #expect(palette.ansiColors[8] == "#51576d")
    }

    @Test func brightWhiteIsSubtext0() {
        #expect(palette.ansiColors[15] == "#a5adce")
    }

    @Test func tabInactiveIsMantle() {
        #expect(palette.tabInactiveBackground == "#292c3c")
    }

    @Test func has16AnsiColors() {
        #expect(palette.ansiColors.count == 16)
    }
}

@Suite("Built-in themes — Catppuccin Macchiato")
@MainActor
struct CatppuccinMacchiatoTests {

    let palette: ThemePalette

    init() throws {
        let engine = ThemeEngineImpl()
        palette = try engine.themeByName("Catppuccin Macchiato").palette
    }

    @Test func backgroundIsBase() {
        #expect(palette.background == "#24273a")
    }

    @Test func foregroundIsText() {
        #expect(palette.foreground == "#cad3f5")
    }

    @Test func cursorIsRosewater() {
        #expect(palette.cursor == "#f4dbd6")
    }

    @Test func ansiRedIsRed() {
        #expect(palette.ansiColors[1] == "#ed8796")
    }

    @Test func ansiGreenIsGreen() {
        #expect(palette.ansiColors[2] == "#a6da95")
    }

    @Test func ansiBlueIsBlue() {
        #expect(palette.ansiColors[4] == "#8aadf4")
    }

    @Test func brightBlackIsSurface1() {
        #expect(palette.ansiColors[8] == "#494d64")
    }

    @Test func brightWhiteIsSubtext0() {
        #expect(palette.ansiColors[15] == "#a5adcb")
    }

    @Test func tabInactiveIsMantle() {
        #expect(palette.tabInactiveBackground == "#1e2030")
    }

    @Test func has16AnsiColors() {
        #expect(palette.ansiColors.count == 16)
    }
}

@Suite("Built-in themes — Nord")
@MainActor
struct NordThemeTests {

    let palette: ThemePalette

    init() throws {
        let engine = ThemeEngineImpl()
        palette = try engine.themeByName("Nord").palette
    }

    @Test func backgroundIsNord0() {
        #expect(palette.background == "#2e3440")
    }

    @Test func foregroundIsNord4() {
        #expect(palette.foreground == "#d8dee9")
    }

    @Test func ansiRedIsNord11() {
        #expect(palette.ansiColors[1] == "#bf616a")
    }

    @Test func ansiGreenIsNord14() {
        #expect(palette.ansiColors[2] == "#a3be8c")
    }

    @Test func ansiBlueIsNord9() {
        #expect(palette.ansiColors[4] == "#81a1c1")
    }

    @Test func ansiCyanIsNord8() {
        #expect(palette.ansiColors[6] == "#88c0d0")
    }

    @Test func brightCyanIsNord7() {
        #expect(palette.ansiColors[14] == "#8fbcbb")
    }

    @Test func brightWhiteIsNord6() {
        #expect(palette.ansiColors[15] == "#eceff4")
    }

    @Test func has16AnsiColors() {
        #expect(palette.ansiColors.count == 16)
    }
}

@Suite("Built-in themes — Gruvbox Dark")
@MainActor
struct GruvboxDarkThemeTests {

    let palette: ThemePalette

    init() throws {
        let engine = ThemeEngineImpl()
        palette = try engine.themeByName("Gruvbox Dark").palette
    }

    @Test func backgroundIsBg() {
        #expect(palette.background == "#282828")
    }

    @Test func foregroundIsFg() {
        #expect(palette.foreground == "#ebdbb2")
    }

    @Test func ansiRedIsDarkRed() {
        #expect(palette.ansiColors[1] == "#cc241d")
    }

    @Test func brightRedIsBrightRed() {
        #expect(palette.ansiColors[9] == "#fb4934")
    }

    @Test func ansiGreenIsDarkGreen() {
        #expect(palette.ansiColors[2] == "#98971a")
    }

    @Test func brightGreenIsBrightGreen() {
        #expect(palette.ansiColors[10] == "#b8bb26")
    }

    @Test func ansiBlueIsDarkBlue() {
        #expect(palette.ansiColors[4] == "#458588")
    }

    @Test func brightBlueIsBrightBlue() {
        #expect(palette.ansiColors[12] == "#83a598")
    }

    @Test func has16AnsiColors() {
        #expect(palette.ansiColors.count == 16)
    }
}

@Suite("Built-in themes — Tokyo Night")
@MainActor
struct TokyoNightThemeTests {

    let palette: ThemePalette

    init() throws {
        let engine = ThemeEngineImpl()
        palette = try engine.themeByName("Tokyo Night").palette
    }

    @Test func backgroundIsStormBg() {
        #expect(palette.background == "#1a1b26")
    }

    @Test func foregroundIsText() {
        #expect(palette.foreground == "#a9b1d6")
    }

    @Test func cursorIsBrightFg() {
        #expect(palette.cursor == "#c0caf5")
    }

    @Test func ansiRedIsRed() {
        #expect(palette.ansiColors[1] == "#f7768e")
    }

    @Test func ansiGreenIsGreen() {
        #expect(palette.ansiColors[2] == "#9ece6a")
    }

    @Test func ansiBlueIsBlue() {
        #expect(palette.ansiColors[4] == "#7aa2f7")
    }

    @Test func ansiMagentaIsPurple() {
        #expect(palette.ansiColors[5] == "#bb9af7")
    }

    @Test func ansiCyanIsCyan() {
        #expect(palette.ansiColors[6] == "#7dcfff")
    }

    @Test func has16AnsiColors() {
        #expect(palette.ansiColors.count == 16)
    }
}

@Suite("ThemeEngine loads all 11 built-in themes")
@MainActor
struct ThemeEngineNewCountTests {

    @Test func engineHas11BuiltInThemes() {
        let engine = ThemeEngineImpl()
        let builtInCount = engine.availableThemes.filter {
            if case .builtIn = $0.source { return true }
            return false
        }.count
        #expect(builtInCount == 11)
    }

    @Test func engineHas9DarkAnd2LightThemes() {
        let engine = ThemeEngineImpl()
        let dark = engine.availableThemes.filter { $0.variant == .dark }.count
        let light = engine.availableThemes.filter { $0.variant == .light }.count
        #expect(dark == 9)
        #expect(light == 2)
    }

    @Test func allNewThemesResolvableByName() throws {
        let engine = ThemeEngineImpl()
        let newNames = [
            "Catppuccin Frappe",
            "Catppuccin Macchiato",
            "Nord",
            "Gruvbox Dark",
            "Tokyo Night"
        ]
        for name in newNames {
            let theme = try engine.themeByName(name)
            #expect(theme.metadata.name == name)
        }
    }

    @Test func newThemesResolvableByKebabCase() throws {
        let engine = ThemeEngineImpl()
        let kebabNames = [
            "catppuccin-frappe",
            "catppuccin-macchiato",
            "gruvbox-dark",
            "tokyo-night"
        ]
        for name in kebabNames {
            #expect(throws: Never.self) {
                _ = try engine.themeByName(name)
            }
        }
    }
}
