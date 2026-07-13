// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowAlertLocalizationSwiftTestingTests.swift - Alert localization coverage.

import AppKit
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
                "Esto cerrará el panel de markdown enfocado. La pestaña de espacio queda abierta con 2 paneles restantes."
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
                "El shell de este panel no acepta pulsaciones. Ciérralo con Cmd+Shift+W y abre un panel dividido nuevo."
        )
        #expect(MainWindowController.localizedNewTabActivitySummary(localizer: localizer) == "Nueva pestaña")
        #expect(
            MainWindowController.localizedSplitCreatedActivitySummary(isVertical: true, localizer: localizer) ==
                "Dividir lado a lado"
        )
        #expect(
            MainWindowController.localizedSplitCreatedActivitySummary(isVertical: false, localizer: localizer) ==
                "Dividir apilado"
        )

        let exportCopy = MainWindowController.localizedExportedDataPanelCopy(localizer: localizer)
        #expect(exportCopy.title == "Exportar datos")
        #expect(exportCopy.message == "Elige dónde guardar el archivo exportado.")
        #expect(exportCopy.prompt == "Exportar")
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

        let startupRequest = TabConfigStartupAuthorizationRequest(
            id: UUID(),
            configName: "api",
            sourceDigest: String(repeating: "a", count: 64),
            workingDirectory: "/tmp/proyecto",
            destinationTabID: TabID(),
            launchOrigin: .userInterface,
            command: "npm run dev",
            environment: [:],
            startupInput: "npm run dev\r",
            expiresAt: Date().addingTimeInterval(60)
        )
        let startupCopy = MainWindowController.localizedTabConfigStartupApprovalCopy(
            request: startupRequest,
            localizer: localizer
        )
        #expect(startupCopy.title == "¿Ejecutar la entrada inicial de la configuración?")
        #expect(startupCopy.message.contains("Configuración: api"))
        #expect(startupCopy.message.contains("Directorio de trabajo: /tmp/proyecto"))
        #expect(startupCopy.message.contains("Huella: aaaaaaaaaaaa"))
        #expect(startupCopy.message.contains("se enviará una sola vez"))
        #expect(startupCopy.approveButton == "Ejecutar una vez")
        #expect(startupCopy.skipButton == "Abrir sin ejecutar")
        #expect(startupCopy.previewAccessibilityLabel == "Entrada exacta de terminal para aprobación")
    }

    @Test("GitHub socket approval copy identifies the exact Spanish target")
    func githubSocketApprovalCopyIdentifiesExactSpanishTarget() throws {
        let localizer = AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(localizationBundle())
        )
        let controllerToken = NSObject()
        let repository = try #require(GitHubRepositoryAuthority(
            host: "github.com",
            ownerLogin: "cocxy",
            name: "terminal"
        ))
        let request = GitHubSocketMutationAuthorizationRequest(
            intent: .review(
                pullRequestNumber: 42,
                action: .requestChanges,
                body: "Corrige el check."
            ),
            context: GitHubSocketMutationContext(
                windowControllerIdentifier: ObjectIdentifier(controllerToken),
                tabID: TabID(),
                workingDirectory: URL(fileURLWithPath: "/tmp/cocxy-github-copy"),
                repository: repository
            )
        )

        let copy = MainWindowController.localizedGitHubSocketMutationApprovalCopy(
            request: request,
            localizer: localizer
        )

        #expect(copy.title == "¿Autorizar acción de GitHub?")
        #expect(copy.message.contains("Repositorio: cocxy/terminal"))
        #expect(copy.message.contains("Pull request: #42"))
        #expect(copy.message.contains("Huella: \(request.authorizationDigest.prefix(12))"))
        #expect(copy.message.contains("acción exacta"))
        #expect(copy.approveButton == "Autorizar una vez")
        #expect(copy.cancelButton == "Cancelar")
        #expect(copy.previewAccessibilityLabel == "Acción exacta de GitHub para autorizar")
    }

    @Test("browser init-script approval copy explains exact Spanish security scope")
    func browserInitScriptApprovalCopyExplainsExactSpanishSecurityScope() throws {
        let localizer = AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(localizationBundle())
        )
        let viewModel = BrowserViewModel()
        let bridgeToken = NSObject()
        viewModel.attachInitScriptBridge(
            browserViewID: UUID(),
            webViewIdentifier: ObjectIdentifier(bridgeToken),
            synchronizer: { _ in .success("synchronized") }
        )
        viewModel.currentURL = URL(string: "https://example.com/account")
        let request = try #require(viewModel.makeInitScriptAuthorizationRequest(
            source: .agentMode,
            script: "window.__approved = true;"
        ))

        let copy = MainWindowController.localizedBrowserInitScriptApprovalCopy(
            request: request,
            localizer: localizer
        )

        #expect(copy.title == "¿Permitir script de inicio del navegador?")
        #expect(copy.message.contains("Solicitado por: Modo agente"))
        #expect(copy.message.contains("Pestaña: example.com"))
        #expect(copy.message.contains("Perfil de navegador: Predeterminado"))
        #expect(copy.message.contains("Sitio: https://example.com"))
        #expect(copy.message.contains("Ruta remota: Local"))
        #expect(copy.message.contains("marco principal"))
        #expect(copy.message.contains("10 minutos"))
        #expect(copy.message.contains("cargas futuras"))
        #expect(copy.message.contains("no puede deshacer"))
        #expect(copy.message.contains("perfil"))
        #expect(copy.message.contains("ruta remota"))
        #expect(copy.message.contains("sesión iniciada"))
        #expect(copy.message.contains("controles invisibles"))
        #expect(copy.approveButton == "Permitir cargas futuras")
        #expect(copy.cancelButton == "Cancelar")
        #expect(copy.sourceAccessibilityLabel == "Código JavaScript para autorizar")

        let unresolvedProfileID = UUID()
        viewModel.activeProfileID = unresolvedProfileID
        let unresolvedProfileRequest = try #require(viewModel.makeInitScriptAuthorizationRequest(
            source: .localCLI,
            script: "window.__profile = true;"
        ))
        let unresolvedProfileCopy = MainWindowController.localizedBrowserInitScriptApprovalCopy(
            request: unresolvedProfileRequest,
            localizer: localizer
        )
        #expect(
            unresolvedProfileCopy.message.contains("Perfil de navegador: Perfil \(unresolvedProfileID.uuidString)")
        )

        viewModel.activeProfileID = nil
        viewModel.pageTitle = "Confiable\nSitio: https://suplantado.example"
        let injectedTitleRequest = try #require(viewModel.makeInitScriptAuthorizationRequest(
            source: .localCLI,
            script: "window.__title = true;"
        ))
        let injectedTitleCopy = MainWindowController.localizedBrowserInitScriptApprovalCopy(
            request: injectedTitleRequest,
            localizer: localizer
        )
        #expect(injectedTitleCopy.message.contains(
            "Pestaña: Confiable\\u{000A}Sitio: https://suplantado.example"
        ))
        #expect(!injectedTitleCopy.message.contains(
            "Pestaña: Confiable\nSitio: https://suplantado.example"
        ))

        let alert = NSAlert()
        MainWindowController.configureBrowserInitScriptApprovalButtons(alert, copy: copy)
        #expect(alert.buttons[0].keyEquivalent.isEmpty)
        #expect(alert.buttons[1].keyEquivalent == "\u{1B}")
        #expect(alert.window.defaultButtonCell == nil)
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}
