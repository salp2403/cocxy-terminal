// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TimelineViewLocalizationSwiftTestingTests.swift - Timeline panel localization contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Timeline view localization")
struct TimelineViewLocalizationSwiftTestingTests {

    @Test("timeline panel chrome strings localize to Spanish")
    func timelinePanelChromeStringsLocalize() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(localizer.string("timeline.title", fallback: "Agent Timeline") == "Línea de tiempo de agentes")
        #expect(localizer.string("timeline.scope.all", fallback: "All Windows") == "Todas las ventanas")
        #expect(localizer.string("timeline.scope.current", fallback: "This Window") == "Esta ventana")
        #expect(localizer.string("timeline.export.json", fallback: "Export JSON") == "Exportar JSON")
        #expect(localizer.string("timeline.filter.tools", fallback: "Tools") == "Herramientas")
        #expect(localizer.string("timeline.filter.errors.accessibility", fallback: "Errors filter") == "Filtro Errores")
        #expect(localizer.string("timeline.empty.current.title", fallback: "No events in this window") == "Sin eventos en esta ventana")
        #expect(
            localizer.string(
                "timeline.empty.all.detail",
                fallback: "Agent actions will appear here\nas they happen in real-time."
            ) == "Las acciones del agente aparecerán aquí\ncuando ocurran en tiempo real."
        )
    }

    @MainActor
    @Test("timeline view accepts the host app localizer")
    func timelineViewAcceptsHostLocalizer() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let store = AgentTimelineStoreImpl()
        let viewModel = TimelineViewModel(
            store: store,
            onExportJSON: {},
            onExportMarkdown: {}
        )

        let view = TimelineView(viewModel: viewModel, localizer: localizer)

        #expect(view.localizer.resolvedLanguage == .spanish)
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}
