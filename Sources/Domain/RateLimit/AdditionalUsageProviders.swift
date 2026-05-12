// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AdditionalUsageProviders.swift - Concrete local usage providers
// backed by fail-soft file readers.

import Foundation

private enum UsageProviderDefaults {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static func urls(_ relativePaths: [String]) -> [URL] {
        relativePaths.map { home.appendingPathComponent($0) }
    }
}

struct CursorUsageProvider: RateLimitProviding {
    let agent: RateLimitSnapshot.AgentKind = .cursor
    private let provider: LocalUsageFileProvider

    init(
        usageFiles: [URL] = UsageProviderDefaults.urls([
            "Library/Application Support/Cursor/User/globalStorage/cocxy/usage.json",
            "Library/Application Support/Cursor/User/globalStorage/cocxy/usage.jsonl",
            ".cursor/usage.json",
            ".cursor/usage.jsonl",
        ]),
        now: @escaping @Sendable () -> Date = { Date() },
        aggregationWindow: TimeInterval = 60 * 60 * 24
    ) {
        provider = LocalUsageFileProvider(
            agent: .cursor,
            usageFiles: usageFiles,
            aggregationWindow: aggregationWindow,
            now: now
        )
    }

    func snapshot() async -> RateLimitSnapshot? { await provider.snapshot() }
}

struct CopilotUsageProvider: RateLimitProviding {
    let agent: RateLimitSnapshot.AgentKind = .copilot
    private let provider: LocalUsageFileProvider

    init(
        usageFiles: [URL] = UsageProviderDefaults.urls([
            "Library/Application Support/Code/User/globalStorage/github.copilot/usage.json",
            "Library/Application Support/Code/User/globalStorage/github.copilot-chat/usage.json",
            ".config/github-copilot/usage.json",
            ".config/github-copilot/usage.jsonl",
        ]),
        now: @escaping @Sendable () -> Date = { Date() },
        aggregationWindow: TimeInterval = 60 * 60 * 24
    ) {
        provider = LocalUsageFileProvider(
            agent: .copilot,
            usageFiles: usageFiles,
            aggregationWindow: aggregationWindow,
            now: now
        )
    }

    func snapshot() async -> RateLimitSnapshot? { await provider.snapshot() }
}

struct OpenCodeUsageProvider: RateLimitProviding {
    let agent: RateLimitSnapshot.AgentKind = .opencode
    private let provider: LocalUsageFileProvider

    init(
        usageFiles: [URL] = UsageProviderDefaults.urls([
            ".opencode/usage.json",
            ".opencode/usage.jsonl",
            ".config/opencode/usage.json",
            ".config/opencode/usage.jsonl",
        ]),
        now: @escaping @Sendable () -> Date = { Date() },
        aggregationWindow: TimeInterval = 60 * 60 * 24
    ) {
        provider = LocalUsageFileProvider(
            agent: .opencode,
            usageFiles: usageFiles,
            aggregationWindow: aggregationWindow,
            now: now
        )
    }

    func snapshot() async -> RateLimitSnapshot? { await provider.snapshot() }
}

struct AmpUsageProvider: RateLimitProviding {
    let agent: RateLimitSnapshot.AgentKind = .amp
    private let provider: LocalUsageFileProvider

    init(
        usageFiles: [URL] = UsageProviderDefaults.urls([
            ".amp/usage.json",
            ".amp/usage.jsonl",
            ".config/amp/usage.json",
            ".config/amp/usage.jsonl",
        ]),
        now: @escaping @Sendable () -> Date = { Date() },
        aggregationWindow: TimeInterval = 60 * 60 * 24
    ) {
        provider = LocalUsageFileProvider(
            agent: .amp,
            usageFiles: usageFiles,
            aggregationWindow: aggregationWindow,
            now: now
        )
    }

    func snapshot() async -> RateLimitSnapshot? { await provider.snapshot() }
}

struct FactoryUsageProvider: RateLimitProviding {
    let agent: RateLimitSnapshot.AgentKind = .factory
    private let provider: LocalUsageFileProvider

    init(
        usageFiles: [URL] = UsageProviderDefaults.urls([
            ".factory/usage.json",
            ".factory/usage.jsonl",
            ".config/factory/usage.json",
            ".config/factory/usage.jsonl",
        ]),
        now: @escaping @Sendable () -> Date = { Date() },
        aggregationWindow: TimeInterval = 60 * 60 * 24
    ) {
        provider = LocalUsageFileProvider(
            agent: .factory,
            usageFiles: usageFiles,
            aggregationWindow: aggregationWindow,
            now: now
        )
    }

    func snapshot() async -> RateLimitSnapshot? { await provider.snapshot() }
}

struct KimiUsageProvider: RateLimitProviding {
    let agent: RateLimitSnapshot.AgentKind = .kimi
    private let provider: LocalUsageFileProvider

    init(
        usageFiles: [URL] = UsageProviderDefaults.urls([
            ".kimi/usage.json",
            ".kimi/usage.jsonl",
            ".config/kimi/usage.json",
            ".config/kimi/usage.jsonl",
        ]),
        now: @escaping @Sendable () -> Date = { Date() },
        aggregationWindow: TimeInterval = 60 * 60 * 24
    ) {
        provider = LocalUsageFileProvider(
            agent: .kimi,
            usageFiles: usageFiles,
            aggregationWindow: aggregationWindow,
            now: now
        )
    }

    func snapshot() async -> RateLimitSnapshot? { await provider.snapshot() }
}

struct MiniMaxUsageProvider: RateLimitProviding {
    let agent: RateLimitSnapshot.AgentKind = .minimax
    private let provider: LocalUsageFileProvider

    init(
        usageFiles: [URL] = UsageProviderDefaults.urls([
            ".minimax/usage.json",
            ".minimax/usage.jsonl",
            ".config/minimax/usage.json",
            ".config/minimax/usage.jsonl",
        ]),
        now: @escaping @Sendable () -> Date = { Date() },
        aggregationWindow: TimeInterval = 60 * 60 * 24
    ) {
        provider = LocalUsageFileProvider(
            agent: .minimax,
            usageFiles: usageFiles,
            aggregationWindow: aggregationWindow,
            now: now
        )
    }

    func snapshot() async -> RateLimitSnapshot? { await provider.snapshot() }
}

struct ZaiUsageProvider: RateLimitProviding {
    let agent: RateLimitSnapshot.AgentKind = .zai
    private let provider: LocalUsageFileProvider

    init(
        usageFiles: [URL] = UsageProviderDefaults.urls([
            ".zai/usage.json",
            ".zai/usage.jsonl",
            ".z-ai/usage.json",
            ".z-ai/usage.jsonl",
            ".config/zai/usage.json",
            ".config/zai/usage.jsonl",
        ]),
        now: @escaping @Sendable () -> Date = { Date() },
        aggregationWindow: TimeInterval = 60 * 60 * 24
    ) {
        provider = LocalUsageFileProvider(
            agent: .zai,
            usageFiles: usageFiles,
            aggregationWindow: aggregationWindow,
            now: now
        )
    }

    func snapshot() async -> RateLimitSnapshot? { await provider.snapshot() }
}
