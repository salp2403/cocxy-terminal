// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
import CocxyCoreKit

@Suite("CocxyCore Session Recording")
struct CocxyCoreSessionRecordingSwiftTestingTests {

    @Test("vendored CocxyCore records and replays local cast files")
    func vendoredCocxyCoreRecordsAndReplaysLocalCastFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cocxy-core-session-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recordingURL = directory.appendingPathComponent("session.cast")
        let source = try #require(cocxycore_terminal_create(4, 40))
        defer { cocxycore_terminal_destroy(source) }

        let recorder = try #require(recordingURL.path.withCString { path in
            "Swift C API".withCString { title in
                cocxycore_session_recorder_start(source, path, title)
            }
        })
        feed("Hello\r\nReplay", into: source)
        cocxycore_session_recorder_stop(recorder)
        #expect(cocxycore_session_recorder_is_active(recorder) == false)
        #expect(cocxycore_session_recorder_bytes_written(recorder) > 0)
        cocxycore_session_recorder_destroy(recorder)

        let contents = try String(contentsOf: recordingURL, encoding: .utf8)
        #expect(contents.contains("\"title\":\"Swift C API\""))
        #expect(contents.contains("\"Hello\\r\\nReplay\""))

        let target = try #require(cocxycore_terminal_create(4, 40))
        defer { cocxycore_terminal_destroy(target) }

        let player = try #require(recordingURL.path.withCString { path in
            cocxycore_session_player_open(target, path)
        })
        cocxycore_session_player_play(player)
        #expect(cocxycore_terminal_cell_char(target, 0, 0) == UInt32(UInt8(ascii: "H")))
        #expect(cocxycore_terminal_cell_char(target, 1, 0) == UInt32(UInt8(ascii: "R")))
        cocxycore_session_player_destroy(player)
    }
}

private func feed(_ text: String, into terminal: OpaquePointer) {
    let bytes = Array(text.utf8)
    cocxycore_terminal_feed(terminal, bytes, bytes.count)
}
