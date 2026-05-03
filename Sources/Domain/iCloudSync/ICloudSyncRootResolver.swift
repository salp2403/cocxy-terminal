// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ICloudSyncRootResolver.swift - iCloud Drive root resolution behind an opt-in gate.

import Foundation

protocol ICloudContainerProviding: Sendable {
    func iCloudDocumentsDirectory() -> URL?
}

struct FileManagerICloudContainerProvider: ICloudContainerProviding {
    func iCloudDocumentsDirectory() -> URL? {
        FileManager.default
            .url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)
    }
}

enum ICloudSyncRootResolution: Sendable, Equatable {
    case disabled
    case unavailable
    case available(URL)
}

struct ICloudSyncRootResolver: Sendable {
    private let containerProvider: any ICloudContainerProviding

    init(containerProvider: any ICloudContainerProviding = FileManagerICloudContainerProvider()) {
        self.containerProvider = containerProvider
    }

    func resolveRoot(for config: ICloudSyncConfig) -> ICloudSyncRootResolution {
        guard config.enabled else { return .disabled }
        guard let iCloudRoot = containerProvider.iCloudDocumentsDirectory() else {
            return .unavailable
        }
        return .available(
            iCloudRoot.appendingPathComponent(config.syncDirectoryName, isDirectory: true)
        )
    }
}
