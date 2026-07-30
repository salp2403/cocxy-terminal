// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import CocxyShared
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Task handoff destination")
struct TaskHandoffDestinationSwiftTestingTests {
    @Test("provider aliases resolve to one canonical destination")
    func aliasesResolveCanonically() throws {
        #expect(try TaskHandoffDestination.make(
            agent: " Claude ",
            artifact: "# Task Handoff"
        ).provider == .claudeCode)
        #expect(try TaskHandoffDestination.make(
            agent: "open-code",
            artifact: "# Task Handoff"
        ).provider == .opencode)
        #expect(try TaskHandoffDestination.make(
            agent: "ROVO",
            artifact: "# Task Handoff"
        ).provider == .rovoDev)
    }

    @Test("authority binds provider, UTF-8 bytes, and exact digest")
    func authorityIsExact() throws {
        let destination = try TaskHandoffDestination.make(
            agent: "codex",
            artifact: "# Task Handoff\n\nContinue \u{1F680}"
        )

        #expect(destination.authorityDetails[TaskHandoffDestination.authorityProviderKey]
            == "codex")
        #expect(destination.authorityDetails[TaskHandoffDestination.authorityArtifactBytesKey]
            == "29")
        #expect(destination.artifactDigest.count == 64)
    }

    @Test("generated config injects the artifact into exactly one teammate")
    func configContainsOnePrompt() throws {
        let artifact = "# Task Handoff\n\nContinue."
        let destination = try TaskHandoffDestination.make(
            agent: "codex",
            artifact: artifact
        )
        let config = destination.makeAgentTeamConfig(
            identifier: UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
        )

        #expect(config.id == "handoff-codex-00000000")
        #expect(config.provider == .codex)
        #expect(config.teammates.count == 1)
        #expect(config.teammates.first?.prompt == artifact)
    }

    @Test("invalid and oversized artifacts fail closed")
    func invalidArtifactsFailClosed() {
        #expect(throws: TaskHandoffDestinationError.self) {
            try TaskHandoffDestination.make(agent: "unknown", artifact: "# Task Handoff")
        }
        #expect(throws: TaskHandoffDestinationError.emptyArtifact) {
            try TaskHandoffDestination.make(agent: "codex", artifact: " \n ")
        }
        #expect(throws: TaskHandoffDestinationError.invalidArtifact) {
            try TaskHandoffDestination.make(agent: "codex", artifact: "bad\0artifact")
        }
        #expect(throws: TaskHandoffDestinationError.artifactTooLarge(
            maximumBytes: CocxyTaskHandoffWireContract.maximumArtifactBytes
        )) {
            try TaskHandoffDestination.make(
                agent: "codex",
                artifact: String(
                    repeating: "a",
                    count: CocxyTaskHandoffWireContract.maximumArtifactBytes + 1
                )
            )
        }
    }
}
