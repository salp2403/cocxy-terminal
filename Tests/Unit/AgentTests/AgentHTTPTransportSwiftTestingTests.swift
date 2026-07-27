// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentHTTPTransportSwiftTestingTests.swift - Bounded HTTP response reception contracts.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Bounded agent HTTP transport", .serialized)
struct AgentHTTPTransportSwiftTestingTests {
    private let maximumResponseBytes = 8

    @Test("transport accepts a response exactly at the byte budget")
    func acceptsResponseAtByteBudget() async throws {
        let scenario = BoundedHTTPTestScenario.exactLimit
        let response = try await transport().send(request(for: scenario, id: scenarioID(for: scenario)))

        #expect(response.statusCode == 200)
        #expect(response.data == Data("12345678".utf8))
    }

    @Test("transport rejects a response whose announced body exceeds the budget")
    func rejectsAnnouncedExcess() async throws {
        let scenario = BoundedHTTPTestScenario.announcedExcess
        let id = scenarioID(for: scenario)
        BoundedHTTPTestURLProtocol.recorder.reset(id)

        await #expect(throws: AgentHTTPTransportError.responseTooLarge(
            maximumBytes: maximumResponseBytes
        )) {
            _ = try await transport().send(request(for: scenario, id: id))
        }

        #expect(await waitForCancellation(of: id))
    }

    @Test("MCP HTTP transport enforces the receive budget before JSON decoding")
    func mcpTransportEnforcesBudgetBeforeDecoding() async throws {
        let scenario = BoundedHTTPTestScenario.announcedExcess
        let id = scenarioID(for: scenario)
        BoundedHTTPTestURLProtocol.recorder.reset(id)
        let server = MCPServer(
            id: "bounded-test",
            transport: .http(url: url(for: scenario, id: id))
        )
        let mcpTransport = MCPHTTPTransport(httpTransport: transport())

        await #expect(throws: AgentHTTPTransportError.responseTooLarge(
            maximumBytes: maximumResponseBytes
        )) {
            _ = try await mcpTransport.send(
                MCPJSONRPCRequest(id: "1", method: "tools/list"),
                to: server
            )
        }

        #expect(await waitForCancellation(of: id))
    }

    @Test("transport cancels a chunked response when streamed bytes cross the budget")
    func rejectsChunkedStreamingExcess() async throws {
        let scenario = BoundedHTTPTestScenario.chunkedExcess
        let id = scenarioID(for: scenario)
        BoundedHTTPTestURLProtocol.recorder.reset(id)

        await #expect(throws: AgentHTTPTransportError.responseTooLarge(
            maximumBytes: maximumResponseBytes
        )) {
            _ = try await transport().send(request(for: scenario, id: id))
        }

        #expect(await waitForCancellation(of: id))
        #expect(BoundedHTTPTestURLProtocol.recorder.snapshot(id).bytesSent == 9)
    }

    @Test("transport rejects malformed Content-Length headers")
    func rejectsMalformedContentLength() async throws {
        let scenario = BoundedHTTPTestScenario.malformedLength
        let id = scenarioID(for: scenario)
        BoundedHTTPTestURLProtocol.recorder.reset(id)

        await #expect(throws: AgentHTTPTransportError.invalidContentLength) {
            _ = try await transport().send(request(for: scenario, id: id))
        }

        #expect(await waitForCancellation(of: id))
    }

    @Test("transport refuses HTTP redirects instead of changing the approved destination")
    func refusesRedirects() async throws {
        let scenario = BoundedHTTPTestScenario.redirect
        let id = scenarioID(for: scenario)
        BoundedHTTPTestURLProtocol.recorder.reset(id)

        do {
            _ = try await transport().send(request(for: scenario, id: id))
        } catch {
            // Cancellation of a denied redirect is an acceptable fail-closed result.
        }

        let snapshot = BoundedHTTPTestURLProtocol.recorder.snapshot(id)
        #expect(snapshot.requestsByPath[BoundedHTTPTestScenario.redirect.rawValue] == 1)
        #expect(snapshot.requestsByPath[BoundedHTTPTestScenario.redirectSink.rawValue] == nil)
    }

    private func transport() -> URLSessionAgentHTTPTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BoundedHTTPTestURLProtocol.self]
        return URLSessionAgentHTTPTransport(
            maximumResponseBytes: maximumResponseBytes,
            sessionConfiguration: configuration
        )
    }

    private func request(for scenario: BoundedHTTPTestScenario, id: String) -> AgentHTTPRequest {
        AgentHTTPRequest(
            url: url(for: scenario, id: id),
            headers: [:],
            body: Data()
        )
    }

    private func url(for scenario: BoundedHTTPTestScenario, id: String) -> URL {
        URL(string: "https://bounded-http.test/\(scenario.rawValue)?id=\(id)")!
    }

    private func scenarioID(for scenario: BoundedHTTPTestScenario) -> String {
        "\(scenario.rawValue)-\(UUID().uuidString)"
    }

    /// Polls for `stopLoading` instead of measuring a fixed window: the stop is
    /// delivered by URLSession's delegate queue, work the scheduler still has to
    /// place, so a short clock measures scheduler latency rather than whether the
    /// transport actually cancelled. Returns false — and therefore fails the
    /// caller's `#expect` — when the cancellation never arrives.
    private func waitForCancellation(of id: String) async -> Bool {
        for _ in 0..<500 {
            if BoundedHTTPTestURLProtocol.recorder.snapshot(id).stopped {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

private enum BoundedHTTPTestScenario: String {
    case exactLimit = "exact-limit"
    case announcedExcess = "announced-excess"
    case chunkedExcess = "chunked-excess"
    case malformedLength = "malformed-length"
    case redirect
    case redirectSink = "redirect-sink"
}

private final class BoundedHTTPTestURLProtocol: URLProtocol, @unchecked Sendable {
    static let recorder = BoundedHTTPTestRecorder()

    private let stateLock = NSLock()
    private var stopped = false
    /// Serial so the scripted body chunks always reach the client before the
    /// completion that follows them. On a concurrent queue the staggered blocks
    /// carry no ordering guarantee once their deadlines pass together, which on
    /// a loaded machine delivers "finished" first and empties the response.
    private let deliveryQueue = DispatchQueue(
        label: "dev.cocxy.tests.bounded-http-delivery"
    )

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "bounded-http.test"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url,
              let scenario = BoundedHTTPTestScenario(rawValue: url.lastPathComponent),
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "id" })?.value else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.recorder.recordRequest(path: scenario.rawValue, id: id)

        switch scenario {
        case .exactLimit:
            sendResponse(url: url, headers: ["Content-Length": "8"])
            send(Data("1234".utf8), id: id, after: 0.005)
            send(Data("5678".utf8), id: id, after: 0.010)
            finish(after: 0.015)
        case .announcedExcess:
            sendResponse(url: url, headers: ["Content-Length": "9"])
            send(Data("1".utf8), id: id, after: 0.050)
            finish(after: 0.100)
        case .chunkedExcess:
            sendResponse(url: url, headers: ["Transfer-Encoding": "chunked"])
            send(Data("1234".utf8), id: id, after: 0.005)
            send(Data("5678".utf8), id: id, after: 0.010)
            send(Data("9".utf8), id: id, after: 0.015)
            finish(after: 0.100)
        case .malformedLength:
            sendResponse(url: url, headers: ["Content-Length": "eight"])
            send(Data("1".utf8), id: id, after: 0.050)
            finish(after: 0.100)
        case .redirect:
            let destination = URL(string: "https://bounded-http.test/redirect-sink?id=\(id)")!
            let redirectRequest = URLRequest(url: destination)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 307,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": destination.absoluteString]
            )!
            client?.urlProtocol(
                self,
                wasRedirectedTo: redirectRequest,
                redirectResponse: response
            )
            client?.urlProtocolDidFinishLoading(self)
        case .redirectSink:
            sendResponse(url: url, headers: ["Content-Length": "0"])
            finish(after: 0.001)
        }
    }

    override func stopLoading() {
        let id = request.url.flatMap { url in
            URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "id" })?.value
        }
        stateLock.withLock {
            stopped = true
        }
        if let id {
            Self.recorder.recordStop(id)
        }
    }

    private func sendResponse(url: URL, headers: [String: String]) {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    private func send(_ data: Data, id: String, after delay: TimeInterval) {
        deliveryQueue.asyncAfter(deadline: .now() + delay) { [self] in
            guard isActive else { return }
            Self.recorder.recordBytes(data.count, id: id)
            client?.urlProtocol(self, didLoad: data)
        }
    }

    private func finish(after delay: TimeInterval) {
        deliveryQueue.asyncAfter(deadline: .now() + delay) { [self] in
            guard isActive else { return }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private var isActive: Bool {
        stateLock.withLock { !stopped }
    }
}

private final class BoundedHTTPTestRecorder: @unchecked Sendable {
    struct Snapshot {
        var bytesSent = 0
        var stopped = false
        var requestsByPath: [String: Int] = [:]
    }

    private let lock = NSLock()
    private var snapshots: [String: Snapshot] = [:]

    func reset(_ id: String) {
        lock.withLock {
            snapshots[id] = Snapshot()
        }
    }

    func recordBytes(_ count: Int, id: String) {
        lock.withLock {
            snapshots[id, default: Snapshot()].bytesSent += count
        }
    }

    func recordStop(_ id: String) {
        lock.withLock {
            snapshots[id, default: Snapshot()].stopped = true
        }
    }

    func recordRequest(path: String, id: String) {
        lock.withLock {
            snapshots[id, default: Snapshot()].requestsByPath[path, default: 0] += 1
        }
    }

    func snapshot(_ id: String) -> Snapshot {
        lock.withLock {
            snapshots[id, default: Snapshot()]
        }
    }
}
