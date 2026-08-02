// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// TaskCollisionDetector.swift - Pure project-scoped task collision analysis.

import Foundation

enum TaskCollisionKind: String, Equatable, Sendable {
    case overlap
    case reportedConflict
}

enum TaskCollisionParticipantKind: String, Equatable, Sendable {
    case plannedTask
    case candidate
    case liveSession
}

struct TaskCollisionParticipant: Equatable, Sendable {
    let id: String
    let label: String
    let kind: TaskCollisionParticipantKind
}

struct TaskFileCollision: Identifiable, Equatable, Sendable {
    let path: String
    let kind: TaskCollisionKind
    let participants: [TaskCollisionParticipant]

    var id: String {
        "\(kind.rawValue):\(path):\(participants.map(\.id).joined(separator: ","))"
    }
}

struct TaskCollisionReport: Equatable, Sendable {
    let collisions: [TaskFileCollision]

    static let empty = TaskCollisionReport(collisions: [])

    var isEmpty: Bool { collisions.isEmpty }
    var paths: [String] { Array(Set(collisions.map(\.path))).sorted() }
}

enum TaskCollisionDetector {
    static func betweenCandidates(
        _ comparisons: [TaskRunCandidateComparison],
        projectRoot: URL
    ) -> TaskCollisionReport {
        let participants = comparisons.map { comparison in
            CandidateFiles(
                participant: TaskCollisionParticipant(
                    id: comparison.candidate.id,
                    label: comparison.candidate.provider.displayName,
                    kind: .candidate
                ),
                paths: normalize(
                    comparison.diffs.map(\.filePath) + comparison.candidate.touchedFiles,
                    projectRoot: projectRoot
                )
            )
        }
        return overlaps(in: participants)
    }

    static func beforeLaunch(
        plannedPaths: [String],
        liveSessions: [AgentSessionInfo],
        projectID: ProjectID,
        projectRoot: URL
    ) -> TaskCollisionReport {
        let planned = CandidateFiles(
            participant: TaskCollisionParticipant(
                id: "planned-task",
                label: "Planned task",
                kind: .plannedTask
            ),
            paths: normalize(plannedPaths, projectRoot: projectRoot)
        )
        let live = liveFiles(
            liveSessions,
            projectID: projectID,
            projectRoot: projectRoot,
            excludingIDs: []
        )
        return combinedReport(
            overlaps: overlaps(in: [planned] + live.files),
            reported: live.reported
        )
    }

    static func beforePromotion(
        candidate: TaskRunCandidateComparison,
        liveSessions: [AgentSessionInfo],
        projectID: ProjectID,
        projectRoot: URL,
        excludingIDs: Set<String> = []
    ) -> TaskCollisionReport {
        let selected = CandidateFiles(
            participant: TaskCollisionParticipant(
                id: candidate.candidate.id,
                label: candidate.candidate.provider.displayName,
                kind: .candidate
            ),
            paths: normalize(
                candidate.diffs.map(\.filePath) + candidate.candidate.touchedFiles,
                projectRoot: projectRoot
            )
        )
        let live = liveFiles(
            liveSessions,
            projectID: projectID,
            projectRoot: projectRoot,
            excludingIDs: excludingIDs.union([
                candidate.candidate.id,
                candidate.candidate.teamID,
            ])
        )
        return combinedReport(
            overlaps: overlaps(in: [selected] + live.files),
            reported: live.reported
        )
    }

    static func normalize(_ paths: [String], projectRoot: URL) -> Set<String> {
        let root = projectRoot.standardizedFileURL.path
        let rootPrefix = root == "/" ? "/" : root + "/"
        return Set(paths.compactMap { rawPath in
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains("\0") else { return nil }
            let absolute: String
            if trimmed.hasPrefix("/") {
                absolute = URL(fileURLWithPath: trimmed).standardizedFileURL.path
            } else {
                absolute = projectRoot.standardizedFileURL
                    .appendingPathComponent(trimmed)
                    .standardizedFileURL.path
            }
            guard absolute.hasPrefix(rootPrefix), absolute.count > rootPrefix.count else {
                return nil
            }
            return String(absolute.dropFirst(rootPrefix.count))
        })
    }

    private struct CandidateFiles {
        let participant: TaskCollisionParticipant
        let paths: Set<String>
    }

    private struct LiveFiles {
        let files: [CandidateFiles]
        let reported: [TaskFileCollision]
    }

    private static func liveFiles(
        _ sessions: [AgentSessionInfo],
        projectID: ProjectID,
        projectRoot: URL,
        excludingIDs: Set<String>
    ) -> LiveFiles {
        let matching = sessions.filter {
            $0.projectIdentity == projectID
                && $0.state != .finished
                && !excludingIDs.contains($0.id)
        }
        let files = matching.map { session in
            CandidateFiles(
                participant: participant(for: session),
                paths: normalize(
                    session.filesTouched.map(\.path) + session.fileConflicts,
                    projectRoot: projectRoot
                )
            )
        }
        let reported = matching.flatMap { session in
            normalize(session.fileConflicts, projectRoot: projectRoot).map { path in
                TaskFileCollision(
                    path: path,
                    kind: .reportedConflict,
                    participants: [participant(for: session)]
                )
            }
        }
        return LiveFiles(files: files, reported: reported)
    }

    private static func participant(for session: AgentSessionInfo) -> TaskCollisionParticipant {
        TaskCollisionParticipant(
            id: session.id,
            label: session.agentName ?? session.projectName,
            kind: .liveSession
        )
    }

    private static func overlaps(in candidates: [CandidateFiles]) -> TaskCollisionReport {
        var participantsByPath: [String: [TaskCollisionParticipant]] = [:]
        for candidate in candidates {
            for path in candidate.paths {
                participantsByPath[path, default: []].append(candidate.participant)
            }
        }
        let collisions = participantsByPath.compactMap { path, participants -> TaskFileCollision? in
            let unique = Dictionary(grouping: participants, by: \.id)
                .compactMap { $0.value.first }
                .sorted { $0.id < $1.id }
            guard unique.count > 1 else { return nil }
            return TaskFileCollision(path: path, kind: .overlap, participants: unique)
        }.sorted { $0.path < $1.path }
        return TaskCollisionReport(collisions: collisions)
    }

    private static func combinedReport(
        overlaps: TaskCollisionReport,
        reported: [TaskFileCollision]
    ) -> TaskCollisionReport {
        let unique = Dictionary(
            (overlaps.collisions + reported).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return TaskCollisionReport(collisions: unique.values.sorted {
            if $0.path != $1.path { return $0.path < $1.path }
            return $0.kind.rawValue < $1.kind.rawValue
        })
    }
}
