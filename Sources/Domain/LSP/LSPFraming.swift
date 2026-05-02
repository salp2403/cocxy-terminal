// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPFraming.swift - Content-Length framing for LSP JSON-RPC messages.

import Foundation

enum LSPFramingError: Error, Equatable {
    case missingHeaderTerminator
    case missingContentLength
    case invalidContentLength(String)
    case incompleteBody(expected: Int, actual: Int)
}

enum LSPFraming {
    static func encode(_ message: LSPMessage) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let body = try encoder.encode(message)
        var frame = Data("Content-Length: \(body.count)\r\n\r\n".utf8)
        frame.append(body)
        return frame
    }

    static func decodeMessages(from data: Data) throws -> [LSPMessage] {
        let bytes = [UInt8](data)
        var offset = 0
        var messages: [LSPMessage] = []

        while offset < bytes.count {
            let headerEnd = try findHeaderEnd(in: bytes, startingAt: offset)
            let headerData = Data(bytes[offset..<headerEnd])
            guard let headerText = String(data: headerData, encoding: .ascii) else {
                throw LSPFramingError.missingContentLength
            }

            let contentLength = try parseContentLength(from: headerText)
            let bodyStart = headerEnd + 4
            let bodyEnd = bodyStart + contentLength
            guard bodyEnd <= bytes.count else {
                throw LSPFramingError.incompleteBody(expected: contentLength, actual: bytes.count - bodyStart)
            }

            let body = Data(bytes[bodyStart..<bodyEnd])
            messages.append(try JSONDecoder().decode(LSPMessage.self, from: body))
            offset = bodyEnd
        }

        return messages
    }

    private static func findHeaderEnd(in bytes: [UInt8], startingAt start: Int) throws -> Int {
        guard bytes.count >= start + 4 else {
            throw LSPFramingError.missingHeaderTerminator
        }

        for index in start...(bytes.count - 4) {
            if bytes[index] == 13,
               bytes[index + 1] == 10,
               bytes[index + 2] == 13,
               bytes[index + 3] == 10 {
                return index
            }
        }

        throw LSPFramingError.missingHeaderTerminator
    }

    private static func parseContentLength(from headerText: String) throws -> Int {
        for line in headerText.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0].caseInsensitiveCompare("Content-Length") == .orderedSame else {
                continue
            }
            guard let length = Int(parts[1]), length >= 0 else {
                throw LSPFramingError.invalidContentLength(parts[1])
            }
            return length
        }

        throw LSPFramingError.missingContentLength
    }
}
