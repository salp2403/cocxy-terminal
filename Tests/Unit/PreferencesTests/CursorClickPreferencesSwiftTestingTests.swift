// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyTerminal

@Suite("PreferencesViewModel - cursor click-to-move")
@MainActor
struct CursorClickPreferencesSwiftTestingTests {
    private final class InMemoryProvider: ConfigFileProviding, @unchecked Sendable {
        var lastWrite: String?

        func readConfigFile() -> String? { nil }
        func writeConfigFile(_ content: String) throws { lastWrite = content }
    }

    private func terminalConfig(cursorClickToMove: Bool) -> TerminalConfig {
        let defaults = TerminalConfig.defaults
        return TerminalConfig(
            scrollbackLines: defaults.scrollbackLines,
            cursorStyle: defaults.cursorStyle,
            cursorBlink: defaults.cursorBlink,
            cursorOpacity: defaults.cursorOpacity,
            mouseHideWhileTyping: defaults.mouseHideWhileTyping,
            copyOnSelect: defaults.copyOnSelect,
            cursorClickToMove: cursorClickToMove,
            clipboardPasteProtection: defaults.clipboardPasteProtection,
            clipboardReadAccess: defaults.clipboardReadAccess,
            clipboardWriteAccess: defaults.clipboardWriteAccess,
            imageMemoryLimitMB: defaults.imageMemoryLimitMB,
            imageFileTransfer: defaults.imageFileTransfer,
            enableSixelImages: defaults.enableSixelImages,
            enableKittyImages: defaults.enableKittyImages,
            enableITerm2Images: defaults.enableITerm2Images,
            imageDiskCacheDirectory: defaults.imageDiskCacheDirectory,
            imageDiskCacheLimitMB: defaults.imageDiskCacheLimitMB
        )
    }

    private func makeViewModel(
        enabled: Bool
    ) -> (PreferencesViewModel, InMemoryProvider) {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: terminalConfig(cursorClickToMove: enabled),
            agentDetection: .defaults,
            notifications: .defaults,
            quickTerminal: .defaults,
            keybindings: .defaults,
            sessions: .defaults
        )
        let provider = InMemoryProvider()
        return (PreferencesViewModel(config: config, fileProvider: provider), provider)
    }

    @Test("saved value loads and discard restores it")
    func savedValueLoadsAndDiscardRestoresIt() {
        let (viewModel, _) = makeViewModel(enabled: false)

        #expect(!viewModel.cursorClickToMove)
        #expect(!viewModel.hasUnsavedChanges)

        viewModel.cursorClickToMove = true
        #expect(viewModel.hasUnsavedChanges)

        viewModel.discardChanges()
        #expect(!viewModel.cursorClickToMove)
        #expect(!viewModel.hasUnsavedChanges)
    }

    @Test("save persists the cursor click setting")
    func savePersistsCursorClickSetting() throws {
        let (viewModel, provider) = makeViewModel(enabled: true)
        viewModel.cursorClickToMove = false

        try viewModel.save()

        #expect(provider.lastWrite?.contains("cursor-click-to-move = false") == true)
        #expect(!viewModel.hasUnsavedChanges)
    }
}
