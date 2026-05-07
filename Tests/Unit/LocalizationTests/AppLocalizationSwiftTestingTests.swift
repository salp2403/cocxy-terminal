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
        #expect(spanish.string("preferences.appearance.enableAurora", fallback: "Enable Aurora chrome") == "Activar interfaz Aurora")
        #expect(spanish.string("preferences.appearance.enableAurora.caption", fallback: "Aurora is an opt-in preview of the redesigned chrome. Turn it off to return to the classic sidebar and status bar.") == "Aurora es una vista previa opcional de la interfaz rediseñada. Desactívalo para volver a la barra lateral y barra de estado clásicas.")
        #expect(spanish.string("preferences.appearance.glassChromeTint", fallback: "Glass chrome tint") == "Tinte de superficies translúcidas")
        #expect(spanish.string("preferences.appearance.fontResolution.included", fallback: "Included with Cocxy: %@") == "Incluida con Cocxy: %@")
        #expect(spanish.string("preferences.appearance.fontResolution.fallbackBundled", fallback: "\"%@\" is not installed. Cocxy will fall back to bundled %@.") == "\"%@\" no está instalada. Cocxy usará como alternativa la fuente incluida %@.")
        #expect(spanish.string("preferences.appearance.fontResolution.fallback", fallback: "\"%@\" is not installed. Cocxy will fall back to %@.") == "\"%@\" no está instalada. Cocxy usará como alternativa %@.")
        #expect(spanish.string("preferences.appearance.showRateLimitIndicator", fallback: "Show rate-limit indicator") == "Mostrar indicador de límite de uso")
        #expect(spanish.string("preferences.appearance.sidebarDensity.detailed", fallback: "Detailed") == "Detallada")
        #expect(spanish.string("preferences.appearance.sidebarRowDetail.state", fallback: "State") == "Estado")
        #expect(spanish.string("preferences.agentDetection.idleTimeout", fallback: "Idle timeout: %d s") == "Tiempo de inactividad: %d s")
        #expect(spanish.string("preferences.agentMode.provider.detail.foundationModels", fallback: "Runs on-device when supported. If unavailable, Cocxy asks you to choose another provider instead of silently falling back.") == "Corre en el dispositivo cuando está soportado. Si no está disponible, Cocxy te pide elegir otro proveedor en vez de cambiar silenciosamente.")
        #expect(spanish.string("preferences.voice.recognitionLocale", fallback: "Recognition locale") == "Idioma de reconocimiento")
        #expect(spanish.string("preferences.voice.resolution.manualUnsupportedSystemFallback", fallback: "%@ is not listed by Speech; using the system locale fallback.") == "%@ no está listado por Speech; usando el idioma del sistema como alternativa.")
        #expect(spanish.string("preferences.activity.trackCosts", fallback: "Track token usage and estimated costs") == "Registrar uso de tokens y costos estimados")
        #expect(spanish.string("preferences.sessionReplay.storageDirectory", fallback: "Storage directory") == "Directorio de almacenamiento")
        #expect(spanish.string("preferences.backup.enable", fallback: "Enable local automatic backups") == "Activar copias automáticas locales")
        #expect(spanish.string("preferences.backup.artifact.aiConversations", fallback: "AI conversations") == "Conversaciones IA")
        #expect(spanish.string("preferences.codeReview.autoShow", fallback: "Auto-show review panel when an agent session ends") == "Mostrar panel de revisión automáticamente cuando termina una sesión de agente")
        #expect(spanish.string("preferences.notifications.dockBadge", fallback: "Dock badge") == "Insignia en el Dock")
        #expect(spanish.string("preferences.terminal.scrollbackLines", fallback: "Scrollback lines") == "Líneas de historial")
        #expect(spanish.string("preferences.terminal.cursorStyle.bar", fallback: "Bar") == "Barra")
        #expect(spanish.string("preferences.terminal.imageMemoryBudget", fallback: "Image memory budget: %d MiB") == "Memoria para imágenes: %d MiB")
        #expect(spanish.string("preferences.terminal.inlineImages.section", fallback: "Inline Images") == "Imágenes en línea")
        #expect(spanish.string("preferences.lsp.enable", fallback: "Enable language servers") == "Activar servidores de lenguaje")
        #expect(spanish.string("preferences.lsp.install.swift", fallback: "Install Xcode or Xcode Command Line Tools to provide sourcekit-lsp.") == "Instala Xcode o las herramientas de línea de comandos de Xcode para usar sourcekit-lsp.")
        #expect(spanish.string("preferences.editor.enableVimMode", fallback: "Enable Vim mode") == "Activar modo Vim")
        #expect(spanish.string("preferences.editor.inlineCompletions.section", fallback: "Inline Completions") == "Autocompletado en línea")
        #expect(spanish.string("preferences.editor.contextWindow", fallback: "Context window: %d UTF-16") == "Ventana de contexto: %d UTF-16")
        #expect(spanish.string("preferences.worktrees.enable", fallback: "Enable worktrees") == "Activar worktrees")
        #expect(spanish.string("preferences.worktrees.showBadge", fallback: "Show worktree badge on tabs") == "Mostrar insignia de worktree en pestañas")
        #expect(spanish.string("preferences.worktrees.onClose.remove", fallback: "Remove if clean") == "Eliminar si está limpio")
        #expect(spanish.string("preferences.agentMode.enable", fallback: "Enable Agent Mode") == "Activar modo agente")
        #expect(spanish.string("preferences.agentMode.apiKey.saved", fallback: "A key is saved in the macOS Keychain for this provider.") == "Hay una llave guardada en Keychain de macOS para este proveedor.")
        #expect(spanish.string("preferences.mcp.configFile.section", fallback: "Config File") == "Archivo de configuración")
        #expect(spanish.string("preferences.mcp.json.section", fallback: "__missing_key__") != "__missing_key__")
        #expect(spanish.string("preferences.mcp.noServers", fallback: "No MCP servers configured.") == "No hay servidores MCP configurados.")
        #expect(spanish.string("preferences.iCloud.enable", fallback: "Enable iCloud Drive sync") == "Activar sincronización con iCloud Drive")
        #expect(spanish.string("preferences.iCloud.optIn.section", fallback: "Opt-In") == "Activación")
        #expect(spanish.string("preferences.iCloud.encryptArtifacts.help", fallback: "Encryption is required for iCloud Sync.") == "El cifrado es obligatorio para la sincronización iCloud.")
        #expect(spanish.string("preferences.iCloud.artifact.settings", fallback: "Settings") == "Ajustes")
        #expect(spanish.string("preferences.iCloud.artifact.notebooks", fallback: "Notebooks") == "Cuadernos")
        #expect(spanish.string("preferences.iCloud.export", fallback: "Export Encrypted Artifacts") == "Exportar artefactos cifrados")
        #expect(spanish.string("preferences.iCloud.conflict.useRemote", fallback: "Use Remote") == "Usar remoto")
        #expect(spanish.string("preferences.iCloud.status.disabled", fallback: "iCloud Sync is disabled.") == "La sincronización iCloud está desactivada.")
        #expect(spanish.string("preferences.github.enable", fallback: "Enable GitHub pane") == "Activar panel de GitHub")
        #expect(spanish.string("preferences.github.autoRefresh", fallback: "Auto-refresh every %d s") == "Actualizar automáticamente cada %d s")
        #expect(spanish.string("preferences.github.includeDrafts", fallback: "Include draft pull requests") == "Incluir solicitudes en borrador")
        #expect(spanish.string("preferences.github.defaultState.merged", fallback: "Merged (PRs only)") == "Fusionadas (solo solicitudes)")
        #expect(spanish.string("preferences.about.subtitle", fallback: "Agent-aware terminal for macOS") == "Terminal para macOS con conciencia de agentes")
        #expect(spanish.string("preferences.about.zeroTelemetry", fallback: "Zero telemetry. Zero tracking.") == "Cero telemetría. Cero rastreo.")
        #expect(spanish.string("preferences.about.checkForUpdates", fallback: "Check for Updates") == "Buscar actualizaciones")
        #expect(spanish.string("agentState.indicator.waitingInput", fallback: "Agent state: waiting for input") == "Estado del agente: esperando entrada")
        #expect(spanish.string("markdown.toolbar.untitledFile", fallback: "Untitled.md") == "Sin título.md")
        #expect(spanish.string("markdown.preview.toc.title", fallback: "Table of Contents") == "Tabla de contenidos")
        #expect(spanish.string("window.activity.tabOpened", fallback: "New tab") == "Nueva pestaña")
        #expect(spanish.string("app.crashRecovery.restore.button", fallback: "Restore") == "Restaurar")
        #expect(spanish.string("app.quit.message", fallback: "All terminal sessions will be closed.") == "Todas las sesiones de terminal se cerrarán.")
        #expect(spanish.string("common.cancel", fallback: "Cancel") == "Cancelar")
    }

    @MainActor
    @Test
    func appDelegateFallbackStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(
            AppDelegate.localizedTerminalEngineInitializationFailure(using: spanish)
                == "No se pudo inicializar el motor de terminal"
        )
    }

    @Test
    func localizerLoadsCommandPaletteResources() throws {
        let bundle = try #require(localizationBundle())

        let english = AppLocalizer(languagePreference: .english, bundle: bundle)
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(english.string("command.tabs.new.name", fallback: "New Tab") == "New Tab")
        #expect(spanish.string("command.tabs.new.name", fallback: "New Tab") == "Nueva pestaña")
        #expect(spanish.string("command.category.tabs", fallback: "Tabs") == "Pestañas")
        #expect(spanish.string("command.category.config", fallback: "Config") == "Ajustes")
        #expect(spanish.string("commandPalette.empty", fallback: "No commands found") == "No se encontraron comandos")
        #expect(spanish.string("commandPalette.footer.navigate", fallback: "Navigate") == "Navegar")
        #expect(spanish.string("commandPalette.footer.action.plural", fallback: "actions") == "acciones")
        #expect(spanish.string("quickSwitch.item.browser.title", fallback: "Browser: %@") == "Navegador: %@")
        #expect(spanish.string("quickSwitch.kind.browserTab", fallback: "Browser tab") == "Pestaña de navegador")
        #expect(spanish.string("command.preferences.show.name", fallback: "Show Preferences") == "Mostrar preferencias")
        #expect(spanish.string("command.onboarding.show.name", fallback: "Show Onboarding") == "Mostrar configuración guiada")
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
        #expect(spanish.string("welcome.shortcut.agentDashboard", fallback: "Agent Dashboard") == "Panel de agentes")
        #expect(spanish.string("welcome.highlight.dashboard.title", fallback: "Dashboard") == "Panel de agentes")
        #expect(spanish.string("onboarding.title", fallback: "Cocxy Setup") == "Configuración de Cocxy")
        #expect(spanish.string("onboarding.accessibilityLabel", fallback: "Cocxy onboarding") == "Configuración guiada de Cocxy")
        #expect(spanish.string("onboarding.subtitle", fallback: "Choose local defaults for this Mac") == "Elige valores predeterminados locales para esta Mac")
        #expect(spanish.string("onboarding.enableLanguageServers", fallback: "Enable language servers") == "Activar servidores de lenguaje")
        #expect(spanish.string("onboarding.createPrimerSkill", fallback: "Create primer skill") == "Crear habilidad inicial")
        #expect(spanish.string("onboarding.apply", fallback: "Apply") == "Aplicar")
        #expect(spanish.string("onboarding.error.apply", fallback: "Unable to apply onboarding settings.") == "No se pudieron aplicar los ajustes de configuración guiada.")
        #expect(spanish.string("onboarding.step.primerSkill", fallback: "Primer Skill") == "Habilidad inicial")
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
        #expect(BrowserDownloadsView.localizedProgressAccessibilityValue(0.42, using: spanish) == "42 por ciento")
        #expect(spanish.string("markdown.toolbar.mode.tooltip", fallback: "Switch between Source, Preview, and Split") == "Cambiar entre Fuente, Previa y Dividida")
        #expect(DevToolsTab.console.localizedTitle(using: spanish) == "Consola")
        #expect(DevToolsTab.network.localizedTitle(using: spanish) == "Red")
        #expect(DevToolsTab.dom.localizedTitle(using: spanish) == "DOM")
        #expect(MarkdownViewMode.split.localizedLabel(using: spanish) == "Dividida")
        #expect(spanish.string("keyboardShortcuts.splits.horizontal", fallback: "Split horizontal") == "Dividir horizontalmente")
        #expect(spanish.string("keyboardShortcuts.splits.vertical", fallback: "Split vertical") == "Dividir verticalmente")
    }

    @Test
    func pluginMarketplaceStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("plugins.sources", fallback: "Sources") == "Fuentes")
        #expect(spanish.string("plugins.replaceExisting", fallback: "Replace existing") == "Reemplazar existente")
        #expect(spanish.string("plugins.empty.installed", fallback: "No plugins installed.") == "No hay plugins instalados.")
        #expect(spanish.string("plugins.status.noUpdates", fallback: "No updates found.") == "No se encontraron actualizaciones.")
        let bundledPlugin = PluginManifest(
            id: "cocxy-github-pane",
            name: "GitHub Pane",
            description: "Adds local shell context for repository and pull request workflows.",
            version: "1.0.0",
            author: "Cocxy",
            minCocxyVersion: nil,
            events: [.sessionStart],
            directoryPath: "/tmp/cocxy-github-pane",
            manifestFileName: PluginManifest.marketplaceManifestFileName,
            repositoryURL: "bundled://cocxy-github-pane",
            homepageURL: nil,
            license: "MIT",
            capabilities: [.environmentRead],
            signature: nil
        )
        #expect(PluginMarketplaceView.localizedPluginName(bundledPlugin, using: spanish) == "Panel GitHub")
        #expect(
            PluginMarketplaceView.localizedPluginDescription(bundledPlugin, using: spanish)
                == "Agrega contexto local de shell para flujos de repositorios y solicitudes de cambio."
        )
    }

    @Test
    func notebookAndWorkflowStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("notebook.untitledTitle", fallback: "Untitled Notebook") == "Notebook sin título")
        #expect(spanish.string("notebook.status.executed.one", fallback: "Executed %d notebook cell.") == "%d celda de notebook ejecutada.")
        #expect(spanish.string("horizontalTab.action.openWorkflow", fallback: "Open Workflow") == "Abrir flujo")
        #expect(spanish.string("horizontalTab.add.workflow", fallback: "Workflow") == "Flujo")
        #expect(spanish.string("window.pane.workflowPanel", fallback: "workflow panel") == "panel de flujo")
        #expect(spanish.string("workflow.defaultSource.name", fallback: "Local Workflow") == "Flujo local")
        #expect(spanish.string("workflow.defaultSource.command", fallback: "echo workflow ready") == "echo flujo listo")
        #expect(spanish.string("workflow.status.new", fallback: "New workflow") == "Flujo nuevo")
        #expect(spanish.string("workflow.status.completed.one", fallback: "Workflow %@ completed after %d step.") == "Flujo %@ completado después de %d paso.")
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
        #expect(spanish.string("github.pane.empty.pullRequests", fallback: "No pull requests") == "No hay solicitudes de cambio")
        #expect(spanish.string("github.pane.context.openInBrowser", fallback: "Open in Browser") == "Abrir en navegador")
        #expect(spanish.string("github.pane.merge.action", fallback: "Merge Pull Request...") == "Fusionar solicitud...")
        #expect(spanish.string("github.pane.empty.noReviewThreads", fallback: "No review threads") == "No hay hilos de revisión")
        #expect(spanish.string("github.pane.context.reviewThreads", fallback: "Show review threads") == "Mostrar hilos de revisión")
        #expect(spanish.string("github.pane.context.resolveReviewThread", fallback: "Resolve thread") == "Resolver hilo")
        #expect(spanish.string("github.pane.reviewThreads.resolve.success", fallback: "Review thread resolved in %@.") == "Hilo de revisión resuelto en %@.")
        #expect(GitHubPaneSetupAction.installCLI.localizedButtonTitle(using: spanish) == "Instalar GitHub CLI")
        #expect(GitHubPaneViewModel.Tab.issues.localizedTitle(using: spanish) == "Incidencias")
        #expect(spanish.string("github.pane.empty.issues", fallback: "No issues") == "No hay incidencias")
        #expect(spanish.string("github.pane.footer.counts", fallback: "%d PRs · %d issues") == "%d PR · %d incidencias")
        #expect(GitHubPaneViewModel.Tab.checks.localizedTitle(using: spanish) == "Verificaciones")
        #expect(GitHubPaneViewModel.Tab.reviewThreads.localizedTitle(using: spanish) == "Hilos de revisión")
        #expect(spanish.string("github.pane.refresh", fallback: "Refresh") == "Refrescar")
        #expect(spanish.string("github.merge.error.cli.rateLimited", fallback: "GitHub rate limit reached. Try again later.") == "Se alcanzó el límite de GitHub. Inténtalo más tarde.")
        #expect(GitHubBannerKind.info.localizedAccessibilityPrefix(using: spanish) == "Información")
        #expect(GitHubCheckStatus.completed.localizedDisplayName(using: spanish) == "Completado")
        #expect(GitHubCheckConclusion.success.localizedDisplayName(using: spanish) == "Correcto")
    }

    @MainActor
    @Test
    func codeReviewPanelStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("codeReview.panel.accessibility", fallback: "Agent code review panel") == "Panel de revisión de código")
        #expect(spanish.string("codeReview.panel.title", fallback: "Agent Code Review") == "Revisión de código")
        #expect(spanish.string("codeReview.panel.empty.title", fallback: "No reviewable changes yet") == "Aún no hay cambios para revisar")
        #expect(spanish.string("codeReview.banner.submitRouteMissing", fallback: "Review feedback could not be sent because the original agent terminal is no longer available.") == "No se pudieron enviar los comentarios porque la terminal original del agente ya no está disponible.")
        #expect(spanish.string("codeReview.prMerge.noPullRequest", fallback: "No pull request is attached to this review.") == "No hay una solicitud adjunta a esta revisión.")
        #expect(spanish.string("github.merge.error.conflict", fallback: "The pull request has merge conflicts. Resolve them in a browser before retrying.") == "La solicitud tiene conflictos de fusión. Resuélvelos en un navegador antes de reintentar.")
        #expect(spanish.string("codeReview.toolbar.editFile", fallback: "Edit File") == "Editar archivo")
        #expect(spanish.string("codeReview.toolbar.shortcuts.title", fallback: "Review Shortcuts") == "Atajos de revisión")
        #expect(MainWindowController.localizedOpenInDefaultEditorTitle(localizer: spanish) == "Abrir en editor predeterminado")
        #expect(MainWindowController.localizedOpenInEditorTitle("Nova", localizer: spanish) == "Abrir en Nova")
        #expect(FileListView.localizedAccessibilityHint(using: spanish) == "Selecciona este archivo para revisar sus bloques")
        #expect(
            FileListView.localizedAccessibilityLabel(
                displayName: "README.md",
                status: .modified,
                additions: 2,
                deletions: 1,
                using: spanish
            ) == "README.md, modificado, más 2, menos 1"
        )
        #expect(DiffMode.uncommitted.localizedTitle(using: spanish) == "Árbol de trabajo")
        #expect(DiffMode.sinceSessionStart.localizedTitle(using: spanish) == "Sesión de agente")
        #expect(DiffMode.vsBranch.localizedTitle(using: spanish) == "Referencia")
        #expect(spanish.string("codeReview.panel.anchorHint", fallback: "Click a line to anchor feedback") == "Haz clic en una línea para anclar un comentario")
        #expect(spanish.string("codeReview.error.invalidWorkingDirectory", fallback: "The working directory for the hunk action is invalid.") == "El directorio de trabajo para la acción del bloque no es válido.")
        #expect(spanish.string("codeReview.editor.layout.picker", fallback: "Editor layout") == "Disposición del editor")
        #expect(spanish.string("codeReview.editor.layout.help", fallback: "Switch between stacked and side-by-side editor/diff layout") == "Cambiar entre disposición apilada y lado a lado para editor/diff")
        #expect(CodeReviewEditorSplitLayout.sideBySide.localizedTitle(using: spanish) == "Lado a lado")
        #expect(spanish.string("codeReview.toolbar.applySuggestions.hint", fallback: "Apply pending suggestion blocks to local files after conflict checks") == "Aplicar bloques de sugerencia pendientes a archivos locales después de revisar conflictos")
        #expect(spanish.string("codeReview.toolbar.shortcuts.nextHunk", fallback: "Next / previous hunk") == "Bloque siguiente / anterior")
        #expect(spanish.string("codeReview.toolbar.shortcuts.acceptReject", fallback: "Accept / reject hunk") == "Aceptar / rechazar bloque")
    }

    @Test
    func codeReviewSecondaryStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("codeReview.gitWorkflow.title", fallback: "Git Workflow") == "Flujo Git")
        #expect(spanish.string("codeReview.gitWorkflow.hide", fallback: "Hide Git workflow") == "Ocultar flujo Git")
        #expect(spanish.string("codeReview.gitWorkflow.commitTip", fallback: "Tip: first line = summary, blank line = details.") == "Consejo: primera línea = resumen, línea en blanco = detalles.")
        #expect(spanish.string("codeReview.gitWorkflow.createBranch", fallback: "Create Branch") == "Crear rama")
        #expect(spanish.string("codeReview.gitWorkflow.push", fallback: "Push") == "Enviar")
        #expect(spanish.string("codeReview.gitWorkflow.stat.ahead", fallback: "ahead %d") == "%d por delante")
        #expect(spanish.string("codeReview.gitWorkflow.stat.behind", fallback: "behind %d") == "%d por detrás")
        #expect(spanish.string("codeReview.gitWorkflow.stat.staged", fallback: "%d staged") == "%d preparados")
        #expect(spanish.string("codeReview.gitWorkflow.footer", fallback: "Commit All stages current review changes, Push sends the branch to origin, Create Pull Request opens a PR on GitHub via gh.") == "Commit de todo prepara los cambios actuales de revisión, Enviar sube la rama a origin y Crear solicitud abre un PR en GitHub vía gh.")
        #expect(spanish.string("codeReview.prMerge.aftermath.synced.ahead", fallback: "`%@` is %d ahead of origin (no pull needed).") == "`%@` está %d por delante de origin (no hace falta pull).")
        #expect(spanish.string("codeReview.inlineComment.title", fallback: "Inline Comment") == "Comentario en línea")
        #expect(spanish.string("codeReview.activity.title", fallback: "Live Agent Workstream") == "Actividad del agente en vivo")
        #expect(spanish.string("codeReview.activity.metric.tools", fallback: "tools") == "herramientas")
        #expect(spanish.string("codeReview.activity.state.idle", fallback: "idle") == "inactivo")
        #expect(spanish.string("codeReview.panel.metric.hunks", fallback: "%d hunks") == "%d bloques")
        #expect(spanish.string("codeReview.openSuggestion.title", fallback: "Agent changes are ready to review") == "Cambios del agente listos para revisar")
    }

    @Test
    @MainActor
    func remoteWorkspaceStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("remoteWorkspace.title", fallback: "Remote Workspaces") == "Espacios remotos")
        #expect(spanish.string("remoteWorkspace.quickConnect.placeholder", fallback: "Quick Connect (user@host:port)") == "Conexión rápida (user@host:port)")
        #expect(spanish.string("remoteWorkspace.empty.title", fallback: "No remote profiles yet") == "Aún no hay perfiles remotos")
        #expect(spanish.string("remoteWorkspace.profile.action.connect", fallback: "Connect to %@") == "Conectar a %@")
        #expect(spanish.string("remoteWorkspace.profileEditor.title.new", fallback: "New Profile") == "Nuevo perfil")
        #expect(spanish.string("remoteWorkspace.profileEditor.field.host", fallback: "Host") == "Servidor")
        #expect(spanish.string("remoteWorkspace.profileEditor.placeholder.name", fallback: "production-web") == "web-produccion")
        #expect(spanish.string("remoteWorkspace.profileEditor.placeholder.host", fallback: "192.168.1.100 or host.example.com") == "192.168.1.100 o host.ejemplo.com")
        #expect(spanish.string("remoteWorkspace.profileEditor.placeholder.group", fallback: "production, staging, personal...") == "producción, pruebas, personal...")
        #expect(spanish.string("remoteWorkspace.profileEditor.section.jumpHosts", fallback: "Jump Hosts") == "Hosts de salto")
        #expect(spanish.string("remoteWorkspace.proxy.systemWide.detail", fallback: "Routes all macOS traffic through the SSH tunnel. Requires admin password.") == "Enruta todo el tráfico de macOS por el túnel SSH. Requiere contraseña de administrador.")
        #expect(spanish.string("remoteWorkspace.daemon.controls", fallback: "Controls") == "Controles")
        #expect(spanish.string("remoteWorkspace.relay.activeChannels", fallback: "Active Channels") == "Canales activos")
        #expect(spanish.string("remoteWorkspace.relay.hosts", fallback: "Hosts:") == "Servidores:")
        #expect(spanish.string("remoteWorkspace.relay.processes", fallback: "Procs:") == "Procesos:")
        #expect(spanish.string("remoteWorkspace.keys.field.passphrase", fallback: "Passphrase") == "Frase de contraseña")
        #expect(spanish.string("remoteWorkspace.sftp.emptyDirectory", fallback: "Empty directory") == "Directorio vacío")
        #expect(RemoteConnectionViewModel.SubPanel.sessions.localizedLabel(using: spanish) == "Sesiones")
        #expect(RemoteConnectionViewModel.SubPanel.tunnels.localizedDetail(using: spanish) == "Redirigir puertos locales y remotos")
        #expect(ForwardTypeOption.dynamic.localizedLabel(using: spanish) == "Dinámico")
        #expect(RemoteProfileEditor.localizedJumpHostPlaceholder(using: spanish) == "bastion.ejemplo.com")
        #expect(RemoteProfileEditor.localizedEnvironmentKeyPlaceholder(using: spanish) == "CLAVE")
        #expect(RemoteProfileEditor.localizedEnvironmentValuePlaceholder(using: spanish) == "valor")
        #expect(SSHKeyManagerView.localizedNewKeyNamePlaceholder(using: spanish) == "mi-llave")
        #expect(DaemonControlView.localizedForwardSpecPlaceholder(using: spanish) == "local:remoto")
    }

    @Test
    func activityDashboardStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("activity.title", fallback: "Activity") == "Actividad")
        #expect(spanish.string("activity.deleteAll.title", fallback: "Delete all Activity data?") == "¿Eliminar todos los datos de actividad?")
        #expect(spanish.string("activity.deleteAll.message", fallback: "This removes local Activity and token records from this Mac.") == "Esto elimina los registros locales de actividad y tokens de esta Mac.")
        #expect(spanish.string("activity.deleteData", fallback: "Delete Activity Data") == "Eliminar datos de actividad")
        #expect(spanish.string("activity.actionFailed.title", fallback: "Activity action failed") == "Acción de actividad fallida")
        #expect(spanish.string("activity.metric.events", fallback: "Events") == "Eventos")
        #expect(spanish.string("activity.section.projectTime", fallback: "Project Time") == "Tiempo por proyecto")
        #expect(spanish.string("activity.section.insights", fallback: "Insights") == "Hallazgos")
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
        #expect(AgentPanelView.localizedSkillPickerTitle(selectedCount: 0, using: spanish) == "Habilidades")
        #expect(AgentPanelView.localizedSkillPickerTitle(selectedCount: 2, using: spanish) == "2 habilidades")
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

        #expect(spanish.string("scrollbackSearch.placeholder", fallback: "Search scrollback...") == "Buscar en historial...")
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

        #expect(DashboardPanelView.localizedPanelTitle(using: spanish) == "Panel de agentes")
        #expect(spanish.string("agentDashboard.accessibility", fallback: "Agent dashboard") == "Panel de agentes")
        #expect(spanish.string("menu.view.agentTimeline", fallback: "Agent Timeline") == "Línea de tiempo de agentes")
        #expect(spanish.string("keyboardShortcuts.panels.agentTimeline", fallback: "Agent timeline") == "Línea de tiempo de agentes")
        #expect(spanish.string("keybindings.action.review.dashboard.name", fallback: "Toggle dashboard") == "Alternar panel de agentes")
        #expect(spanish.string("command.dashboard.toggle.description", fallback: "Show or hide the agent dashboard panel") == "Mostrar u ocultar el panel de agentes")
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
        #expect(spanish.string("keyboardShortcuts.section.splits", fallback: "Splits") == "Divisiones")
        #expect(spanish.string("keyboardShortcuts.splits.close", fallback: "Close split") == "Cerrar división")
        #expect(spanish.string("keyboardShortcuts.terminal.interrupt", fallback: "Interrupt process") == "Interrumpir proceso")
        #expect(AgentState.waitingInput.accessibilityDescription(using: spanish) == "El agente necesita tu entrada")
        #expect(AgentState.error.accessibilityDescription(using: spanish) == "El agente encontró un error")
        #expect(spanish.string("statusBar.agentDot.focusedSuffix", fallback: " (focused)") == " (con foco)")
        #expect(AgentAttachmentBar.localizedRemoveImage(using: spanish) == "Eliminar imagen")
        #expect(spanish.string("terminal.blockOverlay.copyOutput", fallback: "Copy block output") == "Copiar salida del bloque")
        let snapshot = RateLimitSnapshot(
            agent: .codex,
            usagePercent: 0.42,
            usedAmount: 42,
            limitAmount: 100,
            unit: .requests,
            updatedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
        #expect(RateLimitIndicatorView.localizedAccessibilityLabel(for: snapshot, using: spanish) == "Uso de Codex")
    }

    @Test
    @MainActor
    func keybindingsEditorStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let missing = "__missing_key__"

        #expect(KeybindingsEditorView.localizedSaveButton(using: spanish) == "Guardar")
        #expect(KeybindingsEditorView.localizedResetAllButton(using: spanish) == "Restablecer todo")
        #expect(KeybindingsEditorView.localizedConflictsDetected(using: spanish) == "Conflictos detectados")
        #expect(KeybindingCaptureSheet.localizedCaptureHint(using: spanish) == "Presiona el nuevo atajo...")
        #expect(KeybindingsEditorViewModel.localizedInvalidShortcut(using: spanish) == "Ese no es un atajo válido.")
        #expect(KeybindingsEditorViewModel.localizedUnparseableShortcut(using: spanish) == "No se pudo interpretar ese atajo.")
        #expect(KeybindingsEditorViewModel.localizedSaved(using: spanish) == "Atajos guardados.")
        #expect(
            KeybindingsEditorViewModel.localizedDescription(
                for: .invalidShortcut(actionId: KeybindingActionCatalog.tabNew.id),
                using: spanish
            ) == "El atajo para Nueva pestaña no es válido."
        )
        #expect(
            KeybindingsEditorViewModel.localizedDescription(for: .persistenceUnavailable, using: spanish)
                == "La ventana de Preferencias no está disponible para guardar cambios."
        )
        #expect(KeybindingCategory.tab.localizedTitle(using: spanish) == "Pestañas")
        #expect(KeybindingActionCatalog.tabNew.localizedDisplayName(using: spanish) == "Nueva pestaña")
        #expect(KeybindingActionCatalog.tabNew.localizedSummary(using: spanish) == "Abrir una nueva pestaña de terminal.")

        for category in KeybindingCategory.allCases {
            #expect(
                spanish.string("keybindings.category.\(category.id)", fallback: missing) != missing,
                "Missing localized keybinding category: \(category.id)"
            )
        }

        for action in KeybindingActionCatalog.all {
            #expect(
                spanish.string("keybindings.action.\(action.id).name", fallback: missing) != missing,
                "Missing localized keybinding action name: \(action.id)"
            )
            #expect(
                spanish.string("keybindings.action.\(action.id).summary", fallback: missing) != missing,
                "Missing localized keybinding action summary: \(action.id)"
            )
        }

        #expect(spanish.string("keybindings.category.tab", fallback: "Tabs") == "Pestañas")
        #expect(spanish.string("keybindings.action.tab.new.name", fallback: "New Tab") == "Nueva pestaña")
        #expect(spanish.string("keybindings.action.tab.new.summary", fallback: "Open a new terminal tab.") == "Abrir una nueva pestaña de terminal.")
    }

    @Test
    func dbCloudPanelPickerLocalizesSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(spanish.string("dbCloud.kindPicker", fallback: "Kind") == "Tipo")
    }

    @MainActor
    @Test
    func tabBarAndAuroraSidebarStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let update = CocxyUpdateAvailability(displayVersion: "0.2.0", buildVersion: "200", isCritical: true)

        #expect(spanish.string("tabbar.workspaces", fallback: "WORKSPACES") == "ESPACIOS")
        #expect(TabItemView.localizedPinned(using: spanish) == "Fijada")
        #expect(TabItemView.localizedMoreActiveAgents(3, using: spanish) == "3 agentes activos más")
        #expect(TabItemView.localizedAgentAccessibilityValue(.working, using: spanish) == "Agente: El agente está trabajando")
        #expect(TabItemView.localizedRenamePlaceholder(using: spanish) == "Nombre de pestaña")
        #expect(spanish.string("tabbar.tab.ready", fallback: "Ready") == "Listo")
        #expect(spanish.string("tabbar.agent.badge.waitingInput", fallback: "Input") == "Entrada")
        #expect(spanish.string("tabbar.agent.status.waitingInput", fallback: "%@ waiting for input") == "%@ esperando entrada")
        #expect(spanish.string("tabbar.agentPill.focusedSuffix", fallback: ", focused") == ", con foco")
        #expect(Design.VerticalTabSearchBar.localizedPlaceholder(using: spanish) == "Filtrar sesiones...")
        #expect(AuroraSidebarDisplayMode.summary.verticalTabShortLabel(using: spanish) == "R")
        #expect(AuroraSidebarPrimaryInfo.process.verticalTabMenuLabel(using: spanish) == "Proceso en primer plano")
        #expect(Design.VerticalTabControlBar.localizedPrimaryDetailHelp(using: spanish) == "Detalle principal de fila")
        #expect(Design.AuroraSidebarView.localizedCommandPaletteTitle(using: spanish) == "Paleta de comandos")
        #expect(Design.AuroraSidebarView.localizedCommandPaletteHelp(shortcut: "⇧⌘P", using: spanish) == "Paleta de comandos (⇧⌘P)")
        #expect(Design.AuroraSidebarView.localizedToggleNotesTitle(using: spanish) == "Notas")
        #expect(Design.AuroraSidebarView.localizedNotificationsTitle(using: spanish) == "Notificaciones")
        #expect(Design.AuroraSidebarView.localizedNewTabTitle(using: spanish) == "Nueva pestaña")
        #expect(Design.AuroraSidebarView.localizedUpdateButton(using: spanish) == "Actualizar")
        #expect(Design.AuroraSidebarView.localizedUpdateTitle(update, using: spanish) == "Actualización crítica")
        #expect(Design.SessionNodeView.localizedCloseTabAccessibility("README.md", using: spanish) == "Cerrar README.md")
        #expect(RenameSheetController.localizedTitle(using: spanish) == "Renombrar")
        #expect(RenameSheetController.localizedDone(using: spanish) == "Listo")
        #expect(RenameSheetController.localizedDefaultPlaceholder(using: spanish) == "Ingresa nombre...")
        #expect(HorizontalTabStripView.localizedAddPanel(using: spanish) == "Agregar panel")
        #expect(HorizontalTabStripView.localizedAddPanelLimit(maxPaneCount: 4, using: spanish) == "Máximo de 4 paneles alcanzado")
        #expect(HorizontalTabStripView.localizedSwitchToDarkTheme(using: spanish) == "Cambiar a tema oscuro")
        #expect(HorizontalTabStripView.localizedTerminalSideBySide(using: spanish) == "Terminal (lado a lado)")
        #expect(HorizontalTabStripView.localizedTerminalTitle(using: spanish) == "Terminal")
        #expect(HorizontalTabStripView.localizedSessionReplay(using: spanish) == "Reproducción de sesiones")
        #expect(HorizontalTabStripView.localizedOpenSessionReplay(using: spanish) == "Abrir reproducción de sesiones")
        #expect(HorizontalTabStripView.localizedOpenDBCloudHelpers(using: spanish) == "Abrir ayudas DB/Cloud")
        #expect(HorizontalTabStripView.localizedPanelRenamePlaceholder(using: spanish) == "Nombre del panel")
        #expect(MainWindowController.localizedTerminalTitle(using: spanish) == "Terminal")
        #expect(MainWindowController.localizedPanelTitle(.browser, using: spanish) == "Navegador")
        #expect(MainWindowController.localizedPanelTitle(.sessionReplay, using: spanish) == "Reproducción")
        #expect(MainWindowController.localizedPanelTitle(.aiEditHistory, using: spanish) == "Historial de ediciones")
        #expect(MainWindowController.localizedPanelTitle(.subagent, using: spanish) == "Agente")
        #expect(spanish.string("command.workspace.sessionReplay.name", fallback: "Open Session Replay Panel") == "Abrir panel de reproducción de sesiones")
        #expect(spanish.string("sessionReplay.exportPanel.title", fallback: "Export Session Replay") == "Exportar reproducción de sesiones")
    }

    @MainActor
    @Test
    func auroraStatusAndInspectorStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let panes = [
            Design.AuroraPane(
                id: "shell",
                name: "shell",
                agent: .codex,
                state: .working,
                activity: "swift build",
                toolCount: 1,
                errorCount: 0
            ),
            Design.AuroraPane(id: "review", name: "review", agent: .shell, state: .waiting),
            Design.AuroraPane(id: "server", name: "server", agent: .aider, state: .error),
            Design.AuroraPane(id: "done", name: "done", agent: .gemini, state: .finished),
        ]
        let port = Design.AuroraPortBinding(port: 3000, name: "web", health: .ok)

        #expect(Design.LocalBadgeView.localizedLabel(using: spanish) == "sin telemetría")
        #expect(
            Design.LocalBadgeView.localizedHelp(using: spanish)
                == "Sin telemetría ni rastreo. Las actualizaciones solo consultan el appcast firmado de Cocxy."
        )
        #expect(
            Design.LocalBadgeView.localizedAccessibilityLabel(using: spanish)
                == "Sin telemetría ni rastreo"
        )
        #expect(Design.AgentMatrixView.localizedTitle(using: spanish) == "agentes")
        #expect(Design.AgentMatrixView.summaryText(for: [], using: spanish) == "sin actividad")
        #expect(
            Design.AgentMatrixView.summaryText(for: panes, using: spanish)
                == "1 trabajando · 1 esperando · 1 error · 1 finalizado"
        )
        #expect(
            Design.localizedPaneDiagnosticLine(for: panes[0], using: spanish)
                == "• shell — trabajando · swift build · 1 herramienta · 0 errores"
        )
        #expect(
            Design.AgentMatrixView.agentTooltip(for: panes, using: spanish)
                .hasPrefix("Agentes activos:\n• shell — trabajando")
        )
        #expect(Design.PortListView.localizedTitle(using: spanish) == "puertos")
        #expect(Design.PortListView.localizedNone(using: spanish) == "ninguno")
        #expect(
            Design.PortListView.localizedOpenPortHelp(port, using: spanish)
                == "Abrir http://localhost:3000. Usa el menú emergente de puertos para copiar o abrir."
        )
        #expect(Design.PortsPopoverView.localizedCopyButton(using: spanish) == "Copiar")
        #expect(Design.PortChip.localizedAccessibilityLabel(port, using: spanish) == "Puerto 3000 llamado web, estado correcto")
        #expect(Design.AuroraSessionTooltipCard.localizedLivePanesTitle(using: spanish) == "Paneles activos")
        #expect(Design.AuroraSessionTooltipCard.localizedMoreActivePanes(2, using: spanish) == "+ 2 paneles activos más")
        #expect(Design.NotesSectionView.localizedAccessibilityLabel(2, using: spanish) == "Notas — 2 notas")
        #expect(
            Design.PaneTransferHandleView.localizedDragPaneHelp("editor", using: spanish)
                == "Arrastra el panel editor a otra pestaña"
        )
        #expect(
            Design.PaneTransferHandleView.localizedDragPaneHelp("pane 2", using: spanish)
                == "Arrastra el panel 2 a otra pestaña"
        )
        #expect(
            Design.PaneTransferHandleView.localizedMovePaneAccessibility("pane 2", using: spanish)
                == "Mover panel 2"
        )
    }

    @MainActor
    @Test
    func utilityOverlayStringsLocalizeSpanish() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let viewModel = SmartRoutingOverlayViewModel(router: EmptySmartRoutingRouter())

        #expect(QuickTerminalPanel.localizedAccessibilityLabel(using: spanish) == "Terminal rápido")
        #expect(VoiceIndicator.localizedAccessibilityLabel(using: spanish) == "Entrada por voz")
        #expect(SmartRoutingOverlayView.localizedTitle(using: spanish) == "Ruteo inteligente")
        #expect(viewModel.localizedEmptyMessage(using: spanish) == "Ningún agente requiere atención")
        #expect(SmartRoutingFilter.errorsOnly.localizedTitle(using: spanish) == "Errores")
        #expect(SmartRoutingFilterView.localizedFilterAccessibility("Errores", using: spanish) == "Filtro: Errores")
        #expect(SmartRoutingAgentRow.localizedStateDescription(.waitingForInput, using: spanish) == "Esperando entrada")
        #expect(MainWindowController.localizedSSHUploadCompleteTitle(localizer: spanish) == "Subida completada")
        #expect(MainWindowController.localizedSSHUploadFailedTitle(localizer: spanish) == "Falló la subida")
        #expect(MainWindowController.localizedSSHUploadUnknownError(localizer: spanish) == "Error desconocido")
    }

    @MainActor
    @Test
    func commandPaletteViewModelLocalizesActionsAndSearchesSpanish() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let engine = CommandPaletteEngineImpl()
        engine.registerAction(CommandAction(
            id: "preferences.show",
            name: "Show Preferences",
            description: "Open terminal settings",
            shortcut: nil,
            category: .config,
            handler: {}
        ))
        let viewModel = CommandPaletteViewModel(
            engine: engine,
            localizer: localizer
        )

        let newTab = try #require(viewModel.filteredActions.first { $0.id == "tabs.new" })
        #expect(newTab.name == "Nueva pestaña")
        #expect(newTab.description == "Abrir una nueva pestaña de terminal")
        #expect(viewModel.localizedCategoryTitle(.tabs) == "Pestañas")
        #expect(viewModel.localizedCategoryTitle(.worktree) == "Git")

        viewModel.query = "pesta"

        #expect(viewModel.filteredActions.contains { $0.id == "tabs.new" })

        viewModel.query = "preferencias"

        #expect(viewModel.filteredActions.contains { $0.id == "preferences.show" })
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
        #expect(MainWindowController.localizedPictureInPictureTitle(for: "Proyecto", using: localizer) == "Cocxy PIP - Proyecto")
    }

    @MainActor
    @Test
    func commandActionLocalizationHandlesDynamicEditorNames() throws {
        let bundle = try #require(localizationBundle())
        let localizer = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let action = CommandAction(
            id: "editor.open.vscode",
            name: "Open Workspace in Visual Studio Code",
            description: "Open the active tab's workspace using Visual Studio Code",
            shortcut: nil,
            category: .editor,
            handler: {}
        ).localized(using: localizer)

        #expect(action.name == "Abrir espacio en Visual Studio Code")
        #expect(action.description == "Abrir el espacio de la pestaña activa usando Visual Studio Code")
    }

    @MainActor
    @Test
    func wiredCommandPaletteActionsHaveLocalizationKeys() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let english = try localizationKeys(
            at: root.appendingPathComponent("Resources/Localization/en.lproj/Localizable.strings")
        )
        let spanish = try localizationKeys(
            at: root.appendingPathComponent("Resources/Localization/es.lproj/Localizable.strings")
        )
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let actionIDs = controller.createWiredCommandPaletteEngine().allActions
            .map(\.id)
            .filter { id in
                !id.hasPrefix("editor.open.")
                    && !id.hasPrefix("codex.account.switch.")
            }

        let expectedKeys = Set(actionIDs.flatMap { id in
            if id == "window.pictureInPicture" {
                return [
                    "command.\(id).name",
                    "command.\(id).description.enabled",
                    "command.\(id).description.disabled",
                ]
            }
            return [
                "command.\(id).name",
                "command.\(id).description",
            ]
        })

        #expect(english.isSuperset(of: expectedKeys))
        #expect(spanish.isSuperset(of: expectedKeys))
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

    @Test
    func englishAndSpanishLocalizationResourcesExposeTheSameKeys() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let english = try localizationKeys(
            at: root.appendingPathComponent("Resources/Localization/en.lproj/Localizable.strings")
        )
        let spanish = try localizationKeys(
            at: root.appendingPathComponent("Resources/Localization/es.lproj/Localizable.strings")
        )

        #expect(english.subtracting(spanish).isEmpty)
        #expect(spanish.subtracting(english).isEmpty)
    }

    @Test
    func sourceLiteralFallbackLocalizationKeysExistInEnglishAndSpanishResources() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let english = try localizationKeys(
            at: root.appendingPathComponent("Resources/Localization/en.lproj/Localizable.strings")
        )
        let spanish = try localizationKeys(
            at: root.appendingPathComponent("Resources/Localization/es.lproj/Localizable.strings")
        )
        let sourceKeys = try sourceLiteralFallbackLocalizationKeys(
            at: root.appendingPathComponent("Sources", isDirectory: true),
            relativeTo: root
        )

        #expect(!sourceKeys.isEmpty)
        #expect(
            sourceKeys.keys.filter { !english.contains($0) }.isEmpty,
            Comment(
                rawValue: missingLocalizationMessage(
                    sourceKeys: sourceKeys,
                    availableKeys: english,
                    localeName: "English"
                )
            )
        )
        #expect(
            sourceKeys.keys.filter { !spanish.contains($0) }.isEmpty,
            Comment(
                rawValue: missingLocalizationMessage(
                    sourceKeys: sourceKeys,
                    availableKeys: spanish,
                    localeName: "Spanish"
                )
            )
        )
    }

    @Test
    func spanishCodeReviewStringsAvoidResidualEnglishReviewTerms() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let spanish = try localizationStrings(
            at: root.appendingPathComponent("Resources/Localization/es.lproj/Localizable.strings")
        )
        let staleTermPattern = #"\b(feedback|hunk|layout)\b|despues"#
        let violations = spanish
            .filter { key, value in
                key.hasPrefix("codeReview.")
                    && value.range(
                        of: staleTermPattern,
                        options: [.regularExpression, .caseInsensitive]
                    ) != nil
            }
            .map { key, value in "\(key)=\(value)" }
            .sorted()

        #expect(
            violations.isEmpty,
            Comment(rawValue: "Spanish Code Review strings contain residual English terms: \(violations.prefix(20).joined(separator: "; "))")
        )
    }

    @Test
    func visibleUILiteralsStayOnApprovedTechnicalAllowlist() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let allowed: [String: Set<String>] = [
            "Sources/UI/Design/AuroraTweaksPanel.swift": ["AURORA"],
            "Sources/UI/GitHub/GitHubPaneView.swift": ["GitHub"],
            "Sources/UI/Preferences/PreferencesView.swift": [
                "0Oo Il1 | [] {} () => -> == != --",
                "Cocxy Terminal",
                "~/.cocxy/worktrees",
                "cocxy/{agent}/{id}",
                "HEAD",
            ],
            "Sources/UI/RemoteWorkspace/PortForwardingView.swift": ["SOCKS", "8080"],
            "Sources/UI/RemoteWorkspace/ProxyControlView.swift": ["1080", "8888", "*.example.com"],
            "Sources/UI/RemoteWorkspace/RelayControlView.swift": ["127.0.0.1", "10", "3000", "9000"],
            "Sources/UI/RemoteWorkspace/RemoteProfileEditor.swift": ["L", "R", "D", "~/.ssh/id_ed25519"],
            "Sources/UI/RemoteWorkspace/SSHKeyManagerView.swift": ["Ed25519", "RSA", "ECDSA"],
            "Sources/UI/ScrollbackSearch/ScrollbackSearchBarView.swift": ["aA"],
        ]
        let literals = try hardcodedVisibleUILiterals(
            at: [
                root.appendingPathComponent("Sources/App", isDirectory: true),
                root.appendingPathComponent("Sources/UI", isDirectory: true),
            ],
            relativeTo: root
        )
        let violations = literals.filter { literal in
            !allowed[literal.path, default: []].contains(literal.value)
        }

        #expect(
            violations.isEmpty,
            Comment(rawValue: hardcodedVisibleLiteralMessage(violations))
        )
    }

    @Test
    func markdownPreviewTemplateUsesLocalizedTOCTitle() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)
        let html = MarkdownPreviewTemplate.build(
            tableOfContentsTitle: spanish.string(
                "markdown.preview.toc.title",
                fallback: "Table of Contents"
            )
        )

        #expect(html.contains(#"title="Tabla de contenidos""#))
        #expect(!html.contains(#"title="Table of Contents""#))
    }

    @Test
    func markdownPreviewModeUsesCompactSpanishLabelForSegmentedControl() throws {
        let bundle = try #require(localizationBundle())
        let spanish = AppLocalizer(languagePreference: .spanish, bundle: bundle)

        #expect(MarkdownViewMode.preview.localizedLabel(using: spanish) == "Previa")
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }

    private func localizationKeys(at url: URL) throws -> Set<String> {
        Set(try localizationStrings(at: url).keys)
    }

    private func localizationStrings(at url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        return try #require(propertyList as? [String: String])
    }

    private func sourceLiteralFallbackLocalizationKeys(
        at sourcesURL: URL,
        relativeTo root: URL
    ) throws -> [String: [String]] {
        let expression = try NSRegularExpression(
            pattern: #"(?:\.string|localizedString)\(\s*"([A-Za-z0-9_.-]+)"\s*,\s*fallback:"#,
            options: []
        )
        guard let enumerator = FileManager.default.enumerator(
            at: sourcesURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var keysBySource: [String: [String]] = [:]
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift" else { continue }
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in expression.matches(in: source, options: [], range: range) {
                guard let keyRange = Range(match.range(at: 1), in: source) else { continue }
                let key = String(source[keyRange])
                keysBySource[key, default: []].append(relativePath(for: fileURL, from: root))
            }
        }
        return keysBySource
    }

    private func missingLocalizationMessage(
        sourceKeys: [String: [String]],
        availableKeys: Set<String>,
        localeName: String
    ) -> String {
        let missing = sourceKeys.keys
            .filter { !availableKeys.contains($0) }
            .sorted()
            .prefix(20)
            .map { key in
                let locations = sourceKeys[key, default: []].prefix(3).joined(separator: ", ")
                return "\(key) [\(locations)]"
            }
            .joined(separator: "; ")
        return "Missing \(localeName) localization keys: \(missing)"
    }

    private struct HardcodedVisibleLiteral: Comparable {
        let path: String
        let line: Int
        let value: String

        static func < (lhs: HardcodedVisibleLiteral, rhs: HardcodedVisibleLiteral) -> Bool {
            if lhs.path != rhs.path { return lhs.path < rhs.path }
            if lhs.line != rhs.line { return lhs.line < rhs.line }
            return lhs.value < rhs.value
        }
    }

    private func hardcodedVisibleUILiterals(
        at roots: [URL],
        relativeTo root: URL
    ) throws -> [HardcodedVisibleLiteral] {
        let expressions = try [
            #"\b(?:Text|Button|Label)\(\s*"([^"\n]+)""#,
            #"\b(?:DisclosureGroup|GroupBox|Link|Menu|NavigationLink|Picker|Section|SecureField|TableColumn|TextField|Toggle)\(\s*"([^"\n]+)""#,
            #"\bNSButton\(title:\s*"([^"\n]+)""#,
            #"\bNSTextField\(labelWithString:\s*"([^"\n]+)""#,
            #"\.(?:alert|confirmationDialog|navigationTitle)\(\s*"([^"\n]+)""#,
            #"\bsetAccessibilityLabel\(\s*"([^"\n]+)""#,
            #"\.accessibility(?:Label|Hint|Value)\(\s*"([^"\n]+)""#,
            #"\.help\(\s*"([^"\n]+)""#,
        ].map { try NSRegularExpression(pattern: $0, options: []) }
        var result: [HardcodedVisibleLiteral] = []

        for rootURL in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "swift" else { continue }
                let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard values.isRegularFile == true else { continue }

                let source = try String(contentsOf: fileURL, encoding: .utf8)
                let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)
                for expression in expressions {
                    for match in expression.matches(in: source, options: [], range: sourceRange) {
                        guard let valueRange = Range(match.range(at: 1), in: source) else { continue }
                        let value = String(source[valueRange])
                        guard literalContainsLocalizableLetters(value) else {
                            continue
                        }
                        result.append(
                            HardcodedVisibleLiteral(
                                path: relativePath(for: fileURL, from: root),
                                line: lineNumber(in: source, at: match.range.location),
                                value: value
                            )
                        )
                    }
                }
            }
        }
        return result.sorted()
    }

    private func lineNumber(in source: String, at utf16Offset: Int) -> Int {
        let clampedOffset = min(max(utf16Offset, 0), source.utf16.count)
        let index = String.Index(utf16Offset: clampedOffset, in: source)
        return source[..<index].reduce(1) { partial, character in
            partial + (character == "\n" ? 1 : 0)
        }
    }

    private func literalContainsLocalizableLetters(_ literal: String) -> Bool {
        var staticText = ""
        var index = literal.startIndex
        while index < literal.endIndex {
            if literal[index] == "\\",
               literal.index(after: index) < literal.endIndex,
               literal[literal.index(after: index)] == "(" {
                index = endIndexOfSwiftInterpolation(startingAt: index, in: literal)
            } else {
                staticText.append(literal[index])
                index = literal.index(after: index)
            }
        }
        guard staticText.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil else {
            return false
        }
        let compactText = staticText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        return !isTechnicalUnitFragment(compactText)
    }

    private func isTechnicalUnitFragment(_ text: String) -> Bool {
        let allowedUnits: Set<String> = ["f", "ms", "pt", "px", "t", "x"]
        if allowedUnits.contains(text) {
            return true
        }
        return text.range(of: #"^\d+(?:\.\d+)?x$"#, options: .regularExpression) != nil
    }

    private func endIndexOfSwiftInterpolation(startingAt start: String.Index, in literal: String) -> String.Index {
        var index = literal.index(start, offsetBy: 2)
        var depth = 1
        var isEscaped = false
        var isInsideString = false

        while index < literal.endIndex {
            let character = literal[index]
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                isInsideString.toggle()
            } else if !isInsideString, character == "(" {
                depth += 1
            } else if !isInsideString, character == ")" {
                depth -= 1
                if depth == 0 {
                    return literal.index(after: index)
                }
            }
            index = literal.index(after: index)
        }
        return literal.endIndex
    }

    private func hardcodedVisibleLiteralMessage(_ violations: [HardcodedVisibleLiteral]) -> String {
        let sample = violations.prefix(25).map { literal in
            "\(literal.path):\(literal.line) \"\(literal.value)\""
        }.joined(separator: "; ")
        return "Hardcoded visible UI literals must be localized or added to the technical allowlist: \(sample)"
    }

    private func relativePath(for fileURL: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return filePath
        }
        return String(filePath.dropFirst(rootPath.count + 1))
    }
}

private final class EmptySmartRoutingRouter: SmartAgentRouting {
    func agentsNeedingAttention() -> [AgentSessionInfo] { [] }
    func agents(withState state: AgentDashboardState) -> [AgentSessionInfo] { [] }
    func mostUrgentAgent() -> AgentSessionInfo? { nil }
    func navigateToAgent(_ sessionId: String) {}
}
