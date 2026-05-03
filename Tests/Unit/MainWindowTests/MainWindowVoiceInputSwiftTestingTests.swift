// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowVoiceInputSwiftTestingTests.swift - MainWindow Voice wiring coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("MainWindowController Voice input")
struct MainWindowVoiceInputSwiftTestingTests {
    @Test("Voice transcript opens Command Palette and fills query")
    @MainActor
    func voiceTranscriptOpensCommandPaletteAndFillsQuery() async throws {
        let configService = ConfigService(fileProvider: VoiceInputConfigProvider(content: """
        [voice]
        enabled = true
        locale = "system"
        """))
        try configService.reload()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService
        )
        controller.injectedVoiceSessionFactory = { statusDidChange, partialDidChange in
            VoiceSession(
                localeResolver: VoiceLocaleResolver(
                    supportedLocales: [Locale(identifier: "en-US")],
                    systemLocale: Locale(identifier: "en-US")
                ),
                permissionManager: MainWindowVoicePermissionManager(),
                transcriber: MainWindowVoiceTranscriber(
                    result: VoiceTranscript(text: "Open Notes", localeIdentifier: "en-US", isFinal: true)
                ),
                statusDidChange: statusDidChange,
                partialDidChange: partialDidChange
            )
        }

        await controller.startVoiceInput()

        #expect(controller.isCommandPaletteVisible == true)
        #expect(controller.commandPaletteViewModel?.query == "Open Notes")
    }

    @Test("Voice transcript fills visible Agent prompt instead of Command Palette")
    @MainActor
    func voiceTranscriptFillsVisibleAgentPromptInsteadOfCommandPalette() async throws {
        let configService = ConfigService(fileProvider: VoiceInputConfigProvider(content: """
        [voice]
        enabled = true
        locale = "system"

        [agent]
        enabled = true
        """))
        try configService.reload()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService
        )
        controller.injectedAgentPromptRunner = MainWindowAgentPromptRunner()
        _ = controller.resolveAgentPanelViewModel()
        controller.isAgentModeVisible = true
        controller.injectedVoiceSessionFactory = { statusDidChange, partialDidChange in
            VoiceSession(
                localeResolver: VoiceLocaleResolver(
                    supportedLocales: [Locale(identifier: "en-US")],
                    systemLocale: Locale(identifier: "en-US")
                ),
                permissionManager: MainWindowVoicePermissionManager(),
                transcriber: MainWindowVoiceTranscriber(
                    result: VoiceTranscript(text: "summarize terminal output", localeIdentifier: "en-US", isFinal: true)
                ),
                statusDidChange: statusDidChange,
                partialDidChange: partialDidChange
            )
        }

        await controller.startVoiceInput()

        #expect(controller.agentPanelViewModel?.promptDraft == "summarize terminal output")
        #expect(controller.isCommandPaletteVisible == false)
    }
}

private final class VoiceInputConfigProvider: ConfigFileProviding, @unchecked Sendable {
    var content: String?

    init(content: String?) {
        self.content = content
    }

    func readConfigFile() -> String? {
        content
    }

    func writeConfigFile(_ content: String) throws {
        self.content = content
    }
}

private final class MainWindowVoicePermissionManager: VoicePermissionManaging, @unchecked Sendable {
    func currentAuthorizationState() async -> VoiceAuthorizationState {
        .authorized
    }

    func requestAuthorization() async -> VoiceAuthorizationState {
        .authorized
    }
}

private final class MainWindowVoiceTranscriber: VoiceTranscribing, @unchecked Sendable {
    private let result: VoiceTranscript

    init(result: VoiceTranscript) {
        self.result = result
    }

    func transcribe(
        localeIdentifier: String,
        onPartial: @MainActor @Sendable @escaping (VoiceTranscript) -> Void
    ) async throws -> VoiceTranscript {
        result
    }
}

private final class MainWindowAgentPromptRunner: AgentPromptRunning, @unchecked Sendable {
    func run(
        prompt: String,
        history: [AgentMessage],
        configuration: AgentModeConfig
    ) async throws -> AgentLoopResult {
        AgentLoopResult(messages: history, stopReason: .completed)
    }
}
