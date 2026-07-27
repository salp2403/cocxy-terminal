// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentPanelLocalizationSwiftTestingTests.swift - Agent panel presentation localization.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("AgentPanelLocalization")
struct AgentPanelLocalizationSwiftTestingTests {

    @Test("localizes dynamic approval and blocked statuses in Spanish")
    func localizesDynamicApprovalAndBlockedStatusesInSpanish() throws {
        let spanish = AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(localizationBundle())
        )

        #expect(
            AgentPanelLocalization.statusText("Approve command: swift test", using: spanish)
                == "Aprobar comando: swift test"
        )
        #expect(
            AgentPanelLocalization.statusText("Review diff for edit_file.", using: spanish)
                == "Revisar diff de edit_file."
        )
        #expect(
            AgentPanelLocalization.statusText(
                "Blocked run_command because a preview could not be generated.",
                using: spanish
            )
                == "run_command bloqueado porque no se pudo generar una vista previa."
        )
    }

    @Test("localizes Agent Mode error and attachment statuses in Spanish")
    func localizesAgentModeErrorAndAttachmentStatusesInSpanish() throws {
        let spanish = AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(localizationBundle())
        )

        #expect(
            AgentPanelLocalization.statusText("2 images attached.", using: spanish)
                == "2 imágenes adjuntas."
        )
        #expect(
            AgentPanelLocalization.statusText("Failed to load skills: unreadable", using: spanish)
                == "No se pudieron cargar las habilidades: unreadable"
        )
        #expect(
            AgentPanelLocalization.statusText(
                "Foundation Models does not support image attachments in Agent Mode.",
                using: spanish
            )
                == "Foundation Models no admite adjuntos de imagen en Modo agente."
        )
    }

    @Test("localizes built-in skill menu metadata in Spanish")
    func localizesBuiltInSkillMenuMetadataInSpanish() throws {
        let spanish = AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(localizationBundle())
        )
        let builtInSkill = AgentPanelSkillOption(
            id: "review-pr",
            name: "Review PR",
            summary: "Review a local pull request diff and report correctness risks first.",
            source: .builtIn
        )
        let gitBlameSkill = AgentPanelSkillOption(
            id: "git-blame-explain",
            name: "Git Blame Explain",
            summary: "Explain why a line changed using local git history and code context.",
            source: .builtIn
        )
        let userSkill = AgentPanelSkillOption(
            id: "custom-review",
            name: "Custom Review",
            summary: "User-defined skill.",
            source: .user
        )

        #expect(
            AgentPanelLocalization.skillMenuTitle(builtInSkill, using: spanish)
                == "Revisar PR (incluida)"
        )
        #expect(
            AgentPanelLocalization.skillSummary(builtInSkill, using: spanish)
                == "Revisa un diff local de solicitud de cambio y reporta primero riesgos de corrección."
        )
        #expect(
            AgentPanelLocalization.skillMenuTitle(gitBlameSkill, using: spanish)
                == "Explicar autoría Git (incluida)"
        )
        #expect(
            AgentPanelLocalization.skillSummary(gitBlameSkill, using: spanish)
                == "Explica por qué cambió una línea usando historial Git local y contexto de código."
        )
        #expect(
            AgentPanelLocalization.skillMenuTitle(userSkill, using: spanish)
                == "Custom Review (usuario)"
        )
        #expect(AgentPanelLocalization.skillSummary(userSkill, using: spanish) == "User-defined skill.")
    }

    @Test("localizes approval preview title and body copy in Spanish")
    func localizesApprovalPreviewCopyInSpanish() throws {
        let spanish = AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(localizationBundle())
        )

        #expect(
            AgentPanelLocalization.approvalTitle("Approve command", using: spanish)
                == "Aprobar comando"
        )
        #expect(
            AgentPanelLocalization.approvalTitle("Review changes to Sources/App.swift", using: spanish)
                == "Revisar cambios en Sources/App.swift"
        )
        #expect(
            AgentPanelLocalization.approvalTitle("Agent requested input", using: spanish)
                == "El agente solicitó entrada"
        )
        #expect(
            AgentPanelLocalization.approvalTitle("Share terminal output", using: spanish)
                == "Compartir salida del terminal"
        )
        #expect(
            AgentPanelLocalization.approvalBody(
                "Allow computer_click to control this Mac locally.",
                using: spanish
            )
                == "Permitir que computer_click controle esta Mac localmente."
        )
        #expect(
            AgentPanelLocalization.approvalBody(
                "Allow mcp_files_search to call a configured local MCP server.",
                using: spanish
            )
                == "Permitir que mcp_files_search llame a un servidor MCP local configurado."
        )
        #expect(
            AgentPanelLocalization.approvalBody(
                "Diff preview is unavailable for call call-1.",
                using: spanish
            )
                == "La vista previa del diff no está disponible para la llamada call-1."
        )
        #expect(
            AgentPanelLocalization.approvalBody(
                [
                    "Destination: OpenAI",
                    "Terminal: Focused split (ABC12345)",
                    "Command blocks: 2 of at most 64",
                    "Terminal text has not been read yet. Approval reads only these selected blocks, redacts common secret patterns locally, and shares the bounded result once.",
                    "Unknown secret formats may remain. Review the selected terminal before approving.",
                ].joined(separator: "\n"),
                using: spanish
            )
                == [
                    "Destino: OpenAI",
                    "Terminal: División enfocada (ABC12345)",
                    "Bloques de comandos: 2 de un máximo de 64",
                    "El texto del terminal aún no se ha leído. La aprobación lee solo estos bloques seleccionados, oculta localmente patrones comunes de secretos y comparte una vez el resultado limitado.",
                    "Los formatos de secretos desconocidos pueden permanecer. Revisa el terminal seleccionado antes de aprobar.",
                ].joined(separator: "\n")
        )
        #expect(
            AgentPanelLocalization.statusText("Review terminal output before sharing.", using: spanish)
                == "Revisa la salida del terminal antes de compartirla."
        )
    }

    @Test("keeps unknown Agent Mode status unchanged")
    func keepsUnknownAgentModeStatusUnchanged() throws {
        let spanish = AppLocalizer(
            languagePreference: .spanish,
            bundle: try #require(localizationBundle())
        )

        #expect(
            AgentPanelLocalization.statusText("Custom provider detail", using: spanish)
                == "Custom provider detail"
        )
    }

    private func localizationBundle() -> Bundle? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return Bundle(url: root.appendingPathComponent("Resources/Localization", isDirectory: true))
    }
}
