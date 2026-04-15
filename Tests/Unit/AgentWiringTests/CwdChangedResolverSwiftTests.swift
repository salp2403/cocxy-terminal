// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CwdChangedResolverSwiftTests.swift
// Phase 4 coverage: pure resolution of CwdChanged hooks against tab snapshots.
// Tests the routing logic without booting AppKit, MainWindowController, or
// the full AppDelegate stack.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("CwdChangedResolver — pure routing for the CwdChanged hook")
struct CwdChangedResolverSwiftTests {

    @Test("CwdChanged moves the matching tab from previous to new path")
    func cwdChangedMovesTabFromOldToNewPath() {
        let oldPath = "/tmp/cwd-old"
        let newPath = "/tmp/cwd-new"
        let tab = makeTab(workingDirectory: oldPath)
        let snapshot = TabManagerSnapshot(tabs: [tab])

        let resolution = CwdChangedResolver.resolve(
            event: cwdChangedEvent(previous: oldPath, current: newPath),
            controllers: [snapshot]
        )

        #expect(resolution != nil)
        #expect(resolution?.controllerIndex == 0)
        #expect(resolution?.tabID == tab.id)
        #expect(resolution?.newWorkingDirectory.path == newPath)
    }

    @Test("CwdChanged with unknown previous CWD is ignored")
    func cwdChangedWithUnknownPreviousCwdIsIgnored() {
        let tab = makeTab(workingDirectory: "/tmp/tab-actual")
        let snapshot = TabManagerSnapshot(tabs: [tab])

        let resolution = CwdChangedResolver.resolve(
            event: cwdChangedEvent(previous: "/tmp/something-else", current: "/tmp/new"),
            controllers: [snapshot]
        )

        #expect(resolution == nil)
    }

    @Test("CwdChanged where previous == current is a no-op")
    func cwdChangedSameAsCurrentIsNoOp() {
        let path = "/tmp/no-change"
        let tab = makeTab(workingDirectory: path)
        let snapshot = TabManagerSnapshot(tabs: [tab])

        let resolution = CwdChangedResolver.resolve(
            event: cwdChangedEvent(previous: path, current: path),
            controllers: [snapshot]
        )

        #expect(resolution == nil)
    }

    @Test("CwdChanged with missing previous_cwd is dropped")
    func cwdChangedWithMissingPreviousCwdIsDropped() {
        let tab = makeTab(workingDirectory: "/tmp/proj")
        let snapshot = TabManagerSnapshot(tabs: [tab])

        let event = HookEvent(
            type: .cwdChanged,
            sessionId: "sess-x",
            data: .cwdChanged(CwdChangedData(previousCwd: nil)),
            cwd: "/tmp/proj-new"
        )

        let resolution = CwdChangedResolver.resolve(
            event: event,
            controllers: [snapshot]
        )
        #expect(resolution == nil)
    }

    @Test("CwdChanged with missing event.cwd is dropped")
    func cwdChangedWithMissingNewCwdIsDropped() {
        let tab = makeTab(workingDirectory: "/tmp/proj")
        let snapshot = TabManagerSnapshot(tabs: [tab])

        let event = HookEvent(
            type: .cwdChanged,
            sessionId: "sess-x",
            data: .cwdChanged(CwdChangedData(previousCwd: "/tmp/proj")),
            cwd: nil
        )

        let resolution = CwdChangedResolver.resolve(
            event: event,
            controllers: [snapshot]
        )
        #expect(resolution == nil)
    }

    @Test("Race-free dedup: tab already at the new CWD skips re-firing")
    func raceFreeDedupSkipsWhenTabAlreadyAtNewCwd() {
        // Simulates OSC 7 having already updated the tab's CWD before the
        // CwdChanged hook arrived. previousCwd matches an older value but
        // the tab is now at the new path — no work to do.
        let oldPath = "/tmp/race-old"
        let newPath = "/tmp/race-new"
        let tabAlreadyAtNew = makeTab(workingDirectory: newPath)
        let snapshot = TabManagerSnapshot(tabs: [tabAlreadyAtNew])

        let resolution = CwdChangedResolver.resolve(
            event: cwdChangedEvent(previous: oldPath, current: newPath),
            controllers: [snapshot]
        )

        #expect(resolution == nil)
    }

    @Test("Multi-controller search resolves the uniquely matching window")
    func multiControllerSearchReturnsTheUniqueMatch() {
        let tabA = makeTab(workingDirectory: "/tmp/win-A")
        let tabB = makeTab(workingDirectory: "/tmp/win-B")
        let snapshotA = TabManagerSnapshot(tabs: [tabA])
        let snapshotB = TabManagerSnapshot(tabs: [tabB])

        let resolution = CwdChangedResolver.resolve(
            event: cwdChangedEvent(previous: "/tmp/win-B", current: "/tmp/win-B-new"),
            controllers: [snapshotA, snapshotB]
        )

        #expect(resolution?.controllerIndex == 1)
        #expect(resolution?.tabID == tabB.id)
        #expect(resolution?.newWorkingDirectory.path == "/tmp/win-B-new")
    }

    @Test("Ambiguous duplicate previous CWDs are dropped instead of picking arbitrarily")
    func ambiguousDuplicatePreviousCwdsAreDropped() {
        let firstTab = makeTab(workingDirectory: "/tmp/shared")
        let secondTab = makeTab(workingDirectory: "/tmp/shared")

        let resolution = CwdChangedResolver.resolve(
            event: cwdChangedEvent(previous: "/tmp/shared", current: "/tmp/shared-next"),
            controllers: [
                TabManagerSnapshot(tabs: [firstTab]),
                TabManagerSnapshot(tabs: [secondTab]),
            ]
        )

        #expect(resolution == nil)
    }

    @Test("Wrong event.type yields nil even when payload looks valid")
    func resolverIgnoresNonCwdChangedEvents() {
        let tab = makeTab(workingDirectory: "/tmp/proj")
        let snapshot = TabManagerSnapshot(tabs: [tab])

        let event = HookEvent(
            type: .fileChanged,
            sessionId: "sess-misuse",
            data: .cwdChanged(CwdChangedData(previousCwd: "/tmp/proj")),
            cwd: "/tmp/proj-new"
        )

        let resolution = CwdChangedResolver.resolve(
            event: event,
            controllers: [snapshot]
        )
        #expect(resolution == nil)
    }

    @Test("CwdChanged normalizes symlinked macOS paths before exact matching")
    func cwdChangedNormalizesSymlinkedPaths() throws {
        let baseDirectory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("cwd-changed-\(UUID().uuidString)", isDirectory: true)
        let nextDirectory = baseDirectory.appendingPathComponent("next", isDirectory: true)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nextDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let tab = makeTab(workingDirectory: baseDirectory.path)
        let snapshot = TabManagerSnapshot(tabs: [tab])

        let resolution = CwdChangedResolver.resolve(
            event: cwdChangedEvent(
                previous: baseDirectory.resolvingSymlinksInPath().path,
                current: nextDirectory.path
            ),
            controllers: [snapshot]
        )

        #expect(resolution != nil)
        #expect(resolution?.tabID == tab.id)
        #expect(
            HookPathNormalizer.normalize(
                resolution?.newWorkingDirectory.path ?? ""
            ) == HookPathNormalizer.normalize(nextDirectory.path)
        )
    }

    // MARK: - Helpers

    private func makeTab(workingDirectory path: String) -> Tab {
        Tab(
            workingDirectory: URL(fileURLWithPath: path, isDirectory: true)
        )
    }

    private func cwdChangedEvent(previous: String, current: String) -> HookEvent {
        HookEvent(
            type: .cwdChanged,
            sessionId: "sess-resolver",
            data: .cwdChanged(CwdChangedData(previousCwd: previous)),
            cwd: current
        )
    }
}
