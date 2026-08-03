// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectErrorLocalizationSwiftTestingTests.swift - Localized project error boundaries.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Project error localization")
@MainActor
struct ProjectErrorLocalizationSwiftTestingTests {
    @Test("typed project failures use the selected app language")
    func typedFailuresUseSelectedLanguage() throws {
        let localizer = try spanishLocalizer()

        #expect(localizer.projectErrorMessage(
            for: ProjectHomeActionFailure.providerUnavailable,
            context: .teamLaunch
        ) == "El proveedor de agente local seleccionado no está disponible.")
        #expect(localizer.projectErrorMessage(
            for: ProjectActivationError.unavailable("/tmp/proyecto"),
            context: .projectAction
        ) == "La carpeta del proyecto no está disponible: /tmp/proyecto")
    }

    @Test("clone failures expose bounded status without raw process output")
    func cloneFailureHidesRawProcessOutput() throws {
        let localizer = try spanishLocalizer()
        let message = localizer.projectErrorMessage(
            for: ProjectCloneError.cloneFailed(
                exitCode: 7,
                message: "secret-token and untrusted terminal output"
            ),
            context: .projectAction
        )

        #expect(message == "Git no pudo clonar el repositorio (código de salida 7).")
        #expect(!message.contains("secret-token"))
    }

    @Test("clone integrity failures use localized recovery guidance")
    func cloneIntegrityFailuresUseLocalizedRecoveryGuidance() throws {
        let localizer = try spanishLocalizer()

        #expect(localizer.projectErrorMessage(
            for: ProjectCloneError.destinationChanged("/tmp/destino"),
            context: .projectAction
        ) == "El destino de la clonación cambió antes de que pudiera registrarse: /tmp/destino.")
        #expect(localizer.projectErrorMessage(
            for: ProjectCloneError.cleanupUnverified("/tmp/limpieza"),
            context: .projectAction
        ) == "No se pudo verificar de forma segura la limpieza de la clonación en /tmp/limpieza. Revisa la carpeta antes de volver a intentarlo.")
    }

    @Test("unknown failures degrade to localized context copy")
    func unknownFailureUsesLocalizedContextFallback() throws {
        let localizer = try spanishLocalizer()
        let error = NSError(domain: "ProjectErrorLocalizationTests", code: 41)

        #expect(localizer.projectErrorMessage(
            for: error,
            context: .codeReview
        ) == "No se pudo abrir la revisión de código.")
        #expect(localizer.projectErrorMessage(
            for: error,
            context: .metadataWarning
        ) == "El proyecto se abrió, pero no se pudieron guardar sus metadatos en la lista de proyectos recientes.")
    }

    @Test("Project Home view model presents localized action failures")
    func projectHomeViewModelUsesInjectedLocalizer() async throws {
        let localizer = try spanishLocalizer()
        let model = ProjectHomePanelViewModel(
            projectID: ProjectID(rawValue: "/tmp/localized-project"),
            projectRoot: URL(fileURLWithPath: "/tmp/localized-project", isDirectory: true),
            displayName: "Proyecto",
            accent: nil,
            fallbackRemote: nil,
            worktreeConfig: .defaults,
            localizer: localizer,
            recentDiffProvider: { nil },
            actions: ProjectHomeActions(
                createSession: {},
                createWorktree: nil,
                launchTeam: { _ in throw ProjectHomeActionFailure.providerUnavailable },
                openCodeReview: {},
                activateEntry: { _ in },
                focusWorktree: nil,
                openRecentDiff: nil
            )
        )
        let request = try ProjectTeamLaunchRequest.make(
            teamName: "equipo",
            provider: .codex,
            teammates: "implementacion",
            prompt: "Implementar"
        )

        await model.launchTeam(request)

        #expect(model.actionErrorMessage == "El proveedor de agente local seleccionado no está disponible.")
        #expect(model.isTeamSheetPresented == false)
    }

    @Test("fan-out path validation uses the injected app language")
    func fanOutPathValidationUsesInjectedLocalizer() throws {
        let localizer = try spanishLocalizer()
        let model = ProjectFanOutFlowViewModel(
            projectID: ProjectID(rawValue: "/tmp/localized-project"),
            projectRoot: URL(fileURLWithPath: "/tmp/localized-project", isDirectory: true),
            availableProviders: [.codex, .claudeCode],
            availableBaseRefs: ["HEAD"],
            defaultBaseRef: "HEAD",
            defaultAgentNames: ["codex", "claude"],
            localizer: localizer,
            actions: ProjectFanOutActions(
                launch: { _ in throw ProjectHomeActionFailure.servicesUnavailable },
                loadSnapshot: { _ in throw ProjectHomeActionFailure.servicesUnavailable },
                launchCollisions: { _ in .empty },
                preparePromotion: { _, _ in throw ProjectHomeActionFailure.servicesUnavailable },
                executePromotion: { _ in throw ProjectHomeActionFailure.servicesUnavailable },
                recycle: { _, _ in throw ProjectHomeActionFailure.servicesUnavailable }
            )
        )
        model.pendingPath = "../fuera.swift"

        model.addPendingPath()

        #expect(model.errorMessage == "La ruta del archivo debe permanecer dentro de este proyecto.")
        #expect(model.plannedPaths.isEmpty)
    }

    private func spanishLocalizer() throws -> AppLocalizer {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let bundle = try #require(Bundle(
            url: root.appendingPathComponent("Resources/Localization", isDirectory: true)
        ))
        return AppLocalizer(languagePreference: .spanish, bundle: bundle)
    }
}
