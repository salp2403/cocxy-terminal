// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultSidebarViewSwiftTestingTests.swift - UI contracts for the visual Vault sidebar.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Vault sidebar view")
struct VaultSidebarViewSwiftTestingTests {

    @Test("panel width constants cover expanded compact and icon-only modes")
    func panelWidthConstantsCoverAdaptiveModes() {
        #expect(VaultSidebarView.minimumPanelWidth == VaultSidebarWidthMode.iconOnly.panelWidth)
        #expect(VaultSidebarView.defaultPanelWidth == VaultSidebarWidthMode.expanded.panelWidth)
        #expect(VaultSidebarView.compactPanelWidth == VaultSidebarWidthMode.compact.panelWidth)
        #expect(VaultSidebarView.maximumPanelWidth >= VaultSidebarView.defaultPanelWidth)
    }

    @Test("view source uses shared glass panel background")
    func viewSourceUsesSharedGlassBackground() throws {
        let source = try String(contentsOf: repositoryRoot().appendingPathComponent("Sources/UI/Vault/VaultSidebarView.swift"))

        #expect(source.contains(".glassPanelBackground("))
    }

    @Test("Spanish copy covers core sidebar controls and states")
    func spanishCopyCoversCoreControlsAndStates() throws {
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: try #require(localizationBundle()))

        #expect(localizer.string("vault.sidebar.title", fallback: "Vault") == "Vault")
        #expect(localizer.string("vault.search.placeholder", fallback: "Search sessions...") == "Buscar sesiones...")
        #expect(localizer.string("vault.filter.allAgents", fallback: "All") == "Todos")
        #expect(localizer.string("vault.empty.title", fallback: "No sessions yet") == "Sin sesiones todavía")
        #expect(localizer.string("vault.action.resume", fallback: "Resume") == "Reanudar")
        #expect(localizer.string("vault.action.delete", fallback: "Delete") == "Eliminar")
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func localizationBundle() -> Bundle? {
        Bundle(url: repositoryRoot().appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}
