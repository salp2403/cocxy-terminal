// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// Phase6AdditionalTests.swift - Tests adicionales escritos por QA (T-045).
//
// Cubre los gaps identificados en el code review de Fase 6:
//  - Color accuracy: TODOS los 16 colores ANSI de Mocha y Latte contra spec oficial
//  - CodableColor edge cases: string vacío, solo "#", longitud errónea, lower/upper
//  - Theme round-trip: TOML -> parse -> serialize -> comparar
//  - Auto-switch integration: cambio de apariencia -> engine elige tema correcto
//  - Imported-theme edge cases: solo palette, background ausente, claves desconocidas
//  - Hot-reload robustness: archivo sin contenido, reload múltiple, debounce cancelado
//  - Config cascade: tema vía hot-reload -> config reflejada

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - 1. Color accuracy: todos los 16 ANSI de Mocha contra spec oficial

/// Spec oficial: https://github.com/catppuccin/catppuccin
/// Mocha palette: https://catppuccin.com/palette
@MainActor
final class CatppuccinMochaAllAnsiColorsTests: XCTestCase {

    private var palette: ThemePalette!

    override func setUp() {
        super.setUp()
        let engine = ThemeEngineImpl()
        palette = (try? engine.themeByName("Catppuccin Mocha"))?.palette
        XCTAssertNotNil(palette)
    }

    // Normal ANSI (índices 0-7)
    func testMochaAnsi0BlackIsSurface1() {
        // Surface1: #45475a
        XCTAssertEqual(palette.ansiColors[0], "#45475a",
            "Mocha ANSI[0] black debe ser Surface1 (#45475a)")
    }

    func testMochaAnsi1Red() {
        // Red: #f38ba8
        XCTAssertEqual(palette.ansiColors[1], "#f38ba8")
    }

    func testMochaAnsi2Green() {
        // Green: #a6e3a1
        XCTAssertEqual(palette.ansiColors[2], "#a6e3a1")
    }

    func testMochaAnsi3Yellow() {
        // Yellow: #f9e2af
        XCTAssertEqual(palette.ansiColors[3], "#f9e2af")
    }

    func testMochaAnsi4Blue() {
        // Blue: #89b4fa
        XCTAssertEqual(palette.ansiColors[4], "#89b4fa")
    }

    func testMochaAnsi5MagentaIsPink() {
        // Pink: #f5c2e7
        XCTAssertEqual(palette.ansiColors[5], "#f5c2e7")
    }

    func testMochaAnsi6CyanIsTeal() {
        // Teal: #94e2d5
        XCTAssertEqual(palette.ansiColors[6], "#94e2d5")
    }

    func testMochaAnsi7WhiteIsSubtext1() {
        // Subtext1: #bac2de
        XCTAssertEqual(palette.ansiColors[7], "#bac2de",
            "Mocha ANSI[7] white debe ser Subtext1 (#bac2de)")
    }

    // Bright ANSI (índices 8-15)
    func testMochaAnsi8BrightBlackIsSurface2() {
        // Surface2: #585b70
        XCTAssertEqual(palette.ansiColors[8], "#585b70",
            "Mocha ANSI[8] bright-black debe ser Surface2 (#585b70)")
    }

    func testMochaAnsi9BrightRedIsRed() {
        // Bright red == red en Mocha: #f38ba8
        XCTAssertEqual(palette.ansiColors[9], "#f38ba8")
    }

    func testMochaAnsi10BrightGreenIsGreen() {
        XCTAssertEqual(palette.ansiColors[10], "#a6e3a1")
    }

    func testMochaAnsi11BrightYellowIsYellow() {
        XCTAssertEqual(palette.ansiColors[11], "#f9e2af")
    }

    func testMochaAnsi12BrightBlueIsBlue() {
        XCTAssertEqual(palette.ansiColors[12], "#89b4fa")
    }

    func testMochaAnsi13BrightMagentaIsPink() {
        XCTAssertEqual(palette.ansiColors[13], "#f5c2e7")
    }

    func testMochaAnsi14BrightCyanIsTeal() {
        XCTAssertEqual(palette.ansiColors[14], "#94e2d5")
    }

    func testMochaAnsi15BrightWhiteIsSubtext0() {
        // Subtext0: #a6adc8
        XCTAssertEqual(palette.ansiColors[15], "#a6adc8",
            "Mocha ANSI[15] bright-white debe ser Subtext0 (#a6adc8)")
    }

    func testMochaHasExactly16AnsiColors() {
        XCTAssertEqual(palette.ansiColors.count, 16)
    }
}

// MARK: - 2. Color accuracy: todos los 16 ANSI de Latte contra spec oficial

@MainActor
final class CatppuccinLatteAllAnsiColorsTests: XCTestCase {

    private var palette: ThemePalette!

    override func setUp() {
        super.setUp()
        let engine = ThemeEngineImpl()
        palette = (try? engine.themeByName("Catppuccin Latte"))?.palette
        XCTAssertNotNil(palette)
    }

    func testLatteAnsi0BlackIsSubtext0() {
        // Latte normal black = #5c5f77
        XCTAssertEqual(palette.ansiColors[0], "#5c5f77",
            "Latte ANSI[0] black debe ser #5c5f77")
    }

    func testLatteAnsi1Red() {
        XCTAssertEqual(palette.ansiColors[1], "#d20f39")
    }

    func testLatteAnsi2Green() {
        XCTAssertEqual(palette.ansiColors[2], "#40a02b")
    }

    func testLatteAnsi3Yellow() {
        XCTAssertEqual(palette.ansiColors[3], "#df8e1d")
    }

    func testLatteAnsi4Blue() {
        XCTAssertEqual(palette.ansiColors[4], "#1e66f5")
    }

    func testLatteAnsi5MagentaIsPink() {
        // Pink: #ea76cb
        XCTAssertEqual(palette.ansiColors[5], "#ea76cb")
    }

    func testLatteAnsi6CyanIsTeal() {
        // Teal: #179299
        XCTAssertEqual(palette.ansiColors[6], "#179299")
    }

    func testLatteAnsi7WhiteIsSurface2() {
        // Surface2: #acb0be
        XCTAssertEqual(palette.ansiColors[7], "#acb0be",
            "Latte ANSI[7] white debe ser Surface2 (#acb0be)")
    }

    func testLatteAnsi8BrightBlackIsOverlay0() {
        // Overlay0: #6c6f85
        XCTAssertEqual(palette.ansiColors[8], "#6c6f85",
            "Latte ANSI[8] bright-black debe ser Overlay0 (#6c6f85)")
    }

    func testLatteAnsi9BrightRedIsRed() {
        XCTAssertEqual(palette.ansiColors[9], "#d20f39")
    }

    func testLatteAnsi10BrightGreenIsGreen() {
        XCTAssertEqual(palette.ansiColors[10], "#40a02b")
    }

    func testLatteAnsi11BrightYellowIsYellow() {
        XCTAssertEqual(palette.ansiColors[11], "#df8e1d")
    }

    func testLatteAnsi12BrightBlueIsBlue() {
        XCTAssertEqual(palette.ansiColors[12], "#1e66f5")
    }

    func testLatteAnsi13BrightMagentaIsPink() {
        XCTAssertEqual(palette.ansiColors[13], "#ea76cb")
    }

    func testLatteAnsi14BrightCyanIsTeal() {
        XCTAssertEqual(palette.ansiColors[14], "#179299")
    }

    func testLatteAnsi15BrightWhiteIsSurface1() {
        // Surface1: #bcc0cc
        XCTAssertEqual(palette.ansiColors[15], "#bcc0cc",
            "Latte ANSI[15] bright-white debe ser Surface1 (#bcc0cc)")
    }

    func testLatteHasExactly16AnsiColors() {
        XCTAssertEqual(palette.ansiColors.count, 16)
    }
}

// MARK: - 3. CodableColor edge cases adicionales

final class CodableColorEdgeCaseTests: XCTestCase {

    // Solo el signo "#" sin dígitos -> fallback a negro
    func testHashOnlyStringFallsBackToBlack() {
        let color = CodableColor(hex: "#")
        let ns = color.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(ns.redComponent, 0.0, accuracy: 0.001,
            "# solo debe producir negro (fallback)")
        XCTAssertEqual(ns.greenComponent, 0.0, accuracy: 0.001)
        XCTAssertEqual(ns.blueComponent, 0.0, accuracy: 0.001)
    }

    // String vacío -> fallback a negro
    func testEmptyStringFallsBackToBlack() {
        let color = CodableColor(hex: "")
        let ns = color.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(ns.redComponent, 0.0, accuracy: 0.001)
    }

    // Longitud incorrecta: 5 caracteres hex tras # -> fallback
    func testFiveDigitHexFallsBackToBlack() {
        let color = CodableColor(hex: "#12345")
        let ns = color.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(ns.redComponent, 0.0, accuracy: 0.001,
            "Hex de 5 dígitos no es válido")
    }

    // Longitud incorrecta: 7 caracteres hex tras # -> fallback
    func testSevenDigitHexFallsBackToBlack() {
        let color = CodableColor(hex: "#1234567")
        let ns = color.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(ns.redComponent, 0.0, accuracy: 0.001,
            "Hex de 7 dígitos no es válido")
    }

    // Lowercase vs uppercase: deben producir el mismo NSColor
    func testLowercaseAndUppercaseProduceSameColor() {
        let lower = CodableColor(hex: "#ff8800")
        let upper = CodableColor(hex: "#FF8800")

        let lowerNS = lower.nsColor.usingColorSpace(.sRGB)!
        let upperNS = upper.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(lowerNS.redComponent, upperNS.redComponent, accuracy: 0.001)
        XCTAssertEqual(lowerNS.greenComponent, upperNS.greenComponent, accuracy: 0.001)
        XCTAssertEqual(lowerNS.blueComponent, upperNS.blueComponent, accuracy: 0.001)
    }

    // Alpha 0 -> NSColor completamente transparente
    func testZeroAlphaProducesTransparentColor() {
        let color = CodableColor(hex: "#ff000000")
        let ns = color.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(ns.alphaComponent, 0.0, accuracy: 0.001,
            "Alpha 00 debe producir color completamente transparente")
    }

    // Dígitos hex no ASCII (Emoji) -> fallback a negro sin crash
    func testEmojiInHexFallsBackToBlack() {
        let color = CodableColor(hex: "#1e1e😀")
        let ns = color.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(ns.redComponent, 0.0, accuracy: 0.001,
            "Emoji en hex debe degradar graciosamente a negro")
    }

    // Espacios en el string -> fallback sin crash
    func testHexWithSpacesFallsBackToBlack() {
        let color = CodableColor(hex: "#1e 2e3e")
        let ns = color.nsColor.usingColorSpace(.sRGB)!

        XCTAssertEqual(ns.redComponent, 0.0, accuracy: 0.001)
    }

    // Round-trip: CodableColor(nsColor:) -> hex -> CodableColor(hex:) -> nsColor
    func testRoundTripWithKnownCatppuccinColor() {
        // Catppuccin Mocha background: #1e1e2e = R:30, G:30, B:46
        let original = NSColor(srgbRed: 30/255.0, green: 30/255.0, blue: 46/255.0, alpha: 1.0)
        let codable = CodableColor(nsColor: original)

        // El hex generado debe ser #1e1e2e
        XCTAssertEqual(codable.hex, "#1e1e2e",
            "Round-trip debe preservar #1e1e2e exactamente")

        let restored = codable.nsColor.usingColorSpace(.sRGB)!
        XCTAssertEqual(restored.redComponent, 30/255.0, accuracy: 0.005)
        XCTAssertEqual(restored.greenComponent, 30/255.0, accuracy: 0.005)
        XCTAssertEqual(restored.blueComponent, 46/255.0, accuracy: 0.005)
    }
}

// MARK: - 4. Theme round-trip: TOML -> parse -> compare palettes

final class ThemeRoundTripTests: XCTestCase {

    private let mochaToml = """
    [metadata]
    name = "Catppuccin Mocha"
    author = "Catppuccin"
    variant = "dark"

    [colors]
    foreground = "#cdd6f4"
    background = "#1e1e2e"
    cursor = "#f5e0dc"
    selection = "#585b70"

    [colors.normal]
    black = "#45475a"
    red = "#f38ba8"
    green = "#a6e3a1"
    yellow = "#f9e2af"
    blue = "#89b4fa"
    magenta = "#f5c2e7"
    cyan = "#94e2d5"
    white = "#bac2de"

    [colors.bright]
    black = "#585b70"
    red = "#f38ba8"
    green = "#a6e3a1"
    yellow = "#f9e2af"
    blue = "#89b4fa"
    magenta = "#f5c2e7"
    cyan = "#94e2d5"
    white = "#a6adc8"

    [ui]
    tab-active-background = "#1e1e2e"
    tab-inactive-background = "#181825"
    tab-inactive-foreground = "#6c7086"
    badge-attention = "#f9e2af"
    badge-completed = "#a6e3a1"
    badge-error = "#f38ba8"
    badge-working = "#89b4fa"
    """

    func testMochaParsedBackgroundMatchesBuiltIn() throws {
        let parsed = try ThemeTomlParser.parse(mochaToml)
        XCTAssertEqual(parsed.palette.background, "#1e1e2e")
    }

    func testMochaParsedForegroundMatchesBuiltIn() throws {
        let parsed = try ThemeTomlParser.parse(mochaToml)
        XCTAssertEqual(parsed.palette.foreground, "#cdd6f4")
    }

    func testMochaParsedCursorMatchesBuiltIn() throws {
        let parsed = try ThemeTomlParser.parse(mochaToml)
        XCTAssertEqual(parsed.palette.cursor, "#f5e0dc")
    }

    func testMochaParsedSelectionMatchesBuiltIn() throws {
        let parsed = try ThemeTomlParser.parse(mochaToml)
        XCTAssertEqual(parsed.palette.selectionBackground, "#585b70")
    }

    func testMochaParsedAnsiColorsMatchBuiltIn() throws {
        let parsed = try ThemeTomlParser.parse(mochaToml)

        let expectedAnsi = [
            "#45475a", "#f38ba8", "#a6e3a1", "#f9e2af",
            "#89b4fa", "#f5c2e7", "#94e2d5", "#bac2de",
            "#585b70", "#f38ba8", "#a6e3a1", "#f9e2af",
            "#89b4fa", "#f5c2e7", "#94e2d5", "#a6adc8"
        ]

        XCTAssertEqual(parsed.palette.ansiColors, expectedAnsi,
            "El TOML de Mocha debe parsear exactamente los 16 colores ANSI correctos")
    }

    func testMochaParsedUIColorsMatchBuiltIn() throws {
        let parsed = try ThemeTomlParser.parse(mochaToml)

        XCTAssertEqual(parsed.palette.tabActiveBackground, "#1e1e2e")
        XCTAssertEqual(parsed.palette.tabInactiveBackground, "#181825")
        XCTAssertEqual(parsed.palette.tabInactiveForeground, "#6c7086")
        XCTAssertEqual(parsed.palette.badgeAttention, "#f9e2af")
        XCTAssertEqual(parsed.palette.badgeCompleted, "#a6e3a1")
        XCTAssertEqual(parsed.palette.badgeError, "#f38ba8")
        XCTAssertEqual(parsed.palette.badgeWorking, "#89b4fa")
    }

}

// MARK: - 4b. Theme round-trip con ThemeEngine (requiere MainActor)

@MainActor
final class ThemeRoundTripEngineTests: XCTestCase {

    func testTomlParsedThemeMatchesBuiltInPaletteExactly() throws {
        let mochaToml = """
        [metadata]
        name = "Catppuccin Mocha"
        author = "Catppuccin"
        variant = "dark"

        [colors]
        foreground = "#cdd6f4"
        background = "#1e1e2e"
        cursor = "#f5e0dc"
        selection = "#585b70"

        [colors.normal]
        black = "#45475a"
        red = "#f38ba8"
        green = "#a6e3a1"
        yellow = "#f9e2af"
        blue = "#89b4fa"
        magenta = "#f5c2e7"
        cyan = "#94e2d5"
        white = "#bac2de"

        [colors.bright]
        black = "#585b70"
        red = "#f38ba8"
        green = "#a6e3a1"
        yellow = "#f9e2af"
        blue = "#89b4fa"
        magenta = "#f5c2e7"
        cyan = "#94e2d5"
        white = "#a6adc8"

        [ui]
        tab-active-background = "#1e1e2e"
        tab-inactive-background = "#181825"
        tab-inactive-foreground = "#6c7086"
        badge-attention = "#f9e2af"
        badge-completed = "#a6e3a1"
        badge-error = "#f38ba8"
        badge-working = "#89b4fa"
        """

        // La paleta del TOML debe ser idéntica a la del built-in ThemeEngine
        let parsed = try ThemeTomlParser.parse(mochaToml)

        let engine = ThemeEngineImpl()
        let builtIn = try engine.themeByName("Catppuccin Mocha")

        XCTAssertEqual(parsed.palette.background, builtIn.palette.background)
        XCTAssertEqual(parsed.palette.foreground, builtIn.palette.foreground)
        XCTAssertEqual(parsed.palette.cursor, builtIn.palette.cursor)
        XCTAssertEqual(parsed.palette.ansiColors, builtIn.palette.ansiColors,
            "El TOML de Mocha y el built-in deben producir exactamente la misma paleta")
    }
}

// MARK: - 5. Auto-switch integration

@MainActor
final class AutoSwitchIntegrationTests: XCTestCase {

    /// Helper to wait for async Task dispatch in AppearanceObserver.
    private func waitForTaskYield() {
        let exp = expectation(description: "Task yield")
        Task { @MainActor in exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
    }

    func testAutoSwitchFromLightToDarkChangesPalette() throws {
        let engine = ThemeEngineImpl()
        try engine.apply(themeName: "Catppuccin Latte")

        let provider = MockAppearanceProvider(isDarkMode: false)
        let observer = AppearanceObserver(appearanceProvider: provider)

        observer.startObserving(
            themeEngine: engine,
            darkTheme: "Catppuccin Mocha",
            lightTheme: "Catppuccin Latte",
            autoSwitchEnabled: true
        )

        provider.simulateAppearanceChange(isDarkMode: true)
        waitForTaskYield()

        XCTAssertEqual(engine.activeTheme.metadata.variant, .dark,
            "Al activar dark mode, el tema activo debe ser de variante dark")
        XCTAssertEqual(engine.activeTheme.palette.background, "#1e1e2e",
            "El background de Mocha debe activarse tras el cambio")

        observer.stopObserving()
    }

    func testAutoSwitchFromDarkToLightChangesPalette() throws {
        let engine = ThemeEngineImpl()
        try engine.apply(themeName: "Catppuccin Mocha")

        let provider = MockAppearanceProvider(isDarkMode: true)
        let observer = AppearanceObserver(appearanceProvider: provider)

        observer.startObserving(
            themeEngine: engine,
            darkTheme: "Catppuccin Mocha",
            lightTheme: "Catppuccin Latte",
            autoSwitchEnabled: true
        )

        provider.simulateAppearanceChange(isDarkMode: false)
        waitForTaskYield()

        XCTAssertEqual(engine.activeTheme.metadata.variant, .light,
            "Al activar light mode, el tema activo debe ser de variante light")
        XCTAssertEqual(engine.activeTheme.palette.background, "#eff1f5",
            "El background de Latte debe activarse tras el cambio")

        observer.stopObserving()
    }

    func testAutoSwitchPublishesThemeChange() throws {
        let engine = ThemeEngineImpl()
        try engine.apply(themeName: "Catppuccin Latte")

        let provider = MockAppearanceProvider(isDarkMode: false)
        let observer = AppearanceObserver(appearanceProvider: provider)

        var publishedThemeNames: [String] = []
        var cancellables = Set<AnyCancellable>()

        engine.themeChangedPublisher
            .dropFirst()
            .sink { theme in
                publishedThemeNames.append(theme.metadata.name)
            }
            .store(in: &cancellables)

        observer.startObserving(
            themeEngine: engine,
            darkTheme: "Catppuccin Mocha",
            lightTheme: "Catppuccin Latte",
            autoSwitchEnabled: true
        )

        provider.simulateAppearanceChange(isDarkMode: true)
        waitForTaskYield()

        XCTAssertEqual(publishedThemeNames, ["Catppuccin Mocha"],
            "El publisher debe emitir exactamente una vez con el nuevo tema")

        observer.stopObserving()
    }

    func testStopObservingPreventsSubsequentSwitches() throws {
        let engine = ThemeEngineImpl()
        try engine.apply(themeName: "Catppuccin Mocha")

        let provider = MockAppearanceProvider(isDarkMode: true)
        let observer = AppearanceObserver(appearanceProvider: provider)

        observer.startObserving(
            themeEngine: engine,
            darkTheme: "Catppuccin Mocha",
            lightTheme: "Catppuccin Latte",
            autoSwitchEnabled: true
        )

        observer.stopObserving()

        // Después de stop, el cambio de apariencia no debe cambiar el tema
        provider.simulateAppearanceChange(isDarkMode: false)

        XCTAssertEqual(engine.activeTheme.metadata.name, "Catppuccin Mocha",
            "Tras stopObserving, los cambios de apariencia no deben cambiar el tema")
    }

    func testAutoSwitchWithUnknownThemeNameDoesNotCrash() throws {
        let engine = ThemeEngineImpl()
        let provider = MockAppearanceProvider(isDarkMode: false)
        let observer = AppearanceObserver(appearanceProvider: provider)

        let originalTheme = engine.activeTheme.metadata.name

        // Nombre de tema inexistente: no debe crashear, solo ignorar
        observer.startObserving(
            themeEngine: engine,
            darkTheme: "ThemeQueNoExiste",
            lightTheme: "TampocoEsteExiste",
            autoSwitchEnabled: true
        )

        provider.simulateAppearanceChange(isDarkMode: true)

        XCTAssertEqual(engine.activeTheme.metadata.name, originalTheme,
            "Tema inexistente en auto-switch no debe crashear ni cambiar el tema activo")

        observer.stopObserving()
    }
}

// MARK: - 6. Hot-reload robustness

final class ConfigWatcherRobustnessTests: XCTestCase {

    // Archivo sin contenido (nil) durante el watch
    func testHandleFileChangeWithNilContentDoesNotCrash() {
        let fileProvider = InMemoryConfigFileProvider(content: nil)
        let service = ConfigService(fileProvider: fileProvider)

        let watcher = ConfigWatcher(configService: service, fileProvider: fileProvider)

        // No debe crashear con contenido nil
        XCTAssertNoThrow(watcher.handleFileChange(),
            "handleFileChange con contenido nil no debe crashear")
    }

    // Reload múltiple: el estado debe ser consistente
    func testMultipleHandleFileChangesAreStable() throws {
        let fileProvider = InMemoryConfigFileProvider(content: """
        [appearance]
        theme = "dracula"
        """)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        let watcher = ConfigWatcher(configService: service, fileProvider: fileProvider)

        // 10 reloads consecutivos sin cambio de fichero
        for _ in 0..<10 {
            watcher.handleFileChange()
        }

        XCTAssertEqual(service.current.appearance.theme, "dracula",
            "10 reloads consecutivos no deben corromper el estado")
    }

    // Debounce cancelado: si se llama stopWatching antes del debounce, no debe disparar reload
    func testStopWatchingCancelsScheduledReload() throws {
        let fileProvider = InMemoryConfigFileProvider(content: """
        [appearance]
        theme = "dracula"
        """)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        let watcher = ConfigWatcher(configService: service, fileProvider: fileProvider)
        watcher.debounceInterval = 0.5

        fileProvider.content = """
        [appearance]
        theme = "one-dark"
        """
        watcher.scheduleReload()

        // Parar inmediatamente antes de que el debounce dispare
        watcher.stopWatching()

        // Esperar más que el debounce
        let expectation = expectation(description: "Esperar debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2.0)

        // Tras stopWatching, el tema original debe permanecer (debounce cancelado)
        XCTAssertEqual(service.current.appearance.theme, "dracula",
            "stopWatching debe cancelar el reload pendiente por debounce")
    }

    // TOML válido parcialmente (campos opcionales ausentes): no debe crashear
    func testHandleFileChangeWithMinimalValidToml() throws {
        let fileProvider = InMemoryConfigFileProvider(content: "")
        let service = ConfigService(fileProvider: fileProvider)

        let watcher = ConfigWatcher(configService: service, fileProvider: fileProvider)

        XCTAssertNoThrow(watcher.handleFileChange(),
            "TOML vacío debe resultar en config por defecto sin crash")
    }
}

// MARK: - 8. Config cascade: tema via hot-reload -> config refleja el cambio

final class ConfigCascadeTests: XCTestCase {

    func testHotReloadUpdatesThemeInConfig() throws {
        let fileProvider = InMemoryConfigFileProvider(content: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        XCTAssertEqual(service.current.appearance.theme, "catppuccin-mocha")

        // Simular edición del fichero
        fileProvider.content = """
        [appearance]
        theme = "catppuccin-latte"
        """
        let watcher = ConfigWatcher(configService: service, fileProvider: fileProvider)
        watcher.handleFileChange()

        XCTAssertEqual(service.current.appearance.theme, "catppuccin-latte",
            "El cambio de tema via hot-reload debe reflejarse en config.current")
    }

    func testHotReloadConfigChangePublisherEmits() throws {
        let fileProvider = InMemoryConfigFileProvider(content: """
        [appearance]
        theme = "catppuccin-mocha"
        """)
        let service = ConfigService(fileProvider: fileProvider)
        try service.reload()

        let expectation = expectation(description: "Publisher emite tras hot-reload")
        var receivedTheme: String?
        var cancellables = Set<AnyCancellable>()

        service.configChangedPublisher
            .dropFirst()
            .sink { config in
                receivedTheme = config.appearance.theme
                expectation.fulfill()
            }
            .store(in: &cancellables)

        fileProvider.content = """
        [appearance]
        theme = "dracula"
        """
        let watcher = ConfigWatcher(configService: service, fileProvider: fileProvider)
        watcher.handleFileChange()

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(receivedTheme, "dracula",
            "ConfigChangedPublisher debe emitir el nuevo tema tras hot-reload")
    }
}

// MARK: - 9. AgentConfigWatcher edge cases

final class AgentConfigWatcherEdgeCaseTests: XCTestCase {

    func testHandleFileChangeWithNilContentSetsFailed() {
        let provider = InMemoryAgentFileProvider(content: nil)
        let service = AgentConfigService(fileProvider: provider)
        let watcher = AgentConfigWatcher(agentConfigService: service, fileProvider: provider)

        watcher.handleFileChange()

        XCTAssertFalse(watcher.lastReloadSucceeded,
            "Reload con fichero nil debe marcar lastReloadSucceeded como false")
    }

    func testHandleFileChangeWithInvalidTomlSetsFailed() {
        let provider = InMemoryAgentFileProvider(content: "!!! invalid toml !!!")
        let service = AgentConfigService(fileProvider: provider)
        let watcher = AgentConfigWatcher(agentConfigService: service, fileProvider: provider)

        watcher.handleFileChange()

        XCTAssertFalse(watcher.lastReloadSucceeded,
            "Reload con TOML inválido debe marcar lastReloadSucceeded como false")
    }

    func testHandleFileChangeWithValidTomlSetsSucceeded() {
        let provider = InMemoryAgentFileProvider(content: """
        [claude]
        display-name = "Claude Code"
        osc-supported = true
        launch-patterns = ["^claude\\b"]
        waiting-patterns = ["^\\? "]
        error-patterns = ["^Error:"]
        finished-indicators = ["^\\$\\s*$"]
        """)
        let service = AgentConfigService(fileProvider: provider)
        let watcher = AgentConfigWatcher(agentConfigService: service, fileProvider: provider)

        watcher.handleFileChange()

        XCTAssertTrue(watcher.lastReloadSucceeded,
            "Reload con TOML válido debe marcar lastReloadSucceeded como true")
    }
}
