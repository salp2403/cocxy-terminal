// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("CocxyDRemoteImageDrop")
struct CocxyDRemoteImageDropSwiftTestingTests {

    @Test("packetizer writes deterministic scp-like header")
    func packetizerWritesDeterministicHeader() {
        let packet = CocxyDRemoteImageDropPacketizer.packet(
            fileName: "diagram.png",
            mimeType: "image/png",
            data: Data([1, 2, 3])
        )
        let prefix = String(decoding: packet.prefix(80), as: UTF8.self)

        #expect(prefix.contains("COCXY-REMOTE-DROP/1"))
        #expect(prefix.contains("name=diagram.png"))
        #expect(prefix.contains("mime=image/png"))
        #expect(prefix.contains("size=3"))
    }

    @Test("packetizer sanitizes newline in file name")
    func packetizerSanitizesNewlineInFileName() {
        let packet = CocxyDRemoteImageDropPacketizer.packet(
            fileName: "bad\nname.png",
            mimeType: "image/png",
            data: Data([1])
        )
        let prefix = String(decoding: packet.prefix(80), as: UTF8.self)

        #expect(prefix.contains("name=bad_name.png"))
    }

    @Test("uploader chunks image packet over session.write")
    @MainActor func uploaderChunksImagePacketOverSessionWrite() async throws {
        let sender = RecordingRemoteRPCSender()
        let uploader = CocxyDRemoteImageDropUploader(
            sessionRPC: CocxyDRemoteSessionRPC(sender: sender),
            chunkSize: 12
        )

        try await uploader.upload(
            sessionID: "s1",
            fileName: "diagram.png",
            mimeType: "image/png",
            data: Data(repeating: 0x41, count: 40)
        )

        #expect(sender.calls.allSatisfy { $0.method == "session.write" })
        #expect(sender.calls.count > 1)
        #expect(sender.calls.first?.params["sessionID"] == "s1")
    }

    @Test("uploader rejects empty image payload")
    @MainActor func uploaderRejectsEmptyImagePayload() async {
        let uploader = CocxyDRemoteImageDropUploader(
            sessionRPC: CocxyDRemoteSessionRPC(sender: RecordingRemoteRPCSender())
        )

        await #expect(throws: CocxyDRemoteImageDropError.emptyPayload) {
            try await uploader.upload(
                sessionID: "s1",
                fileName: "empty.png",
                mimeType: "image/png",
                data: Data()
            )
        }
    }
}
