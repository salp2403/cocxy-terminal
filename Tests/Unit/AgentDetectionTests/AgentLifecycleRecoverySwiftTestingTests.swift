// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Pure unit coverage for the shell-prompt recovery helper.
///
/// The helper decides whether a surface whose PTY just emitted a shell
/// prompt should have its agent state flushed back to `.idle`. The tests
/// pin the two observable guards — "not already idle" and "foreground is a
/// known shell binary" — and the safety defaults for missing / unusual
/// foreground names. Regression coverage is critical: a behaviour change
/// that widens the "yes, reset" branch would silently kill live agent
/// indicators while the user is in `vim`, `git`, or a sub-command invoked
/// by the agent.
@Suite("AgentLifecycleRecovery")
struct AgentLifecycleRecoverySwiftTestingTests {

    // MARK: - Idle short-circuit

    @Test("returns false when the surface is already .idle")
    func idleIsNoOp() {
        #expect(
            AgentLifecycleRecovery.shouldResetOnShellPrompt(
                currentState: .idle,
                foregroundProcessName: "zsh"
            ) == false
        )
    }

    // MARK: - Shell binaries trigger reset

    @Test("returns true when foreground is zsh")
    func zshTriggersReset() {
        #expect(
            AgentLifecycleRecovery.shouldResetOnShellPrompt(
                currentState: .launched,
                foregroundProcessName: "zsh"
            ) == true
        )
    }

    @Test("returns true when foreground is bash")
    func bashTriggersReset() {
        #expect(
            AgentLifecycleRecovery.shouldResetOnShellPrompt(
                currentState: .working,
                foregroundProcessName: "bash"
            ) == true
        )
    }

    @Test("returns true when foreground is fish")
    func fishTriggersReset() {
        #expect(
            AgentLifecycleRecovery.shouldResetOnShellPrompt(
                currentState: .waitingInput,
                foregroundProcessName: "fish"
            ) == true
        )
    }

    @Test("returns true when foreground is sh")
    func shTriggersReset() {
        #expect(
            AgentLifecycleRecovery.shouldResetOnShellPrompt(
                currentState: .finished,
                foregroundProcessName: "sh"
            ) == true
        )
    }

    @Test("returns true for every supported shell binary from any non-idle state")
    func everyShellTriggersResetForEveryNonIdleState() {
        let shells = ["zsh", "bash", "fish", "sh", "dash", "ksh", "tcsh", "csh"]
        let nonIdleStates: [AgentState] = [
            .launched, .working, .waitingInput, .finished, .error
        ]

        for shell in shells {
            for state in nonIdleStates {
                let result = AgentLifecycleRecovery.shouldResetOnShellPrompt(
                    currentState: state,
                    foregroundProcessName: shell
                )
                #expect(
                    result == true,
                    "Expected shell=\(shell) state=\(state) to trigger reset"
                )
            }
        }
    }

    // MARK: - Non-shell foregrounds do NOT trigger reset

    @Test("returns false when foreground is claude (agent still running)")
    func claudeDoesNotTriggerReset() {
        #expect(
            AgentLifecycleRecovery.shouldResetOnShellPrompt(
                currentState: .working,
                foregroundProcessName: "claude"
            ) == false
        )
    }

    @Test("returns false when foreground is codex (agent still running)")
    func codexDoesNotTriggerReset() {
        #expect(
            AgentLifecycleRecovery.shouldResetOnShellPrompt(
                currentState: .working,
                foregroundProcessName: "codex"
            ) == false
        )
    }

    @Test("returns false when foreground is vim (user in editor)")
    func vimDoesNotTriggerReset() {
        #expect(
            AgentLifecycleRecovery.shouldResetOnShellPrompt(
                currentState: .working,
                foregroundProcessName: "vim"
            ) == false
        )
    }

    @Test("returns false when foreground is git (subprocess)")
    func gitDoesNotTriggerReset() {
        #expect(
            AgentLifecycleRecovery.shouldResetOnShellPrompt(
                currentState: .working,
                foregroundProcessName: "git"
            ) == false
        )
    }

    @Test("returns false for common editor/tool binaries")
    func editorsAndToolsDoNotTriggerReset() {
        let binaries = ["vim", "nvim", "nano", "emacs", "less", "more", "man",
                        "git", "make", "npm", "node", "python", "ruby", "rails",
                        "docker", "kubectl", "cargo", "go", "curl"]
        for binary in binaries {
            #expect(
                AgentLifecycleRecovery.shouldResetOnShellPrompt(
                    currentState: .working,
                    foregroundProcessName: binary
                ) == false,
                "Unexpected reset for binary=\(binary)"
            )
        }
    }

    // MARK: - Case-insensitivity

    @Test("match is case-insensitive")
    func caseInsensitiveMatch() {
        #expect(
            AgentLifecycleRecovery.shouldResetOnShellPrompt(
                currentState: .working,
                foregroundProcessName: "ZSH"
            ) == true
        )
        #expect(
            AgentLifecycleRecovery.shouldResetOnShellPrompt(
                currentState: .working,
                foregroundProcessName: "Bash"
            ) == true
        )
    }

    // MARK: - Whitespace / empty / nil

    @Test("leading and trailing whitespace in foreground name is trimmed")
    func trimsWhitespace() {
        #expect(
            AgentLifecycleRecovery.shouldResetOnShellPrompt(
                currentState: .launched,
                foregroundProcessName: "  zsh\n"
            ) == true
        )
    }

    @Test("nil foreground name is a no-op")
    func nilForegroundIsNoOp() {
        #expect(
            AgentLifecycleRecovery.shouldResetOnShellPrompt(
                currentState: .launched,
                foregroundProcessName: nil
            ) == false
        )
    }

    @Test("empty foreground name is a no-op")
    func emptyForegroundIsNoOp() {
        #expect(
            AgentLifecycleRecovery.shouldResetOnShellPrompt(
                currentState: .launched,
                foregroundProcessName: ""
            ) == false
        )
    }

    @Test("whitespace-only foreground name is a no-op")
    func whitespaceOnlyForegroundIsNoOp() {
        #expect(
            AgentLifecycleRecovery.shouldResetOnShellPrompt(
                currentState: .launched,
                foregroundProcessName: "   \t\n"
            ) == false
        )
    }

    // MARK: - Shell binary surface

    @Test("knownShellBinaries covers every expected interactive shell")
    func knownShellBinariesSurfaceIsStable() {
        let expected: Set<String> = [
            "zsh", "bash", "fish", "sh", "dash", "ksh", "tcsh", "csh"
        ]
        #expect(AgentLifecycleRecovery.knownShellBinaries == expected)
    }
}
