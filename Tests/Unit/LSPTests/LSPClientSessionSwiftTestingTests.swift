// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPClientSessionSwiftTestingTests.swift - LSP session orchestration tests.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("LSP client session")
struct LSPClientSessionSwiftTestingTests {
    @Test("session starts process transport and sends initialize")
    func sessionStartsTransportAndSendsInitialize() throws {
        let transport = FakeLSPProcessTransport()
        let session = LSPClientSession(
            server: try #require(LSPLanguageRegistry.defaults.server(forLanguageID: "swift")),
            transport: transport,
            processID: 4321
        )

        try session.start(workspaceURL: URL(fileURLWithPath: "/tmp/cocxy-project"))

        #expect(session.isRunning)
        #expect(transport.startCount == 1)
        let messages = try transport.decodedMessages()
        #expect(messages.count == 1)
        guard case let .request(id, method, params) = messages[0] else {
            Issue.record("Expected initialize request")
            return
        }
        #expect(id == .int(1))
        #expect(method == "initialize")
        #expect(params?.objectValue?["processId"] == .number(4321))
        #expect(params?.objectValue?["rootUri"] == .string("file:///tmp/cocxy-project"))
    }

    @Test("session routes incoming diagnostics through event handler")
    func sessionRoutesIncomingDiagnostics() throws {
        let transport = FakeLSPProcessTransport()
        let session = LSPClientSession(
            server: try #require(LSPLanguageRegistry.defaults.server(forLanguageID: "swift")),
            transport: transport,
            processID: nil
        )
        let diagnostic = LSPDiagnostic(
            range: .zero,
            severity: .warning,
            message: "Unused value",
            source: "sourcekit-lsp"
        )
        var receivedEvents: [LSPClientEvent] = []
        session.onEvent = { receivedEvents.append($0) }

        try session.start(workspaceURL: URL(fileURLWithPath: "/tmp/cocxy-project"))
        transport.emit(try LSPFraming.encode(.notification(
            method: "textDocument/publishDiagnostics",
            params: .object([
                "uri": .string("file:///tmp/main.swift"),
                "diagnostics": .array([diagnostic.jsonValue]),
            ])
        )))

        #expect(receivedEvents == [.diagnostics(uri: "file:///tmp/main.swift", diagnostics: [diagnostic])])
        #expect(session.diagnostics(forURI: "file:///tmp/main.swift") == [diagnostic])
    }
}

@Suite("LSP manager session startup")
struct LSPManagerSessionStartupSwiftTestingTests {
    @Test("manager starts enabled language session with resolved executable and server args")
    func managerStartsEnabledLanguageSession() throws {
        let factory = CapturingLSPProcessFactory()
        let manager = LSPManager(
            registry: .defaults,
            configuration: .init(enabledLanguageIDs: ["typescript"]),
            discovery: LSPServerDiscovery(
                executableResolver: { executable in
                    executable == "typescript-language-server" ? "/opt/homebrew/bin/typescript-language-server" : nil
                },
                homebrewDetector: { true }
            ),
            processFactory: factory.makeProcess(configuration:)
        )

        let session = try manager.startClient(
            forFileURL: URL(fileURLWithPath: "/tmp/app.ts"),
            workspaceURL: URL(fileURLWithPath: "/tmp"),
            processID: 99
        )

        let configuration = try #require(factory.configurations.first)
        #expect(configuration.executablePath == "/opt/homebrew/bin/typescript-language-server")
        #expect(configuration.arguments == ["--stdio"])
        #expect(configuration.workingDirectoryURL == URL(fileURLWithPath: "/tmp"))
        #expect(session.isRunning)
        #expect(factory.lastProcess?.startCount == 1)
        #expect(try factory.lastProcess?.decodedMessages().count == 1)
    }

    @Test("manager opens initial document after starting the session")
    func managerOpensInitialDocument() throws {
        let factory = CapturingLSPProcessFactory()
        let manager = LSPManager(
            registry: .defaults,
            configuration: .init(enabledLanguageIDs: ["typescript"]),
            discovery: LSPServerDiscovery(
                executableResolver: { executable in
                    executable == "typescript-language-server" ? "/opt/homebrew/bin/typescript-language-server" : nil
                },
                homebrewDetector: { true }
            ),
            processFactory: factory.makeProcess(configuration:)
        )
        let snapshot = LSPDocumentSnapshot(
            uri: "file:///tmp/app.ts",
            languageID: "typescript",
            version: 7,
            text: "const value = 1;\n"
        )

        _ = try manager.startClient(
            forFileURL: URL(fileURLWithPath: "/tmp/app.ts"),
            workspaceURL: URL(fileURLWithPath: "/tmp"),
            processID: 77,
            initialDocumentSnapshot: snapshot
        )

        let process = try #require(factory.lastProcess)
        let sent = try process.decodedMessages()
        #expect(sent.contains {
            if case .notification("textDocument/didOpen", _) = $0 { return true }
            return false
        })
    }

    @Test("manager refuses disabled languages before process creation")
    func managerRefusesDisabledLanguage() throws {
        let factory = CapturingLSPProcessFactory()
        let manager = LSPManager(
            registry: .defaults,
            configuration: .defaults,
            discovery: LSPServerDiscovery(
                executableResolver: { _ in "/opt/homebrew/bin/sourcekit-lsp" },
                homebrewDetector: { true }
            ),
            processFactory: factory.makeProcess(configuration:)
        )

        #expect(throws: LSPManagerError.disabled(languageID: "swift")) {
            _ = try manager.startClient(
                forFileURL: URL(fileURLWithPath: "/tmp/main.swift"),
                workspaceURL: URL(fileURLWithPath: "/tmp"),
                processID: nil
            )
        }
        #expect(factory.configurations.isEmpty)
    }
}

@Suite("LSP workspace coordinator")
struct LSPWorkspaceCoordinatorSwiftTestingTests {
    @Test("workspace reuses one running session per language")
    func workspaceReusesSessionPerLanguage() throws {
        let factory = CapturingLSPProcessFactory()
        let coordinator = LSPWorkspaceCoordinator(
            manager: makeTypeScriptManager(factory: factory),
            workspaceURL: URL(fileURLWithPath: "/tmp/project"),
            processID: 44
        )
        let first = LSPDocumentSnapshot(
            uri: "file:///tmp/project/app.ts",
            languageID: "typescript",
            version: 1,
            text: "const app = 1;\n"
        )
        let second = LSPDocumentSnapshot(
            uri: "file:///tmp/project/view.ts",
            languageID: "typescript",
            version: 1,
            text: "const view = 2;\n"
        )

        #expect(try coordinator.openDocument(
            fileURL: URL(fileURLWithPath: "/tmp/project/app.ts"),
            snapshot: first
        ) == .started(languageID: "typescript"))
        #expect(try coordinator.openDocument(
            fileURL: URL(fileURLWithPath: "/tmp/project/view.ts"),
            snapshot: second
        ) == .reused(languageID: "typescript"))

        #expect(factory.configurations.count == 1)
        #expect(coordinator.activeLanguageIDs == ["typescript"])
        let process = try #require(factory.lastProcess)
        let didOpenCount = try process.decodedMessages().filter {
            if case .notification("textDocument/didOpen", _) = $0 { return true }
            return false
        }.count
        #expect(didOpenCount == 2)
    }

    @Test("workspace routes feature requests through the opened document session")
    func workspaceRoutesFeatureRequests() throws {
        let factory = CapturingLSPProcessFactory()
        let coordinator = LSPWorkspaceCoordinator(
            manager: makeTypeScriptManager(factory: factory),
            workspaceURL: URL(fileURLWithPath: "/tmp/project"),
            processID: nil
        )
        let snapshot = LSPDocumentSnapshot(
            uri: "file:///tmp/project/app.ts",
            languageID: "typescript",
            version: 1,
            text: "const app = 1;\n"
        )

        _ = try coordinator.openDocument(
            fileURL: URL(fileURLWithPath: "/tmp/project/app.ts"),
            snapshot: snapshot
        )
        let requestID = try coordinator.requestCompletion(
            uri: snapshot.uri,
            position: LSPPosition(line: 0, character: 6)
        )

        #expect(requestID == .int(2))
        let process = try #require(factory.lastProcess)
        let messages = try process.decodedMessages()
        #expect(messages.contains {
            if case .request(.int(2), "textDocument/completion", _) = $0 { return true }
            return false
        })
    }

    @Test("workspace routes response events back to the requesting document uri")
    func workspaceRoutesResponseEventsToDocumentURI() throws {
        let factory = CapturingLSPProcessFactory()
        let coordinator = LSPWorkspaceCoordinator(
            manager: makeTypeScriptManager(factory: factory),
            workspaceURL: URL(fileURLWithPath: "/tmp/project"),
            processID: nil
        )
        let snapshot = LSPDocumentSnapshot(
            uri: "file:///tmp/project/app.ts",
            languageID: "typescript",
            version: 1,
            text: "const app = 1;\n"
        )
        var routedURIs: [String] = []
        var routedEvents: [LSPClientEvent] = []
        coordinator.onDocumentEvent = { uri, event in
            routedURIs.append(uri)
            routedEvents.append(event)
        }

        _ = try coordinator.openDocument(
            fileURL: URL(fileURLWithPath: "/tmp/project/app.ts"),
            snapshot: snapshot
        )
        let requestID = try coordinator.requestCompletion(
            uri: snapshot.uri,
            position: LSPPosition(line: 0, character: 6)
        )
        let process = try #require(factory.lastProcess)
        process.emit(try LSPFraming.encode(.response(
            id: requestID,
            result: .array([
                .object([
                    "label": .string("app"),
                    "detail": .string("const app"),
                ]),
            ]),
            error: nil
        )))

        #expect(routedURIs == [snapshot.uri])
        #expect(routedEvents == [
            .completion(
                id: requestID,
                items: [LSPCompletionItem(label: "app", detail: "const app", insertText: nil)]
            ),
        ])
    }

    @Test("workspace exposes diagnostics for opened documents")
    func workspaceExposesDiagnosticsForOpenedDocuments() throws {
        let factory = CapturingLSPProcessFactory()
        let coordinator = LSPWorkspaceCoordinator(
            manager: makeTypeScriptManager(factory: factory),
            workspaceURL: URL(fileURLWithPath: "/tmp/project"),
            processID: nil
        )
        let snapshot = LSPDocumentSnapshot(
            uri: "file:///tmp/project/app.ts",
            languageID: "typescript",
            version: 1,
            text: "const app = missing;\n"
        )
        let diagnostic = LSPDiagnostic(
            range: LSPRange(
                start: LSPPosition(line: 0, character: 12),
                end: LSPPosition(line: 0, character: 19)
            ),
            severity: .error,
            message: "Cannot find name 'missing'.",
            source: "typescript"
        )

        _ = try coordinator.openDocument(
            fileURL: URL(fileURLWithPath: "/tmp/project/app.ts"),
            snapshot: snapshot
        )
        let process = try #require(factory.lastProcess)
        process.emit(try LSPFraming.encode(.notification(
            method: "textDocument/publishDiagnostics",
            params: .object([
                "uri": .string(snapshot.uri),
                "diagnostics": .array([diagnostic.jsonValue]),
            ])
        )))

        #expect(try coordinator.diagnostics(forURI: snapshot.uri) == [diagnostic])
        #expect(throws: LSPWorkspaceCoordinatorError.unopenedDocument(uri: "file:///tmp/project/other.ts")) {
            _ = try coordinator.diagnostics(forURI: "file:///tmp/project/other.ts")
        }
    }

    @Test("workspace closes documents and stops language session after last document")
    func workspaceStopsSessionAfterLastDocumentCloses() throws {
        let factory = CapturingLSPProcessFactory()
        let coordinator = LSPWorkspaceCoordinator(
            manager: makeTypeScriptManager(factory: factory),
            workspaceURL: URL(fileURLWithPath: "/tmp/project"),
            processID: nil
        )
        let first = LSPDocumentSnapshot(
            uri: "file:///tmp/project/app.ts",
            languageID: "typescript",
            version: 1,
            text: "const app = 1;\n"
        )
        let second = LSPDocumentSnapshot(
            uri: "file:///tmp/project/view.ts",
            languageID: "typescript",
            version: 1,
            text: "const view = 2;\n"
        )

        _ = try coordinator.openDocument(fileURL: URL(fileURLWithPath: "/tmp/project/app.ts"), snapshot: first)
        _ = try coordinator.openDocument(fileURL: URL(fileURLWithPath: "/tmp/project/view.ts"), snapshot: second)
        let process = try #require(factory.lastProcess)

        coordinator.closeDocument(uri: first.uri)
        #expect(process.stopCount == 0)
        #expect(coordinator.activeLanguageIDs == ["typescript"])
        #expect(try didCloseCount(in: process) == 1)

        coordinator.closeDocument(uri: second.uri)
        #expect(process.stopCount == 1)
        #expect(coordinator.activeLanguageIDs.isEmpty)
        #expect(try didCloseCount(in: process) == 2)
    }

    private func makeTypeScriptManager(factory: CapturingLSPProcessFactory) -> LSPManager {
        LSPManager(
            registry: .defaults,
            configuration: .init(enabledLanguageIDs: ["typescript"]),
            discovery: LSPServerDiscovery(
                executableResolver: { executable in
                    executable == "typescript-language-server" ? "/opt/homebrew/bin/typescript-language-server" : nil
                },
                homebrewDetector: { true }
            ),
            processFactory: factory.makeProcess(configuration:)
        )
    }

    private func didCloseCount(in process: FakeLSPProcessTransport) throws -> Int {
        try process.decodedMessages().filter {
            if case .notification("textDocument/didClose", _) = $0 { return true }
            return false
        }.count
    }
}

private final class FakeLSPProcessTransport: LSPProcessManaging {
    var onOutputData: ((Data) -> Void)?
    private(set) var sentFrames: [Data] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var isRunning = false

    func start() throws {
        startCount += 1
        isRunning = true
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }

    func send(_ frame: Data) throws {
        sentFrames.append(frame)
    }

    func emit(_ data: Data) {
        onOutputData?(data)
    }

    func decodedMessages() throws -> [LSPMessage] {
        try sentFrames.flatMap { try LSPFraming.decodeMessages(from: $0) }
    }
}

private final class CapturingLSPProcessFactory {
    private(set) var configurations: [LSPProcessConfiguration] = []
    private(set) var lastProcess: FakeLSPProcessTransport?

    func makeProcess(configuration: LSPProcessConfiguration) -> LSPProcessManaging {
        configurations.append(configuration)
        let process = FakeLSPProcessTransport()
        lastProcess = process
        return process
    }
}
