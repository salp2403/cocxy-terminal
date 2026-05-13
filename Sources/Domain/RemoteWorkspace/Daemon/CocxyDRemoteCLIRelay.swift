// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyDRemoteCLIRelay.swift - Authenticated CLI relay request signing.

import Foundation

struct CocxyDRemoteCLIRelayRequest: Codable, Equatable, Sendable {
    let id: String
    var command: String
    var arguments: [String]
    let timestamp: UInt64
    let signature: Data
}

struct CocxyDRemoteCLIRelay: Sendable {
    let token: RelayToken

    func makeSignedRequest(
        command: String,
        arguments: [String],
        timestamp: UInt64,
        id: String = UUID().uuidString
    ) throws -> CocxyDRemoteCLIRelayRequest {
        let payload = try Self.payload(command: command, arguments: arguments, timestamp: timestamp)
        return CocxyDRemoteCLIRelayRequest(
            id: id,
            command: command,
            arguments: arguments,
            timestamp: timestamp,
            signature: token.sign(payload)
        )
    }

    func validate(_ request: CocxyDRemoteCLIRelayRequest) -> Bool {
        guard let payload = try? Self.payload(
            command: request.command,
            arguments: request.arguments,
            timestamp: request.timestamp
        ) else { return false }
        return token.validate(payload: payload, signature: request.signature)
    }

    static func reverseForwardArguments(localPort: Int, remotePort: Int) -> [String] {
        ["-S", "none", "-R", "\(remotePort):127.0.0.1:\(localPort)"]
    }

    static func environment(localPort: Int, tokenID: String) -> [String: String] {
        [
            "COCXY_RELAY_URL": "tcp://127.0.0.1:\(localPort)",
            "COCXY_RELAY_TOKEN_ID": tokenID,
        ]
    }

    private static func payload(command: String, arguments: [String], timestamp: UInt64) throws -> Data {
        var data = Data()
        appendLengthPrefixed(String(timestamp), to: &data)
        appendLengthPrefixed(command, to: &data)
        appendLengthPrefixed(String(arguments.count), to: &data)
        for argument in arguments {
            appendLengthPrefixed(argument, to: &data)
        }
        return data
    }

    private static func appendLengthPrefixed(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        data.append(contentsOf: "\(bytes.count):".utf8)
        data.append(bytes)
    }
}
