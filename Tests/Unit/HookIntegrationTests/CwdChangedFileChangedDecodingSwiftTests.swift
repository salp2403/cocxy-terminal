// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CwdChangedFileChangedDecodingSwiftTests.swift
// Verifies decoding, round-trip encoding, and tolerant handling of the
// new Claude Code 2.1.83+ filesystem lifecycle hooks.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("CwdChanged and FileChanged event decoding")
struct CwdChangedFileChangedDecodingSwiftTests {

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - CwdChanged

    @Test("CwdChanged decodes all fields including previous_cwd")
    func cwdChangedDecodesWithAllFields() throws {
        let json = #"""
        {
            "hook_event_name": "CwdChanged",
            "session_id": "sess-cwd-001",
            "cwd": "/Users/dev/project/sub",
            "previous_cwd": "/Users/dev/project"
        }
        """#

        let event = try makeDecoder().decode(HookEvent.self, from: Data(json.utf8))

        #expect(event.type == .cwdChanged)
        #expect(event.sessionId == "sess-cwd-001")
        #expect(event.cwd == "/Users/dev/project/sub")
        guard case .cwdChanged(let data) = event.data else {
            Issue.record("Expected .cwdChanged data, got \(event.data)")
            return
        }
        #expect(data.previousCwd == "/Users/dev/project")
    }

    @Test("CwdChanged tolerates missing previous_cwd")
    func cwdChangedDecodesWithoutPreviousCwd() throws {
        let json = #"""
        {
            "hook_event_name": "CwdChanged",
            "session_id": "sess-cwd-002",
            "cwd": "/Users/dev/project"
        }
        """#

        let event = try makeDecoder().decode(HookEvent.self, from: Data(json.utf8))

        #expect(event.type == .cwdChanged)
        #expect(event.cwd == "/Users/dev/project")
        guard case .cwdChanged(let data) = event.data else {
            Issue.record("Expected .cwdChanged data")
            return
        }
        #expect(data.previousCwd == nil)
    }

    // MARK: - FileChanged

    @Test("FileChanged decodes all fields including change_type")
    func fileChangedDecodesWithAllFields() throws {
        let json = #"""
        {
            "hook_event_name": "FileChanged",
            "session_id": "sess-file-001",
            "cwd": "/Users/dev/project",
            "file_path": "/Users/dev/project/src/main.swift",
            "change_type": "edit"
        }
        """#

        let event = try makeDecoder().decode(HookEvent.self, from: Data(json.utf8))

        #expect(event.type == .fileChanged)
        #expect(event.sessionId == "sess-file-001")
        #expect(event.cwd == "/Users/dev/project")
        guard case .fileChanged(let data) = event.data else {
            Issue.record("Expected .fileChanged data")
            return
        }
        #expect(data.filePath == "/Users/dev/project/src/main.swift")
        #expect(data.changeType == "edit")
    }

    @Test("FileChanged tolerates missing change_type")
    func fileChangedDecodesWithoutChangeType() throws {
        let json = #"""
        {
            "hook_event_name": "FileChanged",
            "session_id": "sess-file-002",
            "cwd": "/Users/dev/project",
            "file_path": "/Users/dev/project/README.md"
        }
        """#

        let event = try makeDecoder().decode(HookEvent.self, from: Data(json.utf8))

        guard case .fileChanged(let data) = event.data else {
            Issue.record("Expected .fileChanged data")
            return
        }
        #expect(data.filePath == "/Users/dev/project/README.md")
        #expect(data.changeType == nil)
    }

    @Test("FileChanged decodes defensively when file_path is missing")
    func fileChangedWithoutFilePathStillDecodesEmptyPath() throws {
        let json = #"""
        {
            "hook_event_name": "FileChanged",
            "session_id": "sess-file-003",
            "cwd": "/Users/dev/project"
        }
        """#

        let event = try makeDecoder().decode(HookEvent.self, from: Data(json.utf8))

        guard case .fileChanged(let data) = event.data else {
            Issue.record("Expected .fileChanged data")
            return
        }
        // Defensive: empty path lets consumers skip cleanly without crashing.
        #expect(data.filePath == "")
    }

    // MARK: - Round-trip

    @Test("CwdChanged round-trips through legacy encode/decode")
    func cwdChangedRoundTripsThroughLegacyFormat() throws {
        let original = HookEvent(
            type: .cwdChanged,
            sessionId: "sess-rt-001",
            data: .cwdChanged(CwdChangedData(previousCwd: "/old/dir")),
            cwd: "/new/dir"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try makeDecoder().decode(HookEvent.self, from: encoded)

        #expect(decoded.type == .cwdChanged)
        #expect(decoded.sessionId == "sess-rt-001")
        guard case .cwdChanged(let data) = decoded.data else {
            Issue.record("Expected .cwdChanged data after round-trip")
            return
        }
        #expect(data.previousCwd == "/old/dir")
    }

    @Test("FileChanged round-trips through legacy encode/decode")
    func fileChangedRoundTripsThroughLegacyFormat() throws {
        let original = HookEvent(
            type: .fileChanged,
            sessionId: "sess-rt-002",
            data: .fileChanged(FileChangedData(
                filePath: "/Users/dev/project/x.swift",
                changeType: "write"
            )),
            cwd: "/Users/dev/project"
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try makeDecoder().decode(HookEvent.self, from: encoded)

        #expect(decoded.type == .fileChanged)
        guard case .fileChanged(let data) = decoded.data else {
            Issue.record("Expected .fileChanged data after round-trip")
            return
        }
        #expect(data.filePath == "/Users/dev/project/x.swift")
        #expect(data.changeType == "write")
    }

    // MARK: - Receiver integration

    @Test("HookEventReceiver accepts CwdChanged payload")
    func receiverAcceptsCwdChanged() {
        let receiver = HookEventReceiverImpl()
        let json = #"""
        {
            "hook_event_name": "CwdChanged",
            "session_id": "sess-recv-001",
            "cwd": "/x",
            "previous_cwd": "/y"
        }
        """#
        let accepted = receiver.receiveRawJSON(Data(json.utf8))
        #expect(accepted)
        #expect(receiver.receivedEventCount == 1)
        #expect(receiver.failedEventCount == 0)
    }

    @Test("HookEventReceiver accepts FileChanged payload")
    func receiverAcceptsFileChanged() {
        let receiver = HookEventReceiverImpl()
        let json = #"""
        {
            "hook_event_name": "FileChanged",
            "session_id": "sess-recv-002",
            "cwd": "/x",
            "file_path": "/x/file.txt",
            "change_type": "write"
        }
        """#
        let accepted = receiver.receiveRawJSON(Data(json.utf8))
        #expect(accepted)
        #expect(receiver.receivedEventCount == 1)
    }

    @Test("Unknown hook event names do not crash and are tolerated as failures")
    func unknownHookEventNameDoesNotCrash() {
        let receiver = HookEventReceiverImpl()
        let json = #"""
        {
            "hook_event_name": "TotallyUnknownEvent",
            "session_id": "sess-unknown-001",
            "cwd": "/x"
        }
        """#
        // The decoder rejects unknown event names; the receiver counts the
        // failure but never throws or crashes.
        let accepted = receiver.receiveRawJSON(Data(json.utf8))
        #expect(!accepted)
        #expect(receiver.failedEventCount == 1)
    }
}
