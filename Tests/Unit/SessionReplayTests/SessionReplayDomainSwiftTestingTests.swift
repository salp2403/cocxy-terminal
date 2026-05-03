// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SessionReplayDomainSwiftTestingTests.swift - Local session replay foundation.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Session Replay domain")
struct SessionReplayDomainSwiftTestingTests {
    @Test("policy requires enabled auto record and consent")
    func policyRequiresConsent() {
        #expect(SessionReplayPolicy.disabled.canAutoRecord == false)
        #expect(SessionReplayConfig(enabled: true, autoRecord: true, consentGranted: false).policy.canAutoRecord == false)
        #expect(SessionReplayConfig(enabled: true, autoRecord: false, consentGranted: true).policy.canAutoRecord == false)
        #expect(SessionReplayConfig(enabled: true, autoRecord: true, consentGranted: true).policy.canAutoRecord == true)
    }

    @Test("store prepares private recording bundle and lists finished metadata")
    func storePreparesPrivateRecordingBundleAndListsMetadata() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-store")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionReplayStore(rootDirectory: root)
        let surfaceID = SurfaceID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)

        let prepared = try store.prepareRecording(
            title: "Build smoke",
            surfaceID: surfaceID,
            createdAt: createdAt
        )
        try sampleCast().write(to: prepared.castURL, atomically: true, encoding: .utf8)
        try store.finishRecording(
            id: prepared.recording.id,
            durationNs: 1_500_000_000,
            byteCount: 128
        )

        let rootMode = try permissions(at: root)
        let metadataMode = try permissions(at: prepared.metadataURL)
        let castMode = try permissions(at: prepared.castURL)
        #expect(rootMode == 0o700)
        #expect(metadataMode == 0o600)
        #expect(castMode == 0o600)

        let recordings = try store.listRecordings()
        #expect(recordings.count == 1)
        #expect(recordings[0].title == "Build smoke")
        #expect(recordings[0].surfaceID == surfaceID)
        #expect(recordings[0].durationNs == 1_500_000_000)
        #expect(recordings[0].byteCount == 128)
        #expect(recordings[0].castRelativePath == "\(prepared.recording.id.uuidString)/session.cast")
    }

    @Test("bookmarks are clamped sorted and persisted with recording metadata")
    func bookmarksAreClampedSortedAndPersisted() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-bookmarks")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionReplayStore(rootDirectory: root)
        let prepared = try store.prepareRecording(title: "Replay", surfaceID: SurfaceID())
        try sampleCast().write(to: prepared.castURL, atomically: true, encoding: .utf8)
        try store.finishRecording(
            id: prepared.recording.id,
            durationNs: 2_000_000_000,
            byteCount: 256
        )

        let late = try store.addBookmark(
            recordingID: prepared.recording.id,
            offsetNs: 3_000_000_000,
            label: "Done"
        )
        let early = try store.addBookmark(
            recordingID: prepared.recording.id,
            offsetNs: 500_000_000,
            label: "Start"
        )

        #expect(late.offsetNs == 2_000_000_000)
        #expect(try store.bookmarks(for: prepared.recording.id).map(\.id) == [early.id, late.id])
        #expect(try store.listRecordings().first?.bookmarks.map(\.label) == ["Start", "Done"])
    }

    @Test("cast search returns output snippets with nanosecond offsets")
    func castSearchReturnsOutputSnippetsWithOffsets() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-search")
        defer { try? FileManager.default.removeItem(at: root) }

        let store = SessionReplayStore(rootDirectory: root)
        let prepared = try store.prepareRecording(title: "Search", surfaceID: SurfaceID())
        try sampleCast().write(to: prepared.castURL, atomically: true, encoding: .utf8)
        try store.finishRecording(id: prepared.recording.id, durationNs: 1_500_000_000, byteCount: 512)

        let matches = try store.search(recordingID: prepared.recording.id, query: "swift test")

        #expect(matches.count == 1)
        #expect(matches[0].recordingID == prepared.recording.id)
        #expect(matches[0].offsetNs == 1_250_000_000)
        #expect(matches[0].snippet.contains("swift test --filter SessionReplay"))
    }

    @Test("cast search ignores impossible timestamps")
    func castSearchIgnoresImpossibleTimestamps() {
        let recordingID = UUID()
        let matches = SessionReplayCastSearch.matches(
            in: """
            [1.0e40,"o","swift test"]

            """,
            recordingID: recordingID,
            query: "swift test"
        )

        #expect(matches.isEmpty)
    }

    @Test("export copies the cast file without exposing metadata")
    func exportCopiesCastFileOnly() throws {
        let root = try makeTemporaryDirectory(named: "session-replay-export")
        let exportRoot = try makeTemporaryDirectory(named: "session-replay-export-target")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: exportRoot)
        }

        let store = SessionReplayStore(rootDirectory: root)
        let prepared = try store.prepareRecording(title: "Export", surfaceID: SurfaceID())
        try sampleCast().write(to: prepared.castURL, atomically: true, encoding: .utf8)
        try store.finishRecording(id: prepared.recording.id, durationNs: 1_000_000, byteCount: 64)

        let destination = exportRoot.appendingPathComponent("export.cast")
        try store.exportCast(recordingID: prepared.recording.id, to: destination)

        #expect(try String(contentsOf: destination, encoding: .utf8) == sampleCast())
        #expect(try permissions(at: destination) == 0o600)
    }

    private func sampleCast() -> String {
        """
        {"version":2,"width":80,"height":24,"timestamp":1800000000,"env":{"TERM":"xterm-256color"}}
        [0.0,"o","hello world\\r\\n"]
        [1.25,"o","swift test --filter SessionReplay\\r\\n"]

        """
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return url
    }

    private func permissions(at url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}
