// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPWorkspaceCoordinator.swift - Reuses local LSP sessions across workspace documents.

import Foundation

enum LSPWorkspaceCoordinatorError: Error, Equatable {
    case unopenedDocument(uri: String)
}

final class LSPWorkspaceCoordinator {
    enum OpenResult: Equatable {
        case started(languageID: String)
        case reused(languageID: String)
    }

    private let manager: LSPManager
    private let workspaceURL: URL
    private let processID: Int?
    private var sessionsByLanguageID: [String: LSPClientSession] = [:]
    private var documentLanguageByURI: [String: String] = [:]
    private var pendingDocumentURIByRequestID: [LSPRequestID: String] = [:]

    var onEvent: ((LSPClientEvent) -> Void)?
    var onDocumentEvent: ((String, LSPClientEvent) -> Void)?

    var activeLanguageIDs: [String] {
        sessionsByLanguageID.keys.sorted()
    }

    init(manager: LSPManager, workspaceURL: URL, processID: Int?) {
        self.manager = manager
        self.workspaceURL = workspaceURL
        self.processID = processID
    }

    func openDocument(fileURL: URL, snapshot: LSPDocumentSnapshot) throws -> OpenResult {
        guard let server = manager.registry.server(forFileURL: fileURL) else {
            throw LSPManagerError.unsupportedFileExtension(fileURL.pathExtension.lowercased())
        }

        if let session = sessionsByLanguageID[server.languageID] {
            try session.openDocument(snapshot)
            documentLanguageByURI[snapshot.uri] = server.languageID
            return .reused(languageID: server.languageID)
        }

        let session = try manager.startClient(
            forFileURL: fileURL,
            workspaceURL: workspaceURL,
            processID: processID,
            initialDocumentSnapshot: snapshot
        )
        session.onEvent = { [weak self] event in
            self?.routeEvent(event)
        }
        sessionsByLanguageID[server.languageID] = session
        documentLanguageByURI[snapshot.uri] = server.languageID
        return .started(languageID: server.languageID)
    }

    func closeDocument(uri: String) {
        guard let languageID = documentLanguageByURI.removeValue(forKey: uri),
              let session = sessionsByLanguageID[languageID] else {
            return
        }

        try? session.closeDocument(uri: uri)
        if !documentLanguageByURI.values.contains(languageID) {
            session.stop()
            sessionsByLanguageID.removeValue(forKey: languageID)
        }
    }

    @discardableResult
    func requestHover(uri: String, position: LSPPosition) throws -> LSPRequestID {
        let requestID = try session(forDocumentURI: uri).requestHover(uri: uri, position: position)
        pendingDocumentURIByRequestID[requestID] = uri
        return requestID
    }

    @discardableResult
    func requestCompletion(uri: String, position: LSPPosition) throws -> LSPRequestID {
        let requestID = try session(forDocumentURI: uri).requestCompletion(uri: uri, position: position)
        pendingDocumentURIByRequestID[requestID] = uri
        return requestID
    }

    @discardableResult
    func requestDefinition(uri: String, position: LSPPosition) throws -> LSPRequestID {
        let requestID = try session(forDocumentURI: uri).requestDefinition(uri: uri, position: position)
        pendingDocumentURIByRequestID[requestID] = uri
        return requestID
    }

    @discardableResult
    func requestReferences(
        uri: String,
        position: LSPPosition,
        includeDeclaration: Bool = true
    ) throws -> LSPRequestID {
        let requestID = try session(forDocumentURI: uri).requestReferences(
            uri: uri,
            position: position,
            includeDeclaration: includeDeclaration
        )
        pendingDocumentURIByRequestID[requestID] = uri
        return requestID
    }

    func stopAll() {
        for session in sessionsByLanguageID.values {
            session.stop()
        }
        sessionsByLanguageID.removeAll()
        documentLanguageByURI.removeAll()
        pendingDocumentURIByRequestID.removeAll()
    }

    func diagnostics(forURI uri: String) throws -> [LSPDiagnostic] {
        try session(forDocumentURI: uri).diagnostics(forURI: uri)
    }

    private func session(forDocumentURI uri: String) throws -> LSPClientSession {
        guard let languageID = documentLanguageByURI[uri],
              let session = sessionsByLanguageID[languageID] else {
            throw LSPWorkspaceCoordinatorError.unopenedDocument(uri: uri)
        }
        return session
    }

    private func routeEvent(_ event: LSPClientEvent) {
        onEvent?(event)

        switch event {
        case let .diagnostics(uri, _):
            onDocumentEvent?(uri, event)
        case let .hover(id, _),
             let .completion(id, _),
             let .definition(id, _),
             let .references(id, _):
            guard let uri = pendingDocumentURIByRequestID.removeValue(forKey: id) else {
                return
            }
            onDocumentEvent?(uri, event)
        }
    }
}
