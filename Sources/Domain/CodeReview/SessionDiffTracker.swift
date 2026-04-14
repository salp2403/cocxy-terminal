// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionDiffTracker.swift - Tracks per-agent-session git snapshots and touched files.

import Foundation

protocol SessionDiffTracking: AnyObject {
    func recordSnapshot(sessionId: String, ref: String, workingDirectory: URL)
    func snapshotRef(for sessionId: String) -> String?
    func snapshotNotice(for sessionId: String) -> String?
    func workingDirectory(for sessionId: String) -> URL?
    func removeSnapshot(sessionId: String)
    func trackFile(sessionId: String, filePath: String, agentName: String?)
    func trackedFiles(for sessionId: String) -> Set<String>
    func pendingSnapshot(for sessionId: String) -> URL?
    func latestSessionId(for workingDirectory: URL) -> String?
    func reviewRounds(for sessionId: String) -> [ReviewRound]
    func appendReviewRound(sessionId: String, round: ReviewRound)
    func handleHookEvent(_ event: HookEvent)
    func snapshotCurrentHead(
        sessionId: String,
        workingDirectory: URL,
        completion: (@Sendable (Result<String, Error>) -> Void)?
    )
    func computeDiff(
        sessionId: String,
        mode: DiffMode,
        reference: String?,
        completion: @escaping @Sendable (Result<[FileDiff], Error>) -> Void
    )
}

private struct SessionSnapshot: Sendable {
    var ref: String?
    var workingDirectory: URL
    var repoRoot: URL?
    var snapshotNotice: String?
    var trackedFiles: Set<String> = []
    var fileAgentNames: [String: String] = [:]
    var reviewRounds: [ReviewRound] = []
    var pendingSnapshotDirectory: URL?
    var updatedAt: Date = Date()
}

final class SessionDiffTrackerImpl: SessionDiffTracking, @unchecked Sendable {
    private static let maxSnapshotCount = 64

    private let lock = NSLock()
    private var snapshots: [String: SessionSnapshot] = [:]
    private let queue = DispatchQueue(label: "dev.cocxy.codereview.difftracker", qos: .userInitiated)
    private let gitRunner: @Sendable (URL, [String]) throws -> String

    init(gitRunner: (@Sendable (URL, [String]) throws -> String)? = nil) {
        let defaultRunner: @Sendable (URL, [String]) throws -> String = { workingDirectory, arguments in
            try Self.runGit(workingDirectory, arguments)
        }
        self.gitRunner = gitRunner ?? defaultRunner
    }

    func recordSnapshot(sessionId: String, ref: String, workingDirectory: URL) {
        lock.lock()
        var snapshot = snapshots[sessionId] ?? SessionSnapshot(ref: nil, workingDirectory: workingDirectory)
        snapshot.ref = ref
        snapshot.workingDirectory = workingDirectory
        snapshot.repoRoot = snapshot.repoRoot ?? workingDirectory
        snapshot.snapshotNotice = nil
        snapshot.pendingSnapshotDirectory = nil
        snapshot.updatedAt = Date()
        snapshots[sessionId] = snapshot
        evictSnapshotsIfNeededLocked()
        lock.unlock()
    }

    func snapshotRef(for sessionId: String) -> String? {
        lock.withLock { snapshots[sessionId]?.ref }
    }

    func snapshotNotice(for sessionId: String) -> String? {
        lock.withLock { snapshots[sessionId]?.snapshotNotice }
    }

    func workingDirectory(for sessionId: String) -> URL? {
        lock.withLock { snapshots[sessionId]?.workingDirectory }
    }

    func removeSnapshot(sessionId: String) {
        _ = lock.withLock {
            snapshots.removeValue(forKey: sessionId)
        }
    }

    func trackFile(sessionId: String, filePath: String, agentName: String?) {
        lock.withLock {
            guard var snapshot = snapshots[sessionId] else { return }
            let normalized = Self.normalizeTrackedPath(
                filePath,
                relativeTo: snapshot.repoRoot ?? snapshot.workingDirectory
            )
            snapshot.trackedFiles.insert(normalized)
            if let agentName, !agentName.isEmpty {
                snapshot.fileAgentNames[normalized] = agentName
            }
            snapshot.updatedAt = Date()
            snapshots[sessionId] = snapshot
        }
    }

    func trackedFiles(for sessionId: String) -> Set<String> {
        lock.withLock { snapshots[sessionId]?.trackedFiles ?? [] }
    }

    func pendingSnapshot(for sessionId: String) -> URL? {
        lock.withLock { snapshots[sessionId]?.pendingSnapshotDirectory }
    }

    func latestSessionId(for workingDirectory: URL) -> String? {
        lock.withLock {
            snapshots
                .filter { _, snapshot in
                    snapshot.workingDirectory.standardizedFileURL == workingDirectory.standardizedFileURL
                }
                .max { lhs, rhs in
                    lhs.value.updatedAt < rhs.value.updatedAt
                }?
                .key
        }
    }

    func reviewRounds(for sessionId: String) -> [ReviewRound] {
        lock.withLock { snapshots[sessionId]?.reviewRounds ?? [] }
    }

    func appendReviewRound(sessionId: String, round: ReviewRound) {
        lock.withLock {
            guard var snapshot = snapshots[sessionId] else { return }
            snapshot.reviewRounds.append(round)
            snapshots[sessionId] = snapshot
        }
    }

    func handleHookEvent(_ event: HookEvent) {
        switch event.type {
        case .sessionStart:
            let workingDirectoryString = event.cwd ?? Self.workingDirectory(from: event.data)
            guard let workingDirectoryString else { return }
            let workingDirectory = URL(fileURLWithPath: workingDirectoryString, isDirectory: true)
            let shouldStartSnapshot = lock.withLock { () -> Bool in
                var snapshot = snapshots[event.sessionId] ?? SessionSnapshot(ref: nil, workingDirectory: workingDirectory)
                let dedupePendingLookup = snapshot.pendingSnapshotDirectory?.standardizedFileURL == workingDirectory.standardizedFileURL
                snapshot.workingDirectory = workingDirectory
                snapshot.pendingSnapshotDirectory = workingDirectory
                snapshot.updatedAt = Date()
                snapshots[event.sessionId] = snapshot
                evictSnapshotsIfNeededLocked()
                return !dedupePendingLookup
            }
            if shouldStartSnapshot {
                snapshotCurrentHead(sessionId: event.sessionId, workingDirectory: workingDirectory, completion: nil)
            }

        case .postToolUse, .postToolUseFailure, .preToolUse:
            guard case .toolUse(let toolData) = event.data else { return }
            let toolName = toolData.toolName.lowercased()
            guard ["write", "edit", "bash", "multiedit"].contains(toolName) else { return }
            if let candidate = toolData.toolInput?["file_path"] ?? toolData.toolInput?["path"] {
                trackFile(sessionId: event.sessionId, filePath: candidate, agentName: Self.agentName(from: event.data))
            }

        case .taskCompleted, .sessionEnd, .stop, .notification, .teammateIdle, .subagentStart, .subagentStop, .userPromptSubmit:
            break
        }
    }

    func snapshotCurrentHead(
        sessionId: String,
        workingDirectory: URL,
        completion: (@Sendable (Result<String, Error>) -> Void)?
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let repoRootOutput = try? self.gitRunner(workingDirectory, ["rev-parse", "--show-toplevel"])
                let repoRoot = repoRootOutput?.trimmingCharacters(in: .whitespacesAndNewlines)
                let ref = try self.gitRunner(workingDirectory, ["rev-parse", "HEAD"])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                self.lock.withLock {
                    guard var snapshot = self.snapshots[sessionId] else { return }
                    snapshot.ref = ref
                    snapshot.workingDirectory = workingDirectory
                    snapshot.repoRoot = repoRoot.flatMap {
                        guard !$0.isEmpty else { return nil }
                        return URL(fileURLWithPath: $0, isDirectory: true)
                    } ?? snapshot.repoRoot ?? workingDirectory
                    snapshot.snapshotNotice = nil
                    snapshot.pendingSnapshotDirectory = nil
                    snapshot.updatedAt = Date()
                    self.snapshots[sessionId] = snapshot
                    self.evictSnapshotsIfNeededLocked()
                }
                completion?(.success(ref))
            } catch {
                let repoRootOutput = try? self.gitRunner(workingDirectory, ["rev-parse", "--show-toplevel"])
                let repoRoot = repoRootOutput?.trimmingCharacters(in: .whitespacesAndNewlines)
                self.lock.withLock {
                    guard var snapshot = self.snapshots[sessionId] else { return }
                    snapshot.workingDirectory = workingDirectory
                    snapshot.repoRoot = repoRoot.flatMap {
                        guard !$0.isEmpty else { return nil }
                        return URL(fileURLWithPath: $0, isDirectory: true)
                    } ?? snapshot.repoRoot ?? workingDirectory
                    snapshot.snapshotNotice = Self.snapshotNotice(for: error)
                    snapshot.pendingSnapshotDirectory = nil
                    snapshot.updatedAt = Date()
                    self.snapshots[sessionId] = snapshot
                    self.evictSnapshotsIfNeededLocked()
                }
                completion?(.failure(error))
            }
        }
    }

    func computeDiff(
        sessionId: String,
        mode: DiffMode,
        reference: String? = nil,
        completion: @escaping @Sendable (Result<[FileDiff], Error>) -> Void
    ) {
        guard let snapshot = lock.withLock({ snapshots[sessionId] }) else {
            completion(.success([]))
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            do {
                let rawDiff: String
                let diffWorkingDirectory: URL
                switch mode {
                case .uncommitted:
                    diffWorkingDirectory = snapshot.workingDirectory
                    rawDiff = try self.gitRunner(diffWorkingDirectory, ["diff", "--no-color", "--", "."])
                case .sinceSessionStart:
                    diffWorkingDirectory = snapshot.repoRoot ?? snapshot.workingDirectory
                    if let baseRef = snapshot.ref, !baseRef.isEmpty {
                        rawDiff = try self.gitRunner(diffWorkingDirectory, ["diff", "--no-color", baseRef, "--"])
                    } else {
                        rawDiff = try self.gitRunner(diffWorkingDirectory, ["diff", "--no-color", "--"])
                    }
                case .vsBranch:
                    diffWorkingDirectory = snapshot.workingDirectory
                    let targetRef = reference ?? snapshot.ref ?? "HEAD"
                    rawDiff = try self.gitRunner(diffWorkingDirectory, ["diff", "--no-color", targetRef, "--", "."])
                }

                let statusOutput = try self.gitRunner(diffWorkingDirectory, ["status", "--porcelain"])
                var statusMap: [String: FileStatus] = [:]
                for entry in DiffParser.parseStatus(statusOutput) {
                    statusMap[entry.path] = Self.mergeStatus(existing: statusMap[entry.path], incoming: entry.status)
                }

                var diffs = DiffParser.parse(rawDiff).map { diff in
                    FileDiff(
                        filePath: diff.filePath,
                        originalFilePath: diff.originalFilePath,
                        status: statusMap[diff.filePath] ?? diff.status,
                        hunks: diff.hunks,
                        agentName: snapshot.fileAgentNames[diff.filePath],
                        reviewNote: diff.reviewNote
                    )
                }

                let existingPaths = Set(diffs.map(\.filePath))
                for (path, status) in statusMap where !existingPaths.contains(path) {
                    guard status == .untracked || status == .added else { continue }
                    let fileURL = diffWorkingDirectory.appendingPathComponent(path)
                    guard let data = try? Data(contentsOf: fileURL),
                          let content = String(data: data, encoding: .utf8) else {
                        continue
                    }
                    let synthetic = DiffParser.makeSyntheticAddedFileDiff(
                        filePath: path,
                        fileContent: content,
                        agentName: snapshot.fileAgentNames[path]
                    )
                    diffs.append(
                        FileDiff(
                            filePath: synthetic.filePath,
                            status: status == .untracked ? .untracked : .added,
                            hunks: synthetic.hunks,
                            agentName: synthetic.agentName
                        )
                    )
                }

                if mode == .sinceSessionStart, !snapshot.trackedFiles.isEmpty {
                    diffs = diffs.filter {
                        Self.matchesTrackedPath(
                            diffPath: $0.filePath,
                            trackedPaths: snapshot.trackedFiles,
                            repoRoot: snapshot.repoRoot ?? snapshot.workingDirectory,
                            workingDirectory: snapshot.workingDirectory
                        )
                    }
                }

                diffs.sort {
                    if $0.status.sortRank != $1.status.sortRank {
                        return $0.status.sortRank < $1.status.sortRank
                    }
                    return $0.filePath.localizedCaseInsensitiveCompare($1.filePath) == .orderedAscending
                }

                completion(.success(diffs))
            } catch {
                completion(.failure(error))
            }
        }
    }

    static func runGit(_ workingDirectory: URL, _ arguments: [String]) throws -> String {
        let result = try CodeReviewGit.run(workingDirectory: workingDirectory, arguments: arguments)
        guard result.terminationStatus == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw HunkActionError.commandFailed(message.isEmpty ? "git \(arguments.joined(separator: " ")) failed" : message)
        }
        return result.stdout
    }

    private static func workingDirectory(from data: HookEventData) -> String? {
        switch data {
        case .sessionStart(let info):
            return info.workingDirectory
        default:
            return nil
        }
    }

    private static func agentName(from data: HookEventData) -> String? {
        switch data {
        case .sessionStart(let info):
            return info.agentType
        default:
            return nil
        }
    }

    private static func normalizeTrackedPath(_ rawPath: String, relativeTo workingDirectory: URL) -> String {
        let trimmedPath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPath.hasPrefix("/") else {
            return trimmedPath
        }

        let fileURL = URL(fileURLWithPath: trimmedPath)
        if fileURL.path.hasPrefix("/") {
            if let relative = relativePathIfDescendant(fileURL, parent: workingDirectory) {
                return relative
            }
            return fileURL.standardizedFileURL.path
        }
        return trimmedPath
    }

    private static func relativePathIfDescendant(_ fileURL: URL, parent: URL) -> String? {
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        let parentComponents = parent.standardizedFileURL.pathComponents
        guard fileComponents.count >= parentComponents.count else { return nil }
        guard Array(fileComponents.prefix(parentComponents.count)) == parentComponents else { return nil }
        return fileComponents.dropFirst(parentComponents.count).joined(separator: "/")
    }

    private func evictSnapshotsIfNeededLocked() {
        guard snapshots.count > Self.maxSnapshotCount else { return }
        let sortedByAge = snapshots.sorted { $0.value.updatedAt < $1.value.updatedAt }
        let overflow = snapshots.count - Self.maxSnapshotCount
        for (sessionId, _) in sortedByAge.prefix(overflow) {
            snapshots.removeValue(forKey: sessionId)
        }
    }

    private static func mergeStatus(existing: FileStatus?, incoming: FileStatus) -> FileStatus {
        guard let existing else { return incoming }
        let priority: [FileStatus: Int] = [
            .modified: 0,
            .added: 1,
            .untracked: 2,
            .deleted: 3,
            .renamed: 4,
        ]
        return (priority[incoming] ?? 0) >= (priority[existing] ?? 0) ? incoming : existing
    }

    private static func matchesTrackedPath(
        diffPath: String,
        trackedPaths: Set<String>,
        repoRoot: URL,
        workingDirectory: URL
    ) -> Bool {
        if trackedPaths.contains(diffPath) {
            return true
        }

        let absoluteDiffPath = repoRoot.appendingPathComponent(diffPath).standardizedFileURL.path
        if trackedPaths.contains(absoluteDiffPath) {
            return true
        }

        if let workingDirectoryRelative = relativePathIfDescendant(
            URL(fileURLWithPath: absoluteDiffPath),
            parent: workingDirectory
        ) {
            return trackedPaths.contains(workingDirectoryRelative)
        }

        return false
    }

    private static func snapshotNotice(for error: Error) -> String {
        let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        if message.localizedCaseInsensitiveContains("unknown revision") ||
            message.localizedCaseInsensitiveContains("ambiguous argument 'HEAD'") ||
            message.localizedCaseInsensitiveContains("needed a single revision") {
            return "This session started before Git had a commit to diff against, so the review is comparing against the current working tree."
        }
        return "Git could not capture a stable base commit for this review session. The panel is showing the current working tree instead."
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
