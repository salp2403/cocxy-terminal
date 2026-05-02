// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPClient.swift - Testable local LSP JSON-RPC session.

import Foundation

protocol LSPTransporting: AnyObject {
    func send(_ frame: Data) throws
}

struct LSPDocumentSnapshot: Equatable, Sendable {
    let uri: String
    let languageID: String
    let version: Int
    let text: String
}

struct LSPHover: Equatable, Sendable {
    let contents: String
}

struct LSPCompletionItem: Equatable, Sendable {
    let label: String
    let detail: String?
    let insertText: String?
}

struct LSPLocation: Equatable, Sendable {
    let uri: String
    let range: LSPRange
}

enum LSPClientEvent: Equatable, Sendable {
    case diagnostics(uri: String, diagnostics: [LSPDiagnostic])
    case hover(id: LSPRequestID, hover: LSPHover?)
    case completion(id: LSPRequestID, items: [LSPCompletionItem])
    case definition(id: LSPRequestID, locations: [LSPLocation])
    case references(id: LSPRequestID, locations: [LSPLocation])
}

final class LSPClient {
    private enum PendingRequestKind: Equatable {
        case initialize
        case hover
        case completion
        case definition
        case references
    }

    private let server: LSPServerConfiguration
    private let transport: LSPTransporting
    private let processID: Int?
    private var nextRequestID = 1
    private var diagnosticsByURI: [String: [LSPDiagnostic]] = [:]
    private var pendingRequests: [LSPRequestID: PendingRequestKind] = [:]

    init(
        server: LSPServerConfiguration,
        transport: LSPTransporting,
        processID: Int?
    ) {
        self.server = server
        self.transport = transport
        self.processID = processID
    }

    @discardableResult
    func start(workspaceURL: URL) throws -> LSPRequestID {
        let requestID = allocateRequestID()
        let params: LSPJSONValue = .object([
            "processId": processID.map { .number(Double($0)) } ?? .null,
            "rootUri": .string(workspaceURL.absoluteString),
            "capabilities": .object([:]),
        ])
        pendingRequests[requestID] = .initialize
        try send(.request(id: requestID, method: "initialize", params: params))
        return requestID
    }

    func openDocument(_ snapshot: LSPDocumentSnapshot) throws {
        let params: LSPJSONValue = .object([
            "textDocument": .object([
                "uri": .string(snapshot.uri),
                "languageId": .string(snapshot.languageID),
                "version": .number(Double(snapshot.version)),
                "text": .string(snapshot.text),
            ]),
        ])
        try send(.notification(method: "textDocument/didOpen", params: params))
    }

    func closeDocument(uri: String) throws {
        let params: LSPJSONValue = .object([
            "textDocument": .object([
                "uri": .string(uri),
            ]),
        ])
        try send(.notification(method: "textDocument/didClose", params: params))
    }

    @discardableResult
    func requestHover(uri: String, position: LSPPosition) throws -> LSPRequestID {
        try sendTextDocumentPositionRequest(
            method: "textDocument/hover",
            uri: uri,
            position: position
        )
    }

    @discardableResult
    func requestCompletion(uri: String, position: LSPPosition) throws -> LSPRequestID {
        try sendTextDocumentPositionRequest(
            method: "textDocument/completion",
            uri: uri,
            position: position
        )
    }

    @discardableResult
    func requestDefinition(uri: String, position: LSPPosition) throws -> LSPRequestID {
        try sendTextDocumentPositionRequest(
            method: "textDocument/definition",
            uri: uri,
            position: position
        )
    }

    @discardableResult
    func requestReferences(
        uri: String,
        position: LSPPosition,
        includeDeclaration: Bool = true
    ) throws -> LSPRequestID {
        try sendTextDocumentPositionRequest(
            method: "textDocument/references",
            uri: uri,
            position: position,
            extraParams: [
                "context": .object([
                    "includeDeclaration": .bool(includeDeclaration),
                ]),
            ]
        )
    }

    func handleIncomingData(_ data: Data) throws -> [LSPClientEvent] {
        var events: [LSPClientEvent] = []
        for message in try LSPFraming.decodeMessages(from: data) {
            switch message {
            case let .notification(method, params) where method == "textDocument/publishDiagnostics":
                if let event = handleDiagnostics(params: params) {
                    events.append(event)
                }
            case let .response(id, result, error):
                if let event = handleResponse(id: id, result: result, error: error) {
                    events.append(event)
                }
            default:
                continue
            }
        }
        return events
    }

    func diagnostics(forURI uri: String) -> [LSPDiagnostic] {
        diagnosticsByURI[uri] ?? []
    }

    private func allocateRequestID() -> LSPRequestID {
        let id = nextRequestID
        nextRequestID += 1
        return .int(id)
    }

    private func send(_ message: LSPMessage) throws {
        try transport.send(try LSPFraming.encode(message))
    }

    @discardableResult
    private func sendTextDocumentPositionRequest(
        method: String,
        uri: String,
        position: LSPPosition,
        extraParams: [String: LSPJSONValue] = [:]
    ) throws -> LSPRequestID {
        let requestID = allocateRequestID()
        pendingRequests[requestID] = pendingKind(forMethod: method)
        var params: [String: LSPJSONValue] = [
            "textDocument": .object([
                "uri": .string(uri),
            ]),
            "position": position.jsonValue,
        ]
        for (key, value) in extraParams {
            params[key] = value
        }
        try send(.request(id: requestID, method: method, params: .object(params)))
        return requestID
    }

    private func pendingKind(forMethod method: String) -> PendingRequestKind {
        switch method {
        case "textDocument/hover":
            return .hover
        case "textDocument/completion":
            return .completion
        case "textDocument/definition":
            return .definition
        case "textDocument/references":
            return .references
        default:
            return .initialize
        }
    }

    private func handleDiagnostics(params: LSPJSONValue?) -> LSPClientEvent? {
        guard let object = params?.objectValue,
              let uri = object["uri"]?.stringValue,
              let diagnosticValues = object["diagnostics"]?.arrayValue else {
            return nil
        }

        let diagnostics = diagnosticValues.compactMap(LSPDiagnostic.init(jsonValue:))
        diagnosticsByURI[uri] = diagnostics
        return .diagnostics(uri: uri, diagnostics: diagnostics)
    }

    private func handleResponse(
        id: LSPRequestID,
        result: LSPJSONValue?,
        error: LSPResponseError?
    ) -> LSPClientEvent? {
        guard let kind = pendingRequests.removeValue(forKey: id), error == nil else {
            return nil
        }

        switch kind {
        case .initialize:
            return nil
        case .hover:
            return .hover(id: id, hover: result.flatMap(parseHover))
        case .completion:
            return .completion(id: id, items: parseCompletionItems(result))
        case .definition:
            return .definition(id: id, locations: parseLocations(result))
        case .references:
            return .references(id: id, locations: parseLocations(result))
        }
    }

    private func parseHover(_ value: LSPJSONValue) -> LSPHover? {
        if let string = value.objectValue?["contents"].flatMap(extractMarkupString), !string.isEmpty {
            return LSPHover(contents: string)
        }
        if let string = extractMarkupString(value), !string.isEmpty {
            return LSPHover(contents: string)
        }
        return nil
    }

    private func parseCompletionItems(_ value: LSPJSONValue?) -> [LSPCompletionItem] {
        let itemValues: [LSPJSONValue]
        if let array = value?.arrayValue {
            itemValues = array
        } else {
            itemValues = value?.objectValue?["items"]?.arrayValue ?? []
        }

        return itemValues.compactMap { itemValue in
            guard let object = itemValue.objectValue,
                  let label = object["label"]?.stringValue,
                  !label.isEmpty else {
                return nil
            }
            return LSPCompletionItem(
                label: label,
                detail: object["detail"]?.stringValue,
                insertText: object["insertText"]?.stringValue
            )
        }
    }

    private func parseLocations(_ value: LSPJSONValue?) -> [LSPLocation] {
        if let array = value?.arrayValue {
            return array.compactMap(parseLocation)
        }
        if let value, let location = parseLocation(value) {
            return [location]
        }
        return []
    }

    private func parseLocation(_ value: LSPJSONValue) -> LSPLocation? {
        guard let object = value.objectValue,
              let uri = object["uri"]?.stringValue,
              let rangeValue = object["range"],
              let range = LSPRange(jsonValue: rangeValue) else {
            return nil
        }
        return LSPLocation(uri: uri, range: range)
    }

    private func extractMarkupString(_ value: LSPJSONValue) -> String? {
        if let string = value.stringValue {
            return string
        }
        if let array = value.arrayValue {
            let parts = array.compactMap(extractMarkupString)
            return parts.isEmpty ? nil : parts.joined(separator: "\n")
        }
        if let object = value.objectValue {
            return object["value"]?.stringValue
        }
        return nil
    }
}
