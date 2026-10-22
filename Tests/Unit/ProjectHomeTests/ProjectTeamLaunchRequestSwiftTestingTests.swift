// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ProjectTeamLaunchRequestSwiftTestingTests.swift - Project team launch validation coverage.

import Testing
@testable import CocxyTerminal

@Suite("Project team launch request")
struct ProjectTeamLaunchRequestSwiftTestingTests {
    @Test("normalizes identifiers and trims user input")
    func normalizesValidRequest() throws {
        let request = try ProjectTeamLaunchRequest.make(
            teamName: "  Release Review  ",
            provider: .codex,
            teammates: " implementation, review ",
            prompt: "  Verify the project end to end.  "
        )

        #expect(request.teamID == "release-review")
        #expect(request.provider == .codex)
        #expect(request.teammateNames == ["implementation", "review"])
        #expect(request.prompt == "Verify the project end to end.")
    }

    @Test("rejects incomplete and oversized requests")
    func rejectsInvalidRequests() {
        #expect(throws: ProjectTeamLaunchError.emptyTeamName) {
            try ProjectTeamLaunchRequest.make(
                teamName: " ", provider: .codex, teammates: "review", prompt: "Task"
            )
        }
        #expect(throws: ProjectTeamLaunchError.missingProvider) {
            try ProjectTeamLaunchRequest.make(
                teamName: "team", provider: nil, teammates: "review", prompt: "Task"
            )
        }
        #expect(throws: ProjectTeamLaunchError.emptyTeammates) {
            try ProjectTeamLaunchRequest.make(
                teamName: "team", provider: .codex, teammates: " ", prompt: "Task"
            )
        }
        let tooMany = (0...ProjectTeamLaunchRequest.maximumTeammates)
            .map { "member-\($0)" }
            .joined(separator: ",")
        #expect(throws: ProjectTeamLaunchError.tooManyTeammates(
            maximum: ProjectTeamLaunchRequest.maximumTeammates
        )) {
            try ProjectTeamLaunchRequest.make(
                teamName: "team", provider: .codex, teammates: tooMany, prompt: "Task"
            )
        }
        #expect(throws: ProjectTeamLaunchError.emptyPrompt) {
            try ProjectTeamLaunchRequest.make(
                teamName: "team", provider: .codex, teammates: "review", prompt: " "
            )
        }
        let oversizedPrompt = String(
            repeating: "x",
            count: ProjectTeamLaunchRequest.maximumPromptBytes + 1
        )
        #expect(throws: ProjectTeamLaunchError.promptTooLarge(
            maximumBytes: ProjectTeamLaunchRequest.maximumPromptBytes
        )) {
            try ProjectTeamLaunchRequest.make(
                teamName: "team",
                provider: .codex,
                teammates: "review",
                prompt: oversizedPrompt
            )
        }
    }
}
