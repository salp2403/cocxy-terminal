// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserPanelLocalizationSwiftTestingTests.swift - Browser panel localization helpers.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Browser panel localization")
struct BrowserPanelLocalizationSwiftTestingTests {

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
