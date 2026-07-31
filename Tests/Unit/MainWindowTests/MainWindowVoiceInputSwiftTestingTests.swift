// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowVoiceInputSwiftTestingTests.swift - MainWindow Voice wiring coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("MainWindowController Voice input")
struct MainWindowVoiceInputSwiftTestingTests {
    @Test("Voice consent is presented once per app session")
    @MainActor
    func voiceConsentIsPresentedOncePerSession() throws {
        let coordinator = VoiceConsentCoordinator()
        let configService = try voiceConsentConfigService(consentPrompted: false)
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService,
            voiceConsentCoordinator: coordinator
        )
        defer { controller.close() }

        #expect(controller.voiceConsentBannerHostingView != nil)
        #expect(coordinator.presentationCount == 1)

        controller.presentVoiceConsentIfNeeded()

        #expect(coordinator.presentationCount == 1)
    }

    @Test("disabling Voice from consent persists both decisions")
    @MainActor
    func disablingVoiceFromConsentPersistsBothDecisions() throws {
        let configService = try voiceConsentConfigService(consentPrompted: false)
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: configService
        )
        defer { controller.close() }

        controller.resolveVoiceConsent(keepEnabled: false)

        #expect(controller.preferencesWindow == nil)
        #expect(configService.current.voice.enabled == false)
        #expect(configService.current.voice.consentPrompted == true)
        #expect(controller.voiceConsentBannerHostingView == nil)
        let reopenedPreferences = PreferencesViewModel(config: configService.current)
        #expect(reopenedPreferences.voiceEnabled == false)
        #expect(reopenedPreferences.hasUnsavedChanges == false)
    }

    @Test("previous Voice acknowledgement never prompts again")
    @MainActor
    func previousVoiceAcknowledgementDoesNotPromptAgain() throws {
        let coordinator = VoiceConsentCoordinator()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: try voiceConsentConfigService(consentPrompted: true),
            voiceConsentCoordinator: coordinator
        )
        defer { controller.close() }

        #expect(controller.voiceConsentBannerHostingView == nil)
        #expect(coordinator.presentationCount == 0)
    }

    @Test("Voice transcript writes to a detected terminal agent without submitting")
    @MainActor
    func voiceTranscriptWritesToDetectedAgentForReview() throws {
        let engine = MockTerminalEngine()
        let controller = MainWindowController(
            bridge: engine,
            configService: try voiceConfigService(autoSendToAgent: false)
        )
        let store = AgentStatePerSurfaceStore()
        controller.injectedPerSurfaceStore = store
        controller.showWindow(nil)
        _ = controller.createTab()
        controller.injectedAgentPromptRunner = MainWindowAgentPromptRunner()
        let agentPanel = controller.resolveAgentPanelViewModel()
        controller.isAgentModeVisible = true

        let surfaceID = try #require(controller.activeTerminalSurfaceView?.terminalViewModel?.surfaceID)
        store.update(surfaceID: surfaceID) { state in
            state.agentState = .waitingInput
            state.detectedAgent = detectedAgent()
        }

        controller.applyVoiceTranscript(VoiceTranscript(
            text: "  review this change  ",
            localeIdentifier: "en-US",
            isFinal: true
        ))

        #expect(engine.sentTexts.count == 1)
        #expect(engine.sentTexts.first?.surface == surfaceID)
        #expect(engine.sentTexts.first?.text == "review this change")
        #expect(agentPanel.promptDraft.isEmpty)
        #expect(controller.isCommandPaletteVisible == false)
    }

    @Test("Voice auto-send submits to the detected agent in the focused split")
    @MainActor
    func voiceAutoSendTargetsFocusedSplit() throws {
        let engine = MockTerminalEngine()
        let controller = MainWindowController(
            bridge: engine,
            configService: try voiceConfigService(autoSendToAgent: true)
        )
        let store = AgentStatePerSurfaceStore()
        controller.injectedPerSurfaceStore = store
        controller.showWindow(nil)
        _ = controller.createTab()
        let primarySurfaceID = try #require(
            controller.activeTerminalSurfaceView?.terminalViewModel?.surfaceID
        )

        controller.performVisualSplit(isVertical: true)

        let focusedSurfaceID = try #require(
            controller.activeTerminalSurfaceView?.terminalViewModel?.surfaceID
        )
        #expect(focusedSurfaceID != primarySurfaceID)
        store.update(surfaceID: focusedSurfaceID) { state in
            state.agentState = .waitingInput
            state.detectedAgent = detectedAgent()
        }

        controller.applyVoiceTranscript(VoiceTranscript(
            text: "run the checks",
            localeIdentifier: "en-US",
            isFinal: true
        ))

        #expect(engine.sentTexts.count == 1)
        #expect(engine.sentTexts.first?.surface == focusedSurfaceID)
        #expect(engine.sentTexts.first?.text == "run the checks\r")
    }

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

    @MainActor
    private func voiceConfigService(autoSendToAgent: Bool) throws -> ConfigService {
        let service = ConfigService(fileProvider: VoiceInputConfigProvider(content: """
        [voice]
        enabled = true
        locale = "system"
        auto-send-to-agent = \(autoSendToAgent)
        """))
        try service.reload()
        return service
    }

    @MainActor
    private func voiceConsentConfigService(consentPrompted: Bool) throws -> ConfigService {
        let service = ConfigService(fileProvider: VoiceInputConfigProvider(content: """
        [voice]
        enabled = true
        consent-prompted = \(consentPrompted)
        """))
        try service.reload()
        return service
    }

    private func detectedAgent() -> DetectedAgent {
        DetectedAgent(
            name: "codex",
            launchCommand: "codex",
            startedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
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
