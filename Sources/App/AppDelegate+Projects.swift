// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppDelegate+Projects.swift - App-wide project change propagation.

import Combine
import Foundation

extension AppDelegate {
    func startProjectChangeBroadcasting() {
        projectRegistryChangeCancellable?.cancel()
        let metadataChanges = projectRegistry.$records.dropFirst().map { _ in () }
        let aliasChanges = auroraWorkspaceTitleStore.$revision.dropFirst().map { _ in () }
        projectRegistryChangeCancellable = Publishers.Merge(metadataChanges, aliasChanges)
            .sink { [weak self] in
                self?.windowEventBus?.broadcast(
                    .custom(name: "project.changed", payload: [:])
                )
            }
    }
}
