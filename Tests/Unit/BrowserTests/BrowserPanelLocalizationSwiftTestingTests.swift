// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserPanelLocalizationSwiftTestingTests.swift - Browser panel localization helpers.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Browser panel localization")
struct BrowserPanelLocalizationSwiftTestingTests {

    @Test("DevTools header switches tabs to icon-only before labels wrap")
    func devToolsHeaderUsesIconOnlyTabsInNarrowPanes() {
        #expect(BrowserDevToolsHeaderPresentation.resolve(width: 220).usesIconOnlyTabs == true)
        #expect(BrowserDevToolsHeaderPresentation.resolve(width: 259).usesIconOnlyTabs == true)
        #expect(BrowserDevToolsHeaderPresentation.resolve(width: 260).usesIconOnlyTabs == false)
        #expect(BrowserDevToolsHeaderPresentation.resolve(width: 360).usesIconOnlyTabs == false)
    }

    @Test("history clear confirmation localizes range copy")
    func historyClearConfirmationLocalizes() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        let copy = BrowserHistoryView.localizedClearConfirmationCopy(
            localizer: localizer,
            range: .lastHour
        )

        #expect(HistoryClearRange.lastHour.localizedTitle(using: localizer) == "Última hora")
        #expect(copy.messageText == "Borrar historial")
        #expect(copy.informativeText == "Esto eliminará permanentemente la última hora del historial de navegación.")
        #expect(copy.primaryButton == "Borrar")
        #expect(copy.secondaryButton == "Cancelar")
    }

    @Test("history date group labels localize today yesterday and calendar dates")
    func historyDateGroupLabelsLocalize() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 4)))
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: reference))
        let older = try #require(calendar.date(from: DateComponents(year: 2024, month: 3, day: 25)))

        #expect(
            BrowserHistoryView.localizedDateGroupLabel(
                for: reference,
                fallback: "Today",
                using: localizer,
                calendar: calendar,
                referenceDate: reference
            ) == "Hoy"
        )
        #expect(
            BrowserHistoryView.localizedDateGroupLabel(
                for: yesterday,
                fallback: "Yesterday",
                using: localizer,
                calendar: calendar,
                referenceDate: reference
            ) == "Ayer"
        )
        #expect(
            BrowserHistoryView.localizedDateGroupLabel(
                for: older,
                fallback: "25 March",
                using: localizer,
                calendar: calendar,
                referenceDate: reference
            ) == "25 marzo"
        )
    }

    @Test("bookmark delete confirmation distinguishes folders from bookmarks")
    func bookmarkDeleteConfirmationLocalizes() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        let bookmark = BrowserBookmark(title: "Example", url: "https://example.com")
        let folder = BrowserBookmark.folder(name: "Docs")

        let bookmarkCopy = BrowserBookmarksView.localizedDeleteConfirmationCopy(
            localizer: localizer,
            bookmark: bookmark
        )
        let folderCopy = BrowserBookmarksView.localizedDeleteConfirmationCopy(
            localizer: localizer,
            bookmark: folder
        )

        #expect(bookmarkCopy.messageText == "Eliminar marcador")
        #expect(bookmarkCopy.informativeText == "¿Seguro que quieres eliminar este marcador?")
        #expect(bookmarkCopy.primaryButton == "Eliminar")
        #expect(bookmarkCopy.secondaryButton == "Cancelar")
        #expect(folderCopy.informativeText == "¿Seguro que quieres eliminar esta carpeta y todo su contenido?")
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}
