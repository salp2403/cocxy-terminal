// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Additional local usage providers")
struct AdditionalUsageProvidersSwiftTestingTests {

    private static let providerCases: [(RateLimitSnapshot.AgentKind, any RateLimitProviding)] = [
        (.cursor, CursorUsageProvider(usageFiles: [])),
        (.copilot, CopilotUsageProvider(usageFiles: [])),
        (.opencode, OpenCodeUsageProvider(usageFiles: [])),
        (.amp, AmpUsageProvider(usageFiles: [])),
        (.factory, FactoryUsageProvider(usageFiles: [])),
        (.kimi, KimiUsageProvider(usageFiles: [])),
        (.minimax, MiniMaxUsageProvider(usageFiles: [])),
        (.zai, ZaiUsageProvider(usageFiles: [])),
    ]

    private let frozenNow = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("all added providers expose their canonical agent kind")
    func providersExposeCanonicalKind() {
        for (expected, provider) in Self.providerCases {
            #expect(provider.agent == expected)
        }
    }

    @Test("all added providers fail soft when local usage files are missing")
    func providersReturnNilForMissingLocalFiles() async {
        let missingFile = URL(fileURLWithPath: "/tmp/cocxy-rate-limit-missing-\(UUID().uuidString).json")
        let providers: [any RateLimitProviding] = [
            CursorUsageProvider(usageFiles: [missingFile]),
            CopilotUsageProvider(usageFiles: [missingFile]),
            OpenCodeUsageProvider(usageFiles: [missingFile]),
            AmpUsageProvider(usageFiles: [missingFile]),
            FactoryUsageProvider(usageFiles: [missingFile]),
            KimiUsageProvider(usageFiles: [missingFile]),
            MiniMaxUsageProvider(usageFiles: [missingFile]),
            ZaiUsageProvider(usageFiles: [missingFile]),
        ]

        for provider in providers {
            await #expect(provider.snapshot() == nil)
        }
    }

    @Test("JSON fixtures aggregate input and output tokens without reading conversational fields")
    func jsonFixtureAggregatesTokens() async throws {
        let file = try writeFixture(
            name: "cursor-usage.json",
            contents: """
            {
              "timestamp": "2027-01-15T08:00:00Z",
              "input_tokens": 1200,
              "output_tokens": 300,
              "limit": 3000,
              "prompt": "must not be needed"
            }
            """
        )
        let provider = CursorUsageProvider(
            usageFiles: [file],
            now: { frozenNow },
            aggregationWindow: 60 * 60
        )

        let snapshot = await provider.snapshot()

        #expect(snapshot?.agent == .cursor)
        #expect(snapshot?.usedAmount == 1500)
        #expect(snapshot?.limitAmount == 3000)
        #expect(snapshot?.usagePercent == 0.5)
        #expect(snapshot?.unit == .tokens)
    }

    @Test("JSONL fixtures ignore malformed and stale rows")
    func jsonlFixtureFiltersWindowAndMalformedRows() async throws {
        let file = try writeFixture(
            name: "opencode-usage.jsonl",
            contents: """
            {"timestamp":"2027-01-15T07:55:00Z","tokens_used":400,"token_limit":1000}
            {"timestamp":"2027-01-14T07:55:00Z","tokens_used":900,"token_limit":1000}
            {"timestamp":"2027-01-15T07:56:00Z","tokens_used":"bad"}
            not-json
            {"updated_at":1800000000,"total_tokens":100,"token_limit":1000}
            """
        )
        let provider = OpenCodeUsageProvider(
            usageFiles: [file],
            now: { frozenNow },
            aggregationWindow: 60 * 60
        )

        let snapshot = await provider.snapshot()

        #expect(snapshot?.agent == .opencode)
        #expect(snapshot?.usedAmount == 500)
        #expect(snapshot?.limitAmount == 1000)
        #expect(snapshot?.unit == .tokens)
    }

    @Test("malformed local files return nil instead of surfacing errors")
    func malformedFilesReturnNil() async throws {
        let file = try writeFixture(name: "bad.json", contents: "{not valid json")
        let provider = KimiUsageProvider(usageFiles: [file], now: { frozenNow })

        await #expect(provider.snapshot() == nil)
    }

    @Test("resolver maps active provider names to rate-limit kinds")
    func resolverMapsProviderNames() {
        #expect(RateLimitAgentResolver.kind(name: "cursor-agent") == .cursor)
        #expect(RateLimitAgentResolver.kind(name: "agent", displayName: "Copilot CLI") == .copilot)
        #expect(RateLimitAgentResolver.kind(name: "opencode") == .opencode)
        #expect(RateLimitAgentResolver.kind(name: "amp") == .amp)
        #expect(RateLimitAgentResolver.kind(name: "factory") == .factory)
        #expect(RateLimitAgentResolver.kind(name: "kimi-k2") == .kimi)
        #expect(RateLimitAgentResolver.kind(name: "minimax") == .minimax)
        #expect(RateLimitAgentResolver.kind(name: "z-ai") == .zai)
    }

    private func writeFixture(name: String, contents: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-rate-limit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent(name)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
}
