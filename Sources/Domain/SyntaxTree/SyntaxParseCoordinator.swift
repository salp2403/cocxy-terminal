// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SyntaxParseCoordinator.swift - Version gates syntax parse snapshots before editor decoration updates.

import Foundation

struct SyntaxParseRequest: Equatable {
    let documentID: UUID
    let fileURL: URL
    let version: Int
    let buffer: EditorBuffer
}

struct SyntaxParseResult: Equatable {
    let documentID: UUID
    let fileURL: URL
    let version: Int
    let decorations: [EditorDecoration]
}

struct SyntaxParseCoordinator {
    private let service: SyntaxTreeService
    private var latestVersionByDocumentID: [UUID: Int] = [:]

    init(service: SyntaxTreeService) {
        self.service = service
    }

    mutating func makeRequest(for document: EditorDocument) -> SyntaxParseRequest? {
        guard let fileURL = document.fileURL else { return nil }
        latestVersionByDocumentID[document.id] = document.version
        return SyntaxParseRequest(
            documentID: document.id,
            fileURL: fileURL,
            version: document.version,
            buffer: document.buffer
        )
    }

    func parse(_ request: SyntaxParseRequest) -> SyntaxParseResult {
        SyntaxParseResult(
            documentID: request.documentID,
            fileURL: request.fileURL,
            version: request.version,
            decorations: service.decorations(forFileURL: request.fileURL, buffer: request.buffer)
        )
    }

    func acceptedDecorations(from result: SyntaxParseResult) -> [EditorDecoration]? {
        guard latestVersionByDocumentID[result.documentID] == result.version else {
            return nil
        }
        return result.decorations
    }
}
