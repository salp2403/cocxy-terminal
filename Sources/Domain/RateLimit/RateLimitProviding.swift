// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RateLimitProviding.swift - Protocol for per-agent rate-limit
// providers consumed by `RateLimitProbeService`.

import Foundation

/// Provider that produces a `RateLimitSnapshot` for a specific agent.
///
/// Implementations read **only** local data the user already has on
/// disk — no telemetry, no network calls, no external API hits. Cocxy
/// guarantees zero outgoing data; rate-limit indicators that cannot be
/// computed from local files return `nil` rather than calling out.
///
/// `snapshot()` is async so providers can perform file I/O off the
/// main thread without blocking the polling probe service. Returning
/// `nil` is the legitimate way to signal "no data available" — the
/// probe service hides the pill silently in that case so a missing CLI
/// or a dormant agent never surfaces as an error banner.
protocol RateLimitProviding: Sendable {

    /// Agent the provider tracks. Always set so the probe service can
    /// dispatch by agent without inspecting the snapshot.
    var agent: RateLimitSnapshot.AgentKind { get }

    /// Produces the current snapshot, or `nil` when no local data is
    /// available (CLI not installed, files missing, capability not
    /// granted by the user). Implementations MUST NOT throw — every
    /// failure path translates to `nil`.
    func snapshot() async -> RateLimitSnapshot?
}
