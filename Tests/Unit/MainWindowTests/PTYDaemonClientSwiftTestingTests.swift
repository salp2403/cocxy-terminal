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

    @Test("initialize rejects an incompatible daemon protocol")
    func initializeRejectsIncompatibleProtocol() {
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(
                id: "hello",
                ok: true,
                hello: PTYDaemonHello(
                    version: "dev",
                    protocolVersion: PTYDaemonProtocol.protocolVersion + 1,
                    capabilities: terminalSurfaceHello().capabilities
                )
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

    @Test("initialize rejects terminal-engine without host-renderer capability")
    func initializeRejectsTerminalEngineWithoutHostRendererCapability() {
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(
                id: "hello",
                ok: true,
                hello: PTYDaemonHello(
                    version: "dev",
                    capabilities: [
                        PTYDaemonProtocol.jsonLinesCapability,
                        PTYDaemonProtocol.terminalSurfaceCapability,
                        PTYDaemonProtocol.terminalEngineCapability,
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
        #expect(connection.requests.last?.payload?["fontFamily"] == "Menlo")
        #expect(connection.requests.last?.payload?["fontSize"] == "13.0")
        #expect(connection.requests.last?.payload?["ligaturesEnabled"] == "true")
        let dpiScale = Double(connection.requests.last?.payload?["dpiScale"] ?? "")
        #expect(dpiScale?.isFinite == true)
        #expect((dpiScale ?? 0) > 0)
    }

    @Test("font updates preserve surface scale and focus requests are deduplicated")
    func fontAndFocusRequestsPreserveSurfaceState() throws {
        let rawSurfaceID = UUID()
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
            PTYDaemonResponse(id: "create", ok: true, surfaceID: rawSurfaceID.uuidString),
            PTYDaemonResponse(id: "font", ok: true),
            PTYDaemonResponse(id: "focus-in", ok: true),
            PTYDaemonResponse(id: "focus-out", ok: true),
            PTYDaemonResponse(id: "preedit-clear", ok: true),
            PTYDaemonResponse(id: "close", ok: true),
        ])
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig().replacing(ligaturesEnabled: false))
        let surfaceID = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)

        client.applyFont(family: "JetBrainsMono Nerd Font Mono", size: 18, to: surfaceID)
        client.notifyFocus(true, for: surfaceID)
        client.notifyFocus(true, for: surfaceID)
        client.notifyFocus(false, for: surfaceID)
        client.notifyFocus(false, for: surfaceID)
        client.destroySurface(surfaceID)
        client.notifyFocus(true, for: surfaceID)
        client.applyFont(family: "Menlo", size: 12, to: surfaceID)

        #expect(connection.requests.map(\.command) == [
            .hello,
            .surfaceCreate,
            .surfaceFont,
            .surfaceFocus,
            .surfaceFocus,
            .surfacePreedit,
            .surfaceClose,
        ])
        let createPayload = try #require(connection.requests[1].payload)
        let fontPayload = try #require(connection.requests[2].payload)
        #expect(createPayload["ligaturesEnabled"] == "false")
        #expect(fontPayload["fontFamily"] == "JetBrainsMono Nerd Font Mono")
        #expect(fontPayload["fontSize"] == "18.0")
        #expect(fontPayload["dpiScale"] == createPayload["dpiScale"])
        #expect(fontPayload["ligaturesEnabled"] == "false")
        #expect(connection.requests[3].payload?["focused"] == "true")
        #expect(connection.requests[4].payload?["focused"] == "false")
    }

    @Test("font default updates configure surfaces created after a hot reload")
    func fontDefaultUpdatesConfigureFutureSurfaces() throws {
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
            PTYDaemonResponse(id: "first-create", ok: true, surfaceID: UUID().uuidString),
            PTYDaemonResponse(id: "second-create", ok: true, surfaceID: UUID().uuidString),
        ])
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig().replacing(ligaturesEnabled: false))

        _ = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)
        client.updateFontDefaults(family: "Courier", size: 17)
        _ = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)

        let createRequests = connection.requests.filter { $0.command == .surfaceCreate }
        #expect(createRequests.count == 2)
        #expect(createRequests[0].payload?["fontFamily"] == "Menlo")
        #expect(createRequests[0].payload?["fontSize"] == "13.0")
        #expect(createRequests[1].payload?["fontFamily"] == "Courier")
        #expect(createRequests[1].payload?["fontSize"] == "17.0")
        #expect(createRequests[1].payload?["ligaturesEnabled"] == "false")
    }

    @Test("sendText, resize and destroy serialize surface requests")
    func sendTextResizeAndDestroySerializeRequests() throws {
        let surfaceID = UUID()
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
            PTYDaemonResponse(id: "create", ok: true, surfaceID: surfaceID.uuidString),
            PTYDaemonResponse(id: "write", ok: true),
            PTYDaemonResponse(id: "resize", ok: true),
            PTYDaemonResponse(id: "preedit-clear", ok: true),
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
        #expect(commands == [
            .hello,
            .surfaceCreate,
            .surfaceWrite,
            .surfaceResize,
            .surfacePreedit,
            .surfaceClose,
        ])
        #expect(connection.requests[2].payload?["bytesBase64"] == Data("echo ok\n".utf8).base64EncodedString())
        #expect(connection.requests[3].payload?["columns"] == "120")
        #expect(connection.requests[3].payload?["pixelHeight"] == "900")
        #expect(connection.requests[4].payload?["text"] == "")
        #expect(connection.requests[4].payload?["cursorByteOffset"] == "0")
        #expect(connection.requests[5].payload?["surfaceID"] == surfaceID.uuidString)
    }

    @Test("composing key events never cross the daemon transport")
    func composingKeyEventsDoNotSendRequests() throws {
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
        ])
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())

        let handled = client.sendKeyEvent(
            KeyEvent(
                characters: "x",
                keyCode: 7,
                modifiers: [],
                isKeyDown: true,
                isComposing: true
            ),
            to: SurfaceID()
        )

        #expect(handled == false)
        #expect(connection.requests.map(\.command) == [.hello])
    }

    @Test("progressive key press and release serialize complete metadata")
    func progressiveKeyEventsSerializeCompleteMetadata() throws {
        let rawSurfaceID = UUID()
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
            PTYDaemonResponse(id: "create", ok: true, surfaceID: rawSurfaceID.uuidString),
            PTYDaemonResponse(id: "press", ok: true),
            PTYDaemonResponse(id: "release", ok: true),
        ])
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())
        let surfaceID = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)
        let press = KeyEvent(
            characters: "Q",
            keyCode: 12,
            modifiers: [.shift, .command, .capsLock, .numLock],
            isKeyDown: true,
            unshiftedCodepoint: 113,
            shiftedCodepoint: 81,
            baseLayoutCodepoint: 113
        )

        #expect(client.sendKeyEvent(press, to: surfaceID))
        #expect(client.sendKeyEvent(
            KeyEvent(
                characters: "Q",
                keyCode: 12,
                modifiers: press.modifiers,
                isKeyDown: false,
                unshiftedCodepoint: 113,
                shiftedCodepoint: 81,
                baseLayoutCodepoint: 113
            ),
            to: surfaceID
        ))

        let requests = connection.requests.filter { $0.command == .surfaceKey }
        #expect(requests.count == 2)
        #expect(requests[0].payload?["isKeyDown"] == "true")
        #expect(requests[1].payload?["isKeyDown"] == "false")
        #expect(requests[0].payload?["unshiftedCodepoint"] == "113")
        #expect(requests[0].payload?["shiftedCodepoint"] == "81")
        #expect(requests[0].payload?["baseLayoutCodepoint"] == "113")
        #expect(requests[0].payload?["modifiers"] == "201")
    }

    @Test("preedit cursor byte offset is serialized for the daemon")
    func preeditCursorByteOffsetIsSerialized() throws {
        let rawSurfaceID = UUID()
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
            PTYDaemonResponse(id: "create", ok: true, surfaceID: rawSurfaceID.uuidString),
            PTYDaemonResponse(id: "preedit", ok: true),
        ])
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())
        let surfaceID = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)

        client.sendPreeditText("かな", cursorByteOffset: 3, to: surfaceID)

        let request = try #require(connection.requests.last)
        #expect(request.command == .surfacePreedit)
        #expect(request.payload?["text"] == "かな")
        #expect(request.payload?["cursorByteOffset"] == "3")
    }

    @Test("scrollViewport serializes relative daemon scroll requests")
    func scrollViewportSerializesRelativeDaemonScrollRequests() throws {
        let surfaceID = UUID()
        let scrollFrame = PTYDaemonSurfaceFrame(
            surfaceID: surfaceID.uuidString,
            revision: 3,
            timestamp: 3,
            columns: 2,
            rows: 1,
            cells: [],
            cursor: PTYDaemonCursor(row: 0, column: 0),
            scrollbackTop: 18
        )
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
            PTYDaemonResponse(id: "create", ok: true, surfaceID: surfaceID.uuidString),
            PTYDaemonResponse(id: "scroll", ok: true, frame: scrollFrame),
        ])
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())
        let surface = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)
        let deliveredScrollbackTop = LockedBox<Int?>(nil)
        client.setFrameHandler(for: surface) { frame in
            deliveredScrollbackTop.withValue { $0 = frame.scrollbackTop }
        }

        client.scrollViewport(surfaceID: surface, deltaRows: 18)

        #expect(connection.requests.map(\.command) == [.hello, .surfaceCreate, .surfaceScroll])
        #expect(connection.requests[2].payload?["surfaceID"] == surfaceID.uuidString)
        #expect(connection.requests[2].payload?["deltaRows"] == "18")
        #expect(connection.requests[2].payload?["lineNumber"] == nil)
        #expect(deliveredScrollbackTop.withValue { $0 } == 18)
    }

    @Test("semantic navigation sends the negotiated action and delivers its frame")
    func semanticNavigationSendsActionAndDeliversFrame() throws {
        let surfaceID = UUID()
        let frame = PTYDaemonSurfaceFrame(
            surfaceID: surfaceID.uuidString,
            revision: 4,
            timestamp: 4,
            columns: 80,
            rows: 24,
            cells: [],
            cursor: PTYDaemonCursor(row: 0, column: 0),
            scrollbackTop: 12,
            historyMaxVisibleStart: 20
        )
        let result = TerminalSemanticNavigationResult(
            action: .selectCommandOutput,
            viewportStartRow: 12,
            selection: TerminalSemanticSelection(
                blockID: 88,
                startRow: 12,
                startColumn: 0,
                endRow: 15,
                endColumn: 79,
                text: "complete daemon output"
            )
        )
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
            PTYDaemonResponse(id: "create", ok: true, surfaceID: surfaceID.uuidString),
            PTYDaemonResponse(
                id: "semantic",
                ok: true,
                frame: frame,
                semanticNavigation: result
            ),
        ])
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())
        let surface = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)
        let deliveredRevision = LockedBox<UInt64?>(nil)
        client.setFrameHandler(for: surface) { delivered in
            deliveredRevision.withValue { $0 = delivered.revision }
        }

        let returned = client.performSemanticNavigation(.selectCommandOutput, for: surface)

        #expect(returned == result)
        #expect(connection.requests.map(\.command) == [
            .hello,
            .surfaceCreate,
            .surfaceSemanticNavigation,
        ])
        #expect(connection.requests[2].payload?["surfaceID"] == surfaceID.uuidString)
        #expect(connection.requests[2].payload?["action"] == "select_command_output")
        #expect(deliveredRevision.withValue { $0 } == 4)
    }

    @Test("semantic navigation is not sent to an older compatible daemon")
    func semanticNavigationRequiresCapability() throws {
        let surfaceID = UUID()
        let hello = PTYDaemonHello(
            version: "dev",
            capabilities: [
                PTYDaemonProtocol.jsonLinesCapability,
                PTYDaemonProtocol.terminalSurfaceCapability,
                PTYDaemonProtocol.terminalEngineCapability,
                PTYDaemonProtocol.terminalHostRendererCapability,
            ]
        )
        let connection = MockPTYDaemonClientConnection(responses: [
            PTYDaemonResponse(id: "hello", ok: true, hello: hello),
            PTYDaemonResponse(id: "create", ok: true, surfaceID: surfaceID.uuidString),
        ])
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())
        let surface = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)

        #expect(client.performSemanticNavigation(.previousPrompt, for: surface) == nil)
        #expect(connection.requests.map(\.command) == [.hello, .surfaceCreate])
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
        #expect(process?.ptyMasterFD == -1)
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
                PTYDaemonEvent(
                    event: .surfaceOSC,
                    surfaceID: surfaceID.uuidString,
                    osc: PTYDaemonOSCNotification(kind: .processExited, exitCode: 9)
                ),
            ]
        )
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())
        let surface = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)
        let output = LockedBox(Data())
        let title = LockedBox<String?>(nil)
        let processExitCode = LockedBox<Int32?>(nil)

        client.setOutputHandler(for: surface) { chunk in
            output.withValue { $0.append(chunk) }
        }
        client.setOSCHandler(for: surface) { notification in
            if case .titleChange(let value) = notification {
                title.withValue { $0 = value }
            }
            if case .processExited(let exitCode) = notification {
                processExitCode.withValue { $0 = exitCode }
            }
        }

        client.tick()

        #expect(String(data: output.withValue { $0 }, encoding: .utf8) == "ready\n")
        #expect(title.withValue { $0 } == "Daemon Shell")
        #expect(processExitCode.withValue { $0 } == 9)
    }

    @Test("frame subscription requests an initial frame and tick forwards frame events")
    func frameSubscriptionRequestsInitialFrameAndForwardsFrameEvents() throws {
        let surfaceID = UUID()
        let initialFrame = PTYDaemonSurfaceFrame(
            surfaceID: surfaceID.uuidString,
            revision: 1,
            timestamp: 1,
            columns: 2,
            rows: 1,
            cells: [
                PTYDaemonGridCell(
                    row: 0,
                    column: 0,
                    glyph: 65,
                    foregroundRGBA: 0xffffffff,
                    backgroundRGBA: 0x000000ff
                )
            ],
            cursor: PTYDaemonCursor(row: 0, column: 1),
            scrollbackTop: 3,
            detectedContents: [
                PTYDaemonDetectedContent(
                    kind: .url,
                    text: "https://cocxy.dev",
                    target: "https://cocxy.dev",
                    startRow: 3,
                    startColumn: 0,
                    endRow: 3,
                    endColumn: 16
                )
            ]
        )
        let eventFrame = PTYDaemonSurfaceFrame(
            surfaceID: surfaceID.uuidString,
            revision: 2,
            timestamp: 2,
            columns: 2,
            rows: 1,
            cells: [
                PTYDaemonGridCell(
                    row: 0,
                    column: 1,
                    glyph: 66,
                    foregroundRGBA: 0xffffffff,
                    backgroundRGBA: 0x000000ff
                )
            ],
            cursor: PTYDaemonCursor(row: 0, column: 0)
        )
        let connection = MockPTYDaemonClientConnection(
            responses: [
                PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
                PTYDaemonResponse(id: "create", ok: true, surfaceID: surfaceID.uuidString),
                PTYDaemonResponse(id: "frame", ok: true, frame: initialFrame),
            ],
            events: [
                PTYDaemonEvent(event: .surfaceFrame, surfaceID: surfaceID.uuidString, frame: eventFrame)
            ]
        )
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())
        let surface = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)
        let deliveredRevision = LockedBox<UInt64?>(nil)

        client.setFrameHandler(for: surface) { frame in
            deliveredRevision.withValue { $0 = frame.revision }
        }
        let subscribed = client.subscribeFrames(for: surface)
        let cachedContents = client.visibleDetectedContents(for: surface)
        let cachedHit = client.detectedContent(atAbsoluteRow: 3, column: 8, for: surface)
        client.tick()

        #expect(subscribed?.revision == 1)
        #expect(cachedContents.map(\.target) == ["https://cocxy.dev"])
        #expect(cachedHit?.kind == .url)
        #expect(client.detectedContent(atAbsoluteRow: 4, column: 8, for: surface) == nil)
        #expect(deliveredRevision.withValue { $0 } == 2)
        #expect(connection.requests.map(\.command) == [.hello, .surfaceCreate, .surfaceFrameSubscribe])
    }

    @Test("stale daemon frames never replace a newer revision")
    func staleDaemonFramesAreDiscarded() throws {
        let rawSurfaceID = UUID()
        let foreignSurfaceID = UUID()
        func frame(revision: UInt64, surfaceID: UUID? = nil) -> PTYDaemonSurfaceFrame {
            PTYDaemonSurfaceFrame(
                surfaceID: (surfaceID ?? rawSurfaceID).uuidString,
                revision: revision,
                timestamp: Double(revision),
                columns: 2,
                rows: 1,
                cells: [],
                cursor: PTYDaemonCursor(row: 0, column: 0)
            )
        }
        let connection = MockPTYDaemonClientConnection(
            responses: [
                PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
                PTYDaemonResponse(id: "create", ok: true, surfaceID: rawSurfaceID.uuidString),
                PTYDaemonResponse(id: "frame", ok: true, frame: frame(revision: 1)),
            ],
            events: [
                PTYDaemonEvent(
                    event: .surfaceFrame,
                    surfaceID: rawSurfaceID.uuidString,
                    frame: frame(revision: 3)
                ),
                PTYDaemonEvent(
                    event: .surfaceFrame,
                    surfaceID: rawSurfaceID.uuidString,
                    frame: frame(revision: 2)
                ),
                PTYDaemonEvent(
                    event: .surfaceFrame,
                    surfaceID: rawSurfaceID.uuidString,
                    frame: frame(revision: 4, surfaceID: foreignSurfaceID)
                ),
            ]
        )
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())
        let surface = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)
        let deliveredRevisions = LockedBox<[UInt64]>([])
        client.setFrameHandler(for: surface) { frame in
            deliveredRevisions.withValue { $0.append(frame.revision) }
        }

        #expect(client.subscribeFrames(for: surface)?.revision == 1)
        client.tick()

        #expect(deliveredRevisions.withValue { $0 } == [3])
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
        let cachedFrame = PTYDaemonSurfaceFrame(
            surfaceID: surfaceID.uuidString,
            revision: 1,
            timestamp: 1,
            columns: 80,
            rows: 24,
            cells: [],
            cursor: PTYDaemonCursor(row: 0, column: 0),
            detectedContents: [
                PTYDaemonDetectedContent(
                    kind: .url,
                    text: "https://cocxy.dev",
                    target: "https://cocxy.dev",
                    startRow: 0,
                    startColumn: 0,
                    endRow: 0,
                    endColumn: 16
                )
            ]
        )
        let connection = MockPTYDaemonClientConnection(
            responses: [
                PTYDaemonResponse(id: "hello", ok: true, hello: terminalSurfaceHello()),
                PTYDaemonResponse(id: "create", ok: true, surfaceID: surfaceID.uuidString),
                PTYDaemonResponse(id: "frame", ok: true, frame: cachedFrame),
                PTYDaemonResponse(id: "attach", ok: false, error: "missing surface"),
            ],
            throwOnCommands: [.surfaceWrite]
        )
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())
        let surface = try client.createSurface(in: NSView(), workingDirectory: nil, command: nil)
        #expect(client.subscribeFrames(for: surface)?.revision == 1)
        #expect(client.visibleDetectedContents(for: surface).count == 1)

        client.sendText("stalls", to: surface)

        #expect(connection.reconnectCount == 1)
        #expect(connection.requests.map(\.command) == [
            .hello,
            .surfaceCreate,
            .surfaceFrameSubscribe,
            .surfaceWrite,
            .surfaceAttach,
        ])
        #expect(client.isSurfaceStalledForTesting(surface) == true)
        #expect(client.visibleDetectedContents(for: surface).isEmpty)
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

        // Explicit and generous: this test is about the helper being reused, not
        // about how fast a shell answers. The production default would turn a
        // loaded machine's scheduling delay into a dropped transport.
        let connection = PTYDaemonProcessConnection(
            executableURL: scriptURL,
            timeoutSeconds: 30
        )

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

        // Generous for the same reason as above: the subject is event ordering,
        // not the latency of a shell subprocess on a busy runner.
        let connection = PTYDaemonProcessConnection(
            executableURL: scriptURL,
            timeoutSeconds: 30
        )

        _ = try connection.send(PTYDaemonRequest(id: "hello", command: .hello))
        let event = try connection.receiveEvent(timeout: 0)
        _ = try connection.send(PTYDaemonRequest(id: "bye", command: .shutdown))

        #expect(event?.event == .surfaceOutput)
        #expect(event?.surfaceID == surfaceID.uuidString)
        #expect(event?.bytesBase64 == "b2sK")
    }

    @Test("process connection turns a closed helper stdin into an error without SIGPIPE")
    func processConnectionSurvivesClosedHelperInput() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-ptydaemon-epipe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let scriptURL = tempDirectory.appendingPathComponent("fake-cocxyd-epipe.sh")
        let script = """
        #!/bin/sh
        IFS= read -r line
        printf '{"id":"hello","ok":true,"hello":{"version":"dev","protocolVersion":1,"capabilities":["ipc-jsonl-v1"]}}\\n'
        exec 0<&-
        sleep 3
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let connection = PTYDaemonProcessConnection(executableURL: scriptURL, timeoutSeconds: 1)
        _ = try connection.send(PTYDaemonRequest(id: "hello", command: .hello))
        Thread.sleep(forTimeInterval: 0.1)

        #expect(throws: TerminalEngineError.self) {
            try connection.send(PTYDaemonRequest(id: "second", command: .hello))
        }
    }

    @Test("message buffer disconnects on malformed and oversized helper output")
    func messageBufferBoundsMalformedAndOversizedOutput() {
        let malformed = PTYDaemonProcessMessageBuffer()
        let malformedGeneration = malformed.reset()
        malformed.ingest(Data("not-json\n".utf8), generation: malformedGeneration)
        #expect(malformed.isDisconnected == true)

        let oversized = PTYDaemonProcessMessageBuffer()
        let oversizedGeneration = oversized.reset()
        oversized.ingest(
            Data(repeating: 0x41, count: 33 * 1_024 * 1_024),
            generation: oversizedGeneration
        )
        #expect(oversized.isDisconnected == true)
    }

    @Test("stale helper callbacks cannot disconnect a replacement generation")
    func messageBufferIgnoresStaleGenerationCallbacks() {
        let buffer = PTYDaemonProcessMessageBuffer()
        let oldGeneration = buffer.reset()
        _ = buffer.reset()

        buffer.markDisconnected(generation: oldGeneration)

        #expect(buffer.isDisconnected == false)
    }

    @Test("replies and events completed before the helper exits stay deliverable")
    func messageBufferKeepsCompletedMessagesPastEndOfStream() {
        let buffer = PTYDaemonProcessMessageBuffer()
        let generation = buffer.reset()
        buffer.ingest(Data(#"{"event":"surface_closed","surfaceID":"s"}\#n{"id":"bye","ok":true}\#n"#.utf8), generation: generation)
        buffer.markDisconnected(generation: generation)

        #expect(buffer.isDisconnected)
        #expect(buffer.waitForResponse(id: "bye", timeout: 0)?.ok == true)
        #expect(buffer.receiveEvent(timeout: 0)?.event == .surfaceClosed)
    }

    @Test("real helper process connection initializes, writes, streams output and frames")
    func realHelperProcessConnectionDrivesDaemonSurface() throws {
        let helperURL = try realHelperExecutableURL()
        let client = PTYDaemonClient(
            connection: PTYDaemonProcessConnection(executableURL: helperURL, timeoutSeconds: 5)
        )
        try client.initialize(config: testConfig())
        let surface = try client.createSurface(
            in: NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 180)),
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            command: "/bin/sh"
        )
        defer { client.destroySurface(surface) }

        let marker = "s93-client-ok-\(UUID().uuidString.prefix(8))"
        let output = LockedBox("")
        let frameRevisions = LockedBox<[UInt64]>([])
        client.setOutputHandler(for: surface) { data in
            if let text = String(data: data, encoding: .utf8) {
                output.withValue { $0 += text }
            }
        }
        client.setFrameHandler(for: surface) { frame in
            frameRevisions.withValue { $0.append(frame.revision) }
        }
        _ = client.subscribeFrames(for: surface)
        client.sendText("printf '\(marker)\\n'\n", to: surface)

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline,
              output.withValue({ !$0.contains(marker) }) ||
              frameRevisions.withValue({ $0.isEmpty }) {
            client.tick()
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }

        #expect(output.withValue { $0 }.contains(marker))
        #expect(frameRevisions.withValue { $0.isEmpty } == false)
    }

    @Test("real helper crash marks the live surface stalled and reconnects under the hood")
    func realHelperCrashMarksSurfaceStalledAndReconnects() throws {
        let helperURL = try realHelperExecutableURL()
        let connection = PTYDaemonProcessConnection(executableURL: helperURL, timeoutSeconds: 3)
        let client = PTYDaemonClient(connection: connection)
        try client.initialize(config: testConfig())

        let surface = try client.createSurface(
            in: NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120)),
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            command: "/bin/sh"
        )
        let originalPid = connection.underlyingProcessIdentifierForTesting
        #expect(originalPid != nil)

        // Simulate an unexpected daemon termination (SIGKILL).
        connection.killUnderlyingProcessForTesting()

        // The next surface request triggers the client's reconnect path.
        // The new helper has no record of the prior surface, so reattach
        // returns ok=false and the surface is marked stalled.
        client.sendText("printf 'after-crash\\n'\n", to: surface)

        #expect(client.isSurfaceStalledForTesting(surface) == true)

        let recoveredPid = connection.underlyingProcessIdentifierForTesting
        #expect(recoveredPid != nil)
        #expect(recoveredPid != originalPid)

        // The reconnected helper still serves fresh surface lifecycles.
        let replacement = try client.createSurface(
            in: NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120)),
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            command: "/bin/sh"
        )
        #expect(replacement != surface)
        client.destroySurface(replacement)
    }

    @Test("client restart spins up a fresh helper without inheriting prior surfaces")
    func clientRestartConnectsToFreshHelperWithoutPriorSurfaces() throws {
        let helperURL = try realHelperExecutableURL()

        // First lifecycle: create a surface, then drop the client. Process
        // connection's deinit terminates the helper.
        let firstSurface: SurfaceID = try {
            let connection = PTYDaemonProcessConnection(executableURL: helperURL, timeoutSeconds: 3)
            let client = PTYDaemonClient(connection: connection)
            try client.initialize(config: testConfig())
            let id = try client.createSurface(
                in: NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120)),
                workingDirectory: URL(fileURLWithPath: "/tmp"),
                command: "/bin/sh"
            )
            client.sendText("printf 'phase-one\\n'\n", to: id)
            // Tear down explicitly so the helper exits before phase two
            // even if ARC keeps the closure alive briefly.
            client.destroySurface(id)
            return id
        }()

        // Second lifecycle: simulate a relaunched app. The new connection
        // spawns its own helper subprocess and gets a different surface id.
        let connection2 = PTYDaemonProcessConnection(executableURL: helperURL, timeoutSeconds: 3)
        let client2 = PTYDaemonClient(connection: connection2)
        try client2.initialize(config: testConfig())
        let secondSurface = try client2.createSurface(
            in: NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 120)),
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            command: "/bin/sh"
        )
        #expect(secondSurface != firstSurface)
        client2.destroySurface(secondSurface)
    }

    func terminalSurfaceHello() -> PTYDaemonHello {
        PTYDaemonHello(
            version: "dev",
            capabilities: [
                PTYDaemonProtocol.jsonLinesCapability,
                PTYDaemonProtocol.terminalSurfaceCapability,
                PTYDaemonProtocol.terminalEngineCapability,
                PTYDaemonProtocol.terminalHostRendererCapability,
                PTYDaemonProtocol.terminalSemanticNavigationCapability,
            ]
        )
    }

    func testConfig() -> TerminalEngineConfig {
        TerminalEngineConfig(
            fontFamily: "Menlo",
            fontSize: 13,
            themeName: "Catppuccin Mocha",
            shell: "/bin/zsh",
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
    }

    private func realHelperExecutableURL() throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            root.appendingPathComponent(".build/debug/\(PTYDaemonProtocol.helperName)"),
            root.appendingPathComponent(".build/arm64-apple-macosx/debug/\(PTYDaemonProtocol.helperName)"),
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        throw TerminalEngineError.initializationFailed(
            reason: "Missing built cocxyd helper at \(candidates.map(\.path).joined(separator: ", "))"
        )
    }
}

@MainActor
final class MockPTYDaemonClientConnection: PTYDaemonClientConnection {
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
