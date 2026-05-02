// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPClientSwiftTestingTests.swift - Testable client/session behavior.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("LSP client transport")
struct LSPClientTransportSwiftTestingTests {
    @Test("start sends initialize request with local workspace uri")
    func startSendsInitializeRequest() throws {
        let transport = RecordingLSPTransport()
        let client = LSPClient(
            server: try #require(LSPLanguageRegistry.defaults.server(forLanguageID: "swift")),
            transport: transport,
            processID: 1234
        )

        let requestID = try client.start(workspaceURL: URL(fileURLWithPath: "/tmp/project"))
        let messages = try transport.decodedMessages()

        #expect(requestID == .int(1))
        #expect(messages.count == 1)
        guard case let .request(id, method, params) = messages[0] else {
            Issue.record("Expected initialize request")
            return
        }

        #expect(id == .int(1))
        #expect(method == "initialize")
        #expect(params?.objectValue?["processId"] == .number(1234))
        #expect(params?.objectValue?["rootUri"] == .string("file:///tmp/project"))
    }

    @Test("open document sends didOpen notification with document text")
    func openDocumentSendsDidOpen() throws {
        let transport = RecordingLSPTransport()
        let client = LSPClient(
            server: try #require(LSPLanguageRegistry.defaults.server(forLanguageID: "python")),
            transport: transport,
            processID: nil
        )
        let snapshot = LSPDocumentSnapshot(
            uri: "file:///tmp/app.py",
            languageID: "python",
            version: 7,
            text: "print('cocxy')"
        )

        try client.openDocument(snapshot)

        let messages = try transport.decodedMessages()
        #expect(messages.count == 1)
        guard case let .notification(method, params) = messages[0] else {
            Issue.record("Expected didOpen notification")
            return
        }

        let textDocument = params?.objectValue?["textDocument"]?.objectValue
        #expect(method == "textDocument/didOpen")
        #expect(textDocument?["uri"] == .string("file:///tmp/app.py"))
        #expect(textDocument?["languageId"] == .string("python"))
        #expect(textDocument?["version"] == .number(7))
        #expect(textDocument?["text"] == .string("print('cocxy')"))
    }

    @Test("hover completion definition and references send textDocument position requests")
    func textDocumentFeatureRequests() throws {
        let transport = RecordingLSPTransport()
        let client = LSPClient(
            server: try #require(LSPLanguageRegistry.defaults.server(forLanguageID: "swift")),
            transport: transport,
            processID: nil
        )
        let uri = "file:///tmp/main.swift"
        let position = LSPPosition(line: 2, character: 7)

        let hoverID = try client.requestHover(uri: uri, position: position)
        let completionID = try client.requestCompletion(uri: uri, position: position)
        let definitionID = try client.requestDefinition(uri: uri, position: position)
        let referencesID = try client.requestReferences(
            uri: uri,
            position: position,
            includeDeclaration: false
        )

        #expect([hoverID, completionID, definitionID, referencesID] == [.int(1), .int(2), .int(3), .int(4)])
        let messages = try transport.decodedMessages()
        #expect(messages.map(\.methodForTest) == [
            "textDocument/hover",
            "textDocument/completion",
            "textDocument/definition",
            "textDocument/references",
        ])
        #expect(messages.allSatisfy { message in
            guard case let .request(_, _, params) = message,
                  let object = params?.objectValue,
                  let textDocument = object["textDocument"]?.objectValue,
                  let requestPosition = object["position"]?.objectValue else {
                return false
            }
            return textDocument["uri"] == .string(uri)
                && requestPosition["line"] == .number(2)
                && requestPosition["character"] == .number(7)
        })

        guard case let .request(_, "textDocument/references", referencesParams) = messages[3],
              let context = referencesParams?.objectValue?["context"]?.objectValue else {
            Issue.record("Expected references request with context params")
            return
        }
        #expect(context["includeDeclaration"] == .bool(false))
    }
}

@Suite("LSP diagnostics")
struct LSPDiagnosticsSwiftTestingTests {
    @Test("publish diagnostics notification updates client state")
    func diagnosticsNotificationUpdatesState() throws {
        let transport = RecordingLSPTransport()
        let client = LSPClient(
            server: try #require(LSPLanguageRegistry.defaults.server(forLanguageID: "swift")),
            transport: transport,
            processID: nil
        )
        let diagnostic = LSPDiagnostic(
            range: LSPRange(
                start: LSPPosition(line: 1, character: 2),
                end: LSPPosition(line: 1, character: 5)
            ),
            severity: .error,
            message: "Cannot find 'value' in scope",
            source: "sourcekit-lsp"
        )
        let notification = LSPMessage.notification(
            method: "textDocument/publishDiagnostics",
            params: .object([
                "uri": .string("file:///tmp/main.swift"),
                "diagnostics": .array([diagnostic.jsonValue]),
            ])
        )

        let events = try client.handleIncomingData(try LSPFraming.encode(notification))

        #expect(events == [.diagnostics(uri: "file:///tmp/main.swift", diagnostics: [diagnostic])])
        #expect(client.diagnostics(forURI: "file:///tmp/main.swift") == [diagnostic])
    }

    @Test("empty diagnostics notification clears previous diagnostics")
    func emptyDiagnosticsClearsState() throws {
        let transport = RecordingLSPTransport()
        let client = LSPClient(
            server: try #require(LSPLanguageRegistry.defaults.server(forLanguageID: "swift")),
            transport: transport,
            processID: nil
        )

        _ = try client.handleIncomingData(try LSPFraming.encode(.notification(
            method: "textDocument/publishDiagnostics",
            params: .object([
                "uri": .string("file:///tmp/main.swift"),
                "diagnostics": .array([
                    LSPDiagnostic(
                        range: .zero,
                        severity: .warning,
                        message: "Old warning",
                        source: "sourcekit-lsp"
                    ).jsonValue,
                ]),
            ])
        )))

        let events = try client.handleIncomingData(try LSPFraming.encode(.notification(
            method: "textDocument/publishDiagnostics",
            params: .object([
                "uri": .string("file:///tmp/main.swift"),
                "diagnostics": .array([]),
            ])
        )))

        #expect(events == [.diagnostics(uri: "file:///tmp/main.swift", diagnostics: [])])
        #expect(client.diagnostics(forURI: "file:///tmp/main.swift") == [])
    }
}

@Suite("LSP response events")
struct LSPResponseEventsSwiftTestingTests {
    @Test("hover response emits parsed hover contents")
    func hoverResponseEmitsEvent() throws {
        let transport = RecordingLSPTransport()
        let client = LSPClient(
            server: try #require(LSPLanguageRegistry.defaults.server(forLanguageID: "swift")),
            transport: transport,
            processID: nil
        )
        let requestID = try client.requestHover(
            uri: "file:///tmp/main.swift",
            position: LSPPosition(line: 3, character: 4)
        )

        let events = try client.handleIncomingData(try LSPFraming.encode(.response(
            id: requestID,
            result: .object([
                "contents": .object([
                    "kind": .string("markdown"),
                    "value": .string("`String`"),
                ]),
            ]),
            error: nil
        )))

        #expect(events == [.hover(id: requestID, hover: LSPHover(contents: "`String`"))])
    }

    @Test("completion response emits array and completion-list items")
    func completionResponseEmitsEvent() throws {
        let transport = RecordingLSPTransport()
        let client = LSPClient(
            server: try #require(LSPLanguageRegistry.defaults.server(forLanguageID: "swift")),
            transport: transport,
            processID: nil
        )
        let requestID = try client.requestCompletion(
            uri: "file:///tmp/main.swift",
            position: LSPPosition(line: 1, character: 9)
        )

        let events = try client.handleIncomingData(try LSPFraming.encode(.response(
            id: requestID,
            result: .object([
                "isIncomplete": .bool(false),
                "items": .array([
                    .object([
                        "label": .string("print"),
                        "detail": .string("Swift.print"),
                        "insertText": .string("print($0)"),
                    ]),
                ]),
            ]),
            error: nil
        )))

        #expect(events == [.completion(
            id: requestID,
            items: [
                LSPCompletionItem(
                    label: "print",
                    detail: "Swift.print",
                    insertText: "print($0)"
                ),
            ]
        )])
    }

    @Test("definition and references responses emit parsed locations")
    func locationResponsesEmitEvents() throws {
        let transport = RecordingLSPTransport()
        let client = LSPClient(
            server: try #require(LSPLanguageRegistry.defaults.server(forLanguageID: "swift")),
            transport: transport,
            processID: nil
        )
        let definitionID = try client.requestDefinition(
            uri: "file:///tmp/main.swift",
            position: LSPPosition(line: 4, character: 2)
        )
        let referencesID = try client.requestReferences(
            uri: "file:///tmp/main.swift",
            position: LSPPosition(line: 4, character: 2)
        )
        let location = LSPJSONValue.object([
            "uri": .string("file:///tmp/Other.swift"),
            "range": LSPRange(
                start: LSPPosition(line: 10, character: 1),
                end: LSPPosition(line: 10, character: 6)
            ).jsonValue,
        ])

        let definitionEvents = try client.handleIncomingData(try LSPFraming.encode(.response(
            id: definitionID,
            result: location,
            error: nil
        )))
        let referenceEvents = try client.handleIncomingData(try LSPFraming.encode(.response(
            id: referencesID,
            result: .array([location]),
            error: nil
        )))

        let expectedLocation = LSPLocation(
            uri: "file:///tmp/Other.swift",
            range: LSPRange(
                start: LSPPosition(line: 10, character: 1),
                end: LSPPosition(line: 10, character: 6)
            )
        )
        #expect(definitionEvents == [.definition(id: definitionID, locations: [expectedLocation])])
        #expect(referenceEvents == [.references(id: referencesID, locations: [expectedLocation])])
    }

    @Test("response errors and unknown ids do not emit stale UI events")
    func responseErrorsDoNotEmitEvents() throws {
        let transport = RecordingLSPTransport()
        let client = LSPClient(
            server: try #require(LSPLanguageRegistry.defaults.server(forLanguageID: "swift")),
            transport: transport,
            processID: nil
        )
        let requestID = try client.requestHover(
            uri: "file:///tmp/main.swift",
            position: LSPPosition(line: 0, character: 0)
        )

        let errorEvents = try client.handleIncomingData(try LSPFraming.encode(.response(
            id: requestID,
            result: nil,
            error: LSPResponseError(code: -32_602, message: "Server cancelled")
        )))
        let duplicateEvents = try client.handleIncomingData(try LSPFraming.encode(.response(
            id: requestID,
            result: .object(["contents": .string("stale")]),
            error: nil
        )))

        #expect(errorEvents.isEmpty)
        #expect(duplicateEvents.isEmpty)
    }
}

@Suite("LSP capabilities")
struct LSPCapabilitiesSwiftTestingTests {
    @Test("capabilities parse common server feature flags")
    func parsesCommonFeatureFlags() throws {
        let capabilities = try LSPCapabilities(result: .object([
            "capabilities": .object([
                "hoverProvider": .bool(true),
                "definitionProvider": .bool(true),
                "referencesProvider": .bool(false),
                "completionProvider": .object(["triggerCharacters": .array([.string("."), .string(":")])]),
                "textDocumentSync": .number(2),
            ]),
        ]))

        #expect(capabilities.hoverProvider == true)
        #expect(capabilities.definitionProvider == true)
        #expect(capabilities.referencesProvider == false)
        #expect(capabilities.completionProvider == true)
        #expect(capabilities.textDocumentSyncKind == 2)
    }
}

@Suite("LSP restart policy")
struct LSPRestartPolicySwiftTestingTests {
    @Test("restart policy allows bounded retries then stops")
    func restartPolicyBoundsRetries() {
        let policy = LSPRestartPolicy(maxAttempts: 2, baseDelay: 0.25)
        var state = LSPRestartState()

        #expect(state.recordCrash(policy: policy) == .restart(afterSeconds: 0.25))
        #expect(state.recordCrash(policy: policy) == .restart(afterSeconds: 0.5))
        #expect(state.recordCrash(policy: policy) == .stop)
    }
}

private final class RecordingLSPTransport: LSPTransporting {
    private(set) var sentFrames: [Data] = []

    func send(_ frame: Data) throws {
        sentFrames.append(frame)
    }

    func decodedMessages() throws -> [LSPMessage] {
        try sentFrames.flatMap { try LSPFraming.decodeMessages(from: $0) }
    }
}

private extension LSPMessage {
    var methodForTest: String? {
        switch self {
        case let .request(_, method, _), let .notification(method, _):
            return method
        case .response:
            return nil
        }
    }
}
