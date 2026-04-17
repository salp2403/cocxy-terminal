// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentLifecycleRecovery.swift - Pure decision helpers for recovering from stuck agent states.

import Foundation

/// Pure decision helpers for recovering the per-surface agent state when an
/// agent terminates without emitting a `SessionEnd` hook and without taking
/// the surrounding shell process down with it.
///
/// Prior to this helper, four independent signals could in principle clear a
/// surface's agent state:
/// 1. A Layer-0 hook event of type `SessionEnd` (mapped to `.agentExited`).
/// 2. A Layer-0 hook event of type `Stop` (mapped to `.completionDetected`).
/// 3. An OSC `.processExited` notification emitted when the SHELL process
///    itself terminates.
/// 4. Explicit teardown via `destroyTerminalSurface` or `destroyAllSurfaces`.
///
/// None of those catch the most common real-world scenario: the user launches
/// `claude` (or any other agent), the agent terminates on its own without
/// completing the hook handshake (e.g., aborted by `--dangerously-skip-permissions`,
/// `Ctrl+C`, or a crash before bootstrap), the shell prompt returns, and the
/// backing shell process stays alive. In that scenario the per-surface store
/// retains the last observed agent state (`.launched`, `.finished`,
/// `.waitingInput`, …) and the sidebar, status bar, and progress overlay keep
/// reporting activity for an agent that no longer exists.
///
/// This helper complements the existing paths by checking whether a shell
/// prompt (OSC 133;A) arrived on a surface whose PTY foreground process has
/// returned to a known shell binary. When both conditions hold, the caller
/// can safely flush the surface's agent state back to `.idle` without
/// disturbing surfaces that are still running an agent.
///
/// ## Design notes
///
/// - The helper is intentionally conservative. It returns `true` only when
///   the foreground process name is an element of the hand-vetted set of
///   shell binaries (`zsh`, `bash`, `fish`, `sh`, `dash`, `ksh`, `tcsh`,
///   `csh`). Any other foreground (for example `vim`, `git`, `node`, `make`,
///   or another agent binary) leaves the state untouched. This keeps the
///   recovery from firing while the user is in the middle of an editor
///   session, a long-running build, or a sub-command invoked by the agent.
/// - The helper treats `.idle` as a no-op: there is no state to reset.
///   Callers do not need to guard for this case themselves, but they may
///   still short-circuit earlier for efficiency.
/// - Matching is case-insensitive. Shell names surfaced by `sysctl` on macOS
///   are typically lowercase, but the normalization protects against
///   renamed-binary scenarios (`Bash`, `ZSH`) without loosening the contract.
/// - `nil` or empty foreground names produce `false`. Callers that cannot
///   resolve the foreground process still see the "do nothing" outcome and
///   the existing detection layers remain free to drive transitions on
///   their own.
///
/// - SeeAlso: `ForegroundProcessDetector.detect(shellPID:ptyMasterFD:expectedShellIdentity:snapshots:)`
/// - SeeAlso: `AgentDetectionEngineImpl.notifyProcessExited(surfaceID:)`
/// - SeeAlso: `AgentStatePerSurfaceStore.reset(surfaceID:)`
enum AgentLifecycleRecovery {

    /// Binary names that represent a login/interactive shell. Matching is
    /// performed case-insensitively against `ForegroundProcessInfo.name`
    /// (which comes from `kp_proc.p_comm` and is typically lowercase).
    ///
    /// Rationale for each entry:
    /// - `zsh`: macOS default shell since 10.15.
    /// - `bash`: still used by many users and the brew-installed version.
    /// - `fish`: popular alternative interactive shell.
    /// - `sh`: the Bourne shell fallback; present on every POSIX system.
    /// - `dash`: Debian-flavoured minimal shell; harmless to recognise.
    /// - `ksh`, `tcsh`, `csh`: historical shells; included defensively so
    ///   the recovery does not misbehave on unusual user setups.
    ///
    /// Kept as a `static let` so the set is allocated once and reused
    /// for every decision. Changing the set requires a review because
    /// widening it can cause the recovery to fire inside non-shell
    /// contexts (for example, a REPL that happens to be launched via a
    /// shell-like process), which would mask live agent activity.
    static let knownShellBinaries: Set<String> = [
        "zsh", "bash", "fish", "sh", "dash", "ksh", "tcsh", "csh"
    ]

    /// Decides whether a shell-prompt event on a surface should trigger a
    /// full agent-state reset.
    ///
    /// Returns `true` only when **both** of the following hold:
    /// 1. The surface's current `AgentState` is not `.idle`. `.idle` already
    ///    represents "nothing to clean up" — returning `false` here avoids
    ///    spurious refreshes on surfaces that never ran an agent.
    /// 2. The resolved foreground process name matches one of
    ///    `knownShellBinaries` after normalization.
    ///
    /// The helper deliberately does **not** look at the detected agent's
    /// `launchCommand` or compare the foreground name to the list of
    /// configured agent binaries. A conservative "is this a shell?" probe
    /// avoids every edge case where:
    /// - An agent binary was renamed or wrapped (`claude-code` → `npx`).
    /// - The agent invoked a sub-command (`git`, `npm`, `curl`) that
    ///   briefly becomes the foreground.
    /// - The user switched agents by running a different agent in the same
    ///   surface; the new agent itself will drive the state back to
    ///   `.launched` on its own.
    ///
    /// - Parameters:
    ///   - currentState: The agent state currently persisted in the
    ///     per-surface store for the surface that emitted the prompt.
    ///   - foregroundProcessName: The name of the PTY foreground process,
    ///     as reported by `ForegroundProcessDetector.detect(...)`. Pass
    ///     `nil` when detection failed or the registration is missing.
    /// - Returns: `true` when the caller should reset the surface's agent
    ///   state to `.idle`; `false` otherwise.
    static func shouldResetOnShellPrompt(
        currentState: AgentState,
        foregroundProcessName: String?
    ) -> Bool {
        guard currentState != .idle else { return false }

        guard let raw = foregroundProcessName else { return false }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        return knownShellBinaries.contains(trimmed.lowercased())
    }
}
