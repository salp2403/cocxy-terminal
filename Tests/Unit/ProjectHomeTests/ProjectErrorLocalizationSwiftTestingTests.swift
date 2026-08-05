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

    @Test("fan-out failures expose actionable causes without process output")
    func fanOutFailuresAreActionableAndRedacted() throws {
        let localizer = try spanishLocalizer()

        let target = localizer.projectErrorMessage(
            for: TaskRunExecutionError.targetUnavailable,
            context: .fanOut
        )
        #expect(target != "The task target is no longer available. Reopen Project Home and try again.")
        #expect(target.localizedCaseInsensitiveContains("tarea"))

        let promotion = localizer.projectErrorMessage(
            for: TaskRunExecutionError.promotionUnavailable("task changed"),
            context: .fanOut
        )
        #expect(promotion.contains("task changed"))

        let launch = localizer.projectErrorMessage(
            for: TaskRunExecutionError.launchFailed(
                reason: "secret-token from provider stderr",
                rollbackFailures: ["private cleanup path", "second private path"]
            ),
            context: .fanOut
        )
        #expect(launch.contains("2"))
        #expect(!launch.contains("secret-token"))
        #expect(!launch.contains("private cleanup path"))

        let git = localizer.projectErrorMessage(
            for: WorktreeServiceError.gitCommandFailed(
                command: "git merge private-branch",
                stderr: "secret-token and untrusted terminal output",
                exitCode: 7
            ),
            context: .fanOut
        )
        #expect(git.contains("7"))
        #expect(!git.contains("secret-token"))
        #expect(!git.contains("private-branch"))

        let unknown = localizer.projectErrorMessage(
            for: NSError(domain: "secret-domain", code: 41),
            context: .fanOut
        )
        #expect(unknown.contains("NSError [41]"))
        #expect(!unknown.contains("secret-domain"))
    }

    @Test("task run lifecycle and persistence failures are localized and redacted")
    func taskRunFailuresAreLocalizedAndRedacted() throws {
        let localizer = try spanishLocalizer()
        let lifecycleMessages = [
            localizer.projectErrorMessage(
                for: TaskRunLifecycleError.cancellationUnavailable(status: .completed),
                context: .fanOut
            ),
            localizer.projectErrorMessage(
                for: TaskRunLifecycleError.removalUnavailable(status: .running),
                context: .fanOut
            ),
            localizer.projectErrorMessage(
                for: TaskRunLifecycleError.persistenceFailed(
                    action: "removal",
                    reason: "/Users/private/project/task-runs/run.json"
                ),
                context: .fanOut
            ),
        ]

        #expect(lifecycleMessages == [
            "No se puede cancelar esta tarea en su estado actual.",
            "No se puede eliminar esta tarea en su estado actual.",
            "La tarea cambió en memoria, pero no se pudo guardar su estado más reciente.",
        ])
        #expect(!lifecycleMessages.joined().contains("completed"))
        #expect(!lifecycleMessages.joined().contains("running"))
        #expect(!lifecycleMessages.joined().contains("/Users/private"))

        #expect(localizer.taskRunRestoreFailureMessage()
            == "No se pudieron restaurar las ejecuciones de tareas guardadas.")
        #expect(localizer.taskRunRejectedSnapshotsMessage(count: 2)
            == "Se ignoraron 2 instantáneas no válidas de ejecuciones de tareas.")
        #expect(localizer.taskRunRetentionFailureMessage(count: 3)
            == "No se pudieron depurar 3 instantáneas antiguas de ejecuciones de tareas.")
        #expect(localizer.taskRunSaveFailureMessage(runID: "run-seguro")
            == "No se pudo guardar la tarea run-seguro. Los cambios permanecen en memoria.")
    }

    @Test("Project Home view model uses a newly selected language")
    func projectHomeViewModelUpdatesLocalizer() async throws {
        let model = ProjectHomePanelViewModel(
            projectID: ProjectID(rawValue: "/tmp/localized-project"),
            projectRoot: URL(fileURLWithPath: "/tmp/localized-project", isDirectory: true),
            displayName: "Proyecto",
            accent: nil,
            fallbackRemote: nil,
            worktreeConfig: .defaults,
            localizer: AppLocalizer(languagePreference: .english),
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

        model.updateLocalizer(try spanishLocalizer())
        await model.launchTeam(request)

        #expect(model.actionErrorMessage == "El proveedor de agente local seleccionado no está disponible.")
        #expect(model.isTeamSheetPresented == false)
    }

    private func spanishLocalizer() throws -> AppLocalizer {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let bundle = try #require(Bundle(
            url: root.appendingPathComponent("Resources/Localization", isDirectory: true)
        ))
        return AppLocalizer(languagePreference: .spanish, bundle: bundle)
    }
}
