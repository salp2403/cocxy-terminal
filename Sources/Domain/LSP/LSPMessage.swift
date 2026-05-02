// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPMessage.swift - JSON-RPC message envelope for Language Server Protocol.

import Foundation

enum LSPMessage: Codable, Equatable, Sendable {
    case request(id: LSPRequestID, method: String, params: LSPJSONValue?)
    case notification(method: String, params: LSPJSONValue?)
    case response(id: LSPRequestID, result: LSPJSONValue?, error: LSPResponseError?)

    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params, result, error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(String.self, forKey: .jsonrpc)
        guard version == "2.0" else {
            throw DecodingError.dataCorruptedError(forKey: .jsonrpc, in: container, debugDescription: "Expected JSON-RPC 2.0")
        }

        if let method = try container.decodeIfPresent(String.self, forKey: .method) {
            let params = try container.decodeIfPresent(LSPJSONValue.self, forKey: .params)
            if let id = try container.decodeIfPresent(LSPRequestID.self, forKey: .id) {
                self = .request(id: id, method: method, params: params)
            } else {
                self = .notification(method: method, params: params)
            }
            return
        }

        let id = try container.decode(LSPRequestID.self, forKey: .id)
        let result = try container.decodeIfPresent(LSPJSONValue.self, forKey: .result)
        let error = try container.decodeIfPresent(LSPResponseError.self, forKey: .error)
        self = .response(id: id, result: result, error: error)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("2.0", forKey: .jsonrpc)

        switch self {
        case let .request(id, method, params):
            try container.encode(id, forKey: .id)
            try container.encode(method, forKey: .method)
            try container.encodeIfPresent(params, forKey: .params)
        case let .notification(method, params):
            try container.encode(method, forKey: .method)
            try container.encodeIfPresent(params, forKey: .params)
        case let .response(id, result, error):
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(result, forKey: .result)
            try container.encodeIfPresent(error, forKey: .error)
        }
    }
}
