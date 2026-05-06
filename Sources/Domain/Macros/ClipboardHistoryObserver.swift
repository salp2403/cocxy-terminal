// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// ClipboardHistoryObserver.swift - Local system clipboard watcher for clipboard history.

import Foundation
import AppKit

struct ClipboardHistorySnapshot: Equatable {
    let changeCount: Int
    let text: String?
}

struct ClipboardHistoryObservationState: Equatable {
    private(set) var lastChangeCount: Int?

    mutating func reset(to snapshot: ClipboardHistorySnapshot) {
        lastChangeCount = snapshot.changeCount
    }

    mutating func textToRecord(from snapshot: ClipboardHistorySnapshot) -> String? {
        defer { lastChangeCount = snapshot.changeCount }
        guard snapshot.changeCount != lastChangeCount else { return nil }
        guard let text = snapshot.text,
              text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        else {
            return nil
        }
        return text
    }
}

final class ClipboardHistoryObserver: @unchecked Sendable {
    typealias SnapshotProvider = () -> ClipboardHistorySnapshot
    typealias TextHandler = (String) -> Void

    private let pollInterval: TimeInterval
    private let snapshotProvider: SnapshotProvider
    private let onText: TextHandler
    private var state = ClipboardHistoryObservationState()
    private var timer: Timer?

    init(
        pollInterval: TimeInterval = 1.0,
        snapshotProvider: @escaping SnapshotProvider,
        onText: @escaping TextHandler
    ) {
        self.pollInterval = max(0.25, pollInterval)
        self.snapshotProvider = snapshotProvider
        self.onText = onText
    }

    static func generalPasteboardSnapshot() -> ClipboardHistorySnapshot {
        let pasteboard = NSPasteboard.general
        return ClipboardHistorySnapshot(
            changeCount: pasteboard.changeCount,
            text: pasteboard.string(forType: .string)
        )
    }

    deinit {
        timer?.invalidate()
    }

    func start() {
        guard timer == nil else { return }
        state.reset(to: snapshotProvider())
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollNow()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pollNow() {
        guard let text = state.textToRecord(from: snapshotProvider()) else { return }
        onText(text)
    }
}
