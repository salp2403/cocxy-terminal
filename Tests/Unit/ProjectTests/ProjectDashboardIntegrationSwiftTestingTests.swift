// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Project identity in the agent dashboard")
struct ProjectDashboardIntegrationSwiftTestingTests {
    private final class StubProjectResolver: ProjectResolving {
        let descriptors: [String: ProjectDescriptor]

        init(descriptors: [String: ProjectDescriptor]) {
            self.descriptors = descriptors
        }

        func resolveProject(for directory: URL) -> ProjectDescriptor {
            descriptors[directory.standardizedFileURL.path]
                ?? ProjectDescriptor(
                    id: ProjectID(rootURL: directory),
                    rootURL: directory.standardizedFileURL,
                    automaticName: directory.lastPathComponent,
                    displayName: directory.lastPathComponent,
                    parent: nil
                )
        }

        func invalidate(directory: URL) {}
        func invalidateAll() {}
    }

    @Test("same-basename repositories remain distinguishable")
    func sameBasenameRepositoriesRemainDistinct() {
        let first = URL(fileURLWithPath: "/Users/alice/sites/html", isDirectory: true)
        let second = URL(fileURLWithPath: "/Users/alice/archive/html", isDirectory: true)
        let resolver = StubProjectResolver(descriptors: [
            first.path: descriptor(root: first),
            second.path: descriptor(root: second),
        ])
        let viewModel = AgentDashboardViewModel(projectResolver: resolver)

        viewModel.processDetectionSignal(
            agentName: "Agent A", state: .working, tabId: UUID(), workingDirectory: first.path
        )
        viewModel.processDetectionSignal(
            agentName: "Agent B", state: .working, tabId: UUID(), workingDirectory: second.path
        )

        #expect(viewModel.sessions.map(\.projectName) == ["html", "html"])
        #expect(Set(viewModel.sessions.compactMap(\.projectIdentity)).count == 2)
        #expect(Set(viewModel.sessions.compactMap(\.projectLocationLabel)).count == 2)
    }

    @Test("linked worktree sessions group under the origin project")
    func worktreeSessionUsesOriginIdentity() {
        let origin = URL(fileURLWithPath: "/Users/alice/code/cocxy", isDirectory: true)
        let worktree = URL(fileURLWithPath: "/Users/alice/worktrees/feature", isDirectory: true)
        let resolver = StubProjectResolver(descriptors: [
            worktree.path: ProjectDescriptor(
                id: ProjectID(rootURL: worktree),
                rootURL: worktree,
                automaticName: "feature",
                displayName: "feature",
                parent: ProjectID(rootURL: origin)
            ),
        ])
        let viewModel = AgentDashboardViewModel(projectResolver: resolver)

        viewModel.processDetectionSignal(
            agentName: "Agent", state: .working, tabId: UUID(), workingDirectory: worktree.path
        )

        guard let session = viewModel.sessions.first else {
            Issue.record("Expected one dashboard session")
            return
        }
        #expect(session.projectName == "cocxy")
        #expect(session.projectIdentity == ProjectID(rootURL: origin))
    }

    private func descriptor(root: URL) -> ProjectDescriptor {
        ProjectDescriptor(
            id: ProjectID(rootURL: root),
            rootURL: root,
            automaticName: root.lastPathComponent,
            displayName: root.lastPathComponent,
            parent: nil
        )
    }
}
