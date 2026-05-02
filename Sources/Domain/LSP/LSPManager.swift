// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPManager.swift - Phase B client planning and privacy gates.

import Foundation

enum LSPManagerError: Error, Equatable {
    case unsupportedFileExtension(String)
    case disabled(languageID: String)
    case missingServer(languageID: String, suggestion: LSPInstallSuggestion)
}

struct LSPManager {
    typealias ProcessFactory = (LSPProcessConfiguration) -> LSPProcessManaging

    struct Configuration: Equatable, Sendable {
        let enabledLanguageIDs: Set<String>
        let configuredExecutablePaths: [String: String]

        init(
            enabledLanguageIDs: Set<String>,
            configuredExecutablePaths: [String: String] = [:]
        ) {
            self.enabledLanguageIDs = Set(enabledLanguageIDs.map { $0.lowercased() })
            self.configuredExecutablePaths = Dictionary(
                uniqueKeysWithValues: configuredExecutablePaths.map { ($0.key.lowercased(), $0.value) }
            )
        }

        static let defaults = Configuration(enabledLanguageIDs: [])

        func isEnabled(languageID: String) -> Bool {
            enabledLanguageIDs.contains(languageID.lowercased())
        }

        func configuredExecutablePath(languageID: String) -> String? {
            configuredExecutablePaths[languageID.lowercased()]
        }
    }

    struct ClientPlan: Equatable, Sendable {
        let languageID: String?
        let status: ClientPlanStatus
    }

    enum ClientPlanStatus: Equatable, Sendable {
        case unsupported
        case disabled
        case missing(LSPInstallSuggestion)
        case ready(path: String)
    }

    let registry: LSPLanguageRegistry
    let configuration: Configuration
    let discovery: LSPServerDiscovery
    private let processFactory: ProcessFactory

    init(
        registry: LSPLanguageRegistry,
        configuration: Configuration,
        discovery: LSPServerDiscovery,
        processFactory: @escaping ProcessFactory = { configuration in
            LSPProcess(configuration: configuration)
        }
    ) {
        self.registry = registry
        self.configuration = configuration
        self.discovery = discovery
        self.processFactory = processFactory
    }

    func planClient(forFileURL fileURL: URL) -> ClientPlan {
        guard let server = registry.server(forFileURL: fileURL) else {
            return ClientPlan(languageID: nil, status: .unsupported)
        }

        guard configuration.isEnabled(languageID: server.languageID) else {
            return ClientPlan(languageID: server.languageID, status: .disabled)
        }

        let resolution = discovery.resolve(
            server,
            configuredExecutablePath: configuration.configuredExecutablePath(languageID: server.languageID)
        )

        switch resolution {
        case let .available(path, _):
            return ClientPlan(languageID: server.languageID, status: .ready(path: path))
        case let .missing(suggestion):
            return ClientPlan(languageID: server.languageID, status: .missing(suggestion))
        }
    }

    func startClient(
        forFileURL fileURL: URL,
        workspaceURL: URL,
        processID: Int?,
        initialDocumentSnapshot: LSPDocumentSnapshot? = nil
    ) throws -> LSPClientSession {
        guard let server = registry.server(forFileURL: fileURL) else {
            throw LSPManagerError.unsupportedFileExtension(fileURL.pathExtension.lowercased())
        }

        guard configuration.isEnabled(languageID: server.languageID) else {
            throw LSPManagerError.disabled(languageID: server.languageID)
        }

        let resolution = discovery.resolve(
            server,
            configuredExecutablePath: configuration.configuredExecutablePath(languageID: server.languageID)
        )

        switch resolution {
        case let .available(path, _):
            let processConfiguration = LSPProcessConfiguration(
                executablePath: path,
                arguments: server.arguments,
                workingDirectoryURL: workspaceURL
            )
            let session = LSPClientSession(
                server: server,
                transport: processFactory(processConfiguration),
                processID: processID
            )
            do {
                try session.start(workspaceURL: workspaceURL)
                if let initialDocumentSnapshot {
                    try session.openDocument(initialDocumentSnapshot)
                }
            } catch {
                session.stop()
                throw error
            }
            return session
        case let .missing(suggestion):
            throw LSPManagerError.missingServer(languageID: server.languageID, suggestion: suggestion)
        }
    }
}
