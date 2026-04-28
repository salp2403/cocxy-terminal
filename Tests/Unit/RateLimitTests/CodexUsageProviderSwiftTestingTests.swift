// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

/// Unit coverage for `CodexUsageProvider`.
///
/// At the time of writing, Codex CLI does not publish a
/// stable, documented surface that exposes locally-observable token
/// usage:
///
///   * `~/.codex/state_5.sqlite` is internal CLI state with an
///     undocumented schema and is subject to change. The
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
/// outgoing telemetry, so consulting that dashboard remotely is also
/// ruled out.
///
/// The provider therefore returns `nil` deliberately. The probe
/// service hides the pill silently on `nil`, which is exactly the
/// contract `RateLimitProviding` documents for "no reliable data
/// available". When the CLI ships a documented, programmatic, locally
/// reachable surface, the provider implementation can change in place
/// without touching the wiring in `MainWindowController`.
@Suite("CodexUsageProvider")
struct CodexUsageProviderSwiftTestingTests {

    @Test("agent kind is .codex so the probe service registers the provider against the canonical enum case")
    func agentKindIsCodex() {
        let provider = CodexUsageProvider()

        #expect(provider.agent == .codex)
    }

    @Test("snapshot returns nil deliberately so the pill hides silently for Codex until a stable usage surface exists")
    func snapshotReturnsNilDeliberately() async {
        let provider = CodexUsageProvider()

        let snapshot = await provider.snapshot()

        #expect(snapshot == nil)
    }

    @Test("snapshot stays nil across repeated calls so the polling probe never observes a transient value")
    func snapshotIsIdempotentlyNil() async {
        let provider = CodexUsageProvider()

        let first = await provider.snapshot()
        let second = await provider.snapshot()
        let third = await provider.snapshot()

        #expect(first == nil)
        #expect(second == nil)
        #expect(third == nil)
    }

    @Test("provider value-types are equal when constructed with the default initializer so the probe service treats them as a single registration")
    func providersWithDefaultInitAreEquivalent() {
        let lhs = CodexUsageProvider()
        let rhs = CodexUsageProvider()

        #expect(lhs.agent == rhs.agent)
    }
}
