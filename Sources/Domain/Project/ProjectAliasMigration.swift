// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectAliasMigration.swift - Legacy alias discovery for canonical writes.

import Foundation

enum LegacyProjectAliasIdentityResolver {
    static func identity(
        for directory: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        maximumDepth: Int = 12
    ) -> String {
        var current = directory.standardizedFileURL
        let home = homeDirectory.standardizedFileURL
        for _ in 0..<maximumDepth {
            if current == home { break }
            if FileManager.default.fileExists(
                atPath: current.appendingPathComponent(".git").path
            ) {
                return current.path
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent == current { break }
            current = parent
        }
        return directory.standardizedFileURL.path
    }
}

@MainActor
enum ProjectAliasMigrationPlanner {
    static func legacyIdentities(
        for projectID: ProjectID,
        directories: [URL],
        requestedDirectory: URL?,
        projectResolver: any ProjectResolving
    ) -> Set<String> {
        var identities: Set<String> = []
        for directory in directories {
            let descriptor = projectResolver.resolveProject(for: directory)
            guard descriptor.groupingID == projectID else { continue }
            identities.insert(descriptor.id.rawValue)
            identities.insert(LegacyProjectAliasIdentityResolver.identity(for: directory))
        }
        if let requestedDirectory,
           projectResolver.resolveProject(for: requestedDirectory).groupingID == projectID {
            identities.insert(LegacyProjectAliasIdentityResolver.identity(for: requestedDirectory))
        }
        identities.remove(projectID.rawValue)
        return identities
    }
}
