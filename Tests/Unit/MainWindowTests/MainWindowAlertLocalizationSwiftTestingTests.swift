// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowAlertLocalizationSwiftTestingTests.swift - Alert localization coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("MainWindow alert localization")
@MainActor
struct MainWindowAlertLocalizationSwiftTestingTests {
    @Test("close and pane alert copy follows configured app language")
    func closeAndPaneAlertCopyFollowsConfiguredAppLanguage() throws {
        let localizer = AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(localizationBundle())
        )

        let closeTab = MainWindowController.localizedCloseTabConfirmationCopy(localizer: localizer)
        #expect(closeTab.messageText == "¿Cerrar pestaña?")
        #expect(closeTab.informativeText == "Los procesos en esta pestaña se terminarán.")
        #expect(closeTab.primaryButton == "Cerrar")
        #expect(closeTab.secondaryButton == "Cancelar")

        let closePane = MainWindowController.localizedFocusedPaneCloseCopy(
            localizer: localizer,
            paneType: .markdown,
            remainingPaneCount: 2
        )
        #expect(closePane.messageText == "¿Cerrar panel enfocado?")
        #expect(
            closePane.informativeText ==
                "Esto cerrará el panel de markdown enfocado. La pestaña de workspace queda abierta con 2 paneles restantes."
        )
        #expect(closePane.primaryButton == "Cerrar panel")
        #expect(closePane.secondaryButton == "Cancelar")

        #expect(
            MainWindowController.localizedStuckPaneNotificationTitle(localizer: localizer) ==
                "El panel dejó de aceptar entrada"
        )
        #expect(
            MainWindowController.localizedStuckPaneNotificationBody(reason: .surfaceMissing, localizer: localizer) ==
                "Este panel perdió su terminal y ya no enruta la entrada. Ciérralo con Cmd+Shift+W."
        )
        #expect(
            MainWindowController.localizedStuckPaneNotificationBody(reason: .ptyWriteFailed, localizer: localizer) ==
                "El shell de este panel no acepta pulsaciones. Ciérralo con Cmd+Shift+W y abre un split nuevo."
        )
        #expect(MainWindowController.localizedNewTabActivitySummary(localizer: localizer) == "Nueva pestaña")
        #expect(
            MainWindowController.localizedSplitCreatedActivitySummary(isVertical: true, localizer: localizer) ==
                "Split lado a lado"
        )
        #expect(
            MainWindowController.localizedSplitCreatedActivitySummary(isVertical: false, localizer: localizer) ==
                "Split apilado"
        )
    }

    @Test("worktree and tab config alert copy follows configured app language")
    func worktreeAndTabConfigAlertCopyFollowsConfiguredAppLanguage() throws {
        let localizer = AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(localizationBundle())
        )

        let worktree = MainWindowController.localizedCloseWorktreeTabCopy(localizer: localizer)
        #expect(worktree.messageText == "¿Cerrar pestaña de worktree?")
        #expect(worktree.primaryButton == "Mantener worktree")
        #expect(worktree.secondaryButton == "Eliminar si está limpio")
        #expect(worktree.tertiaryButton == "Cancelar")

        let saveConfig = MainWindowController.localizedSaveTabConfigCopy(localizer: localizer)
        #expect(saveConfig.messageText == "Guardar pestaña actual como configuración")
        #expect(saveConfig.primaryButton == "Guardar")
        #expect(saveConfig.secondaryButton == "Cancelar")

        let openConfig = MainWindowController.localizedOpenTabConfigCopy(localizer: localizer)
        #expect(openConfig.messageText == "Abrir pestaña desde configuración")
        #expect(openConfig.primaryButton == "Abrir")
        #expect(openConfig.secondaryButton == "Cancelar")
        #expect(
            MainWindowController.localizedTabConfigSaveFailureMessage(localizer: localizer) ==
                "No se pudo guardar la configuración de pestaña."
        )
        #expect(
            MainWindowController.localizedTabConfigOpenFailureMessage(localizer: localizer) ==
                "No se pudo abrir la configuración de pestaña."
        )
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}
