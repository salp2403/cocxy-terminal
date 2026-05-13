// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyDRemoteImageDrop.swift - Remote image drop packetization over session RPC.

import Foundation

enum CocxyDRemoteImageDropError: Error, Equatable {
    case emptyPayload
    case invalidChunkSize
}

enum CocxyDRemoteImageDropPacketizer {
    static func packet(fileName: String, mimeType: String, data: Data) -> Data {
        let sanitizedName = sanitizeHeaderValue(fileName)
        let sanitizedMime = sanitizeHeaderValue(mimeType)
        let header = """
        COCXY-REMOTE-DROP/1
        name=\(sanitizedName)
        mime=\(sanitizedMime)
        size=\(data.count)

        """
        var packet = Data(header.utf8)
        packet.append(data)
        return packet
    }

    private static func sanitizeHeaderValue(_ value: String) -> String {
        value.map { character in
            character == "\n" || character == "\r" ? "_" : character
        }.map(String.init).joined()
    }
}
@MainActor
final class CocxyDRemoteImageDropUploader {
    private let sessionRPC: CocxyDRemoteSessionRPC
    private let chunkSize: Int

    init(sessionRPC: CocxyDRemoteSessionRPC, chunkSize: Int = 48 * 1024) {
        self.sessionRPC = sessionRPC
        self.chunkSize = chunkSize
    }

    func upload(sessionID: String, fileName: String, mimeType: String, data: Data) async throws {
        guard !data.isEmpty else { throw CocxyDRemoteImageDropError.emptyPayload }
        guard chunkSize > 0 else { throw CocxyDRemoteImageDropError.invalidChunkSize }

        let packet = CocxyDRemoteImageDropPacketizer.packet(
            fileName: fileName,
            mimeType: mimeType,
            data: data
        )
        var offset = 0
        while offset < packet.count {
            let next = min(offset + chunkSize, packet.count)
            try await sessionRPC.write(sessionID: sessionID, data: packet.subdata(in: offset..<next))
            offset = next
        }
    }
}
