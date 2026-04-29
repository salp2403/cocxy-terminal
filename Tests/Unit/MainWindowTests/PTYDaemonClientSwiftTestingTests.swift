// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonClientSwiftTestingTests.swift - Experimental PTY daemon adapter coverage.

import AppKit
import Foundation
import Testing
@testable import CocxyTerminal
import CocxyShared

@MainActor
@Suite("PTYDaemonClient TerminalEngine adapter")
struct PTYDaemonClientSwiftTestingTests {

    @Test("initialize rejects an IPC-only helper")
    func initializeRejectsIPCOnlyHelper() {
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(
                id: "hello",
                ok: true,
                hello: PTYDaemonHello(version: "dev")
            )
        ])
        let client = PTYDaemonClient(connection: connection)

        #expect(throws: TerminalEngineError.self) {
            try client.initialize(config: testConfig())
        }
    }

    @Test("initialize rejects terminal-surface without terminal-engine capability")
    func initializeRejectsTerminalSurfaceWithoutEngineCapability() {
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(
                id: "hello",
                ok: true,
                hello: PTYDaemonHello(
                    version: "dev",
                    capabilities: [
                        PTYDaemonProtocol.jsonLinesCapability,
                        PTYDaemonProtocol.terminalSurfaceCapability,
                    ]
                )
            )
        ])
        let client = PTYDaemonClient(connection: connection)

        #expect(throws: TerminalEngineError.self) {
            try client.initialize(config: testConfig())
        }
    }

    @Test("initialize accepts complete terminal engine capability set")
    func initializeAcceptsTerminalEngineCapabilitySet() throws {
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(
                id: "hello",
                ok: true,
                hello: terminalSurfaceHello()
            )
        ])
        let client = PTYDaemonClient(connection: connection)

        try client.initialize(config: testConfig())

        #expect(connection.requests.map(\.command) == [.hello])
    }

    @Test("createSurface sends working directory and parses surface ID")
    func createSurfaceSendsWorkingDirectoryAndParsesSurfaceID() throws {
        let surfaceID = UUID()
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
            PTYDaemonResponse(id: "create", ok: true, surfaceID: surfaceID.uuidString),
        ])
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())

        let created = try client.createSurface(
            in: NSView(),
            workingDirectory: URL(fileURLWithPath: "/tmp/project"),
            command: "/bin/zsh"
        )

        #expect(created.rawValue == surfaceID)
        #expect(connection.requests.last?.command == .surfaceCreate)
        #expect(connection.requests.last?.payload?["workingDirectory"] == "/tmp/project")
        #expect(connection.requests.last?.payload?["command"] == "/bin/zsh")
    }

    @Test("sendText, resize and destroy serialize surface requests")
    func sendTextResizeAndDestroySerializeRequests() throws {
        let surfaceID = UUID()
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
            PTYDaemonResponse(id: "create", ok: true, surfaceID: surfaceID.uuidString),
            PTYDaemonResponse(id: "write", ok: true),
            PTYDaemonResponse(id: "resize", ok: true),
            PTYDaemonResponse(id: "close", ok: true),
        ])
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())
        let surface = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)

        client.sendText("echo ok\n", to: surface)
        client.resize(
            surface,
            to: TerminalSize(columns: 120, rows: 30, pixelWidth: 1_200, pixelHeight: 900)
        )
        client.destroySurface(surface)

        let commands = connection.requests.map(\.command)
        #expect(commands == [.hello, .surfaceCreate, .surfaceWrite, .surfaceResize, .surfaceClose])
        #expect(connection.requests[2].payload?["bytesBase64"] == Data("echo ok\n".utf8).base64EncodedString())
        #expect(connection.requests[3].payload?["columns"] == "120")
        #expect(connection.requests[3].payload?["pixelHeight"] == "900")
        #expect(connection.requests[4].payload?["surfaceID"] == surfaceID.uuidString)
    }

    @Test("search and process registration map daemon payloads to domain models")
    func searchAndProcessRegistrationMapPayloads() throws {
        let surfaceID = UUID()
        let resultID = UUID()
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
            PTYDaemonResponse(id: "create", ok: true, surfaceID: surfaceID.uuidString),
            PTYDaemonResponse(
                id: "search",
                ok: true,
                searchResults: [
                    PTYDaemonSearchResult(
                        id: resultID.uuidString,
                        lineNumber: 9,
                        column: 2,
                        matchText: "needle",
                        contextBefore: "hay ",
                        contextAfter: " stack"
                    )
                ]
            ),
            PTYDaemonResponse(
                id: "process",
                ok: true,
                process: PTYDaemonProcessRegistration(
                    shellPID: 123,
                    ptyMasterFD: 7,
                    startSeconds: 456,
                    startMicroseconds: 789
                )
            ),
        ])
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())
        let surface = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)

        let results = client.searchScrollback(
            surfaceID: surface,
            options: SearchOptions(query: "needle", caseSensitive: true, useRegex: false, maxResults: 5)
        )
        let process = client.processMonitorRegistration(for: surface)

        #expect(results?.first?.id == resultID)
        #expect(results?.first?.contextBefore == "hay ")
        #expect(process?.shellPID == 123)
        #expect(process?.ptyMasterFD == 7)
        #expect(process?.shellIdentity?.startMicroseconds == 789)
    }

    @Test("tick drains output and OSC events from the daemon connection")
    func tickDrainsOutputAndOSCEvents() throws {
        let surfaceID = UUID()
        let connection = MockPTYDaemonClientConnection(
            responses: [
                PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
                PTYDaemonResponse(id: "create", ok: true, surfaceID: surfaceID.uuidString),
            ],
            events: [
                PTYDaemonEvent(
                    event: .surfaceOutput,
                    surfaceID: surfaceID.uuidString,
                    bytesBase64: Data("ready\n".utf8).base64EncodedString()
                ),
                PTYDaemonEvent(
                    event: .surfaceOSC,
                    surfaceID: surfaceID.uuidString,
                    osc: PTYDaemonOSCNotification(kind: .titleChange, text: "Daemon Shell")
                ),
            ]
        )
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())
        let surface = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)
        let output = LockedBox(Data())
        let title = LockedBox<String?>(nil)

        client.setOutputHandler(for: surface) { chunk in
            output.withValue { $0.append(chunk) }
        }
        client.setOSCHandler(for: surface) { notification in
            if case .titleChange(let value) = notification {
                title.withValue { $0 = value }
            }
        }

        client.tick()

        #expect(String(data: output.withValue { $0 }, encoding: .utf8) == "ready\n")
        #expect(title.withValue { $0 } == "Daemon Shell")
    }

    @Test("surface send reconnects and reattaches live surfaces before retry")
    func surfaceSendReconnectsAndReattachesLiveSurfacesBeforeRetry() throws {
        let surfaceID = UUID()
        let connection = MockPTYDaemonClientConnection(
            responses: [
                PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
                PTYDaemonResponse(id: "create", ok: true, surfaceID: surfaceID.uuidString),
                PTYDaemonResponse(id: "attach", ok: true),
                PTYDaemonResponse(id: "write", ok: true),
            ],
            throwOnCommands: [.surfaceWrite]
        )
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())
        let surface = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)

        client.sendText("after reconnect", to: surface)

        #expect(connection.reconnectCount == 1)
        #expect(connection.requests.map(\.command) == [
            .hello,
            .surfaceCreate,
            .surfaceWrite,
            .surfaceAttach,
            .surfaceWrite,
        ])
        #expect(client.isSurfaceStalledForTesting(surface) == false)
    }

    @Test("surface send marks the surface stalled when reattach fails")
    func surfaceSendMarksSurfaceStalledWhenReattachFails() throws {
        let surfaceID = UUID()
        let connection = MockPTYDaemonClientConnection(
            responses: [
                PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
                PTYDaemonResponse(id: "create", ok: true, surfaceID: surfaceID.uuidString),
                PTYDaemonResponse(id: "attach", ok: false, error: "missing surface"),
            ],
            throwOnCommands: [.surfaceWrite]
        )
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())
        let surface = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)

        client.sendText("stalls", to: surface)

        #expect(connection.reconnectCount == 1)
        #expect(connection.requests.map(\.command) == [.hello, .surfaceCreate, .surfaceWrite, .surfaceAttach])
        #expect(client.isSurfaceStalledForTesting(surface) == true)
    }

    @Test("surface closed event removes the live surface and blocks later writes")
    func surfaceClosedEventRemovesLiveSurfaceAndBlocksLaterWrites() throws {
        let surfaceID = UUID()
        let connection = MockPTYDaemonClientConnection(
            responses: [
                PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
                PTYDaemonResponse(id: "create", ok: true, surfaceID: surfaceID.uuidString),
            ],
            events: [
                PTYDaemonEvent(event: .surfaceClosed, surfaceID: surfaceID.uuidString)
            ]
        )
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())
        let surface = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)

        client.tick()
        client.sendText("ignored", to: surface)

        #expect(client.isSurfaceStalledForTesting(surface) == true)
        #expect(connection.requests.map(\.command) == [.hello, .surfaceCreate])
    }

    @Test("process connection reuses one helper process for multiple requests")
    func processConnectionReusesHelperProcess() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-ptydaemon-connection-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let scriptURL = tempDirectory.appendingPathComponent("fake-cocxyd.sh")
        let markerURL = tempDirectory.appendingPathComponent("starts.log")
        let script = """
        #!/bin/sh
        echo start >> "\(markerURL.path)"
        while IFS= read -r line; do
          case "$line" in
            *\\"command\\":\\"shutdown\\"*)
              printf '{"id":"bye","ok":true}\\n'
              exit 0
              ;;
            *\\"command\\":\\"hello\\"*)
              case "$line" in
                *\\"id\\":\\"one\\"*) printf '{"id":"one","ok":true,"hello":{"version":"dev","protocolVersion":1,"capabilities":["ipc-jsonl-v1"]}}\\n' ;;
                *\\"id\\":\\"two\\"*) printf '{"id":"two","ok":true,"hello":{"version":"dev","protocolVersion":1,"capabilities":["ipc-jsonl-v1"]}}\\n' ;;
                *) printf '{"id":"hello","ok":true,"hello":{"version":"dev","protocolVersion":1,"capabilities":["ipc-jsonl-v1"]}}\\n' ;;
              esac
              ;;
            *)
              printf '{"id":"unknown","ok":true}\\n'
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let connection = PTYDaemonProcessConnection(executableURL: scriptURL)

        _ = try connection.send(PTYDaemonRequest(id: "one", command: .hello))
        _ = try connection.send(PTYDaemonRequest(id: "two", command: .hello))
        _ = try connection.send(PTYDaemonRequest(id: "bye", command: .shutdown))

        let starts = try String(contentsOf: markerURL, encoding: .utf8)
            .split(separator: "\n")
        #expect(starts.count == 1)
    }

    @Test("process connection queues daemon events received before a response")
    func processConnectionQueuesDaemonEventsReceivedBeforeResponse() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-ptydaemon-events-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let scriptURL = tempDirectory.appendingPathComponent("fake-cocxyd-events.sh")
        let surfaceID = UUID()
        let script = """
        #!/bin/sh
        while IFS= read -r line; do
          case "$line" in
            *\\"command\\":\\"hello\\"*)
              printf '{"event":"surface_output","surfaceID":"\(surfaceID.uuidString)","bytesBase64":"b2sK"}\\n'
              printf '{"id":"hello","ok":true,"hello":{"version":"dev","protocolVersion":1,"capabilities":["ipc-jsonl-v1"]}}\\n'
              ;;
            *\\"command\\":\\"shutdown\\"*)
              printf '{"id":"bye","ok":true}\\n'
              exit 0
              ;;
          esac
        done
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let connection = PTYDaemonProcessConnection(executableURL: scriptURL)

        _ = try connection.send(PTYDaemonRequest(id: "hello", command: .hello))
        let event = try connection.receiveEvent(timeout: 0)
        _ = try connection.send(PTYDaemonRequest(id: "bye", command: .shutdown))

        #expect(event?.event == .surfaceOutput)
        #expect(event?.surfaceID == surfaceID.uuidString)
        #expect(event?.bytesBase64 == "b2sK")
    }

    private func terminalSurfaceHello() -> PTYDaemonHello {
        PTYDaemonHello(
            version: "dev",
            capabilities: [
                PTYDaemonProtocol.jsonLinesCapability,
                PTYDaemonProtocol.terminalSurfaceCapability,
                PTYDaemonProtocol.terminalEngineCapability,
            ]
        )
    }

    private func testConfig() -> TerminalEngineConfig {
        TerminalEngineConfig(
            fontFamily: "Menlo",
            fontSize: 13,
            themeName: "Catppuccin Mocha",
            shell: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
    }
}

@MainActor
private final class MockPTYDaemonClientConnection: PTYDaemonClientConnection {
    private var responses: [PTYDaemonResponse]
    private var events: [PTYDaemonEvent]
    private var throwOnCommands: [PTYDaemonRequest.Command]
    private(set) var requests: [PTYDaemonRequest] = []
    private(set) var reconnectCount = 0

    init(
        responses: [PTYDaemonResponse],
        events: [PTYDaemonEvent] = [],
        throwOnCommands: [PTYDaemonRequest.Command] = []
    ) {
        self.responses = responses
        self.events = events
        self.throwOnCommands = throwOnCommands
    }

    func send(_ request: PTYDaemonRequest) throws -> PTYDaemonResponse {
        requests.append(request)
        if let index = throwOnCommands.firstIndex(of: request.command) {
            throwOnCommands.remove(at: index)
            throw TerminalEngineError.initializationFailed(reason: "mock transport failure")
        }
        guard responses.isEmpty == false else {
            return PTYDaemonResponse(id: request.id, ok: false, error: "missing mock response")
        }
        return responses.removeFirst()
    }

    func receiveEvent(timeout: TimeInterval) throws -> PTYDaemonEvent? {
        events.isEmpty ? nil : events.removeFirst()
    }

    func reconnect() throws {
        reconnectCount += 1
    }
}
