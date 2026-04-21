// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewPanelViewModel.swift - Main state coordinator for the review panel.

import Combine
import Foundation

enum CodeReviewEditorSplitLayout: String, CaseIterable, Identifiable {
    case stacked
    case sideBySide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stacked: return "Stacked"
        case .sideBySide: return "Side by side"
        }
    }

    var systemImage: String {
        switch self {
        case .stacked: return "rectangle.split.2x1"
        case .sideBySide: return "rectangle.split.2x2"
        }
    }
}

struct CodeReviewPendingEditorSwitch: Identifiable, Equatable {
    let targetFilePath: String

    var id: String { targetFilePath }
}

struct CodeReviewEditorCommandToken: Equatable {
    enum Kind: Equatable {
        case undo
        case redo
    }

    let id = UUID()
    let kind: Kind
}

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
    @Published private(set) var gitStatus: CodeReviewGitStatus?
    @Published private(set) var isGitActionRunning = false
    @Published var branchNameDraft = ""
    @Published var commitMessageDraft = ""
    @Published var isEditorVisible = false
    @Published var editorContent = ""
    @Published var editorHeight: Double = 420
    @Published var editorFontSize: Double = 13
    @Published var isEditorExpanded = false
    @Published var isGitWorkflowVisible = false
    @Published var editorSplitLayout: CodeReviewEditorSplitLayout = .stacked
    @Published var editorSplitFraction: Double = 0.48
    @Published var pendingEditorSwitch: CodeReviewPendingEditorSwitch?
    @Published var editorCommandToken: CodeReviewEditorCommandToken?
    @Published private(set) var editorFilePath: String?
    @Published private(set) var editorLanguage = "Plain Text"
    @Published private(set) var editorErrorMessage: String?
    @Published private(set) var editorOriginalContent = ""
    @Published private(set) var reviewAgentSessions: [AgentSessionInfo] = []

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
    private let gitWorkflow: CodeReviewGitWorkflowing
    private var refreshGeneration: UInt64 = 0
    private var refreshTask: Task<Void, Never>?
    private var gitActionTask: Task<Void, Never>?
    private var gitStatusTask: Task<Void, Never>?
    private var dashboardSessionCancellable: AnyCancellable?
    private var allAgentSessionsSnapshot: [AgentSessionInfo] = []
    private var lastReviewSuggestionKey: String?

    /// Debounced refresh trigger for FileChanged hooks. A new event resets the
    /// pending work item so a burst of edits collapses into a single diff
    /// refresh after the burst settles.
    ///
    /// Module-internal (not `private`) so the `+FileChanged` extension can
    /// own the scheduling/cancellation logic. External callers cannot reach
    /// this because the type itself is internal to `CocxyTerminal`.
    var fileChangeRefreshWorkItem: DispatchWorkItem?

    /// Debounce window applied to FileChanged events before refreshing diffs.
    /// Keeping this internal (test-tunable, not exposed in production) lets the
    /// integration tests collapse the wait without weakening the real default.
    var fileChangeRefreshDebounce: TimeInterval = 0.2

    init(
        tracker: SessionDiffTracking,
        hookEventReceiver: HookEventReceiving? = nil,
        commentStore: CommentStore = CommentStore(),
        gitWorkflow: CodeReviewGitWorkflowing = CodeReviewGitWorkflowService(),
        directDiffLoader: (@Sendable (URL, DiffMode, String?) async throws -> [FileDiff])? = nil
    ) {
        self.tracker = tracker
        self.hookEventReceiver = hookEventReceiver
        self.commentStore = commentStore
        self.gitWorkflow = gitWorkflow
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

    var reviewSubagentCount: Int {
        reviewAgentSessions.reduce(0) { $0 + $1.subagents.count }
    }

    var reviewTouchedFileCount: Int {
        Set(reviewAgentSessions.flatMap { $0.filesTouched.map(\.path) }).count
    }

    var reviewConflictCount: Int {
        Set(reviewAgentSessions.flatMap(\.fileConflicts)).count
    }

    var reviewToolCallCount: Int {
        reviewAgentSessions.reduce(0) { $0 + $1.totalToolCalls }
    }

    var reviewErrorCount: Int {
        reviewAgentSessions.reduce(0) { $0 + $1.totalErrors }
    }

    func bindAgentSessionsPublisher(_ publisher: AnyPublisher<[AgentSessionInfo], Never>) {
        dashboardSessionCancellable = publisher
            .sink { [weak self] sessions in
                Task { @MainActor in
                    self?.applyAgentSessionsSnapshot(sessions)
                }
            }
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
        if path == selectedFilePath {
            if isEditorVisible, editorFilePath != path {
                if isEditorDirty {
                    pendingEditorSwitch = CodeReviewPendingEditorSwitch(targetFilePath: path)
                } else {
                    openFileInEditor(path)
                }
            }
            return
        }
        if isEditorVisible, isEditorDirty, editorFilePath != path {
            pendingEditorSwitch = CodeReviewPendingEditorSwitch(targetFilePath: path)
            return
        }
        applyFileSelection(path, syncEditorIfOpen: true)
    }

    func refreshDiffs() {
        refreshTask?.cancel()
        refreshGeneration &+= 1
        let generation = refreshGeneration

        let sessionId = activeSessionIdProvider?()
        activeSessionId = sessionId
        activeTabID = activeTabIDProvider?()
        rebuildReviewAgentSessions()
        lastErrorMessage = nil
        lastInfoMessage = nil
        isLoading = true

        if let sessionId {
            activeWorkingDirectory = tracker.workingDirectory(for: sessionId) ?? activeTabCwdProvider?()
            refreshGitStatus()
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
        refreshGitStatus()

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

    var isEditorDirty: Bool {
        editorContent != editorOriginalContent
    }

    func refreshGitStatus() {
        guard let workingDirectory = activeWorkingDirectory ?? resolvedWorkingDirectory else {
            gitStatus = nil
            return
        }

        let workflow = gitWorkflow
        gitStatusTask?.cancel()
        gitStatusTask = Task { [weak self] in
            do {
                let status = try await Task.detached(priority: .userInitiated) {
                    try workflow.status(workingDirectory: workingDirectory)
                }.value
                await MainActor.run {
                    self?.gitStatus = status
                }
            } catch {
                await MainActor.run {
                    self?.gitStatus = nil
                }
            }
        }
    }

    func createBranchFromDraft() {
        let branchName = branchNameDraft
        performGitAction(successMessage: "Branch created.") { workflow, workingDirectory in
            try workflow.createBranch(named: branchName, workingDirectory: workingDirectory)
            return nil
        }
    }

    func commitAllChangesFromDraft() {
        let message = commitMessageDraft
        performGitAction(successMessage: "Commit created.") { workflow, workingDirectory in
            try workflow.commitAll(message: message, workingDirectory: workingDirectory)
        }
    }

    func pushCurrentBranch() {
        performGitAction(successMessage: "Branch pushed.") { workflow, workingDirectory in
            try workflow.pushCurrentBranch(workingDirectory: workingDirectory)
        }
    }

    func toggleGitWorkflowVisibility() {
        isGitWorkflowVisible.toggle()
        if isGitWorkflowVisible {
            refreshGitStatus()
        }
    }

    func openSelectedFileInEditor() {
        guard let fileDiff = selectedFileDiff else { return }
        openFileInEditor(fileDiff.filePath)
    }

    func openFileInEditor(_ filePath: String) {
        guard let fileURL = resolvedFileURL(for: filePath) else {
            editorErrorMessage = "The selected file is outside the review working directory."
            return
        }

        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            editorFilePath = filePath
            editorContent = content
            editorOriginalContent = content
            editorLanguage = Self.languageName(for: filePath)
            editorErrorMessage = nil
            isEditorVisible = true
        } catch {
            editorErrorMessage = Self.userFacingErrorMessage(for: error)
        }
    }

    func saveEditorContent() {
        _ = writeEditorContent(refreshAfterSave: true)
    }

    @discardableResult
    private func writeEditorContent(refreshAfterSave: Bool) -> Bool {
        guard let editorFilePath,
              let fileURL = resolvedFileURL(for: editorFilePath) else {
            editorErrorMessage = "The selected file is outside the review working directory."
            return false
        }

        do {
            try editorContent.write(to: fileURL, atomically: true, encoding: .utf8)
            editorOriginalContent = editorContent
            editorErrorMessage = nil
            if refreshAfterSave {
                refreshDiffs()
            }
            return true
        } catch {
            editorErrorMessage = Self.userFacingErrorMessage(for: error)
            return false
        }
    }

    func reloadEditorContent() {
        guard let editorFilePath else { return }
        openFileInEditor(editorFilePath)
    }

    func closeEditor() {
        isEditorVisible = false
        editorFilePath = nil
        editorContent = ""
        editorOriginalContent = ""
        editorLanguage = "Plain Text"
        editorErrorMessage = nil
        isEditorExpanded = false
    }

    func adjustEditorHeight(by delta: Double) {
        editorHeight = min(max(editorHeight + delta, 240), 900)
    }

    func adjustEditorSplitFraction(by delta: Double) {
        setEditorSplitFraction(editorSplitFraction + delta)
    }

    func setEditorSplitFraction(_ proposedFraction: Double) {
        editorSplitFraction = min(max(proposedFraction, 0.28), 0.72)
    }

    func adjustEditorFontSize(by delta: Double) {
        editorFontSize = min(max(editorFontSize + delta, 10), 22)
    }

    func toggleEditorExpanded() {
        isEditorExpanded.toggle()
    }

    func requestEditorUndo() {
        editorCommandToken = CodeReviewEditorCommandToken(kind: .undo)
    }

    func requestEditorRedo() {
        editorCommandToken = CodeReviewEditorCommandToken(kind: .redo)
    }

    func saveAndSwitchEditorFile() {
        guard let pendingEditorSwitch else { return }
        let target = pendingEditorSwitch.targetFilePath
        guard writeEditorContent(refreshAfterSave: false) else { return }
        self.pendingEditorSwitch = nil
        applyFileSelection(target, syncEditorIfOpen: true)
        refreshDiffs()
    }

    func discardAndSwitchEditorFile() {
        guard let pendingEditorSwitch else { return }
        let target = pendingEditorSwitch.targetFilePath
        self.pendingEditorSwitch = nil
        editorErrorMessage = nil
        applyFileSelection(target, syncEditorIfOpen: true)
    }

    func cancelEditorFileSwitch() {
        pendingEditorSwitch = nil
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

    private func applyFileSelection(_ path: String, syncEditorIfOpen: Bool) {
        selectedFilePath = path
        selectedLineNumber = nil
        selectedLineForComment = nil
        selectedHunkID = currentDiffs.first(where: { $0.filePath == path })?.hunks.first?.id
        if syncEditorIfOpen, isEditorVisible {
            openFileInEditor(path)
        }
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
            if let first = paths.first {
                selectFile(first)
            }
            return
        }
        let next = (index + 1) % paths.count
        selectFile(paths[next])
    }

    func previousFile() {
        guard !currentDiffs.isEmpty else { return }
        let paths = currentDiffs.map(\.filePath)
        guard let selectedFilePath,
              let index = paths.firstIndex(of: selectedFilePath) else {
            if let first = paths.first {
                selectFile(first)
            }
            return
        }
        let previous = (index - 1 + paths.count) % paths.count
        selectFile(paths[previous])
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

    private func applyAgentSessionsSnapshot(_ sessions: [AgentSessionInfo]) {
        allAgentSessionsSnapshot = sessions
        rebuildReviewAgentSessions()
    }

    func requestReviewSuggestionIfNeeded(key: String) {
        guard autoShowEnabledProvider?() ?? true else { return }
        guard !isVisible else { return }
        guard lastReviewSuggestionKey != key else { return }
        lastReviewSuggestionKey = key
        shouldAutoShow = true
    }

    private func rebuildReviewAgentSessions() {
        let resolvedSessionId = activeSessionId ?? activeSessionIdProvider?()
        let resolvedTabID = activeTabID ?? activeTabIDProvider?()
        let resolvedTabUUID = resolvedTabID?.rawValue

        let filtered = allAgentSessionsSnapshot.filter { session in
            if let resolvedSessionId, session.id == resolvedSessionId {
                return true
            }
            if let resolvedTabUUID, session.tabId == resolvedTabUUID {
                return true
            }
            return false
        }

        guard filtered != reviewAgentSessions else { return }
        reviewAgentSessions = filtered
    }

    private func performGitAction(
        successMessage: String,
        operation: @escaping @Sendable (CodeReviewGitWorkflowing, URL) throws -> String?
    ) {
        guard let workingDirectory = activeWorkingDirectory ?? resolvedWorkingDirectory else {
            lastErrorMessage = HunkActionError.invalidWorkingDirectory.localizedDescription
            lastInfoMessage = nil
            return
        }

        let workflow = gitWorkflow
        isGitActionRunning = true
        lastErrorMessage = nil
        lastInfoMessage = nil

        gitActionTask?.cancel()
        gitActionTask = Task { [weak self] in
            do {
                let output = try await Task.detached(priority: .userInitiated) {
                    try operation(workflow, workingDirectory)
                }.value
                await MainActor.run {
                    guard let self else { return }
                    self.isGitActionRunning = false
                    self.lastInfoMessage = output?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                        ? output?.trimmingCharacters(in: .whitespacesAndNewlines)
                        : successMessage
                    self.lastErrorMessage = nil
                    self.refreshGitStatus()
                    self.refreshDiffs()
                }
            } catch {
                await MainActor.run {
                    self?.isGitActionRunning = false
                    self?.lastErrorMessage = Self.userFacingErrorMessage(for: error)
                    self?.lastInfoMessage = nil
                }
            }
        }
    }

    private func resolvedFileURL(for filePath: String) -> URL? {
        guard let root = activeWorkingDirectory ?? resolvedWorkingDirectory else { return nil }
        let candidate = URL(fileURLWithPath: filePath, relativeTo: root).standardizedFileURL
        let rootPath = root.standardizedFileURL.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            return nil
        }
        return candidate
    }

    private func bindHookEvents() {
        hookEventReceiver?.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                let activeSessionId = self.activeSessionIdProvider?()
                let activeDirectory = self.activeTabCwdProvider?().map(HookPathNormalizer.normalize)
                let sameSession = activeSessionId == event.sessionId
                let sameDirectory = activeDirectory != nil
                    && event.cwd.map(HookPathNormalizer.normalize) == activeDirectory

                switch event.type {
                case .postToolUse, .postToolUseFailure:
                    if sameSession || sameDirectory || self.isVisible {
                        self.refreshDiffs()
                    }
                    if sameSession || sameDirectory,
                       !self.tracker.trackedFiles(for: event.sessionId).isEmpty {
                        self.requestReviewSuggestionIfNeeded(key: "\(event.sessionId):tool")
                    }
                case .taskCompleted, .sessionEnd, .stop:
                    guard self.autoShowEnabledProvider?() ?? true else { return }
                    if (sameSession || sameDirectory) && !self.tracker.trackedFiles(for: event.sessionId).isEmpty {
                        self.activeSessionId = event.sessionId
                        self.requestReviewSuggestionIfNeeded(key: "\(event.sessionId):finished")
                        self.refreshDiffs()
                    }
                case .fileChanged:
                    self.handleFileChangedHook(event)
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    // FileChanged handling lives in `+FileChanged.swift` to keep this file
    // under the 600-LOC ceiling and to give the new behaviour a clear,
    // self-documenting home.

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

    static func languageName(for filePath: String) -> String {
        switch URL(fileURLWithPath: filePath).pathExtension.lowercased() {
        case "swift": return "Swift"
        case "zig": return "Zig"
        case "js", "jsx": return "JavaScript"
        case "ts", "tsx": return "TypeScript"
        case "py": return "Python"
        case "rb": return "Ruby"
        case "php": return "PHP"
        case "java": return "Java"
        case "go": return "Go"
        case "rs": return "Rust"
        case "c", "h": return "C"
        case "cc", "cpp", "cxx", "hpp": return "C++"
        case "html", "htm": return "HTML"
        case "css": return "CSS"
        case "json": return "JSON"
        case "toml": return "TOML"
        case "yaml", "yml": return "YAML"
        case "md", "markdown": return "Markdown"
        case "sh", "bash", "zsh": return "Shell"
        default: return "Plain Text"
        }
    }
}

private extension Result {
    var failureValue: Failure? {
        guard case .failure(let error) = self else { return nil }
        return error
    }
}
