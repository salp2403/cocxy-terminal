// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
@testable import CocxyTerminal

@MainActor
final class RecordingRemoteRPCSender: CocxyDRemoteRPCSending {
    struct Call: Equatable {
        let method: String
        let params: [String: String]
    }

    var calls: [Call] = []
    var responses: [[String: String]] = []

    func sendRemoteRPC(method: String, params: [String: String]) async throws -> [String: String] {
        calls.append(Call(method: method, params: params))
        if responses.isEmpty {
            return [:]
        }
        return responses.removeFirst()
    }
}
