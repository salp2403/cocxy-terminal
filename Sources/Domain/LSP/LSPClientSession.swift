// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPClientSession.swift - Bridges an LSP client to a local process transport.

import Foundation

final class LSPClientSession {
    private let transport: LSPProcessManaging
    private let client: LSPClient
    private let eventLock = NSLock()

    var onEvent: ((LSPClientEvent) -> Void)?

    var isRunning: Bool {
        transport.isRunning
    }

    init(
        server: LSPServerConfiguration,
        transport: LSPProcessManaging,
        processID: Int?
    ) {
        self.transport = transport
        self.client = LSPClient(server: server, transport: transport, processID: processID)
    }

    func start(workspaceURL: URL) throws {
        transport.onOutputData = { [weak self] data in
            self?.handleOutputData(data)
        }
        try transport.start()
        try client.start(workspaceURL: workspaceURL)
    }

    func stop() {
        transport.stop()
    }

    func openDocument(_ snapshot: LSPDocumentSnapshot) throws {
        try client.openDocument(snapshot)
    }

    func closeDocument(uri: String) throws {
        try client.closeDocument(uri: uri)
    }

    @discardableResult
    func requestHover(uri: String, position: LSPPosition) throws -> LSPRequestID {
        try client.requestHover(uri: uri, position: position)
    }

    @discardableResult
    func requestCompletion(uri: String, position: LSPPosition) throws -> LSPRequestID {
        try client.requestCompletion(uri: uri, position: position)
    }

    @discardableResult
    func requestDefinition(uri: String, position: LSPPosition) throws -> LSPRequestID {
        try client.requestDefinition(uri: uri, position: position)
    }

    @discardableResult
    func requestReferences(
        uri: String,
        position: LSPPosition,
        includeDeclaration: Bool = true
    ) throws -> LSPRequestID {
        try client.requestReferences(
            uri: uri,
            position: position,
            includeDeclaration: includeDeclaration
        )
    }

    func diagnostics(forURI uri: String) -> [LSPDiagnostic] {
        eventLock.lock()
        defer { eventLock.unlock() }
        return client.diagnostics(forURI: uri)
    }

    private func handleOutputData(_ data: Data) {
        let events: [LSPClientEvent]
        eventLock.lock()
        do {
            events = try client.handleIncomingData(data)
        } catch {
            eventLock.unlock()
            return
        }
        eventLock.unlock()

        for event in events {
            onEvent?(event)
        }
    }
}
