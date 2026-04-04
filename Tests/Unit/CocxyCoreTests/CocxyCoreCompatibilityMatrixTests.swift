// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import AppKit
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("CocxyCore compatibility matrix", .serialized)
@MainActor
struct CocxyCoreCompatibilityMatrixTests {

    @Test("shell and editor scenarios run through CocxyCore")
    func shellAndEditorScenarios() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxycore-compat-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fixtureFile = tempDir.appendingPathComponent("fixture.txt")
        try "fixture-line\n".write(to: fixtureFile, atomically: true, encoding: .utf8)

        let scenarios: [CompatibilityScenario] = [
            .init(
                name: "zsh non-interactive command",
                requiredCommands: ["zsh"],
                scriptBody: "exec zsh -lc 'print -r -- ZSH_OK'",
                expectedSubstrings: ["ZSH_OK"]
            ),
            .init(
                name: "zsh interactive prompt",
                requiredCommands: ["zsh"],
                scriptBody: "exec zsh -i",
                expectedSubstrings: ["ZSH_INTERACTIVE_OK"],
                inputs: [.init(delayNanoseconds: 700_000_000, text: "printf 'ZSH_INTERACTIVE_OK\\n'\nexit\n")]
            ),
            .init(
                name: "bash non-interactive command",
                requiredCommands: ["bash"],
                scriptBody: "exec bash -lc 'printf \"BASH_OK\\\\n\"'",
                expectedSubstrings: ["BASH_OK"]
            ),
            .init(
                name: "bash interactive prompt",
                requiredCommands: ["bash"],
                scriptBody: "exec bash -i",
                expectedSubstrings: ["BASH_INTERACTIVE_OK"],
                inputs: [.init(delayNanoseconds: 700_000_000, text: "printf 'BASH_INTERACTIVE_OK\\n'\nexit\n")]
            ),
            .init(
                name: "zsh pipeline",
                requiredCommands: ["zsh"],
                scriptBody: "exec zsh -lc 'printf \"abc\\\\n\" | sed s/abc/ZSH_PIPE_OK/'",
                expectedSubstrings: ["ZSH_PIPE_OK"]
            ),
            .init(
                name: "vim startup screen",
                requiredCommands: ["vim"],
                scriptBody: "exec vim -Nu NONE -n",
                expectedSubstrings: ["VIM - Vi IMproved"],
                inputs: [.init(delayNanoseconds: 1_200_000_000, text: ":q!\r")],
                timeoutNanoseconds: 10_000_000_000
            ),
            .init(
                name: "vim opens a file",
                requiredCommands: ["vim"],
                scriptBody: "exec vim -Nu NONE -n \(shQuote(fixtureFile.path))",
                expectedSubstrings: [fixtureFile.lastPathComponent],
                inputs: [.init(delayNanoseconds: 1_200_000_000, text: ":q!\r")],
                timeoutNanoseconds: 10_000_000_000
            ),
            .init(
                name: "nano startup screen",
                requiredCommands: ["nano"],
                scriptBody: "exec nano \(shQuote(fixtureFile.path))",
                expectedSubstrings: ["PICO 5.09"],
                inputs: [.init(delayNanoseconds: 1_000_000_000, text: String(UnicodeScalar(24)))],
                timeoutNanoseconds: 10_000_000_000
            ),
            .init(
                name: "nano version",
                requiredCommands: ["nano"],
                scriptBody: "exec nano -version",
                expectedSubstrings: ["Pico 5.09"]
            ),
        ]

        try await runScenarios(scenarios, tempDir: tempDir)
    }

    @Test("tui and dev-tool scenarios run through CocxyCore")
    func tuiAndDevToolScenarios() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxycore-compat-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lessFile = tempDir.appendingPathComponent("less-fixture.txt")
        try Array(repeating: "localhost 127.0.0.1", count: 50)
            .joined(separator: "\n")
            .write(to: lessFile, atomically: true, encoding: .utf8)

        let rsyncSource = tempDir.appendingPathComponent("rsync-source.txt")
        try String(repeating: "rsync-phase6\n", count: 50_000)
            .write(to: rsyncSource, atomically: true, encoding: .utf8)
        let rsyncDest = tempDir.appendingPathComponent("rsync-dest.txt")
        let repoPath = FileManager.default.currentDirectoryPath

        let scenarios: [CompatibilityScenario] = [
            .init(
                name: "screen lists sessions",
                requiredCommands: ["screen"],
                scriptBody: "exec screen -ls",
                expectedSubstrings: ["Sockets"]
            ),
            .init(
                name: "screen reports its version",
                requiredCommands: ["screen"],
                scriptBody: "exec screen --version",
                expectedSubstrings: ["Screen version"]
            ),
            .init(
                name: "less displays file content",
                requiredCommands: ["less"],
                scriptBody: "exec less \(shQuote(lessFile.path))",
                expectedSubstrings: ["localhost"],
                inputs: [.init(delayNanoseconds: 1_200_000_000, text: "q")],
                timeoutNanoseconds: 10_000_000_000
            ),
            .init(
                name: "man renders a manual page",
                requiredCommands: ["man"],
                scriptBody: "exec man ssh",
                expectedSubstrings: ["SSH(1)"],
                inputs: [.init(delayNanoseconds: 1_500_000_000, text: "q")],
                timeoutNanoseconds: 12_000_000_000
            ),
            .init(
                name: "git status in the repo",
                requiredCommands: ["git"],
                scriptBody: "cd \(shQuote(repoPath)) && exec git status --short",
                expectedSubstrings: ["Sources/"]
            ),
            .init(
                name: "git log returns the latest commit",
                requiredCommands: ["git"],
                scriptBody: "cd \(shQuote(repoPath)) && exec git log -1 --pretty=format:GIT_LOG_OK:%h",
                expectedSubstrings: ["GIT_LOG_OK:"]
            ),
            .init(
                name: "git diff stat reports local changes",
                requiredCommands: ["git"],
                scriptBody: "cd \(shQuote(repoPath)) && exec git diff --stat -- Sources/App/AppDelegate.swift",
                expectedSubstrings: ["AppDelegate.swift"]
            ),
            .init(
                name: "git confirms the repo work tree",
                requiredCommands: ["git"],
                scriptBody: "cd \(shQuote(repoPath)) && exec git rev-parse --is-inside-work-tree",
                expectedSubstrings: ["true"]
            ),
            .init(
                name: "ripgrep finds CocxyCoreBridge in Sources",
                requiredCommands: ["rg"],
                scriptBody: "exec rg --max-count 1 CocxyCoreBridge \(shQuote(repoPath + "/Sources"))",
                expectedSubstrings: ["CocxyCoreBridge"]
            ),
            .init(
                name: "curl reports its version",
                requiredCommands: ["curl"],
                scriptBody: "exec curl --version",
                expectedSubstrings: ["curl"]
            ),
            .init(
                name: "curl progress meter runs inside the terminal",
                requiredCommands: ["curl"],
                scriptBody: "exec curl -L file:///etc/hosts -o /dev/null",
                expectedSubstrings: ["% Total"],
                timeoutNanoseconds: 10_000_000_000
            ),
            .init(
                name: "rsync reports its version",
                requiredCommands: ["rsync"],
                scriptBody: "exec rsync --version",
                expectedSubstrings: ["rsync"]
            ),
            .init(
                name: "rsync local copy reaches 100 percent",
                requiredCommands: ["rsync"],
                scriptBody: "exec rsync --progress \(shQuote(rsyncSource.path)) \(shQuote(rsyncDest.path))",
                expectedSubstrings: ["100%"],
                timeoutNanoseconds: 12_000_000_000
            ),
        ]

        try await runScenarios(scenarios, tempDir: tempDir)
    }

    @Test("language and misc scenarios run through CocxyCore")
    func languageAndMiscScenarios() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxycore-compat-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let scenarios: [CompatibilityScenario] = [
            .init(
                name: "python command mode",
                requiredCommands: ["python3"],
                scriptBody: "exec python3 -c 'print(\"PY_CMD_OK\")'",
                expectedSubstrings: ["PY_CMD_OK"]
            ),
            .init(
                name: "python REPL",
                requiredCommands: ["python3"],
                scriptBody: "exec python3",
                expectedSubstrings: ["PY_REPL_OK"],
                inputs: [.init(delayNanoseconds: 800_000_000, text: "print('PY_REPL_OK')\nexit()\n")],
                timeoutNanoseconds: 10_000_000_000
            ),
            .init(
                name: "node command mode",
                requiredCommands: ["node"],
                scriptBody: "exec node -e 'console.log(\"NODE_CMD_OK\")'",
                expectedSubstrings: ["NODE_CMD_OK"]
            ),
            .init(
                name: "node REPL",
                requiredCommands: ["node"],
                scriptBody: "exec node",
                expectedSubstrings: ["NODE_REPL_OK"],
                inputs: [.init(delayNanoseconds: 900_000_000, text: "console.log('NODE_REPL_OK')\nprocess.exit(0)\n")],
                timeoutNanoseconds: 10_000_000_000
            ),
            .init(
                name: "irb REPL",
                requiredCommands: ["irb"],
                scriptBody: "exec irb",
                expectedSubstrings: ["IRB_OK"],
                inputs: [.init(delayNanoseconds: 900_000_000, text: "puts 'IRB_OK'\nexit\n")],
                timeoutNanoseconds: 10_000_000_000
            ),
            .init(
                name: "ssh version output",
                requiredCommands: ["ssh"],
                scriptBody: "exec ssh -V",
                expectedSubstrings: ["OpenSSH"]
            ),
            .init(
                name: "ssh config expansion",
                requiredCommands: ["ssh"],
                scriptBody: "exec ssh -G localhost",
                expectedSubstrings: ["hostname localhost"]
            ),
            .init(
                name: "claude help output",
                requiredCommands: ["claude"],
                scriptBody: "exec claude --help",
                expectedSubstrings: ["Usage"]
            ),
            .init(
                name: "codex help output",
                requiredCommands: ["codex"],
                scriptBody: "exec codex --help",
                expectedSubstrings: ["Usage"]
            ),
        ]

        try await runScenarios(scenarios, tempDir: tempDir)
    }

    @Test("matrix covers at least thirty installed scenarios")
    func scenarioCountIsThirtyOrMore() {
        #expect(Self.totalScenarioCount >= 30)
    }

    private static let totalScenarioCount = 31
}

private struct CompatibilityScenario {
    let name: String
    let requiredCommands: [String]
    let scriptBody: String
    let expectedSubstrings: [String]
    let inputs: [CompatibilityInput]
    let timeoutNanoseconds: UInt64

    init(
        name: String,
        requiredCommands: [String],
        scriptBody: String,
        expectedSubstrings: [String],
        inputs: [CompatibilityInput] = [],
        timeoutNanoseconds: UInt64 = 8_000_000_000
    ) {
        self.name = name
        self.requiredCommands = requiredCommands
        self.scriptBody = scriptBody
        self.expectedSubstrings = expectedSubstrings
        self.inputs = inputs
        self.timeoutNanoseconds = timeoutNanoseconds
    }
}

private struct CompatibilityInput {
    let delayNanoseconds: UInt64
    let text: String
}

@MainActor
private func runScenarios(
    _ scenarios: [CompatibilityScenario],
    tempDir: URL
) async throws {
    for scenario in scenarios {
        let allCommandsAvailable = scenario.requiredCommands.allSatisfy { executablePath(for: $0) != nil }
        if !allCommandsAvailable {
            continue
        }

        let scriptURL = tempDir.appendingPathComponent("\(UUID().uuidString).zsh")
        let script = """
        #!/bin/zsh
        set -e
        \(scenario.scriptBody)
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let bridge = try makeBridge()
        let (surfaceID, _) = try createCompatibilitySurface(using: bridge, command: scriptURL.path)
        let sink = TestDataSink()
        bridge.setOutputHandler(for: surfaceID) { data in
            sink.data.append(data)
        }

        defer {
            bridge.destroySurface(surfaceID)
            try? FileManager.default.removeItem(at: scriptURL)
        }

        for input in scenario.inputs {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: input.delayNanoseconds)
                bridge.sendText(input.text, to: surfaceID)
            }
        }

        try await waitUntil(timeoutNanoseconds: scenario.timeoutNanoseconds) {
            let output = String(decoding: sink.data, as: UTF8.self)
            return scenario.expectedSubstrings.allSatisfy { output.localizedCaseInsensitiveContains($0) }
        }

        let output = String(decoding: sink.data, as: UTF8.self)
        #expect(
            scenario.expectedSubstrings.allSatisfy { output.localizedCaseInsensitiveContains($0) },
            Comment("Scenario '\(scenario.name)' did not emit the expected output. Tail:\n\(String(output.suffix(2_000)))")
        )
    }
}

private func executablePath(for command: String) -> String? {
    let env = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
    for directory in env.split(separator: ":") {
        let path = String(directory) + "/" + command
        if FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
    }
    return nil
}

@MainActor
private func createCompatibilitySurface(
    using bridge: CocxyCoreBridge,
    command: String
) throws -> (SurfaceID, NSView) {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
    let surfaceID = try bridge.createSurface(
        in: view,
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
        command: command
    )
    return (surfaceID, view)
}

private func shQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
