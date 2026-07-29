// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

struct AuroraWorkspaceDescriptor: Equatable, Sendable {
    let identity: String
    let automaticName: String
    let rootPath: String
}

/// Pure workspace identity and rename policy shared by Aurora source
/// construction and the window-level rename flow.
enum AuroraWorkspacePlanner {

    static func descriptor(
        for tab: Tab,
        resolver: AuroraWorkspaceRootResolver
    ) -> AuroraWorkspaceDescriptor {
        let root = (resolver.workspaceRoot(for: tab.workingDirectory) ?? tab.workingDirectory)
            .standardizedFileURL
        let path = root.path
        let identity = path.isEmpty ? "tab:\(tab.id.rawValue.uuidString)" : path
        let folderName = root.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let automaticName: String
        if !folderName.isEmpty {
            automaticName = folderName
        } else if path == "/" {
            automaticName = "root"
        } else {
            automaticName = tab.id.rawValue.uuidString
        }

        return AuroraWorkspaceDescriptor(
            identity: identity,
            automaticName: automaticName,
            rootPath: path
        )
    }

    static func normalizedTitle(_ rawValue: String?) -> String? {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    static func matchingTabIDs(
        workspaceID: String,
        in tabs: [Tab],
        resolver: AuroraWorkspaceRootResolver
    ) -> [TabID] {
        tabs.compactMap { tab in
            descriptor(for: tab, resolver: resolver).identity == workspaceID ? tab.id : nil
        }
    }

    static func legacyTitlesByIdentity(
        from tabs: [Tab],
        resolver: AuroraWorkspaceRootResolver
    ) -> [String: String] {
        var result: [String: String] = [:]
        for tab in tabs {
            guard let title = normalizedTitle(tab.workspaceCustomTitle) else { continue }
            let identity = descriptor(for: tab, resolver: resolver).identity
            if result[identity] == nil {
                result[identity] = title
            }
        }
        return result
    }
}
