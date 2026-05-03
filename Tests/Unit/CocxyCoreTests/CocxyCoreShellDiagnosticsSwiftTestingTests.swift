// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
import CocxyCoreKit

@Suite("CocxyCore shell diagnostics", .serialized)
struct CocxyCoreShellDiagnosticsSwiftTestingTests {

    @Test("vendored CocxyCore exposes shell diagnostics null safety")
    func vendoredCocxyCoreExposesShellDiagnosticsNullSafety() throws {
        var diagnostics = cocxycore_shell_diagnostics()
        #expect(cocxycore_shell_get_diagnostics(nil, &diagnostics) == false)

        let terminal = try #require(cocxycore_terminal_create(24, 80))
        defer { cocxycore_terminal_destroy(terminal) }

        #expect(cocxycore_shell_get_diagnostics(terminal, nil) == false)
        #expect(cocxycore_shell_get_diagnostics(terminal, &diagnostics) == true)
        #expect(diagnostics.avg_preexec_latency_ns == 0)
        #expect(diagnostics.max_preexec_latency_ns == 0)
        #expect(diagnostics.preexec_warning_count == 0)
        #expect(diagnostics.osc7_retry_count == 0)
        #expect(diagnostics.detected_p10k == false)
        #expect(diagnostics.detected_tmux == false)
        #expect(diagnostics.detected_screen == false)
    }

    @Test("vendored CocxyCore measures preexec latency and stale cwd")
    func vendoredCocxyCoreMeasuresShellTiming() throws {
        let terminal = try #require(cocxycore_terminal_create(24, 80))
        defer { cocxycore_terminal_destroy(terminal) }

        cocxycore_shell_set_preexec_warning_threshold_ns(terminal, 1)
        feed("\u{001B}]133;B\u{0007}", into: terminal)
        Thread.sleep(forTimeInterval: 0.001)
        feed("\u{001B}]133;C\u{0007}", into: terminal)

        cocxycore_shell_set_osc7_retry_timeout_ns(terminal, 1_000_000)
        feed("\u{001B}]7;file:///tmp/cocxy\u{0007}", into: terminal)
        Thread.sleep(forTimeInterval: 0.003)
        feed("\u{001B}]133;A\u{0007}", into: terminal)

        var diagnostics = cocxycore_shell_diagnostics()
        #expect(cocxycore_shell_get_diagnostics(terminal, &diagnostics) == true)
        #expect(diagnostics.avg_preexec_latency_ns > 0)
        #expect(diagnostics.max_preexec_latency_ns >= diagnostics.avg_preexec_latency_ns)
        #expect(diagnostics.preexec_warning_count == 1)
        #expect(diagnostics.osc7_retry_count == 1)
    }

    @Test("vendored CocxyCore gates tmux shell passthrough")
    func vendoredCocxyCoreGatesTmuxPassthrough() throws {
        let enabledTerminal = try #require(cocxycore_terminal_create(24, 80))
        defer { cocxycore_terminal_destroy(enabledTerminal) }

        #expect(cocxycore_terminal_enable_semantic(enabledTerminal, 16) == true)
        cocxycore_shell_enable_tmux_passthrough(enabledTerminal, true)
        feed("\u{001B}Ptmux;\u{001B}\u{001B}]133;A\u{0007}\u{001B}\\", into: enabledTerminal)

        var enabledDiagnostics = cocxycore_shell_diagnostics()
        #expect(cocxycore_shell_get_diagnostics(enabledTerminal, &enabledDiagnostics) == true)
        #expect(enabledDiagnostics.detected_tmux == true)
        #expect(cocxycore_terminal_semantic_state(enabledTerminal) == 1)

        let disabledTerminal = try #require(cocxycore_terminal_create(24, 80))
        defer { cocxycore_terminal_destroy(disabledTerminal) }

        #expect(cocxycore_terminal_enable_semantic(disabledTerminal, 16) == true)
        cocxycore_shell_enable_tmux_passthrough(disabledTerminal, false)
        feed("\u{001B}Ptmux;\u{001B}\u{001B}]133;A\u{0007}\u{001B}\\", into: disabledTerminal)

        var disabledDiagnostics = cocxycore_shell_diagnostics()
        #expect(cocxycore_shell_get_diagnostics(disabledTerminal, &disabledDiagnostics) == true)
        #expect(disabledDiagnostics.detected_tmux == false)
        #expect(cocxycore_terminal_semantic_state(disabledTerminal) == 0)
    }

    @Test("vendored CocxyCore detects screen shell passthrough")
    func vendoredCocxyCoreDetectsScreenPassthrough() throws {
        let terminal = try #require(cocxycore_terminal_create(24, 80))
        defer { cocxycore_terminal_destroy(terminal) }

        #expect(cocxycore_terminal_enable_semantic(terminal, 16) == true)
        feed("\u{001B}Pp\u{001B}]133;A\u{0007}\u{001B}\\", into: terminal)

        var diagnostics = cocxycore_shell_diagnostics()
        #expect(cocxycore_shell_get_diagnostics(terminal, &diagnostics) == true)
        #expect(diagnostics.detected_screen == true)
        #expect(cocxycore_terminal_semantic_state(terminal) == 1)
    }

    @Test("vendored CocxyCore detects multiplexer protocol markers")
    func vendoredCocxyCoreDetectsMultiplexerProtocolMarkers() throws {
        let terminal = try #require(cocxycore_terminal_create(24, 80))
        defer { cocxycore_terminal_destroy(terminal) }

        feed("\u{001B}]7770;{\"type\":\"cocxy_shell_multiplexer\",\"name\":\"screen\"}\u{0007}", into: terminal)

        var diagnostics = cocxycore_shell_diagnostics()
        #expect(cocxycore_shell_get_diagnostics(terminal, &diagnostics) == true)
        #expect(diagnostics.detected_screen == true)
        #expect(diagnostics.detected_tmux == false)

        feed("\u{001B}]7770;{\"type\":\"cocxy_shell_multiplexer\",\"name\":\"tmux\"}\u{0007}", into: terminal)

        #expect(cocxycore_shell_get_diagnostics(terminal, &diagnostics) == true)
        #expect(diagnostics.detected_screen == true)
        #expect(diagnostics.detected_tmux == true)
    }

    @Test("shell integration scripts wrap OSC output for tmux and screen")
    func shellIntegrationScriptsWrapOSCForMultiplexers() throws {
        let expectations = [
            ("zsh/cocxy-integration", "_cocxy_wrap_control_sequence"),
            ("bash/cocxy.bash", "__cocxy_wrap_control_sequence"),
            ("fish/cocxy.fish", "__cocxy_fish_wrap_control_sequence"),
        ]

        for (relativePath, wrapperName) in expectations {
            let script = try shellIntegrationScript(relativePath)
            #expect(script.contains(wrapperName), "\(relativePath) should centralize OSC wrapping")
            #expect(script.contains("TMUX"), "\(relativePath) should detect tmux")
            #expect(script.contains("STY"), "\(relativePath) should detect GNU screen")
            #expect(script.contains("tmux;"), "\(relativePath) should emit tmux DCS passthrough")
            #expect(script.contains("cocxy_shell_multiplexer"), "\(relativePath) should emit Cocxy multiplexer markers")
            #expect(!script.contains("\\ePp"), "\(relativePath) should not emit visible Cocxy screen DCS sentinels")
        }
    }

    @Test("zsh and bash wrappers emit exact multiplexer passthrough bytes")
    func shellIntegrationWrappersEmitExpectedPassthroughBytes() throws {
        let zshScript = shellIntegrationScriptURL("zsh/cocxy-integration").path
        let bashScript = shellIntegrationScriptURL("bash/cocxy.bash").path
        let sequenceLiteral = "$'\\e]133;A\\a'"

        let markerType = "\"type\":\"cocxy_shell_multiplexer\""
        let expectedTmux = Data(
            "\u{001B}Ptmux;\u{001B}\u{001B}]7770;{\(markerType),\"name\":\"tmux\"}\u{0007}\u{001B}\u{001B}]133;A\u{0007}\u{001B}\\".utf8
        )
        let expectedScreen = Data(
            "\u{001B}P\u{001B}]7770;{\(markerType),\"name\":\"screen\"}\u{0007}\u{001B}]133;A\u{0007}\u{001B}\\".utf8
        )

        let zshTmux = try runShell(
            executable: "/bin/zsh",
            arguments: ["-fc", "source \(zshScript.shellQuoted); TMUX=1 _cocxy_wrap_control_sequence \(sequenceLiteral)"]
        )
        #expect(zshTmux.stderr.isEmpty)
        #expect(zshTmux.stdout == expectedTmux)

        let zshScreen = try runShell(
            executable: "/bin/zsh",
            arguments: ["-fc", "source \(zshScript.shellQuoted); STY=screen-smoke _cocxy_wrap_control_sequence \(sequenceLiteral)"]
        )
        #expect(zshScreen.stderr.isEmpty)
        #expect(zshScreen.stdout == expectedScreen)

        let bashTmux = try runShell(
            executable: "/bin/bash",
            arguments: ["--noprofile", "--norc", "-ic", "source \(bashScript.shellQuoted); TMUX=1 __cocxy_wrap_control_sequence \(sequenceLiteral)"]
        )
        #expect(!bashTmux.stderrText.contains("bad substitution"))
        #expect(bashTmux.stdout == expectedTmux)

        let bashScreen = try runShell(
            executable: "/bin/bash",
            arguments: ["--noprofile", "--norc", "-ic", "source \(bashScript.shellQuoted); STY=screen-smoke __cocxy_wrap_control_sequence \(sequenceLiteral)"]
        )
        #expect(!bashScreen.stderrText.contains("bad substitution"))
        #expect(bashScreen.stdout == expectedScreen)
    }
}

private func feed(_ sequence: String, into terminal: OpaquePointer) {
    let bytes = Array(sequence.utf8)
    cocxycore_terminal_feed(terminal, bytes, bytes.count)
}

private func shellIntegrationScript(_ relativePath: String) throws -> String {
    try String(contentsOf: shellIntegrationScriptURL(relativePath), encoding: .utf8)
}

private func shellIntegrationScriptURL(_ relativePath: String) -> URL {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return packageRoot
        .appendingPathComponent("Resources/shell-integration", isDirectory: true)
        .appendingPathComponent(relativePath, isDirectory: false)
}

private struct ShellRunResult {
    let stdout: Data
    let stderr: Data

    var stderrText: String {
        String(decoding: stderr, as: UTF8.self)
    }
}

private func runShell(executable: String, arguments: [String]) throws -> ShellRunResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    let stdout = Pipe()
    let stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr

    try process.run()
    process.waitUntilExit()

    let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
    #expect(process.terminationStatus == 0)
    return ShellRunResult(stdout: stdoutData, stderr: stderrData)
}

private extension String {
    var shellQuoted: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
