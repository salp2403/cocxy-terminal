// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Task collision detector")
struct TaskCollisionDetectorSwiftTestingTests {
    private let root = URL(fileURLWithPath: "/tmp/cocxy-project", isDirectory: true)
    private var projectID: ProjectID { ProjectID(rootURL: root) }

    @Test("N-way comparison reports only files shared by candidates")
    func candidateOverlaps() {
        let report = TaskCollisionDetector.betweenCandidates([
            comparison(id: "one", files: ["Sources/A.swift", "Sources/B.swift"]),
            comparison(id: "two", files: ["Sources/B.swift", "Sources/C.swift"]),
            comparison(id: "three", files: ["Sources/B.swift"]),
        ], projectRoot: root)

        #expect(report.paths == ["Sources/B.swift"])
        #expect(report.collisions.first?.participants.map(\.id) == ["one", "three", "two"])
    }

    @Test("prelaunch compares planned files with live project work")
    func prelaunchCollision() {
        let report = TaskCollisionDetector.beforeLaunch(
            plannedPaths: ["Sources/App.swift", "/tmp/cocxy-project/Tests/New.swift"],
            liveSessions: [
                session(id: "same", projectID: projectID, touched: ["Sources/App.swift"]),
                session(
                    id: "other",
                    projectID: ProjectID(rawValue: "/tmp/another-project"),
                    touched: ["Sources/App.swift"]
                ),
            ],
            projectID: projectID,
            projectRoot: root
        )

        #expect(report.paths == ["Sources/App.swift"])
        #expect(report.collisions.first?.participants.map(\.id) == ["planned-task", "same"])
    }

    @Test("reported live conflicts remain visible without planned file hints")
    func reportedConflict() {
        let report = TaskCollisionDetector.beforeLaunch(
            plannedPaths: [],
            liveSessions: [session(
                id: "live",
                projectID: projectID,
                conflicts: ["Sources/Shared.swift"]
            )],
            projectID: projectID,
            projectRoot: root
        )

        #expect(report.collisions == [TaskFileCollision(
            path: "Sources/Shared.swift",
            kind: .reportedConflict,
            participants: [TaskCollisionParticipant(
                id: "live",
                label: "Codex",
                kind: .liveSession
            )]
        )])
    }

    @Test("prepromotion excludes the selected runtime and detects other live work")
    func prepromotionCollision() {
        let selected = comparison(id: "candidate", teamID: "candidate-team", files: ["A.swift"])
        let report = TaskCollisionDetector.beforePromotion(
            candidate: selected,
            liveSessions: [
                session(id: "candidate-team", projectID: projectID, touched: ["A.swift"]),
                session(id: "independent", projectID: projectID, touched: ["A.swift"]),
            ],
            projectID: projectID,
            projectRoot: root
        )

        #expect(report.paths == ["A.swift"])
        #expect(report.collisions.first?.participants.map(\.id) == ["candidate", "independent"])
    }

    @Test("normalization rejects paths outside the canonical project root")
    func normalizationBoundary() {
        #expect(TaskCollisionDetector.normalize([
            "Sources/../Tests/A.swift",
            "/tmp/cocxy-project/Sources/B.swift",
            "../outside.swift",
            "/tmp/cocxy-project-copy/C.swift",
        ], projectRoot: root) == ["Sources/B.swift", "Tests/A.swift"])
    }

    @Test("legacy candidate payload defaults new touched file metadata")
    func legacyCandidatePayload() throws {
        let data = Data(#"{"id":"old","provider":"codex","teamID":"old-team","status":"finished","estimatedCostMicros":0}"#.utf8)
        let candidate = try JSONDecoder().decode(TaskRunCandidate.self, from: data)

        #expect(candidate.touchedFiles.isEmpty)
        #expect(try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(candidate)
        ) as? [String: Any] != nil)
    }

    private func comparison(
        id: String,
        teamID: String? = nil,
        files: [String]
    ) -> TaskRunCandidateComparison {
        let candidate = TaskRunCandidate(
            id: id,
            provider: .codex,
            teamID: teamID ?? "\(id)-team"
        )
        return TaskRunCandidateComparison(
            candidate: candidate,
            diffs: files.map {
                FileDiff(filePath: $0, status: .modified, hunks: [])
            }
        )
    }

    private func session(
        id: String,
        projectID: ProjectID,
        touched: [String] = [],
        conflicts: [String] = []
    ) -> AgentSessionInfo {
        AgentSessionInfo(
            id: id,
            projectName: "Project",
            projectIdentity: projectID,
            gitBranch: "main",
            agentName: "Codex",
            state: .working,
            lastActivity: nil,
            lastActivityTime: nil,
            tabId: UUID(),
            subagents: [],
            priority: .standard,
            model: nil,
            filesTouched: touched.map { FileImpact(path: $0) },
            fileConflicts: conflicts
        )
    }
}
