// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditorOpenCLIArgumentParserSwiftTestingTests.swift - `cocxy open` parser coverage.

import Testing
@testable import CocxyCLILib

@Suite("CLI editor-open parsing")
struct EditorOpenCLIArgumentParserSwiftTestingTests {

    @Test("`cocxy open` parses a bare path")
    func openBarePathParses() throws {
        let parsed = try CLIArgumentParser.parse(["open", "/tmp/project"])
        #expect(parsed == .editorOpen(path: "/tmp/project", editor: nil, line: nil, column: nil))
    }

    @Test("`cocxy open` accepts editor, line, and column")
    func openWithEditorAndPositionParses() throws {
        let parsed = try CLIArgumentParser.parse([
            "open", "/tmp/project/Sources/App.swift",
            "--editor", "vscode",
            "--line", "42",
            "--column", "7",
        ])
        #expect(parsed == .editorOpen(
            path: "/tmp/project/Sources/App.swift",
            editor: "vscode",
            line: 42,
            column: 7
        ))
    }

    @Test("`cocxy open` supports -e editor alias")
    func openEditorShortAliasParses() throws {
        let parsed = try CLIArgumentParser.parse(["open", "README.md", "-e", "zed"])
        #expect(parsed == .editorOpen(path: "README.md", editor: "zed", line: nil, column: nil))
    }

    @Test("`cocxy open` rejects missing path")
    func openMissingPathThrows() {
        #expect(throws: CLIError.self) {
            _ = try CLIArgumentParser.parse(["open", "--editor", "vscode"])
        }
    }

    @Test("`cocxy open` rejects unknown editor")
    func openUnknownEditorThrows() {
        #expect(throws: CLIError.self) {
            _ = try CLIArgumentParser.parse(["open", "README.md", "--editor", "unknown-editor"])
        }
    }

    @Test("`cocxy open --help` returns global help")
    func openHelpReturnsHelp() throws {
        #expect(try CLIArgumentParser.parse(["open", "--help"]) == .help)
    }

    @Test("global help documents local-only open command")
    func globalHelpDocumentsOpenCommand() {
        let help = CLIArgumentParser.helpText()

        #expect(help.contains("cocxy open <path>"))
        #expect(help.contains("registered editor"))
    }
}
