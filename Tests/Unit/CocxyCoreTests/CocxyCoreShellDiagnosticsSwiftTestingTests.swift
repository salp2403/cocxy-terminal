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
}

private func feed(_ sequence: String, into terminal: OpaquePointer) {
    let bytes = Array(sequence.utf8)
    cocxycore_terminal_feed(terminal, bytes, bytes.count)
}
