// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonClient.swift - Experimental TerminalEngine adapter for cocxyd.

import Foundation
import CocxyShared

@MainActor
protocol PTYDaemonClientConnection: AnyObject {
    func send(_ request: PTYDaemonRequest) throws -> PTYDaemonResponse
    func receiveEvent(timeout: TimeInterval) throws -> PTYDaemonEvent?
    func reconnect() throws
}

private struct PTYDaemonMessageEnvelope: Decodable {
    let event: PTYDaemonEvent.Kind?
}

private final class PTYDaemonProcessMessageBuffer: @unchecked Sendable {
    private let pendingBytes = LockedBox<Data>(Data())
    private let responses = LockedBox<[String: PTYDaemonResponse]>([:])
    private let events = LockedBox<[PTYDaemonEvent]>([])
    private let responseSemaphore = DispatchSemaphore(value: 0)
    private let eventSemaphore = DispatchSemaphore(value: 0)

    func reset() {
        pendingBytes.withValue { $0.removeAll(keepingCapacity: false) }
        responses.withValue { $0.removeAll(keepingCapacity: false) }
        events.withValue { $0.removeAll(keepingCapacity: false) }
    }

    func ingest(_ chunk: Data) {
        guard chunk.isEmpty == false else { return }
        let lines = pendingBytes.withValue { buffer -> [Data] in
            buffer.append(chunk)
            var complete: [Data] = []
            while let newline = buffer.firstIndex(of: 0x0A) {
                complete.append(Data(buffer.prefix(through: newline)))
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            return complete
        }

        for line in lines {
            store(line)
        }
    }

    func waitForResponse(id: String, timeout: TimeInterval) -> PTYDaemonResponse? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let response = responses.withValue({ $0.removeValue(forKey: id) }) {
                return response
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            if responseSemaphore.wait(timeout: .now() + remaining) == .timedOut {
                return nil
            }
        }
    }

    func receiveEvent(timeout: TimeInterval) -> PTYDaemonEvent? {
        if let event = events.withValue({ $0.isEmpty ? nil : $0.removeFirst() }) {
            return event
        }
        guard timeout > 0 else { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return nil }
            if eventSemaphore.wait(timeout: .now() + remaining) == .timedOut {
                return nil
            }
            if let event = events.withValue({ $0.isEmpty ? nil : $0.removeFirst() }) {
                return event
            }
        }
    }

    private func store(_ line: Data) {
        do {
            let envelope = try PTYDaemonLineCodec.decode(PTYDaemonMessageEnvelope.self, fromLine: line)
            if envelope.event != nil {
                let event = try PTYDaemonLineCodec.decode(PTYDaemonEvent.self, fromLine: line)
                events.withValue { $0.append(event) }
                eventSemaphore.signal()
            } else {
                let response = try PTYDaemonLineCodec.decode(PTYDaemonResponse.self, fromLine: line)
                responses.withValue { $0[response.id] = response }
                responseSemaphore.signal()
            }
        } catch {
            // The daemon protocol is fail-closed: malformed lines are ignored
            // so a bad helper cannot crash the app process.
        }
    }
}

/// Persistent stdio connection used by the experimental daemon adapter.
///
/// The current helper is intentionally IPC-only in production builds. This
/// connection gives the client adapter a real transport once a future helper
/// advertises the complete terminal-engine capability set, without changing
/// app behavior while either capability is absent.
@MainActor
final class PTYDaemonProcessConnection: PTYDaemonClientConnection {
    private let executableURL: URL
    private let timeoutSeconds: TimeInterval
    private let messageBuffer = PTYDaemonProcessMessageBuffer()
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?

    init(executableURL: URL, timeoutSeconds: TimeInterval = 2) {
        self.executableURL = executableURL
        self.timeoutSeconds = timeoutSeconds
    }

    deinit {
        process?.terminate()
    }

    func send(_ request: PTYDaemonRequest) throws -> PTYDaemonResponse {
        try ensureProcessRunning()
        guard let inputPipe else {
            throw TerminalEngineError.initializationFailed(reason: "PTY daemon transport is not connected")
        }

        inputPipe.fileHandleForWriting.write(try PTYDaemonLineCodec.encode(request))
        guard let response = messageBuffer.waitForResponse(id: request.id, timeout: timeoutSeconds) else {
            resetProcess()
            throw TerminalEngineError.initializationFailed(reason: "PTY daemon request timed out")
        }
        if request.command == .shutdown {
            resetProcess()
        }
        return response
    }

    func receiveEvent(timeout: TimeInterval = 0) throws -> PTYDaemonEvent? {
        guard process?.isRunning == true else { return nil }
        return messageBuffer.receiveEvent(timeout: timeout)
    }

    func reconnect() throws {
        resetProcess()
        try ensureProcessRunning()
    }

    private func ensureProcessRunning() throws {
        if process?.isRunning == true { return }
        resetProcess()

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--stdio"]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw TerminalEngineError.initializationFailed(reason: String(describing: error))
        }

        messageBuffer.reset()
        output.fileHandleForReading.readabilityHandler = { [messageBuffer] handle in
            messageBuffer.ingest(handle.availableData)
        }

        self.process = process
        self.inputPipe = input
        self.outputPipe = output
    }

    private func resetProcess() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        inputPipe?.fileHandleForWriting.closeFile()
        outputPipe?.fileHandleForReading.closeFile()
        inputPipe = nil
        outputPipe = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        messageBuffer.reset()
    }
}

@MainActor
final class PTYDaemonClient: TerminalEngine {
    private let connection: PTYDaemonClientConnection
    private var initialized = false
    private var liveSurfaces = Set<SurfaceID>()
    private var stalledSurfaces = Set<SurfaceID>()
    private var outputHandlers: [SurfaceID: @Sendable (Data) -> Void] = [:]
    private var oscHandlers: [SurfaceID: @Sendable (OSCNotification) -> Void] = [:]
    private var frameHandlers: [SurfaceID: @Sendable (PTYDaemonSurfaceFrame) -> Void] = [:]

    init(connection: PTYDaemonClientConnection) {
        self.connection = connection
    }

    func initialize(config: TerminalEngineConfig) throws {
        let response = try connection.send(PTYDaemonRequest(id: UUID().uuidString, command: .hello))
        guard response.ok, let hello = response.hello else {
            throw TerminalEngineError.initializationFailed(
                reason: response.error ?? "PTY daemon did not return hello"
            )
        }
        guard hello.supportsTerminalEngineAdapter else {
            throw TerminalEngineError.initializationFailed(
                reason: "PTY daemon lacks the complete terminal engine and host renderer capability set"
            )
        }
        initialized = true
    }

    func createSurface(
        in view: NativeTerminalView,
        workingDirectory: URL?,
        command: String?
    ) throws -> SurfaceID {
        guard initialized else {
            throw TerminalEngineError.surfaceCreationFailed(reason: "PTY daemon client is not initialized")
        }

        let response = try connection.send(
            PTYDaemonRequest(
                id: UUID().uuidString,
                command: .surfaceCreate,
                payload: [
                    "workingDirectory": workingDirectory?.path ?? "",
                    "command": command ?? "",
                ]
            )
        )
        guard response.ok,
              let rawSurfaceID = response.surfaceID,
              let uuid = UUID(uuidString: rawSurfaceID)
        else {
            throw TerminalEngineError.surfaceCreationFailed(
                reason: response.error ?? "PTY daemon did not return a valid surface id"
            )
        }

        let surfaceID = SurfaceID(rawValue: uuid)
        liveSurfaces.insert(surfaceID)
        stalledSurfaces.remove(surfaceID)
        return surfaceID
    }

    func destroySurface(_ id: SurfaceID) {
        _ = try? sendSurfaceRequest(id, command: .surfaceClose)
        liveSurfaces.remove(id)
        stalledSurfaces.remove(id)
        outputHandlers[id] = nil
        oscHandlers[id] = nil
        frameHandlers[id] = nil
    }

    @discardableResult
    func sendKeyEvent(_ event: KeyEvent, to surface: SurfaceID) -> Bool {
        let response = try? sendSurfaceRequest(
            surface,
            command: .surfaceKey,
            payload: [
                "characters": event.characters ?? "",
                "keyCode": "\(event.keyCode)",
                "modifiers": "\(event.modifiers.rawValue)",
                "isKeyDown": "\(event.isKeyDown)",
                "isRepeat": "\(event.isRepeat)",
                "isComposing": "\(event.isComposing)",
                "unshiftedCodepoint": "\(event.unshiftedCodepoint)",
                "consumedModsRaw": "\(event.consumedModsRaw)",
            ]
        )
        return response?.ok == true
    }

    func sendText(_ text: String, to surface: SurfaceID) {
        let data = Data(text.utf8).base64EncodedString()
        _ = try? sendSurfaceRequest(surface, command: .surfaceWrite, payload: ["bytesBase64": data])
    }

    func sendPreeditText(_ text: String, to surface: SurfaceID) {
        _ = try? sendSurfaceRequest(surface, command: .surfacePreedit, payload: ["text": text])
    }

    func resize(_ surface: SurfaceID, to size: TerminalSize) {
        _ = try? sendSurfaceRequest(
            surface,
            command: .surfaceResize,
            payload: [
                "columns": "\(size.columns)",
                "rows": "\(size.rows)",
                "pixelWidth": "\(size.pixelWidth)",
                "pixelHeight": "\(size.pixelHeight)",
            ]
        )
    }

    func tick() {
        guard initialized else { return }
        for _ in 0..<32 {
            guard let event = try? connection.receiveEvent(timeout: 0.001) else { break }
            handleEvent(event)
        }
    }

    func setOutputHandler(
        for surface: SurfaceID,
        handler: @escaping @Sendable (Data) -> Void
    ) {
        outputHandlers[surface] = handler
    }

    func setOSCHandler(
        for surface: SurfaceID,
        handler: @escaping @Sendable (OSCNotification) -> Void
    ) {
        oscHandlers[surface] = handler
    }

    func setFrameHandler(
        for surface: SurfaceID,
        handler: @escaping @Sendable (PTYDaemonSurfaceFrame) -> Void
    ) {
        frameHandlers[surface] = handler
    }

    func subscribeFrames(for surface: SurfaceID) -> PTYDaemonSurfaceFrame? {
        let response = try? sendSurfaceRequest(surface, command: .surfaceFrameSubscribe)
        return response?.ok == true ? response?.frame : nil
    }

    func scrollToSearchResult(surfaceID: SurfaceID, lineNumber: Int) {
        _ = try? sendSurfaceRequest(surfaceID, command: .surfaceScroll, payload: ["lineNumber": "\(lineNumber)"])
    }

    func notifyFocus(_ focused: Bool, for surface: SurfaceID) {
        _ = try? sendSurfaceRequest(surface, command: .surfaceFocus, payload: ["focused": "\(focused)"])
    }

    func searchScrollback(surfaceID: SurfaceID, options: SearchOptions) -> [SearchResult]? {
        let response = try? sendSurfaceRequest(
            surfaceID,
            command: .surfaceSearch,
            payload: [
                "query": options.query,
                "caseSensitive": "\(options.caseSensitive)",
                "useRegex": "\(options.useRegex)",
                "maxResults": "\(options.maxResults)",
            ]
        )
        guard response?.ok == true, let results = response?.searchResults else { return nil }
        return results.compactMap { result in
            guard let uuid = UUID(uuidString: result.id) else { return nil }
            return SearchResult(
                id: uuid,
                lineNumber: result.lineNumber,
                column: result.column,
                matchText: result.matchText,
                contextBefore: result.contextBefore,
                contextAfter: result.contextAfter
            )
        }
    }

    func processMonitorRegistration(for surface: SurfaceID) -> TerminalProcessMonitorRegistration? {
        let response = try? sendSurfaceRequest(surface, command: .surfaceProcess)
        guard response?.ok == true, let process = response?.process else { return nil }
        let identity: TerminalProcessIdentity?
        if let startSeconds = process.startSeconds,
           let startMicroseconds = process.startMicroseconds {
            identity = TerminalProcessIdentity(
                pid: process.shellPID,
                startSeconds: startSeconds,
                startMicroseconds: startMicroseconds
            )
        } else {
            identity = nil
        }
        return TerminalProcessMonitorRegistration(
            shellPID: process.shellPID,
            ptyMasterFD: process.ptyMasterFD,
            shellIdentity: identity
        )
    }

    func isSurfaceStalledForTesting(_ surface: SurfaceID) -> Bool {
        stalledSurfaces.contains(surface)
    }

    private func sendSurfaceRequest(
        _ surface: SurfaceID,
        command: PTYDaemonRequest.Command,
        payload: [String: String] = [:]
    ) throws -> PTYDaemonResponse {
        guard stalledSurfaces.contains(surface) == false else {
            throw TerminalEngineError.initializationFailed(reason: "PTY daemon surface is stalled")
        }

        let request = surfaceRequest(surface, command: command, payload: payload)
        do {
            return try connection.send(request)
        } catch {
            try reconnectAndReattachLiveSurfaces()
            guard stalledSurfaces.contains(surface) == false else {
                throw TerminalEngineError.initializationFailed(reason: "PTY daemon surface failed reattach")
            }
            return try connection.send(request)
        }
    }

    private func reconnectAndReattachLiveSurfaces() throws {
        try connection.reconnect()
        for surface in liveSurfaces {
            let response = try? connection.send(surfaceRequest(surface, command: .surfaceAttach))
            if response?.ok != true {
                stalledSurfaces.insert(surface)
            }
        }
    }

    private func handleEvent(_ event: PTYDaemonEvent) {
        guard let uuid = UUID(uuidString: event.surfaceID) else { return }
        let surface = SurfaceID(rawValue: uuid)

        switch event.event {
        case .surfaceOutput:
            guard let raw = event.bytesBase64,
                  let data = Data(base64Encoded: raw) else { return }
            outputHandlers[surface]?(data)
        case .surfaceOSC:
            guard let osc = event.osc,
                  let notification = makeOSCNotification(from: osc) else { return }
            oscHandlers[surface]?(notification)
        case .surfaceFrame:
            guard let frame = event.frame else { return }
            frameHandlers[surface]?(frame)
        case .surfaceClosed:
            liveSurfaces.remove(surface)
            stalledSurfaces.insert(surface)
        }
    }

    private func makeOSCNotification(from osc: PTYDaemonOSCNotification) -> OSCNotification? {
        switch osc.kind {
        case .titleChange:
            return .titleChange(osc.text ?? "")
        case .notification:
            return .notification(title: osc.title ?? "", body: osc.body ?? "")
        case .shellPrompt:
            return .shellPrompt
        case .commandStarted:
            return .commandStarted
        case .commandFinished:
            return .commandFinished(exitCode: osc.exitCode)
        case .currentDirectory:
            guard let rawURL = osc.url else { return nil }
            let url = rawURL.hasPrefix("file:")
                ? URL(string: rawURL)
                : URL(fileURLWithPath: rawURL)
            guard let url else { return nil }
            return .currentDirectory(url)
        case .inlineImage:
            return .inlineImage(osc.text ?? "")
        case .processExited:
            return .processExited
        }
    }

    private func surfaceRequest(
        _ surface: SurfaceID,
        command: PTYDaemonRequest.Command,
        payload: [String: String] = [:]
    ) -> PTYDaemonRequest {
        var payload = payload
        payload["surfaceID"] = surface.rawValue.uuidString
        return PTYDaemonRequest(id: UUID().uuidString, command: command, payload: payload)
    }
}
