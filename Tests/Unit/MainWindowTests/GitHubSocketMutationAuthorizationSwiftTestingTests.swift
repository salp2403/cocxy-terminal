// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("GitHub socket mutation approval")
struct GitHubSocketMutationAuthorizationSwiftTestingTests {
    @Test("approval is bound to the active tab and consumed once")
    func approvalIsContextBoundAndSingleUse() throws {
        let fixture = try makeFixture()
        let request = makeRequest(
            controller: fixture.controller,
            tabID: fixture.tabID,
            directory: fixture.directory
        )
        var presentationCount = 0
        fixture.controller.githubSocketMutationAuthorizationPresenter = { received in
            presentationCount += 1
            return received == request
        }

        #expect(fixture.controller.authorizeGitHubSocketMutation(request) != nil)
        #expect(fixture.controller.authorizeGitHubSocketMutation(request) == nil)
        #expect(presentationCount == 1)
    }

    @Test("changing the active tab context during approval fails closed")
    func changedContextFailsClosed() throws {
        let fixture = try makeFixture()
        let request = makeRequest(
            controller: fixture.controller,
            tabID: fixture.tabID,
            directory: fixture.directory
        )
        fixture.controller.githubSocketMutationAuthorizationPresenter = { _ in
            fixture.controller.tabManager.updateTab(id: fixture.tabID) {
                $0.workingDirectory = URL(fileURLWithPath: "/tmp/cocxy-github-after")
            }
            return true
        }

        #expect(fixture.controller.authorizeGitHubSocketMutation(request) == nil)
    }

    @Test("expired requests never reach the presenter")
    func expiredRequestsNeverReachPresenter() throws {
        let fixture = try makeFixture()
        let request = GitHubSocketMutationAuthorizationRequest(
            intent: .review(
                pullRequestNumber: 42,
                action: .approve,
                body: nil
            ),
            context: makeContext(
                controller: fixture.controller,
                tabID: fixture.tabID,
                directory: fixture.directory
            ),
            createdAt: Date(timeIntervalSince1970: 0),
            lifetime: 1
        )
        var presentationCount = 0
        fixture.controller.githubSocketMutationAuthorizationPresenter = { _ in
            presentationCount += 1
            return true
        }

        #expect(fixture.controller.authorizeGitHubSocketMutation(request) == nil)
        #expect(presentationCount == 0)
    }

    @Test("approval preview escapes invisible controls and backslashes")
    func approvalPreviewEscapesInvisibleControls() throws {
        let fixture = try makeFixture()
        let request = GitHubSocketMutationAuthorizationRequest(
            intent: .review(
                pullRequestNumber: 42,
                action: .requestChanges,
                body: "line\\path\u{202E}\nnext\u{0007}"
            ),
            context: makeContext(
                controller: fixture.controller,
                tabID: fixture.tabID,
                directory: fixture.directory
            )
        )

        let preview = GitHubSocketMutationSecurity.approvalPreview(request)
        #expect(preview.contains("line\\\\path\\u{202E}\\n\nnext\\u{0007}"))
        #expect(!preview.contains("\u{202E}"))
        #expect(!preview.contains("\u{0007}"))
    }

    private func makeFixture() throws -> (
        controller: MainWindowController,
        tabID: TabID,
        directory: URL
    ) {
        let controller = MainWindowController(
            bridge: MockTerminalEngine(),
            deferContentSetup: true
        )
        let directory = URL(fileURLWithPath: "/tmp/cocxy-github-approval")
        let tab = controller.tabManager.addTab(workingDirectory: directory)
        return (controller, tab.id, directory)
    }

    private func makeRequest(
        controller: MainWindowController,
        tabID: TabID,
        directory: URL
    ) -> GitHubSocketMutationAuthorizationRequest {
        GitHubSocketMutationAuthorizationRequest(
            intent: .merge(GitHubMergeRequest(
                pullRequestNumber: 42,
                method: .squash,
                deleteBranch: false,
                subject: "Ship it",
                body: "Reviewed"
            )),
            context: makeContext(
                controller: controller,
                tabID: tabID,
                directory: directory
            )
        )
    }

    private func makeContext(
        controller: MainWindowController,
        tabID: TabID,
        directory: URL
    ) -> GitHubSocketMutationContext {
        GitHubSocketMutationContext(
            windowControllerIdentifier: ObjectIdentifier(controller),
            tabID: tabID,
            workingDirectory: directory,
            repository: GitHubRepositoryAuthority(
                host: "github.com",
                ownerLogin: "owner",
                name: "repo"
            )!
        )
    }
}
