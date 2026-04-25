// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// GitHubAuthenticationCommandSwiftTestingTests.swift - Regression tests for
// the interactive GitHub auth command launched from the pane and settings.

import Testing
@testable import CocxyTerminal

@Suite("GitHub authentication command")
struct GitHubAuthenticationCommandSwiftTestingTests {

    @Test("auth command routes gh browser opens through Cocxy helper")
    func authCommand_usesInternalBrowserHelper() {
        let command = MainWindowController.gitHubAuthenticationCommand(
            browserOpenerPath: "/tmp/cocxy browser opener.sh"
        )

        #expect(command == "BROWSER='/tmp/cocxy browser opener.sh' gh auth login\r")
    }

    @Test("auth command leaves browser behavior intact when helper is unavailable")
    func authCommand_doesNotOverrideBrowserWhenHelperIsUnavailable() {
        let command = MainWindowController.gitHubAuthenticationCommand(browserOpenerPath: nil)

        #expect(command == "gh auth login\r")
    }

    @Test("browser opener script navigates the internal browser")
    func browserOpenerScript_usesBrowserNavigate() {
        let script = MainWindowController.browserOpenerScript(
            cliPath: "/Applications/Cocxy Terminal.app/Contents/Resources/cocxy"
        )

        #expect(script.contains("browser navigate \"$@\""))
        #expect(script.contains("'/Applications/Cocxy Terminal.app/Contents/Resources/cocxy'"))
    }
}
