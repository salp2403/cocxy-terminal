// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Combine
import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("CodeReview integration")
struct CodeReviewIntegrationSwiftTestingTests {
    @Test("ViewModel refresh populates diffs and selectFile updates selection")
    func refreshAndSelectFile() async throws {
        let tracker = SessionDiffTrackerImpl()
        let cwd = URL(fileURLWithPath: "/tmp", isDirectory: true)
        tracker.recordSnapshot(sessionId: "s1", ref: "abc123", workingDirectory: cwd)

        let viewModel = CodeReviewPanelViewModel(
            tracker: tracker,
            hookEventReceiver: nil,
            directDiffLoader: { _, _, _ in
                [
                    FileDiff(
                        filePath: "foo.swift",
                        status: .modified,
                        hunks: [
                            DiffHunk(
                                header: "@@ -1,1 +1,2 @@",
                                oldStart: 1,
                                oldCount: 1,
                                newStart: 1,
                                newCount: 2,
                                lines: [
                                    DiffLine(kind: .context, content: "hello", oldLineNumber: 1, newLineNumber: 1),
                                    DiffLine(kind: .addition, content: "world", oldLineNumber: nil, newLineNumber: 2),
                                ]
                            )
                        ]
                    )
                ]
            }
        )
        viewModel.activeTabCwdProvider = { cwd }

        viewModel.refreshDiffs()
        try await waitForReviewCondition {
            viewModel.currentDiffs.count == 1
        }

        #expect(viewModel.currentDiffs.count == 1)
        viewModel.selectFile("foo.swift")
        #expect(viewModel.selectedFilePath == "foo.swift")
    }

    @Test("submitComments formats and clears pending comments")
    func submitComments() {
        let tracker = SessionDiffTrackerImpl()
        tracker.recordSnapshot(
            sessionId: "s1",
            ref: "abc123",
            workingDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true)
        )

        let viewModel = CodeReviewPanelViewModel(tracker: tracker, hookEventReceiver: nil)
        viewModel.activeSessionIdProvider = { "s1" }
        viewModel.refreshDiffs()
        viewModel.refreshDelay = 0

        var sentText: String?
        viewModel.ptyWriteHandler = { text, _, _, _ in
            sentText = text
            return true
        }

        viewModel.addComment(filePath: "foo.swift", line: 12, body: "Handle nil")
        viewModel.submitComments()

        #expect(sentText?.contains("foo.swift") == true)
        #expect(viewModel.pendingComments.isEmpty)
        #expect(tracker.reviewRounds(for: "s1").count == 1)
    }

    @Test("submit stays bound to the loaded review context even after tab providers change")
    func submitUsesLoadedReviewContext() async throws {
        let tracker = SessionDiffTrackerImpl()
        let cwdA = URL(fileURLWithPath: "/tmp/review-a", isDirectory: true)
        let cwdB = URL(fileURLWithPath: "/tmp/review-b", isDirectory: true)
        tracker.recordSnapshot(sessionId: "s1", ref: "aaa111", workingDirectory: cwdA)
        tracker.recordSnapshot(sessionId: "s2", ref: "bbb222", workingDirectory: cwdB)

        let tabA = TabID()
        let tabB = TabID()

        let viewModel = CodeReviewPanelViewModel(
            tracker: tracker,
            hookEventReceiver: nil,
            directDiffLoader: { _, _, _ in
                [FileDiff(filePath: "foo.swift", status: .modified, hunks: [])]
            }
        )
        viewModel.activeSessionIdProvider = { "s1" }
        viewModel.activeTabCwdProvider = { cwdA }
        viewModel.activeTabIDProvider = { tabA }
        viewModel.refreshDelay = 0

        viewModel.refreshDiffs()
        try await waitForReviewCondition {
            viewModel.activeSessionId == "s1" && viewModel.activeWorkingDirectory == cwdA
        }

        viewModel.activeSessionIdProvider = { "s2" }
        viewModel.activeTabCwdProvider = { cwdB }
        viewModel.activeTabIDProvider = { tabB }

        var submittedSessionID: String?
        var submittedDirectory: URL?
        var submittedTabID: TabID?
        viewModel.ptyWriteHandler = { _, sessionId, workingDirectory, tabID in
            submittedSessionID = sessionId
            submittedDirectory = workingDirectory
            submittedTabID = tabID
            return true
        }

        viewModel.addComment(filePath: "foo.swift", line: 7, body: "Keep this with session A")
        viewModel.submitComments()

        #expect(submittedSessionID == "s1")
        #expect(submittedDirectory == cwdA)
        #expect(submittedTabID == tabA)
        #expect(tracker.reviewRounds(for: "s1").count == 1)
        #expect(tracker.reviewRounds(for: "s2").isEmpty)
    }

    @Test("submit keeps drafts and surfaces an error when the original terminal is gone")
    func submitPreservesDraftsOnRouteFailure() async throws {
        let tracker = SessionDiffTrackerImpl()
        let cwd = URL(fileURLWithPath: "/tmp/review-submit-failure", isDirectory: true)
        tracker.recordSnapshot(sessionId: "s1", ref: "abc123", workingDirectory: cwd)

        let viewModel = CodeReviewPanelViewModel(
            tracker: tracker,
            hookEventReceiver: nil,
            directDiffLoader: { _, _, _ in
                [FileDiff(filePath: "foo.swift", status: .modified, hunks: [])]
            }
        )
        viewModel.activeSessionIdProvider = { "s1" }
        viewModel.activeTabCwdProvider = { cwd }
        viewModel.refreshDiffs()
        try await waitForReviewCondition {
            viewModel.activeSessionId == "s1"
        }

        viewModel.ptyWriteHandler = { _, _, _, _ in false }
        viewModel.addComment(filePath: "foo.swift", line: 3, body: "Still pending")
        viewModel.submitComments()

        #expect(viewModel.pendingComments.count == 1)
        #expect(viewModel.lastErrorMessage?.contains("could not be sent") == true)
        #expect(tracker.reviewRounds(for: "s1").isEmpty)
    }

    @Test("session end auto-triggers review when tracked files exist")
    func sessionEndAutoShowsReview() async throws {
        let tracker = SessionDiffTrackerImpl()
        let cwd = URL(fileURLWithPath: "/tmp/code-review-auto-show", isDirectory: true)
        tracker.recordSnapshot(sessionId: "s1", ref: "abc123", workingDirectory: cwd)
        tracker.trackFile(sessionId: "s1", filePath: "Sources/Foo.swift", agentName: "codex")

        let hookReceiver = HookEventReceiverStub()
        let viewModel = CodeReviewPanelViewModel(
            tracker: tracker,
            hookEventReceiver: hookReceiver,
            directDiffLoader: { _, _, _ in [] }
        )
        viewModel.activeSessionIdProvider = { "s1" }
        viewModel.activeTabCwdProvider = { cwd }
        viewModel.autoShowEnabledProvider = { true }

        hookReceiver.send(HookEvent(type: .sessionEnd, sessionId: "s1", cwd: cwd.path))
        try await waitForReviewCondition {
            viewModel.shouldAutoShow && viewModel.activeSessionId == "s1"
        }

        #expect(viewModel.shouldAutoShow)
        #expect(viewModel.activeSessionId == "s1")
    }

    @Test("refreshDiffs ignores stale completions from an older request")
    func refreshDiffsIgnoresStaleCompletion() async throws {
        let cwd = URL(fileURLWithPath: "/tmp/review-stale", isDirectory: true)
        let oldDiff = [FileDiff(filePath: "old.swift", status: .modified, hunks: [])]
        let newDiff = [FileDiff(filePath: "new.swift", status: .modified, hunks: [])]
        let counter = LockedCounter()
        let firstLoaderStarted = AsyncGate()
        let firstLoaderGate = AsyncGate()

        let viewModel = CodeReviewPanelViewModel(
            tracker: SessionDiffTrackerImpl(),
            hookEventReceiver: nil,
            directDiffLoader: { _, _, _ in
                let call = counter.next()
                if call == 1 {
                    await firstLoaderStarted.open()
                    await firstLoaderGate.wait()
                    return oldDiff
                }
                return newDiff
            }
        )
        viewModel.activeTabCwdProvider = { cwd }

        viewModel.refreshDiffs()
        await firstLoaderStarted.waitUntilOpened()
        viewModel.refreshDiffs()

        try await waitForReviewCondition(timeoutNanoseconds: 3_000_000_000) {
            viewModel.isLoading == false && viewModel.currentDiffs.first?.filePath == "new.swift"
        }
        await firstLoaderGate.open()
        try await waitForReviewCondition(timeoutNanoseconds: 3_000_000_000) {
            viewModel.isLoading == false && viewModel.currentDiffs.first?.filePath == "new.swift"
        }

        #expect(viewModel.currentDiffs.count == 1)
        #expect(viewModel.currentDiffs.first?.filePath == "new.swift")
        #expect(viewModel.isLoading == false)
    }

    @Test("refreshDiffs surfaces loader errors instead of failing silently")
    func refreshDiffsSurfacesErrors() async throws {
        enum TestError: Error, LocalizedError {
            case explode
            var errorDescription: String? { "Loader failed." }
        }

        let cwd = URL(fileURLWithPath: "/tmp/review-error", isDirectory: true)
        let viewModel = CodeReviewPanelViewModel(
            tracker: SessionDiffTrackerImpl(),
            hookEventReceiver: nil,
            directDiffLoader: { _, _, _ in throw TestError.explode }
        )
        viewModel.activeTabCwdProvider = { cwd }

        viewModel.refreshDiffs()
        try await waitForReviewCondition {
            viewModel.isLoading == false && viewModel.lastErrorMessage != nil
        }

        #expect(viewModel.currentDiffs.isEmpty)
        #expect(viewModel.lastErrorMessage == "Loader failed.")
    }

    @Test("refreshDiffs surfaces snapshot notices as informational messages")
    func refreshDiffsSurfacesSnapshotNotice() async throws {
        let tracker = NoticeTracker()
        let cwd = URL(fileURLWithPath: "/tmp/review-info", isDirectory: true)
        let viewModel = CodeReviewPanelViewModel(
            tracker: tracker,
            hookEventReceiver: nil,
            directDiffLoader: nil
        )
        viewModel.activeSessionIdProvider = { "s1" }
        viewModel.activeTabCwdProvider = { cwd }

        viewModel.refreshDiffs()
        try await waitForReviewCondition {
            viewModel.isLoading == false && viewModel.lastInfoMessage != nil
        }

        #expect(viewModel.currentDiffs.count == 1)
        #expect(viewModel.lastErrorMessage == nil)
        #expect(viewModel.lastInfoMessage?.contains("working tree") == true)
    }
}

private final class NoticeTracker: SessionDiffTracking {
    private let cwd = URL(fileURLWithPath: "/tmp/review-info", isDirectory: true)

    func recordSnapshot(sessionId: String, ref: String, workingDirectory: URL) {}
    func snapshotRef(for sessionId: String) -> String? { "abc123" }
    func snapshotNotice(for sessionId: String) -> String? {
        "This session started before Git had a commit to diff against, so the review is comparing against the current working tree."
    }
    func workingDirectory(for sessionId: String) -> URL? { cwd }
    func removeSnapshot(sessionId: String) {}
    func trackFile(sessionId: String, filePath: String, agentName: String?) {}
    func trackedFiles(for sessionId: String) -> Set<String> { [] }
    func pendingSnapshot(for sessionId: String) -> URL? { nil }
    func latestSessionId(for workingDirectory: URL) -> String? { nil }
    func reviewRounds(for sessionId: String) -> [ReviewRound] { [] }
    func appendReviewRound(sessionId: String, round: ReviewRound) {}
    func handleHookEvent(_ event: HookEvent) {}
    func snapshotCurrentHead(
        sessionId: String,
        workingDirectory: URL,
        completion: (@Sendable (Result<String, Error>) -> Void)?
    ) {
        completion?(.success("abc123"))
    }
    func computeDiff(
        sessionId: String,
        mode: DiffMode,
        reference: String?,
        completion: @escaping @Sendable (Result<[FileDiff], Error>) -> Void
    ) {
        completion(.success([FileDiff(filePath: "foo.swift", status: .modified, hunks: [])]))
    }
}

private final class HookEventReceiverStub: HookEventReceiving {
    private let subject = PassthroughSubject<HookEvent, Never>()

    @discardableResult
    func receiveRawJSON(_ data: Data) -> Bool { false }

    var eventPublisher: AnyPublisher<HookEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    var activeSessionIds: Set<String> = []
    var receivedEventCount: Int = 0
    var failedEventCount: Int = 0

    func send(_ event: HookEvent) {
        subject.send(event)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pendingWaiters = waiters
        waiters.removeAll()
        pendingWaiters.forEach { $0.resume() }
    }

    func waitUntilOpened() async {
        await wait()
    }
}

@MainActor
private func waitForReviewCondition(
    timeoutNanoseconds: UInt64 = 3_000_000_000,
    pollNanoseconds: UInt64 = 20_000_000,
    _ condition: () -> Bool
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while condition() == false {
        if DispatchTime.now().uptimeNanoseconds >= deadline {
            Issue.record("Timed out waiting for asynchronous review state update")
            return
        }
        try await Task.sleep(nanoseconds: pollNanoseconds)
    }
}
