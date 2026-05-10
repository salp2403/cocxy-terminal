// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ContextAwareShortcutsSwiftTestingTests.swift - Cmd+L routing coverage.

import Testing
@testable import CocxyTerminal

@Suite("UX polish - context-aware shortcuts")
struct ContextAwareShortcutsSwiftTestingTests {

    @Test("Cmd+L focuses the address field when browser already owns focus")
    func commandLFocusesAddressFieldForFocusedBrowser() {
        let action = ContextAwareShortcuts.commandLAction(
            focusedSurface: .browser,
            browserSurfaceAvailable: true
        )

        #expect(action == .focusBrowserAddressField)
    }

    @Test("Cmd+L opens browser split when terminal has no browser surface")
    func commandLOpensBrowserFromTerminalWithoutBrowser() {
        let action = ContextAwareShortcuts.commandLAction(
            focusedSurface: .terminal,
            browserSurfaceAvailable: false
        )

        #expect(action == .openBrowserSplitAndFocusAddressField)
    }

    @Test("Cmd+L reuses an existing browser surface instead of duplicating it")
    func commandLReusesExistingBrowserSurfaceFromTerminal() {
        let action = ContextAwareShortcuts.commandLAction(
            focusedSurface: .terminal,
            browserSurfaceAvailable: true
        )

        #expect(action == .focusBrowserAddressField)
    }
}
