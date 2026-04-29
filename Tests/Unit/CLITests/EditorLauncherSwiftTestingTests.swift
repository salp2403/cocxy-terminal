// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorLauncherSwiftTestingTests.swift - Shared editor registry coverage.

import Testing
import CocxyShared

@Suite("Editor integration registry")
struct EditorLauncherSwiftTestingTests {

    @Test("registry resolves ids, display names, and executable aliases")
    func registryResolvesCommonNames() {
        #expect(EditorRegistry.launcher(matching: "vscode")?.id == "vscode")
        #expect(EditorRegistry.launcher(matching: "VS Code")?.id == "vscode")
        #expect(EditorRegistry.launcher(matching: "code")?.id == "vscode")
        #expect(EditorRegistry.launcher(matching: "Sublime Text")?.id == "sublime")
        #expect(EditorRegistry.launcher(matching: "emacsclient")?.id == "emacs")
        #expect(EditorRegistry.launcher(matching: "Aquamacs")?.id == "aquamacs")
    }

    @Test("system/default editor falls back to /usr/bin/open")
    func systemDefaultPlanUsesOpen() {
        let plan = EditorLaunchPlanner.plan(
            request: EditorOpenRequest(filePath: "/tmp/a b.txt", editorID: nil),
            launcher: nil,
            executablePath: nil,
            bundleIdentifier: nil
        )
        #expect(plan.executablePath == "/usr/bin/open")
        #expect(plan.arguments == ["/tmp/a b.txt"])
        #expect(plan.displayName == "Default Editor")
    }

    @Test("VS Code and Cursor use -g for line and column")
    func codeStyleEditorsUseGoToFlag() {
        let launcher = EditorRegistry.launcher(matching: "cursor")
        let args = EditorLaunchPlanner.commandArguments(
            for: launcher!,
            filePath: "/tmp/App.swift",
            line: 12,
            column: 4
        )
        #expect(args == ["-g", "/tmp/App.swift:12:4"])
    }

    @Test("Xcode uses xed line syntax")
    func xcodeUsesXedLineSyntax() {
        let launcher = EditorRegistry.launcher(matching: "xcode")
        let args = EditorLaunchPlanner.commandArguments(
            for: launcher!,
            filePath: "/tmp/App.swift",
            line: 9,
            column: 4
        )
        #expect(args == ["--line", "9", "/tmp/App.swift"])
    }

    @Test("Emacs uses non-blocking emacsclient line syntax")
    func emacsUsesNonBlockingClientLineSyntax() {
        let launcher = EditorRegistry.launcher(matching: "emacs")
        let args = EditorLaunchPlanner.commandArguments(
            for: launcher!,
            filePath: "/tmp/App.swift",
            line: 9,
            column: 4
        )
        #expect(args == ["-n", "+9:4", "/tmp/App.swift"])
    }

    @Test("terminal editors are marked in launch plans")
    func terminalEditorPlansAreMarked() {
        let launcher = EditorRegistry.launcher(matching: "nvim")
        let plan = EditorLaunchPlanner.plan(
            request: EditorOpenRequest(filePath: "/tmp/App.swift", editorID: "nvim", line: 5),
            launcher: launcher,
            executablePath: "/opt/homebrew/bin/nvim",
            bundleIdentifier: nil
        )
        #expect(plan.launchesTerminalEditor == true)
        #expect(plan.arguments == ["+5", "/tmp/App.swift"])
    }

    @Test("bundle fallback keeps GUI editors usable without CLI shims")
    func bundleFallbackUsesOpenBundleIdentifier() {
        let launcher = EditorRegistry.launcher(matching: "zed")
        let plan = EditorLaunchPlanner.plan(
            request: EditorOpenRequest(filePath: "/tmp/App.swift", editorID: "zed"),
            launcher: launcher,
            executablePath: nil,
            bundleIdentifier: "dev.zed.Zed"
        )
        #expect(plan.executablePath == "/usr/bin/open")
        #expect(plan.arguments == ["-b", "dev.zed.Zed", "/tmp/App.swift"])
        #expect(plan.displayName == "Zed")
    }
}
