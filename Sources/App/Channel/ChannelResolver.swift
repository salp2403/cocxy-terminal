// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ChannelResolver.swift - Resolves the app's current update channel.

import Foundation

struct ChannelResolver: Sendable {
    private let bundleIdentifierProvider: @Sendable () -> String?

    init(bundleIdentifierProvider: @escaping @Sendable () -> String? = {
        Bundle.main.bundleIdentifier
    }) {
        self.bundleIdentifierProvider = bundleIdentifierProvider
    }

    func currentChannel() -> ChannelKind {
        ChannelKind(bundleIdentifier: bundleIdentifierProvider())
    }
}
