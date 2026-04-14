// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewPanelViewModel.swift - Main state coordinator for the review panel.

import Combine
import Foundation

@MainActor
final class CodeReviewPanelViewModel: CodeReviewProviding, ObservableObject {
    @Published var isVisible: Bool = false
    @Published private(set) var currentDiffs: [FileDiff] = []
    @Published var selectedFilePath: String?
    @Published var diffMode: DiffMode = .sinceSessionStart
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var activeSessionId: String?
    @Published private(set) var activeWorkingDirectory: URL?
    @Published private(set) var activeTabID: TabID?
    @Published var shouldAutoShow: Bool = false
    @Published var selectedLineForComment: (filePath: String, line: Int)?
    @Published var selectedLineNumber: Int?
    @Published var selectedHunkID: String?
    @Published private(set) var reviewRounds: [ReviewRound] = []
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastInfoMessage: String?

    var activeTabCwdProvider: (() -> URL?)?
    var activeTabIDProvider: (() -> TabID?)?
    var activeSessionIdProvider: (() -> String?)?
    var referenceProvider: (() -> String?)?
    var ptyWriteHandler: ((String, String?, URL?, TabID?) -> Bool)?
    var autoShowEnabledProvider: (() -> Bool)?
    var refreshDelay: TimeInterval = 2.0
    var onDiffsUpdated: (([FileDiff]) -> Void)?

    private let tracker: SessionDiffTracking
    private var cancellables = Set<AnyCancellable>()
    private let hookEventReceiver: HookEventReceiving?
    private let directDiffLoader: (@Sendable (URL, DiffMode, String?) async throws -> [FileDiff])?
    private let commentStore: CommentStore
    private var refreshGeneration: UInt64 = 0
    private var refreshTask: Task<Void, Never>?

    init(
        tracker: SessionDiffTracking,
        hookEventReceiver: HookEventReceiving? = nil,
        commentStore: CommentStore = CommentStore(),
        directDiffLoader: (@Sendable (URL, DiffMode, String?) async throws -> [FileDiff])? = nil
    ) {
        self.tracker = tracker
        self.hookEventReceiver = hookEventReceiver
        self.commentStore = commentStore
        self.directDiffLoader = directDiffLoader

        commentStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        bindHookEvents()
    }

    var pendingComments: [ReviewComment] {
        commentStore.allComments
    }

    var pendingCommentCount: Int {
        pendingComments.count
    }

    func comments(for filePath: String) -> [ReviewComment] {
        commentStore.comments(for: filePath)
    }

    func comments(for filePath: String, line: Int) -> [ReviewComment] {
        commentStore.comments(for: filePath, line: line)
    }

    func commentCount(for filePath: String) -> Int {
        commentStore.commentCount(for: filePath)
    }

    func toggleVisibility() {
        isVisible.toggle()
        if isVisible {
            refreshDiffs()
        }
    }

    func selectFile(_ path: String) {
        selectedFilePath = path
        if selectedHunkID == nil {
            selectedHunkID = currentDiffs.first(where: { $0.filePath == path })?.hunks.first?.id
        }
    }

    func refreshDiffs() {
        refreshTask?.cancel()
        refreshGeneration &+= 1
        let generation = refreshGeneration

        let sessionId = activeSessionIdProvider?()
        activeSessionId = sessionId
        activeTabID = activeTabIDProvider?()
        lastErrorMessage = nil
        lastInfoMessage = nil
        isLoading = true

        if let sessionId {
            activeWorkingDirectory = tracker.workingDirectory(for: sessionId) ?? activeTabCwdProvider?()
            tracker.computeDiff(
                sessionId: sessionId,
                mode: diffMode,
                reference: referenceProvider?()
            ) { [weak self] result in
                Task { @MainActor in
                    self?.applyDiffResult(result, sessionId: sessionId, generation: generation)
                }
            }
            return
        }

        guard let cwd = activeTabCwdProvider?() else {
            activeWorkingDirectory = nil
            activeTabID = nil
            currentDiffs = []
            reviewRounds = []
            isLoading = false
            return
        }

        activeWorkingDirectory = cwd

        refreshTask = Task { [weak self] in
            guard let self else { return }
            do {
                let diffs: [FileDiff]
                if let directDiffLoader {
                    diffs = try await directDiffLoader(cwd, diffMode, referenceProvider?())
                } else {
                    diffs = try await Self.loadDirectDiff(workingDirectory: cwd, mode: diffMode, reference: referenceProvider?())
                }
                await MainActor.run {
                    guard generation == self.refreshGeneration else { return }
                    self.currentDiffs = diffs
                    self.reconcileSelection(with: diffs)
                    self.isLoading = false
                    self.lastErrorMessage = nil
                    self.lastInfoMessage = nil
                    self.onDiffsUpdated?(diffs)
                }
            } catch {
                await MainActor.run {
                    guard generation == self.refreshGeneration else { return }
                    self.currentDiffs = []
                    self.lastErrorMessage = Self.userFacingErrorMessage(for: error)
                    self.lastInfoMessage = nil
                    self.isLoading = false
                }
            }
        }
    }

    func addComment(filePath: String, line: Int, body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        commentStore.add(
            ReviewComment(
                filePath: filePath,
                lineRange: line...line,
                body: trimmed
            )
        )
        selectedLineForComment = nil
        selectedLineNumber = line
    }

    func removeComment(id: UUID) {
        commentStore.remove(id: id)
    }

    func submitComments() {
        let pending = pendingComments
        let formatted = FeedbackFormatter.format(pending)
        guard !formatted.isEmpty else { return }

        let targetSessionId = activeSessionId
        let targetWorkingDirectory = activeWorkingDirectory ?? resolvedWorkingDirectory
        let didSend = ptyWriteHandler?(formatted + "\n", targetSessionId, targetWorkingDirectory, activeTabID) ?? false
        guard didSend else {
            lastErrorMessage = "Review feedback could not be sent because the original agent terminal is no longer available."
            lastInfoMessage = nil
            return
        }
        lastErrorMessage = nil
        lastInfoMessage = nil

        if let sessionId = activeSessionId,
           let baseRef = tracker.snapshotRef(for: sessionId) {
            let nextRound = tracker.reviewRounds(for: sessionId).count + 1
            if let archived = commentStore.archivePendingComments(
                nextRoundID: nextRound,
                baseRef: baseRef,
                diffs: currentDiffs
            ) {
                tracker.appendReviewRound(sessionId: sessionId, round: archived)
                reviewRounds = tracker.reviewRounds(for: sessionId)
            }
        } else {
            commentStore.clearAll()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + refreshDelay) { [weak self] in
            self?.refreshDiffs()
        }
    }

    func discardPendingComments() {
        commentStore.clearAll()
        selectedLineForComment = nil
        lastErrorMessage = nil
        lastInfoMessage = nil
    }

    func addDraftCommentAnchor(filePath: String, line: Int) {
        selectedLineForComment = (filePath, line)
        selectedLineNumber = line
    }

    func clearDraftCommentAnchor() {
        selectedLineForComment = nil
    }

    func selectLine(filePath: String, line: Int) {
        selectedFilePath = filePath
        selectedLineNumber = line
    }

    func selectHunk(_ hunk: DiffHunk) {
        selectedHunkID = hunk.id
        if let firstLine = hunk.firstDisplayLine {
            selectedLineNumber = firstLine
        }
    }

    func selectedHunk(in fileDiff: FileDiff?) -> DiffHunk? {
        guard let fileDiff else { return nil }
        if let selectedHunkID {
            return fileDiff.hunks.first(where: { $0.id == selectedHunkID })
        }
        return fileDiff.hunks.first
    }

    var selectedFileDiff: FileDiff? {
        if let selectedFilePath {
            return currentDiffs.first(where: { $0.filePath == selectedFilePath })
        }
        return currentDiffs.first
    }

    func selectNextHunk() {
        guard let fileDiff = selectedFileDiff else { return }
        let hunks = fileDiff.hunks
        guard !hunks.isEmpty else { return }
        guard let selectedHunkID,
              let index = hunks.firstIndex(where: { $0.id == selectedHunkID }) else {
            selectHunk(hunks[0])
            return
        }
        selectHunk(hunks[(index + 1) % hunks.count])
    }

    func selectPreviousHunk() {
        guard let fileDiff = selectedFileDiff else { return }
        let hunks = fileDiff.hunks
        guard !hunks.isEmpty else { return }
        guard let selectedHunkID,
              let index = hunks.firstIndex(where: { $0.id == selectedHunkID }) else {
            selectHunk(hunks[0])
            return
        }
        selectHunk(hunks[(index - 1 + hunks.count) % hunks.count])
    }

    func toggleDiffMode() {
        let allCases = DiffMode.allCases
        guard let index = allCases.firstIndex(of: diffMode) else {
            diffMode = .sinceSessionStart
            selectedLineNumber = nil
            selectedHunkID = nil
            refreshDiffs()
            return
        }
        diffMode = allCases[(index + 1) % allCases.count]
        selectedLineNumber = nil
        selectedHunkID = nil
        refreshDiffs()
    }

    func activateCommentComposerForSelection() {
        guard let selectedFilePath, let selectedLineNumber else { return }
        addDraftCommentAnchor(filePath: selectedFilePath, line: selectedLineNumber)
    }

    func accept(
        hunk: DiffHunk,
        in fileDiff: FileDiff,
        completion: (@Sendable (Result<Void, Error>) -> Void)? = nil
    ) {
        guard let workingDirectory = activeWorkingDirectory ?? resolvedWorkingDirectory else {
            completion?(.failure(HunkActionError.invalidWorkingDirectory))
            return
        }
        HunkActionService.acceptHunk(
            fileDiff: fileDiff,
            hunk: hunk,
            workingDirectory: workingDirectory
        ) { [weak self] result in
            Task { @MainActor in
                if case .success = result {
                    self?.lastErrorMessage = nil
                    self?.lastInfoMessage = nil
                    self?.refreshDiffs()
                } else if case .failure(let error) = result {
                    self?.lastErrorMessage = Self.userFacingErrorMessage(for: error)
                    self?.lastInfoMessage = nil
                }
                completion?(result)
            }
        }
    }

    func reject(
        hunk: DiffHunk,
        in fileDiff: FileDiff,
        completion: (@Sendable (Result<Void, Error>) -> Void)? = nil
    ) {
        guard let workingDirectory = activeWorkingDirectory ?? resolvedWorkingDirectory else {
            completion?(.failure(HunkActionError.invalidWorkingDirectory))
            return
        }
        HunkActionService.revertHunk(
            fileDiff: fileDiff,
            hunk: hunk,
            workingDirectory: workingDirectory
        ) { [weak self] result in
            Task { @MainActor in
                if case .success = result {
                    self?.lastErrorMessage = nil
                    self?.lastInfoMessage = nil
                    self?.refreshDiffs()
                } else if case .failure(let error) = result {
                    self?.lastErrorMessage = Self.userFacingErrorMessage(for: error)
                    self?.lastInfoMessage = nil
                }
                completion?(result)
            }
        }
    }

    func nextFile() {
        guard !currentDiffs.isEmpty else { return }
        let paths = currentDiffs.map(\.filePath)
        guard let selectedFilePath,
              let index = paths.firstIndex(of: selectedFilePath) else {
            self.selectedFilePath = paths.first
            return
        }
        let next = (index + 1) % paths.count
        self.selectedFilePath = paths[next]
    }

    func previousFile() {
        guard !currentDiffs.isEmpty else { return }
        let paths = currentDiffs.map(\.filePath)
        guard let selectedFilePath,
              let index = paths.firstIndex(of: selectedFilePath) else {
            self.selectedFilePath = paths.first
            return
        }
        let previous = (index - 1 + paths.count) % paths.count
        self.selectedFilePath = paths[previous]
    }

    func acceptSelectedHunk(completion: (@Sendable (Result<Void, Error>) -> Void)? = nil) {
        guard let fileDiff = selectedFileDiff,
              let selectedHunk = selectedHunk(in: fileDiff) else {
            return
        }
        accept(hunk: selectedHunk, in: fileDiff, completion: completion)
    }

    func rejectSelectedHunk(completion: (@Sendable (Result<Void, Error>) -> Void)? = nil) {
        guard let fileDiff = selectedFileDiff,
              let selectedHunk = selectedHunk(in: fileDiff) else {
            return
        }
        reject(hunk: selectedHunk, in: fileDiff, completion: completion)
    }

    private var resolvedWorkingDirectory: URL? {
        if let sessionId = activeSessionId,
           let directory = tracker.workingDirectory(for: sessionId) {
            return directory
        }
        if let sessionId = activeSessionIdProvider?(),
           let directory = tracker.workingDirectory(for: sessionId) {
            return directory
        }
        return activeTabCwdProvider?()
    }

    private func bindHookEvents() {
        hookEventReceiver?.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                let activeSessionId = self.activeSessionIdProvider?()
                let activeDirectory = self.activeTabCwdProvider?()?.standardizedFileURL
                let sameSession = activeSessionId == event.sessionId
                let sameDirectory = event.cwd.map { URL(fileURLWithPath: $0).standardizedFileURL == activeDirectory } ?? false

                switch event.type {
                case .postToolUse, .postToolUseFailure:
                    if sameSession || sameDirectory || self.isVisible {
                        self.refreshDiffs()
                    }
                case .taskCompleted, .sessionEnd, .stop:
                    guard self.autoShowEnabledProvider?() ?? true else { return }
                    if (sameSession || sameDirectory) && !self.tracker.trackedFiles(for: event.sessionId).isEmpty {
                        self.activeSessionId = event.sessionId
                        self.shouldAutoShow = true
                        self.refreshDiffs()
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    private func applyDiffResult(_ result: Result<[FileDiff], Error>, sessionId: String, generation: UInt64) {
        guard generation == refreshGeneration else { return }
        switch result {
        case .success(let diffs):
            currentDiffs = diffs
            reconcileSelection(with: diffs)
            reviewRounds = tracker.reviewRounds(for: sessionId)
            lastErrorMessage = nil
            lastInfoMessage = tracker.snapshotNotice(for: sessionId)
            isLoading = false
            onDiffsUpdated?(diffs)
        case .failure:
            currentDiffs = []
            reviewRounds = tracker.reviewRounds(for: sessionId)
            lastErrorMessage = Self.userFacingErrorMessage(for: result.failureValue)
            lastInfoMessage = nil
            isLoading = false
        }
    }

    private func reconcileSelection(with diffs: [FileDiff]) {
        guard !diffs.isEmpty else {
            selectedFilePath = nil
            selectedHunkID = nil
            selectedLineNumber = nil
            return
        }

        if let selectedFilePath,
           diffs.contains(where: { $0.filePath == selectedFilePath }) == false {
            self.selectedFilePath = nil
        }

        if self.selectedFilePath == nil {
            self.selectedFilePath = diffs.first?.filePath
        }

        guard let fileDiff = selectedFileDiff else {
            selectedHunkID = nil
            selectedLineNumber = nil
            return
        }

        if let selectedHunkID,
           fileDiff.hunks.contains(where: { $0.id == selectedHunkID }) == false {
            self.selectedHunkID = nil
        }

        if self.selectedHunkID == nil {
            self.selectedHunkID = fileDiff.hunks.first?.id
        }

        if let selectedLineNumber,
           fileDiff.hunks.flatMap(\.lines).contains(where: { $0.displayLineNumber == selectedLineNumber }) == false {
            self.selectedLineNumber = nil
        }
    }

    private static func loadDirectDiff(
        workingDirectory: URL,
        mode: DiffMode,
        reference: String?
    ) async throws -> [FileDiff] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let arguments: [String]
                    switch mode {
                    case .uncommitted:
                        arguments = ["diff", "--no-color", "--", "."]
                    case .sinceSessionStart:
                        let base = reference ?? "HEAD"
                        arguments = ["diff", "--no-color", base, "--", "."]
                    case .vsBranch:
                        let base = reference ?? "HEAD"
                        arguments = ["diff", "--no-color", base, "--", "."]
                    }

                    let raw = try SessionDiffTrackerImpl.runGit(workingDirectory, arguments)
                    continuation.resume(returning: DiffParser.parse(raw))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func userFacingErrorMessage(for error: Error?) -> String? {
        guard let error else { return nil }
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return "The review panel could not complete that action." }
        return message
    }
}

private extension Result {
    var failureValue: Failure? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
