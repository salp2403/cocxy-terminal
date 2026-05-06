// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotesOverlayViewSwiftTestingTests.swift - Lightweight UI contract
// checks for the docked Notes panel.

import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import CocxyTerminal

@Suite("NotesOverlayView")
struct NotesOverlayViewSwiftTestingTests {

    @Test("panel width constants keep the note editor usable in the right-docked overlay")
    func panelWidthConstantsRespectUsabilityBounds() {
        #expect(NotesOverlayView.minimumPanelWidth >= 400)
        #expect(NotesOverlayView.minimumPanelWidth < NotesOverlayView.defaultPanelWidth)
        #expect(NotesOverlayView.defaultPanelWidth < NotesOverlayView.maximumPanelWidth)
        #expect(NotesOverlayView.maximumPanelWidth <= 900)
    }

    @Test("note rows and count badges keep usable hit and visibility bounds")
    func noteRowsAndCountBadgesStayReadableAndClickable() {
        #expect(NotesOverlayView.noteRowMinimumHitHeight >= 44)
        #expect(NotesOverlayView.countBadgeMinimumWidth >= 20)
    }

    @Test("layout switches to stacked when the panel is compact so list and editor do not crush each other")
    func compactPanelUsesStackedLayout() {
        let compactWidth = NotesOverlayView.compactLayoutThreshold - 1

        #expect(NotesOverlayView.contentLayout(forPanelWidth: compactWidth) == .stacked)
    }

    @Test("default panel uses stacked layout because the docked notes pane prioritizes editor width")
    func defaultPanelUsesStackedLayout() {
        #expect(
            NotesOverlayView.contentLayout(
                forPanelWidth: NotesOverlayView.defaultPanelWidth
            ) == .stacked
        )
    }

    @Test("layout uses split view only when the panel has enough width for both list and editor")
    func widePanelUsesSplitLayout() {
        #expect(
            NotesOverlayView.contentLayout(
                forPanelWidth: NotesOverlayView.compactLayoutThreshold
            ) == .split
        )
        #expect(
            NotesOverlayView.contentLayout(
                forPanelWidth: NotesOverlayView.maximumPanelWidth
            ) == .split
        )
    }

    @Test("leading corner radius matches Design.Radius.large so the docked overlay aligns with the rest of the Aurora chrome")
    func leadingCornerRadiusMatchesDesignToken() {
        #expect(
            NotesOverlayView.leadingCornerRadius == Design.Radius.large.rawValue
        )
    }

    @Test("panel shape rounds the leading edge and keeps the trailing edge flat so the docked panel hugs the window border without a visible gap")
    func panelShapeRoundsLeadingEdgeOnly() {
        let shape = NotesOverlayView.panelShape
        let radius = NotesOverlayView.leadingCornerRadius

        #expect(shape.cornerRadii.topLeading == radius)
        #expect(shape.cornerRadii.bottomLeading == radius)
        #expect(shape.cornerRadii.topTrailing == 0)
        #expect(shape.cornerRadii.bottomTrailing == 0)
    }

    @Test("default theme identity is Aurora so previews and tests render with the dark default palette without forcing every host to compute one")
    @MainActor
    func themeIdentityDefaultsToAurora() {
        let viewModel = Self.makeViewModel()
        let view = NotesOverlayView(viewModel: viewModel)

        #expect(view.themeIdentity == .aurora)
    }

    @Test("paper theme identity propagates so overlays render in the light palette when the user picks a light terminal theme")
    @MainActor
    func themeIdentityCanBePaperForLightThemes() {
        let viewModel = Self.makeViewModel()
        let view = NotesOverlayView(
            viewModel: viewModel,
            themeIdentity: .paper
        )

        #expect(view.themeIdentity == .paper)
    }

    @Test("delete confirmation copy localizes to configured app language")
    func deleteConfirmationCopyLocalizes() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        let copy = NotesOverlayView.localizedDeleteNoteCopy(localizer: localizer)

        #expect(copy.messageText == "¿Eliminar nota?")
        #expect(copy.informativeText == "Esto elimina la nota de este espacio.")
        #expect(copy.primaryButton == "Eliminar nota")
        #expect(copy.secondaryButton == "Cancelar")
    }

    @Test("Spanish notes panel copy uses space wording across surfaces")
    func notesPanelCopyUsesSpanishSpaceTerminology() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(
            localizer.string(
                "notes.workspaceNotes",
                fallback: "Workspace Notes"
            ) == "Notas del espacio"
        )
        #expect(
            localizer.string(
                "notes.empty.noNotes.message",
                fallback: "Create a note for this workspace."
            ) == "Crea una nota para este espacio."
        )
        #expect(
            localizer.string(
                "command.notes.toggle.description",
                fallback: "Show or hide workspace notes"
            ) == "Mostrar u ocultar notas por espacio"
        )
    }

    @Test("Spanish notes accessibility copy localizes controls that replace decorative symbols")
    func notesAccessibilityCopyLocalizesSpanishControls() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(localizer.string("notes.panel.accessibility", fallback: "Notes panel") == "Panel de notas")
        #expect(localizer.string("notes.search.accessibility", fallback: "Search notes") == "Buscar notas")
        #expect(localizer.string("notes.search.clear", fallback: "Clear search") == "Limpiar búsqueda")
        #expect(localizer.string("notes.newNote.help", fallback: "New note") == "Nueva nota")
        #expect(localizer.string("notes.close", fallback: "Close notes") == "Cerrar notas")
    }

    // MARK: - Test helpers

    @MainActor
    private static func makeViewModel() -> NotesViewModel {
        let temp = URL(
            fileURLWithPath: NSTemporaryDirectory(),
            isDirectory: true
        )
        .appendingPathComponent("notes-overlay-tests-\(UUID().uuidString)")
        let store = NoteStore(storageRoot: temp, autoSaveInterval: 0)
        return NotesViewModel(
            store: store,
            resolver: DefaultNoteWorkspaceResolver(),
            searchEngine: NoteSearchGrep(store: store)
        )
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}
