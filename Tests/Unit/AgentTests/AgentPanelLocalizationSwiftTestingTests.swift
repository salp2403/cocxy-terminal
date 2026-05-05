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
                == "No se pudieron cargar las skills: unreadable"
        )
        #expect(
            AgentPanelLocalization.statusText(
                "Foundation Models does not support image attachments in Agent Mode.",
                using: spanish
            )
                == "Foundation Models no admite adjuntos de imagen en Modo agente."
        )
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
