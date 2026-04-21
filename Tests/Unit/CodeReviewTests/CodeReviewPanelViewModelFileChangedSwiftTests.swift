// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CodeReviewPanelViewModelFileChangedSwiftTests.swift
// Phase 2 coverage for the FileChanged auto-refresh handler — debounce,
// CWD exact match, file boundary check and visibility gating.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("CodeReviewPanelViewModel FileChanged auto-refresh")
struct CodeReviewPanelViewModelFileChangedSwiftTests {

    private static let activeCwd = URL(fileURLWithPath: "/private/tmp/active-project", isDirectory: true)
    private static let unrelatedCwd = URL(fileURLWithPath: "/private/tmp/unrelated", isDirectory: true)

    // Negative-path quiet windows: under parallel CI load, GCD scheduling
    // jitter means a refresh that would have fired could still be pending
    // ~1 s after we believe the work item should have run. Keeping the
    // quiet window generous (1.5 s) avoids relying on retries to mask
    // flakiness — see `feedback_no_retry_for_timeouts`.
    private static let negativeQuietWindowNanoseconds: UInt64 = 1_500_000_000

    @Test("FileChanged inside the active CWD triggers exactly one debounced refresh")
    func fileChangedInActiveCwdTriggersDebouncedRefresh() async throws {
        let harness = makeHarness()
        emit(.fileChanged, on: harness.receiver, cwd: Self.activeCwd.path,
             filePath: Self.activeCwd.appendingPathComponent("src/main.swift").path,
             changeType: "edit")

        try await waitForCondition { harness.refreshCount() >= 1 }
        // Flush the run loop a bit longer to make sure no stray refresh
        // sneaks in. 400 ms is enough even under parallel CI load.
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(harness.refreshCount() == 1)
    }

    @Test("FileChanged in an unrelated CWD does not refresh")
    func fileChangedInDifferentCwdIsIgnored() async throws {
        let harness = makeHarness()
        emit(.fileChanged, on: harness.receiver, cwd: Self.unrelatedCwd.path,
             filePath: Self.unrelatedCwd.appendingPathComponent("foo.swift").path)

        try await Task.sleep(nanoseconds: Self.negativeQuietWindowNanoseconds)
        #expect(harness.refreshCount() == 0)
    }

    @Test("Multiple rapid FileChanged events collapse into a single refresh")
    func multipleRapidFileChangedFiresOnlyOneRefresh() async throws {
        let harness = makeHarness()
        for index in 0..<6 {
            emit(.fileChanged, on: harness.receiver, cwd: Self.activeCwd.path,
                 filePath: Self.activeCwd.appendingPathComponent("burst-\(index).swift").path,
                 changeType: "write")
        }

        try await waitForCondition { harness.refreshCount() >= 1 }
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(harness.refreshCount() == 1)
    }

    @Test("FileChanged with file_path outside the active CWD is ignored")
    func fileChangedOutsideCwdPathIsIgnored() async throws {
        let harness = makeHarness()
        emit(.fileChanged, on: harness.receiver, cwd: Self.activeCwd.path,
             filePath: "/private/tmp/somewhere-else/file.swift")

        try await Task.sleep(nanoseconds: Self.negativeQuietWindowNanoseconds)
        #expect(harness.refreshCount() == 0)
    }

    @Test("FileChanged without a file_path is tolerated and skipped")
    func fileChangedWithoutFilePathIsTolerated() async throws {
        let harness = makeHarness()
        emit(.fileChanged, on: harness.receiver, cwd: Self.activeCwd.path,
             filePath: "")

        try await Task.sleep(nanoseconds: Self.negativeQuietWindowNanoseconds)
        #expect(harness.refreshCount() == 0)
    }

    @Test("FileChanged matches symlinked tmp paths after canonicalization")
    func fileChangedCanonicalizesSymlinkedTmpPaths() async throws {
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("file-changed-\(UUID().uuidString)", isDirectory: true)
        let nestedFile = directory.appendingPathComponent("src/main.swift")
        try FileManager.default.createDirectory(
            at: nestedFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let receiver = HookEventReceiverImpl()
        let counter = AtomicInt()
        let viewModel = CodeReviewPanelViewModel(
            tracker: SessionDiffTrackerImpl(),
            hookEventReceiver: receiver,
            directDiffLoader: { _, _, _ in
                counter.increment()
                return []
            }
        )
        viewModel.activeTabCwdProvider = { directory }
        viewModel.fileChangeRefreshDebounce = 0.05
        viewModel.refreshDelay = 0
        viewModel.isVisible = true

        emit(
            .fileChanged,
            on: receiver,
            cwd: directory.resolvingSymlinksInPath().path,
            filePath: nestedFile.resolvingSymlinksInPath().path
        )

        try await waitForCondition { counter.value >= 1 }
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(counter.value == 1)
    }

    @Test("Hidden panel skips FileChanged refreshes and asks before opening review")
    func noRefreshWhenPanelNotVisible() async throws {
        let harness = makeHarness(initiallyVisible: false)
        harness.viewModel.autoShowEnabledProvider = { true }
        emit(.fileChanged, on: harness.receiver, cwd: Self.activeCwd.path,
             filePath: Self.activeCwd.appendingPathComponent("ignored.swift").path)

        try await Task.sleep(nanoseconds: Self.negativeQuietWindowNanoseconds)
        #expect(harness.refreshCount() == 0)
        #expect(harness.viewModel.shouldAutoShow)
    }

    // MARK: - Harness

    private struct Harness {
        let viewModel: CodeReviewPanelViewModel
        let receiver: HookEventReceiverImpl
        let refreshCount: () -> Int
    }

    private func makeHarness(initiallyVisible: Bool = true) -> Harness {
        let receiver = HookEventReceiverImpl()
        let counter = AtomicInt()
        let viewModel = CodeReviewPanelViewModel(
            tracker: SessionDiffTrackerImpl(),
            hookEventReceiver: receiver,
            directDiffLoader: { _, _, _ in
                counter.increment()
                return []
            }
        )
        viewModel.activeTabCwdProvider = { Self.activeCwd }
        viewModel.fileChangeRefreshDebounce = 0.05
        viewModel.refreshDelay = 0
        viewModel.isVisible = initiallyVisible
        return Harness(
            viewModel: viewModel,
            receiver: receiver,
            refreshCount: { counter.value }
        )
    }

    private func emit(
        _ type: HookEventType,
        on receiver: HookEventReceiverImpl,
        cwd: String,
        filePath: String,
        changeType: String? = nil
    ) {
        var payload: [String: Any] = [
            "hook_event_name": type.rawValue,
            "session_id": "sess-fc-test",
            "cwd": cwd,
            "file_path": filePath
        ]
        if let changeType {
            payload["change_type"] = changeType
        }
        let data = try! JSONSerialization.data(withJSONObject: payload)
        receiver.receiveRawJSON(data)
    }

    private func waitForCondition(
        // 8 s tolerates worst-case GCD scheduling delays observed under
        // parallel CI load. Using a generous timeout instead of retries
        // keeps stalls deterministic — see `feedback_no_retry_for_timeouts`.
        timeoutNanoseconds: UInt64 = 8_000_000_000,
        pollNanoseconds: UInt64 = 15_000_000,
        _ condition: () -> Bool
    ) async throws {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while condition() == false {
            if DispatchTime.now().uptimeNanoseconds >= deadline {
                Issue.record("Timed out waiting for refresh count update")
                return
            }
            try await Task.sleep(nanoseconds: pollNanoseconds)
        }
    }
}

/// Lock-protected counter shared between the directDiffLoader closure
/// (called off the main actor) and the test body (main actor).
private final class AtomicInt: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Int = 0

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return _value
    }

    func increment() {
        lock.lock(); defer { lock.unlock() }
        _value += 1
    }
}
