// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WorktreeTemplate.swift - Built-in presets for advanced worktree creation.

import Foundation

enum WorktreeBranchKind: String, Codable, CaseIterable, Sendable, Equatable {
    case feature
    case hotfix
    case experiment
}

struct WorktreeTemplate: Identifiable, Codable, Sendable, Equatable {
    let id: String
    let displayName: String
    let description: String
    let branchKind: WorktreeBranchKind
    let branchPattern: String
    let defaultBaseRef: String

    static let feature = WorktreeTemplate(
        id: "feature",
        displayName: "Feature Branch",
        description: "New feature work isolated from the origin repository.",
        branchKind: .feature,
        branchPattern: "feat/{slug}-{id}",
        defaultBaseRef: "HEAD"
    )

    static let hotfix = WorktreeTemplate(
        id: "hotfix",
        displayName: "Hotfix",
        description: "Small urgent fix with an optional issue key.",
        branchKind: .hotfix,
        branchPattern: "fix/{issue}/{slug}",
        defaultBaseRef: "HEAD"
    )

    static let experiment = WorktreeTemplate(
        id: "experiment",
        displayName: "Experiment",
        description: "Disposable spike or prototype branch.",
        branchKind: .experiment,
        branchPattern: "experiment/{slug}-{id}",
        defaultBaseRef: "HEAD"
    )

    static let builtIns: [WorktreeTemplate] = [
        .feature,
        .hotfix,
        .experiment
    ]

    func localizedDisplayName(using localizer: AppLocalizer) -> String {
        localizer.string("worktree.template.\(id).name", fallback: displayName)
    }

    func localizedDescription(using localizer: AppLocalizer) -> String {
        localizer.string("worktree.template.\(id).description", fallback: description)
    }
}

struct WorktreeAdvancedCreationRequest: Sendable, Equatable {
    let templateID: String
    let branch: String
    let baseRef: String
    let agent: String?

    var cliParams: [String: String] {
        var params = [
            "branch": branch,
            "base-ref": baseRef
        ]
        if let agent, !agent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            params["agent"] = agent
        }
        return params
    }
}
