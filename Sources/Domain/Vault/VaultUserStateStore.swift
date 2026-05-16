// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// VaultUserStateStore.swift - User-facing Vault state shared by app and CLI.

import Foundation

public final class VaultUserStateStore {
    public enum Key {
        public static let pinnedSessionIDs = "vaultSidebar.pinnedSessionIDs"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var pinnedSessionIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.pinnedSessionIDs) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.pinnedSessionIDs) }
    }

    public func setPinned(_ pinned: Bool, sessionID: String) {
        let trimmedID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return }
        var ids = pinnedSessionIDs
        if pinned {
            ids.insert(trimmedID)
        } else {
            ids.remove(trimmedID)
        }
        pinnedSessionIDs = ids
    }
}
