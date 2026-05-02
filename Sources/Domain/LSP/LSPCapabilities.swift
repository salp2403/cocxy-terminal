// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPCapabilities.swift - Server capability parsing used by client planning.

import Foundation

enum LSPCapabilitiesError: Error, Equatable {
    case missingCapabilities
}

struct LSPCapabilities: Equatable, Sendable {
    let hoverProvider: Bool
    let definitionProvider: Bool
    let referencesProvider: Bool
    let completionProvider: Bool
    let textDocumentSyncKind: Int?

    init(result: LSPJSONValue) throws {
        guard let root = result.objectValue,
              let capabilities = root["capabilities"]?.objectValue else {
            throw LSPCapabilitiesError.missingCapabilities
        }

        self.hoverProvider = LSPCapabilities.providerEnabled(capabilities["hoverProvider"])
        self.definitionProvider = LSPCapabilities.providerEnabled(capabilities["definitionProvider"])
        self.referencesProvider = LSPCapabilities.providerEnabled(capabilities["referencesProvider"])
        self.completionProvider = capabilities["completionProvider"] != nil
        self.textDocumentSyncKind = capabilities["textDocumentSync"]?.intValue
    }

    private static func providerEnabled(_ value: LSPJSONValue?) -> Bool {
        switch value {
        case let .bool(enabled):
            return enabled
        case .object:
            return true
        default:
            return false
        }
    }
}
