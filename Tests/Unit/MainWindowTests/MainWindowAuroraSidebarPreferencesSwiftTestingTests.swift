// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowAuroraSidebarPreferencesSwiftTestingTests.swift - Aurora sidebar preference persistence coverage.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("MainWindowController - Aurora sidebar preferences")
struct MainWindowAuroraSidebarPreferencesSwiftTestingTests {

    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var content: String?
        private(set) var writtenContent: String?

        init(content: String? = ConfigService.generateDefaultToml()) {
            self.content = content
        }

        func readConfigFile() -> String? { content }

        func writeConfigFile(_ content: String) throws {
            writtenContent = content
            self.content = content
        }
    }

    @Test
    func sidebarDisplayModeSelectionPersistsThroughConfigService() throws {
        let provider = InMemoryProvider()
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: service
        )

        controller.persistAuroraSidebarPreferences(displayMode: .compact)

        let written = try #require(provider.writtenContent)
        #expect(written.contains("aurora-sidebar-display-mode = \"compact\""))
        #expect(written.contains("aurora-sidebar-primary-info = \"state\""))
        #expect(service.current.appearance.auroraSidebarDisplayMode == .compact)

        let reloaded = ConfigService(fileProvider: provider)
        try reloaded.reload()
        #expect(reloaded.current.appearance.auroraSidebarDisplayMode == .compact)
    }

    @Test
    func sidebarPrimaryInfoSelectionPreservesExistingDisplayMode() throws {
        let provider = InMemoryProvider(content: """
        [appearance]
        aurora-sidebar-display-mode = "summary"
        aurora-sidebar-primary-info = "state"
        """)
        let service = ConfigService(fileProvider: provider)
        try service.reload()
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            configService: service
        )

        controller.persistAuroraSidebarPreferences(primaryInfo: .process)

        let written = try #require(provider.writtenContent)
        #expect(written.contains("aurora-sidebar-display-mode = \"summary\""))
        #expect(written.contains("aurora-sidebar-primary-info = \"process\""))
        #expect(service.current.appearance.auroraSidebarDisplayMode == .summary)
        #expect(service.current.appearance.auroraSidebarPrimaryInfo == .process)
    }
}
