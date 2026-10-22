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
    case queuedTask
    case taskRun
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

struct TaskLaunchCollisionAnalysis: Equatable, Sendable {
    let inferredPaths: [String]
    let report: TaskCollisionReport

    static let empty = TaskLaunchCollisionAnalysis(
        inferredPaths: [],
        report: .empty
    )
}

struct TaskCollisionLiveSession: Equatable, Sendable {
    let session: AgentSessionInfo
    let effectiveRoot: URL
    let worktreeID: String?
}

struct TaskCollisionWorkload: Equatable, Sendable {
    let participant: TaskCollisionParticipant
    let paths: [String]
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
        liveWork: [TaskCollisionLiveSession],
        otherWork: [TaskCollisionWorkload],
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
            liveWork,
            projectID: projectID,
            projectRoot: projectRoot,
            excludingIDs: [],
            excludingWorktreeIDs: []
        )
        return combinedReport(
            overlaps: overlaps(
                in: [planned] + live.files + candidateFiles(
                    otherWork,
                    projectRoot: projectRoot
                ),
                requiringParticipantID: planned.participant.id
            ),
            reported: live.reported
        )
    }

    static func beforePromotion(
        candidate: TaskRunCandidateComparison,
        liveWork: [TaskCollisionLiveSession],
        otherWork: [TaskCollisionWorkload],
        projectID: ProjectID,
        projectRoot: URL,
        excludingIDs: Set<String> = [],
        excludingWorktreeIDs: Set<String> = []
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
            liveWork,
            projectID: projectID,
            projectRoot: projectRoot,
            excludingIDs: excludingIDs.union([
                candidate.candidate.id,
                candidate.candidate.teamID,
            ]),
            excludingWorktreeIDs: excludingWorktreeIDs
        )
        return combinedReport(
            overlaps: overlaps(
                in: [selected] + live.files + candidateFiles(
                    otherWork,
                    projectRoot: projectRoot
                ),
                requiringParticipantID: selected.participant.id
            ),
            reported: live.reported
        )
    }

    static func normalize(_ paths: [String], projectRoot: URL) -> Set<String> {
        let canonicalRoot = ProjectPathCanonicalizer.canonicalURL(projectRoot)
        let root = canonicalRoot.path
        let rootPrefix = root == "/" ? "/" : root + "/"
        return Set(paths.compactMap { rawPath in
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.contains("\0") else { return nil }
            let expandedPath = (trimmed as NSString).expandingTildeInPath
            let expandsHomeDirectory = trimmed == "~" || trimmed.hasPrefix("~/")
            let absolute: URL
            if expandsHomeDirectory {
                absolute = ProjectPathCanonicalizer.canonicalURL(
                    URL(fileURLWithPath: expandedPath)
                )
            } else if !trimmed.hasPrefix("~"), NSString(string: trimmed).isAbsolutePath {
                absolute = ProjectPathCanonicalizer.canonicalURL(
                    URL(fileURLWithPath: trimmed)
                )
            } else {
                absolute = ProjectPathCanonicalizer.canonicalURL(
                    canonicalRoot.appendingPathComponent(trimmed)
                )
            }
            guard absolute.path.hasPrefix(rootPrefix), absolute.path.count > rootPrefix.count else {
                return nil
            }
            return String(absolute.path.dropFirst(rootPrefix.count))
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
        _ sessions: [TaskCollisionLiveSession],
        projectID: ProjectID,
        projectRoot: URL,
        excludingIDs: Set<String>,
        excludingWorktreeIDs: Set<String>
    ) -> LiveFiles {
        let matching = sessions.filter {
            $0.session.projectIdentity == projectID
                && $0.session.state != .finished
                && !excludingIDs.contains($0.session.id)
                && !($0.worktreeID.map(excludingWorktreeIDs.contains) ?? false)
        }
        let files = matching.map { live in
            CandidateFiles(
                participant: participant(for: live.session),
                paths: normalize(
                    live.session.filesTouched.map(\.path) + live.session.fileConflicts,
                    projectRoot: live.effectiveRoot
                )
            )
        }
        let reported = matching.flatMap { live in
            normalize(live.session.fileConflicts, projectRoot: live.effectiveRoot).map { path in
                TaskFileCollision(
                    path: path,
                    kind: .reportedConflict,
                    participants: [participant(for: live.session)]
                )
            }
        }
        return LiveFiles(files: files, reported: reported)
    }

    private static func candidateFiles(
        _ workloads: [TaskCollisionWorkload],
        projectRoot: URL
    ) -> [CandidateFiles] {
        workloads.map {
            CandidateFiles(
                participant: $0.participant,
                paths: normalize($0.paths, projectRoot: projectRoot)
            )
        }
    }

    private static func participant(for session: AgentSessionInfo) -> TaskCollisionParticipant {
        TaskCollisionParticipant(
            id: session.id,
            label: session.agentName ?? session.projectName,
            kind: .liveSession
        )
    }

    private static func overlaps(
        in candidates: [CandidateFiles],
        requiringParticipantID requiredID: String? = nil
    ) -> TaskCollisionReport {
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
            guard unique.count > 1,
                  requiredID.map({ id in unique.contains { $0.id == id } }) ?? true else {
                return nil
            }
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
