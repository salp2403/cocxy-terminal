// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Combine
import Foundation

/// Local workspace aliases keyed by canonical Aurora workspace identity.
/// An empty stored value is an intentional reset to the automatic folder
/// name, preventing a legacy per-tab alias from reappearing after restart.
@MainActor
final class AuroraWorkspaceTitleStore: ObservableObject {
    private static let defaultStorageKey = "aurora.workspace-titles.v1"

    private let defaults: UserDefaults
    private let storageKey: String
    private var storedValues: [String: String]
    @Published private(set) var revision: UInt64 = 0

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = AuroraWorkspaceTitleStore.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.storedValues = defaults.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }

    var snapshot: [String: String] {
        storedValues
    }

    func title(for identity: String) -> String? {
        AuroraWorkspacePlanner.normalizedTitle(storedValues[identity])
    }

    func setTitle(
        _ title: String?,
        for identity: String,
        migrating legacyIdentities: Set<String> = []
    ) {
        storedValues[identity] = AuroraWorkspacePlanner.normalizedTitle(title) ?? ""
        for legacyIdentity in legacyIdentities where legacyIdentity != identity {
            storedValues.removeValue(forKey: legacyIdentity)
        }
        persist()
    }

    func mergeMissing(_ titlesByIdentity: [String: String]) {
        var didChange = false
        for (identity, title) in titlesByIdentity where storedValues[identity] == nil {
            guard let normalized = AuroraWorkspacePlanner.normalizedTitle(title) else { continue }
            storedValues[identity] = normalized
            didChange = true
        }
        if didChange {
            persist()
        }
    }

    private func persist() {
        defaults.set(storedValues, forKey: storageKey)
        revision &+= 1
    }
}
