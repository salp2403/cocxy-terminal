// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing

private enum WebSocketTestProbeError: Error, CustomStringConvertible {
    case timeout(expected: String)
    case unsupportedMessage

    var description: String {
        switch self {
        case .timeout(let expected):
            "Timed out waiting for WebSocket message containing \(expected)"
        case .unsupportedMessage:
            "Received unsupported WebSocket message"
        }
    }
}

final class WebSocketTestProbe: @unchecked Sendable {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    init(port: UInt16, bearerToken: String, origin: String? = nil) throws {
        let url = try #require(URL(string: "ws://127.0.0.1:\(port)/"))
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        if let origin {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
        let configuration = URLSessionConfiguration.ephemeral
        self.session = URLSession(configuration: configuration)
        self.task = session.webSocketTask(with: request)
        task.resume()
    }

    var responseStatusCode: Int? {
        (task.response as? HTTPURLResponse)?.statusCode
    }

    func receive(
        containing expected: String,
        timeoutNanoseconds: UInt64 = 5_000_000_000
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { [self] in
                while true {
                    let message = try await task.receive()
                    let text: String
                    switch message {
                    case .string(let value):
                        text = value
                    case .data(let data):
                        text = String(decoding: data, as: UTF8.self)
                    @unknown default:
                        throw WebSocketTestProbeError.unsupportedMessage
                    }
                    if text.contains(expected) {
                        return text
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw WebSocketTestProbeError.timeout(expected: expected)
            }

            let value = try await group.next() ?? ""
            group.cancelAll()
            return value
        }
    }

    func send(_ text: String) async throws {
        try await task.send(.string(text))
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }
}
