// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodexUsageProvider.swift - Local-only provider that returns `nil`
// until the CLI ships a stable, documented local usage surface.

import Foundation

/// Local-only `RateLimitProviding` implementation for Codex CLI.
///
/// ## Why this provider returns `nil`
///
/// At the time of writing, the Codex CLI does not publish a stable,
/// documented, locally-reachable surface that exposes billable token
/// usage:
///
///   * `~/.codex/state_5.sqlite` is internal CLI state with an
///     undocumented schema and grows across CLI versions. The
///     `threads.tokens_used` column also includes context, prompt
///     cache, and plugin/skill overhead rather than billable tokens,
///     so the value can be one to two orders of magnitude larger than
///     what an account dashboard would report.
///   * `~/.codex/logs_2.sqlite` is similarly undocumented, grows
///     unboundedly, and contains conversation transcripts which are
///     PII. Reading it without an audited schema is unsafe.
///   * `~/.codex/session_index.jsonl` does not include token counts
///     in any version observed locally.
///   * `codex exec --json` emits state events but the schema does not
///     document a stable token-usage payload.
///
/// Official CLI guidance directs users to the account dashboard for
/// accurate token accounting. Cocxy guarantees zero
/// outgoing telemetry (principio inmutable del proyecto), so
/// consulting that dashboard remotely is also ruled out.
///
/// The provider therefore returns `nil` deliberately. The probe
/// service hides the pill silently on `nil`, which is exactly the
/// contract `RateLimitProviding` documents for "no reliable data
/// available":
///
/// > Returning `nil` is the legitimate way to signal "no data
/// > available" — the probe service hides the pill silently in that
/// > case so a missing CLI or a dormant agent never surfaces as an
/// > error banner.
///
/// ## When to update this provider
///
/// When the CLI ships a documented, programmatic, locally-reachable
/// surface for usage data, the provider implementation can change in
/// place without touching the wiring in `MainWindowController`. The
/// closed `RateLimitSnapshot` value type is already shared across
/// providers, so a future implementation only needs to:
///
///   1. Read the new local surface (file or local socket).
///   2. Aggregate values inside the polling window.
///   3. Return a `RateLimitSnapshot(agent: .codex, ...)`.
///
/// ## Why register the provider at all
///
/// Even though `snapshot()` returns `nil` today, the provider is
/// registered in `MainWindowController.rateLimitProbeService` so that
/// `RateLimitAgentResolver.kind(for:)` can map a detected Codex agent
/// onto the canonical `.codex` enum case without producing a "no
/// provider registered" hole. The probe service treats a `nil`
/// snapshot identically to an unregistered provider for rendering
/// purposes (the pill hides), but registering the provider keeps the
/// wiring uniform across agents and lets a future swap-in implementation
/// take effect with no callsite changes.
struct CodexUsageProvider: RateLimitProviding {

    /// Agent the provider tracks. Always `.codex` so the probe service
    /// can dispatch by agent without inspecting the snapshot.
    let agent: RateLimitSnapshot.AgentKind = .codex

    /// Default initializer with no parameters — the provider has no
    /// configurable knobs because it has no usable data source today.
    /// Once a future implementation reads a local surface, this
    /// initializer can grow parameters without breaking call sites
    /// (the existing `MainWindowController` registration uses the
    /// no-argument form).
    init() {}

    // MARK: - RateLimitProviding

    /// Returns `nil` so the rate-limit pill hides silently for Codex.
    ///
    /// See the type-level documentation above for the rationale: the
    /// Codex CLI does not currently expose a stable, documented,
    /// locally-reachable surface for billable token usage, and Cocxy's
    /// zero-telemetry contract rules out consulting the account
    /// dashboard remotely.
    func snapshot() async -> RateLimitSnapshot? {
        nil
    }
}
