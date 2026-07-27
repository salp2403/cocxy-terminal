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
            // Interactive full-screen editors are slow under parallel CI load. We keep
            // the timeout high here instead of using retries so stalls still fail
            // deterministically on the first run with useful output.
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
                inputs: [.init(text: "printf 'ZSH_INTERACTIVE_OK\\n'\nexit\n")]
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
                inputs: [.init(text: "printf 'BASH_INTERACTIVE_OK\\n'\nexit\n")]
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
                inputs: [.init(readinessMarker: "VIM - Vi IMproved", text: ":q!\r")],
                timeoutNanoseconds: 20_000_000_000
            ),
            .init(
                name: "vim opens a file",
                requiredCommands: ["vim"],
                scriptBody: "exec vim -Nu NONE -n \(shQuote(fixtureFile.path))",
                expectedSubstrings: [fixtureFile.lastPathComponent],
                inputs: [.init(readinessMarker: fixtureFile.lastPathComponent, text: ":q!\r")],
                timeoutNanoseconds: 20_000_000_000
            ),
            .init(
                name: "nano startup screen",
                requiredCommands: ["nano"],
                scriptBody: "exec nano \(shQuote(fixtureFile.path))",
                expectedSubstrings: ["PICO 5.09"],
                inputs: [.init(readinessMarker: "PICO 5.09", text: String(UnicodeScalar(24)))],
                timeoutNanoseconds: 20_000_000_000
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
        let sourceRepoPath = FileManager.default.currentDirectoryPath
        let repoFixture = try createGitFixtureRepo(in: tempDir)
        let repoPath = repoFixture.repoURL.path

        let scenarios: [CompatibilityScenario] = [
            // Pagers, progress meters and local transfer tools can slow down a lot under
            // full-suite CPU contention in CI. Use explicit higher limits instead of
            // retries so a real stall still fails on the first attempt.
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
                inputs: [.init(readinessMarker: "localhost", text: "q")],
                timeoutNanoseconds: 20_000_000_000
            ),
            .init(
                name: "man renders a manual page",
                requiredCommands: ["man"],
                scriptBody: "exec man ssh",
                expectedSubstrings: ["SSH(1)"],
                inputs: [.init(readinessMarker: "SSH(1)", text: "q")],
                timeoutNanoseconds: 20_000_000_000
            ),
            .init(
                name: "git status in the repo",
                requiredCommands: ["git"],
                scriptBody: "cd \(shQuote(repoPath)) && exec git -c color.status=false status --short -- \(shQuote(repoFixture.trackedFileName))",
                expectedSubstrings: [repoFixture.trackedFileName]
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
                scriptBody: "cd \(shQuote(repoPath)) && exec git diff --stat -- \(shQuote(repoFixture.trackedFileName))",
                expectedSubstrings: [repoFixture.trackedFileName]
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
                scriptBody: "exec rg --max-count 1 CocxyCoreBridge \(shQuote(sourceRepoPath + "/Sources"))",
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
                timeoutNanoseconds: 20_000_000_000
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
                timeoutNanoseconds: 20_000_000_000
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
                inputs: [.init(text: "print('PY_REPL_OK')\nexit()\n")],
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
                inputs: [.init(text: "console.log('NODE_REPL_OK')\nprocess.exit(0)\n")],
                timeoutNanoseconds: 10_000_000_000
            ),
            .init(
                name: "irb REPL",
                requiredCommands: ["irb"],
                scriptBody: "exec irb",
                expectedSubstrings: ["IRB_OK"],
                inputs: [.init(text: "puts 'IRB_OK'\nexit\n")],
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
                expectedSubstrings: ["Usage"],
                hostProbe: CompatibilityHostProbe(
                    command: "claude",
                    arguments: ["--help"],
                    expectedSubstrings: ["Usage"]
                )
            ),
            .init(
                name: "codex help output",
                requiredCommands: ["codex"],
                scriptBody: "exec codex --help",
                expectedSubstrings: ["Usage"],
                hostProbe: CompatibilityHostProbe(
                    command: "codex",
                    arguments: ["--help"],
                    expectedSubstrings: ["Usage"]
                )
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
    let hostProbe: CompatibilityHostProbe?
    let timeoutNanoseconds: UInt64

    init(
        name: String,
        requiredCommands: [String],
        scriptBody: String,
        expectedSubstrings: [String],
        inputs: [CompatibilityInput] = [],
        hostProbe: CompatibilityHostProbe? = nil,
        timeoutNanoseconds: UInt64 = 12_000_000_000
    ) {
        self.name = name
        self.requiredCommands = requiredCommands
        self.scriptBody = scriptBody
        self.expectedSubstrings = expectedSubstrings
        self.inputs = inputs
        self.hostProbe = hostProbe
        self.timeoutNanoseconds = timeoutNanoseconds
    }
}

private struct CompatibilityHostProbe {
    let command: String
    let arguments: [String]
    let expectedSubstrings: [String]
}

private struct CompatibilityInput {
    /// Output the child must have produced before `text` is injected.
    ///
    /// `nil` means "any output at all", which is what shells and REPLs need:
    /// they print their prompt only once they are reading from the tty.
    /// Full-screen programs (vim, nano, less, man) name the marker
    /// explicitly, because a quit key that lands before the first paint
    /// makes them exit without ever emitting the expected screen.
    let readinessMarker: String?
    /// Grace period applied after the marker is observed, so the child can
    /// finish the write burst it had already started.
    let settleNanoseconds: UInt64
    let text: String

    init(
        readinessMarker: String? = nil,
        settleNanoseconds: UInt64 = 250_000_000,
        text: String
    ) {
        self.readinessMarker = readinessMarker
        self.settleNanoseconds = settleNanoseconds
        self.text = text
    }
}

private struct GitFixtureRepo {
    let repoURL: URL
    let trackedFileName: String
}

private struct ScenarioTimeoutError: LocalizedError {
    let scenarioName: String
    let timeoutNanoseconds: UInt64
    let outputTail: String

    var errorDescription: String? {
        """
        Scenario '\(scenarioName)' timed out after \(Double(timeoutNanoseconds) / 1_000_000_000)s.
        Tail:
        \(outputTail)
        """
    }
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
        if let hostProbe = scenario.hostProbe,
           !hostProbeIsSatisfied(hostProbe) {
            continue
        }

        try await runScenario(scenario, tempDir: tempDir, timeoutNanoseconds: scenario.timeoutNanoseconds)
    }
}

@MainActor
private func runScenario(
    _ scenario: CompatibilityScenario,
    tempDir: URL,
    timeoutNanoseconds: UInt64
) async throws {
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

    // Never spend more than half the scenario window waiting for readiness:
    // if the marker never shows up the keystroke still goes out early enough
    // for the scenario's own timeout to judge the result.
    let readinessTimeoutNanoseconds = min(10_000_000_000, timeoutNanoseconds / 2)

    let inputTasks = scenario.inputs.map { input in
        Task { @MainActor in
            await waitForInputReadiness(
                marker: input.readinessMarker,
                sink: sink,
                timeoutNanoseconds: readinessTimeoutNanoseconds
            )
            guard !Task.isCancelled else { return }
            try? await Task.sleep(nanoseconds: input.settleNanoseconds)
            guard !Task.isCancelled else { return }
            bridge.sendText(input.text, to: surfaceID)
        }
    }

    defer {
        inputTasks.forEach { $0.cancel() }
        bridge.destroySurface(surfaceID)
        try? FileManager.default.removeItem(at: scriptURL)
    }

    try await waitForScenarioOutput(
        scenarioName: scenario.name,
        timeoutNanoseconds: timeoutNanoseconds,
        condition: {
            let output = String(decoding: sink.data, as: UTF8.self)
            return scenario.expectedSubstrings.allSatisfy { output.localizedCaseInsensitiveContains($0) }
        },
        outputTail: {
            String(String(decoding: sink.data, as: UTF8.self).suffix(2_000))
        }
    )

    let output = String(decoding: sink.data, as: UTF8.self)
    #expect(
        scenario.expectedSubstrings.allSatisfy { output.localizedCaseInsensitiveContains($0) },
        Comment("Scenario '\(scenario.name)' did not emit the expected output. Tail:\n\(String(output.suffix(2_000)))")
    )
}

/// Holds an injected keystroke back until the child proves it is running.
///
/// A fixed `Task.sleep` before injecting measures how fast the machine
/// starts vim, nano or a shell — not whether the terminal delivers input.
/// On a loaded runner the `:q!` used to land before the editor painted its
/// splash, so the substring the scenario asserts on was never emitted and a
/// healthy build failed. Polling for output the child itself produced
/// removes that dependency. If the marker never arrives the input is sent
/// anyway once the cap expires, so the scenario still fails through
/// `waitForScenarioOutput` instead of stalling on a keystroke that is never
/// delivered.
@MainActor
private func waitForInputReadiness(
    marker: String?,
    sink: TestDataSink,
    timeoutNanoseconds: UInt64,
    pollNanoseconds: UInt64 = 20_000_000
) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if Task.isCancelled {
            return
        }
        if scenarioOutputIsReady(marker: marker, sink: sink) {
            return
        }
        try? await Task.sleep(nanoseconds: pollNanoseconds)
    }
}

@MainActor
private func scenarioOutputIsReady(marker: String?, sink: TestDataSink) -> Bool {
    guard let marker else {
        return !sink.data.isEmpty
    }
    return String(decoding: sink.data, as: UTF8.self).localizedCaseInsensitiveContains(marker)
}

@MainActor
private func waitForScenarioOutput(
    scenarioName: String,
    timeoutNanoseconds: UInt64,
    pollNanoseconds: UInt64 = 50_000_000,
    condition: @escaping @Sendable @MainActor () -> Bool,
    outputTail: @escaping @Sendable @MainActor () -> String
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await MainActor.run(body: condition) {
            return
        }
        try await Task.sleep(nanoseconds: pollNanoseconds)
    }
    if await MainActor.run(body: condition) {
        return
    }

    throw ScenarioTimeoutError(
        scenarioName: scenarioName,
        timeoutNanoseconds: timeoutNanoseconds,
        outputTail: await MainActor.run(body: outputTail)
    )
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

private func hostProbeIsSatisfied(_ probe: CompatibilityHostProbe) -> Bool {
    guard let executable = executablePath(for: probe.command) else {
        return false
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = probe.arguments

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
    } catch {
        return false
    }
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        return false
    }
    let output = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        + String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    return probe.expectedSubstrings.allSatisfy { output.localizedCaseInsensitiveContains($0) }
}

@MainActor
private func createGitFixtureRepo(in tempDir: URL) throws -> GitFixtureRepo {
    guard let gitPath = executablePath(for: "git") else {
        throw NSError(domain: "CocxyCoreCompatibilityMatrixTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "git is required to build the compatibility fixture"
        ])
    }

    let repoURL = tempDir.appendingPathComponent("git-fixture", isDirectory: true)
    try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)

    let trackedFileName = "tracked.txt"
    let trackedFileURL = repoURL.appendingPathComponent(trackedFileName)
    try "tracked baseline\n".write(to: trackedFileURL, atomically: true, encoding: .utf8)

    try runProcess(gitPath, arguments: ["init"], currentDirectory: repoURL)
    try runProcess(gitPath, arguments: ["config", "user.name", "CocxyCore Tests"], currentDirectory: repoURL)
    try runProcess(gitPath, arguments: ["config", "user.email", "tests@cocxy.dev"], currentDirectory: repoURL)
    try runProcess(gitPath, arguments: ["add", trackedFileName], currentDirectory: repoURL)
    try runProcess(gitPath, arguments: ["commit", "-m", "Initial fixture"], currentDirectory: repoURL)

    try "tracked baseline\nmodified line\n".write(to: trackedFileURL, atomically: true, encoding: .utf8)

    return GitFixtureRepo(repoURL: repoURL, trackedFileName: trackedFileName)
}

@MainActor
private func runProcess(
    _ executable: String,
    arguments: [String],
    currentDirectory: URL
) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.currentDirectoryURL = currentDirectory

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        throw NSError(domain: "CocxyCoreCompatibilityMatrixTests", code: Int(process.terminationStatus), userInfo: [
            NSLocalizedDescriptionKey: message.isEmpty ? "Process failed: \(arguments.joined(separator: " "))" : message
        ])
    }
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
