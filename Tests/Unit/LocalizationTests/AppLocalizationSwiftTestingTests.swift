// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppLocalizationSwiftTestingTests.swift - Local app-language resolver tests.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("App localization")
struct AppLocalizationSwiftTestingTests {

    @Test
    func normalizesLanguageIdentifiers() {
        #expect(AppLanguage.normalized("system") == .system)
        #expect(AppLanguage.normalized("en-US") == .english)
        #expect(AppLanguage.normalized("es_HN") == .spanish)
        #expect(AppLanguage.normalized("fr") == nil)
    }

    @Test
    func systemPreferenceResolvesFirstSupportedLocale() {
        let spanish = AppLocalizationResolver(preferredLanguageIdentifiers: ["fr-FR", "es-HN"])
        let fallback = AppLocalizationResolver(preferredLanguageIdentifiers: ["fr-FR"])

        #expect(spanish.resolve(.system) == .spanish)
        #expect(fallback.resolve(.system) == .english)
        #expect(fallback.resolve(.spanish) == .spanish)
    }

    @Test
    func localizerLoadsEnglishAndSpanishResources() throws {
        let bundle = try #require(localizationBundle())

        let english = AppLocalizer(languagePreference: .english, bundle: bundle)
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(english.string(.preferencesAppearanceLanguageTitle) == "Language")
        #expect(spanish.string(.preferencesAppearanceLanguageTitle) == "Idioma")
        #expect(spanish.string(.preferencesAppearanceLanguagePicker) == "Idioma de la app")
        #expect(spanish.string("preferences.section.appearance", fallback: "Appearance") == "Apariencia")
        #expect(spanish.string("preferences.save.button", fallback: "Save") == "Guardar")
        #expect(spanish.string("preferences.general.shellPath", fallback: "Shell path") == "Ruta del shell")
        #expect(spanish.string("preferences.appearance.fontSize", fallback: "Font size") == "Tamaño de fuente")
        #expect(spanish.string("preferences.appearance.glassChromeTint.dark", fallback: "Dark") == "Oscuro")
        #expect(spanish.string("preferences.appearance.fontResolution.included", fallback: "Included with Cocxy: %@") == "Incluida con Cocxy: %@")
        #expect(spanish.string("preferences.appearance.sidebarDensity.detailed", fallback: "Detailed") == "Detallada")
        #expect(spanish.string("preferences.appearance.sidebarRowDetail.state", fallback: "State") == "Estado")
        #expect(spanish.string("preferences.agentDetection.idleTimeout", fallback: "Idle timeout: %d s") == "Timeout de inactividad: %d s")
        #expect(spanish.string("preferences.voice.recognitionLocale", fallback: "Recognition locale") == "Idioma de reconocimiento")
        #expect(spanish.string("preferences.activity.trackCosts", fallback: "Track token usage and estimated costs") == "Registrar uso de tokens y costos estimados")
        #expect(spanish.string("preferences.sessionReplay.storageDirectory", fallback: "Storage directory") == "Directorio de almacenamiento")
        #expect(spanish.string("preferences.backup.enable", fallback: "Enable local automatic backups") == "Activar copias automáticas locales")
        #expect(spanish.string("preferences.backup.artifact.aiConversations", fallback: "AI conversations") == "Conversaciones IA")
        #expect(spanish.string("preferences.codeReview.autoShow", fallback: "Auto-show review panel when an agent session ends") == "Mostrar panel de revisión automáticamente cuando termina una sesión de agente")
        #expect(spanish.string("preferences.notifications.dockBadge", fallback: "Dock badge") == "Badge en el Dock")
        #expect(spanish.string("preferences.terminal.imageMemoryBudget", fallback: "Image memory budget: %d MiB") == "Memoria para imágenes: %d MiB")
        #expect(spanish.string("preferences.lsp.enable", fallback: "Enable language servers") == "Activar servidores de lenguaje")
        #expect(spanish.string("preferences.editor.enableVimMode", fallback: "Enable Vim mode") == "Activar modo Vim")
        #expect(spanish.string("preferences.editor.contextWindow", fallback: "Context window: %d UTF-16") == "Ventana de contexto: %d UTF-16")
        #expect(spanish.string("preferences.worktrees.enable", fallback: "Enable worktrees") == "Activar worktrees")
        #expect(spanish.string("preferences.worktrees.onClose.remove", fallback: "Remove if clean") == "Eliminar si está limpio")
        #expect(spanish.string("preferences.agentMode.enable", fallback: "Enable Agent Mode") == "Activar modo agente")
        #expect(spanish.string("preferences.agentMode.apiKey.saved", fallback: "A key is saved in the macOS Keychain for this provider.") == "Hay una llave guardada en Keychain de macOS para este provider.")
        #expect(spanish.string("preferences.mcp.configFile.section", fallback: "Config File") == "Archivo de configuración")
        #expect(spanish.string("preferences.mcp.noServers", fallback: "No MCP servers configured.") == "No hay servidores MCP configurados.")
        #expect(spanish.string("preferences.iCloud.enable", fallback: "Enable iCloud Drive sync") == "Activar sincronización con iCloud Drive")
        #expect(spanish.string("preferences.iCloud.artifact.settings", fallback: "Settings") == "Ajustes")
        #expect(spanish.string("preferences.iCloud.export", fallback: "Export Encrypted Artifacts") == "Exportar artefactos cifrados")
        #expect(spanish.string("preferences.iCloud.conflict.useRemote", fallback: "Use Remote") == "Usar remoto")
        #expect(spanish.string("preferences.github.enable", fallback: "Enable GitHub pane") == "Activar panel de GitHub")
        #expect(spanish.string("preferences.github.defaultState.merged", fallback: "Merged (PRs only)") == "Fusionados (solo PRs)")
        #expect(spanish.string("preferences.about.subtitle", fallback: "Agent-aware terminal for macOS") == "Terminal para macOS con conciencia de agentes")
        #expect(spanish.string("preferences.about.checkForUpdates", fallback: "Check for Updates") == "Buscar actualizaciones")
        #expect(spanish.string("app.crashRecovery.restore.button", fallback: "Restore") == "Restaurar")
        #expect(spanish.string("app.quit.message", fallback: "All terminal sessions will be closed.") == "Todas las sesiones de terminal se cerrarán.")
        #expect(spanish.string("common.cancel", fallback: "Cancel") == "Cancelar")
    }

    @Test
    func localizerLoadsCommandPaletteResources() throws {
        let bundle = try #require(localizationBundle())

        let english = AppLocalizer(languagePreference: .english, bundle: bundle)
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(english.string("command.tabs.new.name", fallback: "New Tab") == "New Tab")
        #expect(spanish.string("command.tabs.new.name", fallback: "New Tab") == "Nueva pestaña")
        #expect(spanish.string("command.category.tabs", fallback: "Tabs") == "Pestañas")
        #expect(spanish.string("commandPalette.empty", fallback: "No commands found") == "No se encontraron comandos")
        #expect(spanish.string("commandPalette.footer.navigate", fallback: "Navigate") == "Navegar")
        #expect(spanish.string("commandPalette.footer.action.plural", fallback: "actions") == "acciones")
    }

    @Test
    func auroraCommandPaletteStringsLocalizeChrome() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        let strings = Design.AuroraPaletteStrings(localizer: spanish)

        #expect(strings.accessibilityLabel == "Paleta de comandos")
        #expect(strings.searchPlaceholder == "Escribe un comando...")
        #expect(strings.searchAccessibilityLabel == "Buscar en la paleta de comandos")
        #expect(strings.emptyMessage == "No se encontraron comandos")
        #expect(strings.navigateHint == "Navegar")
        #expect(strings.selectHint == "Seleccionar")
        #expect(strings.closeHint == "Cerrar")
        #expect(strings.actionCountLabel(for: 1) == "1 acción")
        #expect(strings.actionCountLabel(for: 2) == "2 acciones")
    }

    @Test
    func localizerLoadsWelcomeAndOnboardingResources() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("welcome.subtitle", fallback: "Agent-aware terminal for macOS") == "Terminal para macOS con conciencia de agentes")
        #expect(spanish.string("welcome.getStarted", fallback: "Get Started") == "Comenzar")
        #expect(spanish.string("welcome.shortcut.commandPalette", fallback: "Command Palette") == "Paleta de comandos")
        #expect(spanish.string("onboarding.title", fallback: "Cocxy Setup") == "Configuración de Cocxy")
        #expect(spanish.string("onboarding.subtitle", fallback: "Choose local defaults for this Mac") == "Elige valores predeterminados locales para esta Mac")
        #expect(spanish.string("onboarding.enableLanguageServers", fallback: "Enable language servers") == "Activar servidores de lenguaje")
        #expect(spanish.string("onboarding.apply", fallback: "Apply") == "Aplicar")
        #expect(spanish.string("onboarding.error.apply", fallback: "Unable to apply onboarding settings.") == "No se pudieron aplicar los ajustes de onboarding.")
    }

    @Test
    func browserChromeStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("browser.panel.title", fallback: "Browser") == "Navegador")
        #expect(spanish.string("browser.panel.empty.title", fallback: "No page loaded") == "Sin página cargada")
        #expect(spanish.string("browser.find.results.count", fallback: "%d of %d") == "%d de %d")
        #expect(spanish.string("browser.profile.defaultBadge", fallback: "(Default)") == "(Predeterminado)")
        #expect(spanish.string("browser.downloads.unknownSize", fallback: "Unknown size") == "Tamaño desconocido")
        #expect(DevToolsTab.console.localizedTitle(using: spanish) == "Consola")
        #expect(DevToolsTab.network.localizedTitle(using: spanish) == "Red")
        #expect(DevToolsTab.dom.localizedTitle(using: spanish) == "DOM")
    }

    @Test
    func pluginMarketplaceStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("plugins.sources", fallback: "Sources") == "Fuentes")
        #expect(spanish.string("plugins.replaceExisting", fallback: "Replace existing") == "Reemplazar existente")
        #expect(spanish.string("plugins.empty.installed", fallback: "No plugins installed.") == "No hay plugins instalados.")
        #expect(spanish.string("plugins.status.noUpdates", fallback: "No updates found.") == "No se encontraron actualizaciones.")
    }

    @Test
    func notebookAndWorkflowStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("notebook.untitledTitle", fallback: "Untitled Notebook") == "Notebook sin título")
        #expect(spanish.string("notebook.status.executed.one", fallback: "Executed %d notebook cell.") == "%d celda de notebook ejecutada.")
        #expect(spanish.string("workflow.status.completed.one", fallback: "Workflow %@ completed after %d step.") == "Workflow %@ completado después de %d paso.")
        #expect(spanish.string("workflow.step.status.completed", fallback: "Completed") == "Completado")
    }

    @Test
    func macroPanelStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("macros.section.clipboard", fallback: "Clipboard") == "Portapapeles")
        #expect(spanish.string("macros.record", fallback: "Record") == "Grabar")
        #expect(spanish.string("macros.status.recorded.one", fallback: "Recorded %d event") == "Grabada %d acción")
        #expect(spanish.string("macros.status.clipboard.many", fallback: "%d clipboard items") == "%d elementos del portapapeles")
    }

    @Test
    func gitHubPaneStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("github.pane.accessibility", fallback: "GitHub pane") == "Panel de GitHub")
        #expect(spanish.string("github.pane.empty.pullRequests", fallback: "No pull requests") == "No hay pull requests")
        #expect(spanish.string("github.pane.context.openInBrowser", fallback: "Open in Browser") == "Abrir en navegador")
        #expect(spanish.string("github.pane.merge.action", fallback: "Merge Pull Request...") == "Fusionar pull request...")
        #expect(GitHubPaneSetupAction.installCLI.localizedButtonTitle(using: spanish) == "Instalar GitHub CLI")
        #expect(GitHubPaneViewModel.Tab.issues.localizedTitle(using: spanish) == "Issues")
        #expect(GitHubBannerKind.info.localizedAccessibilityPrefix(using: spanish) == "Información")
        #expect(GitHubCheckStatus.completed.localizedDisplayName(using: spanish) == "Completado")
        #expect(GitHubCheckConclusion.success.localizedDisplayName(using: spanish) == "Correcto")
    }

    @Test
    func codeReviewPanelStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("codeReview.panel.accessibility", fallback: "Agent code review panel") == "Panel de revisión de código")
        #expect(spanish.string("codeReview.panel.title", fallback: "Agent Code Review") == "Revisión de código")
        #expect(spanish.string("codeReview.panel.empty.title", fallback: "No reviewable changes yet") == "Aún no hay cambios para revisar")
        #expect(spanish.string("codeReview.toolbar.editFile", fallback: "Edit File") == "Editar archivo")
        #expect(spanish.string("codeReview.toolbar.shortcuts.title", fallback: "Review Shortcuts") == "Atajos de revisión")
        #expect(DiffMode.sinceSessionStart.localizedTitle(using: spanish) == "Sesión de agente")
        #expect(CodeReviewEditorSplitLayout.sideBySide.localizedTitle(using: spanish) == "Lado a lado")
    }

    @Test
    func codeReviewSecondaryStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("codeReview.gitWorkflow.title", fallback: "Git Workflow") == "Workflow Git")
        #expect(spanish.string("codeReview.gitWorkflow.createBranch", fallback: "Create Branch") == "Crear rama")
        #expect(spanish.string("codeReview.inlineComment.title", fallback: "Inline Comment") == "Comentario inline")
        #expect(spanish.string("codeReview.activity.title", fallback: "Live Agent Workstream") == "Actividad del agente en vivo")
        #expect(spanish.string("codeReview.openSuggestion.title", fallback: "Agent changes are ready to review") == "Cambios del agente listos para revisar")
    }

    @Test
    func remoteWorkspaceStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("remoteWorkspace.title", fallback: "Remote Workspaces") == "Workspaces remotos")
        #expect(spanish.string("remoteWorkspace.quickConnect.placeholder", fallback: "Quick Connect (user@host:port)") == "Conexión rápida (user@host:port)")
        #expect(spanish.string("remoteWorkspace.empty.title", fallback: "No remote profiles yet") == "Aún no hay perfiles remotos")
        #expect(spanish.string("remoteWorkspace.profile.action.connect", fallback: "Connect to %@") == "Conectar a %@")
        #expect(spanish.string("remoteWorkspace.profileEditor.title.new", fallback: "New Profile") == "Nuevo perfil")
        #expect(spanish.string("remoteWorkspace.proxy.systemWide.detail", fallback: "Routes all macOS traffic through the SSH tunnel. Requires admin password.") == "Enruta todo el tráfico de macOS por el túnel SSH. Requiere contraseña de administrador.")
        #expect(spanish.string("remoteWorkspace.daemon.controls", fallback: "Controls") == "Controles")
        #expect(spanish.string("remoteWorkspace.relay.activeChannels", fallback: "Active Channels") == "Canales activos")
        #expect(spanish.string("remoteWorkspace.sftp.emptyDirectory", fallback: "Empty directory") == "Directorio vacío")
        #expect(RemoteConnectionViewModel.SubPanel.sessions.localizedLabel(using: spanish) == "Sesiones")
        #expect(RemoteConnectionViewModel.SubPanel.tunnels.localizedDetail(using: spanish) == "Redirigir puertos locales y remotos")
        #expect(ForwardTypeOption.dynamic.localizedLabel(using: spanish) == "Dinámico")
    }

    @Test
    func activityDashboardStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("activity.title", fallback: "Activity") == "Actividad")
        #expect(spanish.string("activity.metric.events", fallback: "Events") == "Eventos")
        #expect(spanish.string("activity.section.projectTime", fallback: "Project Time") == "Tiempo por proyecto")
        #expect(spanish.string("activity.empty.noCommands", fallback: "No commands yet") == "Aún no hay comandos")
        #expect(ActivityDashboardTrackingState.enabled.localizedTitle(using: spanish) == "Registro local activado")
        #expect(ActivityDashboardExportFormat.eventsCSV.localizedMenuTitle(using: spanish) == "Eventos CSV")
        #expect(ActivityEventKind.projectSwitched.localizedDashboardTitle(using: spanish) == "Cambios de proyecto")
    }

    @Test
    func agentPanelStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("agent.panel.title", fallback: "Agent Mode") == "Modo agente")
        #expect(spanish.string("agent.panel.prompt.placeholder", fallback: "Ask Agent Mode") == "Preguntar a Modo agente")
        #expect(spanish.string("agent.panel.approval.approve", fallback: "Approve") == "Aprobar")
        #expect(spanish.string("agent.panel.message.you", fallback: "You") == "Tú")
        #expect(AgentPanelView.localizedSkillPickerTitle(selectedCount: 0, using: spanish) == "Skills")
        #expect(AgentPanelView.localizedSkillPickerTitle(selectedCount: 2, using: spanish) == "2 skills")
    }

    @Test
    func subagentPanelStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(SubagentPanelView.localizedFallbackTitle(using: spanish) == "Subagente")
        #expect(SubagentPanelView.localizedStartingText(using: spanish) == "Iniciando...")
        #expect(SubagentPanelView.localizedRunningText(using: spanish) == "Ejecutando...")
        #expect(SubagentPanelView.localizedAgentStartingText(using: spanish) == "Agente iniciando...")
        #expect(spanish.string("subagent.panel.close", fallback: "Close panel") == "Cerrar panel")
    }

    @MainActor
    @Test
    func scrollbackSearchStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let viewModel = ScrollbackSearchBarViewModel()

        #expect(spanish.string("scrollbackSearch.placeholder", fallback: "Search scrollback...") == "Buscar en scrollback...")
        #expect(spanish.string("scrollbackSearch.close", fallback: "Close search") == "Cerrar búsqueda")
        #expect(viewModel.localizedResultCountDisplay(using: spanish) == "Sin coincidencias")

        viewModel.applySearchResults([
            SearchResult(
                id: UUID(),
                lineNumber: 1,
                column: 0,
                matchText: "match",
                contextBefore: "",
                contextAfter: ""
            ),
            SearchResult(
                id: UUID(),
                lineNumber: 2,
                column: 0,
                matchText: "match",
                contextBefore: "",
                contextAfter: ""
            ),
        ])
        viewModel.navigateNext()
        #expect(viewModel.localizedResultCountDisplay(using: spanish) == "2 de 2 coincidencias")
    }

    @Test
    func agentDashboardStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(DashboardPanelView.localizedPanelTitle(using: spanish) == "Dashboard de agentes")
        #expect(DashboardPanelView.localizedCurrentWindowScopeTitle(using: spanish) == "Esta ventana")
        #expect(DashboardSessionRow.localizedFilesCount(2, using: spanish) == "2 archivos")
        #expect(DashboardSessionRow.localizedFileConflictPrefix(using: spanish) == "Conflicto de archivo")
        #expect(DashboardStateIndicator.localizedAccessibilityLabel(for: .working, using: spanish) == "Trabajando")
    }

    @Test
    func statusBarUtilityStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(StatusBarView.localizedCommandRunning(using: spanish) == "Comando ejecutándose")
        #expect(KeyboardShortcutsButton.localizedTitle(using: spanish) == "Atajos de teclado")
        #expect(spanish.string("keyboardShortcuts.terminal.interrupt", fallback: "Interrupt process") == "Interrumpir proceso")
        #expect(AgentAttachmentBar.localizedRemoveImage(using: spanish) == "Eliminar imagen")
    }

    @Test
    func keybindingsEditorStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(KeybindingsEditorView.localizedSaveButton(using: spanish) == "Guardar")
        #expect(KeybindingsEditorView.localizedResetAllButton(using: spanish) == "Restablecer todo")
        #expect(KeybindingsEditorView.localizedConflictsDetected(using: spanish) == "Conflictos detectados")
        #expect(KeybindingCaptureSheet.localizedCaptureHint(using: spanish) == "Presiona el nuevo atajo...")
    }

    @Test
    func dbCloudPanelPickerLocalizesSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("dbCloud.kindPicker", fallback: "Kind") == "Tipo")
    }

    @MainActor
    @Test
    func commandPaletteViewModelLocalizesActionsAndSearchesSpanish() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let viewModel = CommandPaletteViewModel(
            engine: CommandPaletteEngineImpl(),
            localizer: localizer
        )

        let newTab = try #require(viewModel.filteredActions.first { $0.id == "tabs.new" })
        #expect(newTab.name == "Nueva pestaña")
        #expect(newTab.description == "Abrir una nueva pestaña de terminal")
        #expect(viewModel.localizedCategoryTitle(.tabs) == "Pestañas")

        viewModel.query = "pesta"

        #expect(viewModel.filteredActions.contains { $0.id == "tabs.new" })
    }

    @MainActor
    @Test
    func commandActionLocalizationPreservesDynamicPictureInPictureState() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let disabled = CommandAction(
            id: "window.pictureInPicture",
            name: "Float Active Terminal",
            description: "Enable [experimental].pip-enabled to use terminal Picture-in-Picture",
            shortcut: nil,
            category: .navigation,
            handler: {}
        ).localized(using: localizer)
        let enabled = CommandAction(
            id: "window.pictureInPicture",
            name: "Float Active Terminal",
            description: "Move the active terminal into a floating Picture-in-Picture panel",
            shortcut: nil,
            category: .navigation,
            handler: {}
        ).localized(using: localizer)

        #expect(disabled.description == "Activa [experimental].pip-enabled para usar Picture-in-Picture del terminal")
        #expect(enabled.description == "Mover el terminal activo a un panel flotante Picture-in-Picture")
    }

    @Test
    func buildAndVerifyScriptsIncludeLocalizationResources() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let buildScript = try String(
            contentsOf: root.appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )
        let verifyScript = try String(
            contentsOf: root.appendingPathComponent("scripts/verify-app-bundle.sh"),
            encoding: .utf8
        )

        #expect(buildScript.contains("Resources/Localization"))
        #expect(verifyScript.contains("en.lproj/Localizable.strings"))
        #expect(verifyScript.contains("es.lproj/Localizable.strings"))
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}
