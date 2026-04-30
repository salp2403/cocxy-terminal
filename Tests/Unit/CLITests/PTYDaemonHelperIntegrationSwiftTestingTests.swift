// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonHelperIntegrationSwiftTestingTests.swift - Real cocxyd smoke tests.

import Foundation
import Testing
import CocxyShared

@Suite("PTY daemon helper integration")
struct PTYDaemonHelperIntegrationSwiftTestingTests {

    @Test("built cocxyd helper reports the complete terminal engine capability set")
    func helperHelloReportsTerminalCapabilities() throws {
        let response = try runHelper(arguments: ["--hello"])
        let decoded = try PTYDaemonLineCodec.decode(PTYDaemonResponse.self, fromLine: firstLine(response))

        #expect(decoded.ok == true)
        #expect(decoded.hello?.capabilities == [
            PTYDaemonProtocol.jsonLinesCapability,
            PTYDaemonProtocol.terminalSurfaceCapability,
            PTYDaemonProtocol.terminalEngineCapability,
            PTYDaemonProtocol.terminalHostRendererCapability,
        ])
        #expect(decoded.hello?.supportsTerminalSurfaces == true)
        #expect(decoded.hello?.supportsTerminalHostRenderer == true)
        #expect(decoded.hello?.supportsTerminalEngineAdapter == true)
    }

    @Test("daemon spawn strips host NO_COLOR before forking the child shell")
    func helperSpawnStripsHostNoColor() throws {
        let helper = try RunningHelperProcess(extraEnvironment: ["NO_COLOR": "1"])
        defer { helper.shutdownIfNeeded() }

        let create = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "create",
                command: .surfaceCreate,
                payload: [
                    "command": "/bin/sh",
                    "workingDirectory": "/tmp",
                    "rows": "8",
                    "columns": "60",
                ]
            )
        )
        let surfaceID = try #require(create.surfaceID)

        // The probe expands `$NO_COLOR` so the resulting line is either
        // `NOCOLOR_PROBE__END` (variable unset, the success case) or
        // `NOCOLOR_PROBE_1_END` (the host value leaked through). The literal
        // command echoed by the PTY contains `${NO_COLOR}` with the dollar
        // sign and braces, never the post-expansion sentinel, so a substring
        // match is unambiguous against the executed result.
        let probeScript = "echo NOCOLOR_PROBE_${NO_COLOR}_END\n"
        let write = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "write",
                command: .surfaceWrite,
                payload: [
                    "surfaceID": surfaceID,
                    "bytesBase64": Data(probeScript.utf8).base64EncodedString(),
                ]
            )
        )
        #expect(write.ok == true)

        let output = try helper.waitForOutputText(
            surfaceID: surfaceID,
            containingUTF8: "NOCOLOR_PROBE__END",
            timeout: 5
        )
        #expect(output.contains("NOCOLOR_PROBE__END"))
        #expect(output.contains("NOCOLOR_PROBE_1_END") == false)

        _ = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "close",
                command: .surfaceClose,
                payload: ["surfaceID": surfaceID]
            )
        )
    }

    @Test("daemon isolates output across N concurrent surfaces under one helper process")
    func helperIsolatesOutputAcrossConcurrentSurfaces() throws {
        let helper = try RunningHelperProcess()
        defer { helper.shutdownIfNeeded() }

        let surfaceCount = 3
        var live: [(id: String, marker: String)] = []
        live.reserveCapacity(surfaceCount)

        for index in 0..<surfaceCount {
            let create = try helper.sendAndWait(
                PTYDaemonRequest(
                    id: "create-\(index)",
                    command: .surfaceCreate,
                    payload: [
                        "command": "/bin/sh",
                        "workingDirectory": "/tmp",
                        "rows": "8",
                        "columns": "40",
                    ]
                )
            )
            let id = try #require(create.surfaceID)
            let marker = "phase52-\(index)-\(UUID().uuidString.prefix(8))"
            live.append((id: id, marker: marker))
        }

        for (id, marker) in live {
            let subscribe = try helper.sendAndWait(
                PTYDaemonRequest(
                    id: "subscribe-\(id)",
                    command: .surfaceFrameSubscribe,
                    payload: ["surfaceID": id]
                )
            )
            #expect(subscribe.ok == true)

            let write = try helper.sendAndWait(
                PTYDaemonRequest(
                    id: "write-\(id)",
                    command: .surfaceWrite,
                    payload: [
                        "surfaceID": id,
                        "bytesBase64": Data("printf '\(marker)\\n'\n".utf8).base64EncodedString(),
                    ]
                )
            )
            #expect(write.ok == true)
        }

        for (id, marker) in live {
            let output = try helper.waitForOutputText(
                surfaceID: id,
                containingUTF8: marker,
                timeout: 5
            )
            #expect(output.contains(marker))
            for (otherID, otherMarker) in live where otherID != id {
                #expect(
                    output.contains(otherMarker) == false,
                    "surface \(id) leaked marker from surface \(otherID)"
                )
            }
        }

        for (id, _) in live {
            let close = try helper.sendAndWait(
                PTYDaemonRequest(
                    id: "close-\(id)",
                    command: .surfaceClose,
                    payload: ["surfaceID": id]
                )
            )
            #expect(close.ok == true)
        }
    }

    @Test("daemon emits a frame event within the SLO budget after a write")
    func helperFrameLatencyStaysWithinBudget() throws {
        let helper = try RunningHelperProcess()
        defer { helper.shutdownIfNeeded() }

        let create = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "create",
                command: .surfaceCreate,
                payload: [
                    "command": "/bin/sh",
                    "workingDirectory": "/tmp",
                    "rows": "8",
                    "columns": "40",
                ]
            )
        )
        let surfaceID = try #require(create.surfaceID)

        let subscribe = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "subscribe",
                command: .surfaceFrameSubscribe,
                payload: ["surfaceID": surfaceID]
            )
        )
        #expect(subscribe.ok == true)

        let marker = "latency-\(UUID().uuidString.prefix(8))"
        let startedAt = Date()
        let write = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "write",
                command: .surfaceWrite,
                payload: [
                    "surfaceID": surfaceID,
                    "bytesBase64": Data("printf '\(marker)\\n'\n".utf8).base64EncodedString(),
                ]
            )
        )
        #expect(write.ok == true)

        let frameEvent = try helper.waitForEvent(
            surfaceID: surfaceID,
            kind: .surfaceFrame,
            timeout: 2.0
        )
        let elapsed = Date().timeIntervalSince(startedAt)

        #expect(frameEvent.frame != nil)
        // Budget: 500ms is a generous local upper bound covering JSONL
        // round-trip, PTY shell echo, and frame build. Real production
        // p50 should be well below this; the test catches catastrophic
        // regressions, not micro-fluctuations.
        #expect(elapsed < 0.5, "frame latency \(elapsed)s exceeded SLO budget")

        _ = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "close",
                command: .surfaceClose,
                payload: ["surfaceID": surfaceID]
            )
        )
    }

    @Test("real helper creates a surface, streams output, serves frames and closes cleanly")
    func helperSurfaceLifecycleStreamsOutputFramesAndClose() throws {
        let helper = try RunningHelperProcess()
        defer { helper.shutdownIfNeeded() }

        let hello = try helper.sendAndWait(
            PTYDaemonRequest(id: "hello", command: .hello)
        )
        #expect(hello.ok == true)
        #expect(hello.hello?.supportsTerminalEngineAdapter == true)

        let invalidCreate = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "invalid-create",
                command: .surfaceCreate,
                payload: [
                    "command": "/bin/sh",
                    "workingDirectory": "/tmp/cocxy-missing-\(UUID().uuidString)",
                    "rows": "8",
                    "columns": "40",
                ]
            )
        )
        #expect(invalidCreate.ok == false)
        #expect(invalidCreate.error?.contains("workingDirectory") == true)

        let create = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "create",
                command: .surfaceCreate,
                payload: [
                    "command": "/bin/sh",
                    "workingDirectory": "/tmp",
                    "rows": "8",
                    "columns": "40",
                ]
            )
        )
        let surfaceID = try #require(create.surfaceID)

        let attach = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "attach",
                command: .surfaceAttach,
                payload: ["surfaceID": surfaceID]
            )
        )
        #expect(attach.ok == true)
        #expect(attach.surfaceID == surfaceID)

        let resize = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "resize",
                command: .surfaceResize,
                payload: ["surfaceID": surfaceID, "rows": "9", "columns": "42"]
            )
        )
        #expect(resize.ok == true)

        let focus = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "focus",
                command: .surfaceFocus,
                payload: ["surfaceID": surfaceID, "focused": "true"]
            )
        )
        #expect(focus.ok == true)

        let preedit = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "preedit",
                command: .surfacePreedit,
                payload: ["surfaceID": surfaceID, "text": "compose"]
            )
        )
        #expect(preedit.ok == true)

        let preeditClear = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "preedit-clear",
                command: .surfacePreedit,
                payload: ["surfaceID": surfaceID, "text": ""]
            )
        )
        #expect(preeditClear.ok == true)

        let frame = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "frame",
                command: .surfaceFrameSubscribe,
                payload: ["surfaceID": surfaceID]
            )
        )
        #expect(frame.ok == true)
        #expect(frame.frame?.surfaceID == surfaceID)
        #expect(frame.frame?.rows == 9)
        #expect(frame.frame?.columns == 42)

        let marker = "s93-helper-ok-\(UUID().uuidString.prefix(8))"
        let write = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "write",
                command: .surfaceWrite,
                payload: [
                    "surfaceID": surfaceID,
                    "bytesBase64": Data("printf '\(marker)\\n'\n".utf8).base64EncodedString(),
                ]
            )
        )
        #expect(write.ok == true)

        let outputText = try helper.waitForOutputText(
            surfaceID: surfaceID,
            containingUTF8: marker,
            timeout: 5
        )
        #expect(outputText.contains(marker))

        let key = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "key",
                command: .surfaceKey,
                payload: [
                    "surfaceID": surfaceID,
                    "characters": "\n",
                    "keyCode": "36",
                    "modifiers": "0",
                    "isKeyDown": "true",
                ]
            )
        )
        #expect(key.ok == true)

        let frameEvent = try helper.waitForEvent(
            surfaceID: surfaceID,
            kind: .surfaceFrame,
            timeout: 5
        )
        #expect(frameEvent.frame?.surfaceID == surfaceID)

        let search = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "search",
                command: .surfaceSearch,
                payload: [
                    "surfaceID": surfaceID,
                    "query": marker,
                    "caseSensitive": "true",
                    "useRegex": "false",
                    "maxResults": "5",
                ]
            )
        )
        #expect(search.ok == true)
        #expect(search.searchResults?.isEmpty == false)

        let scroll = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "scroll",
                command: .surfaceScroll,
                payload: ["surfaceID": surfaceID, "lineNumber": "0"]
            )
        )
        #expect(scroll.ok == true)

        let signal = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "signal",
                command: .surfaceSignal,
                payload: ["surfaceID": surfaceID, "signal": "0"]
            )
        )
        #expect(signal.ok == true)

        let missingSignal = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "signal-missing",
                command: .surfaceSignal,
                payload: ["surfaceID": surfaceID]
            )
        )
        #expect(missingSignal.ok == false)
        #expect(missingSignal.error?.contains("signal") == true)

        let process = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "process",
                command: .surfaceProcess,
                payload: ["surfaceID": surfaceID]
            )
        )
        #expect(process.ok == true)
        #expect((process.process?.shellPID ?? -1) > 0)
        #expect((process.process?.ptyMasterFD ?? -1) >= 0)

        let close = try helper.sendAndWait(
            PTYDaemonRequest(
                id: "close",
                command: .surfaceClose,
                payload: ["surfaceID": surfaceID]
            )
        )
        #expect(close.ok == true)
    }

    private func runHelper(arguments: [String], stdin: Data? = nil) throws -> Data {
        let executable = try helperExecutableURL()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }

        try process.run()
        if let stdin {
            input.fileHandleForWriting.write(stdin)
        }
        input.fileHandleForWriting.closeFile()

        if group.wait(timeout: .now() + 3) == .timedOut {
            process.terminate()
            Issue.record("cocxyd helper timed out")
        }

        return output.fileHandleForReading.readDataToEndOfFile()
    }
}

/// Long-lived `cocxyd --stdio` process used by the integration tests.
///
/// Decodes each newline-delimited message at ingest time into either a
/// response (keyed by request id) or an event (FIFO order, scanned by
/// callers). The earlier byte-queue design discarded events whose
/// `surfaceID` did not match a single waiter, which broke multi-surface
/// scenarios where output and frame events for several surfaces interleave
/// over one helper. Decoded queues let waiters inspect events without
/// removing matches that belong to other surfaces.
private final class RunningHelperProcess {
    private struct EventEnvelope: Decodable {
        let event: PTYDaemonEvent.Kind?
    }

    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var pending = Data()
    private var responses: [String: PTYDaemonResponse] = [:]
    private var events: [PTYDaemonEvent] = []
    private var isShutdown = false

    init(extraEnvironment: [String: String] = [:]) throws {
        process.executableURL = try helperExecutableURL()
        process.arguments = ["--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        if extraEnvironment.isEmpty == false {
            var env = ProcessInfo.processInfo.environment
            for (key, value) in extraEnvironment {
                env[key] = value
            }
            process.environment = env
        }
        try process.run()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.ingest(handle.availableData)
        }
    }

    deinit {
        shutdownIfNeeded()
    }

    /// Forcefully kills the helper without sending the graceful `shutdown`
    /// command. Used by crash-recovery tests to simulate an unexpected
    /// daemon termination.
    func killAbruptly() {
        guard isShutdown == false else { return }
        isShutdown = true
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        try? input.fileHandleForWriting.close()
    }

    var isRunning: Bool {
        process.isRunning
    }

    func sendAndWait(_ request: PTYDaemonRequest, timeout: TimeInterval = 5) throws -> PTYDaemonResponse {
        input.fileHandleForWriting.write(try PTYDaemonLineCodec.encode(request))
        return try waitForResponse(id: request.id, timeout: timeout)
    }

    func waitForEvent(
        surfaceID: String,
        kind: PTYDaemonEvent.Kind,
        timeout: TimeInterval
    ) throws -> PTYDaemonEvent {
        try waitForEvent(timeout: timeout) { event in
            event.surfaceID == surfaceID && event.event == kind
        }
    }

    /// Removes and returns the first event matching the predicate, blocking
    /// for new input until `timeout` elapses. Lines that do not match are
    /// preserved so other surfaces' waiters can still consume them.
    func waitForEvent(
        timeout: TimeInterval,
        matching predicate: (PTYDaemonEvent) -> Bool
    ) throws -> PTYDaemonEvent {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let event = consumeEvent(matching: predicate) {
                return event
            }
            _ = semaphore.wait(timeout: .now() + 0.05)
        }
        throw HelperTestError.timeout("event matching predicate")
    }

    /// Drains output events for the given surface until `marker` appears in
    /// the accumulated UTF-8 text. Events for other surfaces stay in the
    /// queue so concurrent waiters keep working.
    func waitForOutputText(
        surfaceID: String,
        containingUTF8 marker: String,
        timeout: TimeInterval
    ) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var accumulated = ""
        while Date() < deadline {
            if let event = consumeEvent(matching: { e in
                e.surfaceID == surfaceID && e.event == .surfaceOutput
            }),
               let raw = event.bytesBase64,
               let data = Data(base64Encoded: raw),
               let text = String(data: data, encoding: .utf8) {
                accumulated += text
                if accumulated.contains(marker) {
                    return accumulated
                }
            } else {
                _ = semaphore.wait(timeout: .now() + 0.05)
            }
        }
        throw HelperTestError.timeout("output containing \(marker)")
    }

    func shutdownIfNeeded() {
        guard isShutdown == false else { return }
        isShutdown = true
        output.fileHandleForReading.readabilityHandler = nil
        if process.isRunning {
            try? input.fileHandleForWriting.write(
                PTYDaemonLineCodec.encode(PTYDaemonRequest(id: "shutdown", command: .shutdown))
            )
            input.fileHandleForWriting.closeFile()
            process.terminate()
        }
    }

    private func waitForResponse(id: String, timeout: TimeInterval) throws -> PTYDaemonResponse {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let response = lock.withLock({ responses.removeValue(forKey: id) }) {
                return response
            }
            _ = semaphore.wait(timeout: .now() + 0.05)
        }
        throw HelperTestError.timeout("response \(id)")
    }

    private func consumeEvent(matching predicate: (PTYDaemonEvent) -> Bool) -> PTYDaemonEvent? {
        lock.withLock {
            for index in events.indices where predicate(events[index]) {
                return events.remove(at: index)
            }
            return nil
        }
    }

    private func ingest(_ data: Data) {
        guard data.isEmpty == false else { return }
        var notify = false
        lock.withLock {
            pending.append(data)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = Data(pending.prefix(through: newline))
                pending.removeSubrange(pending.startIndex...newline)
                store(line, &notify)
            }
        }
        if notify {
            semaphore.signal()
        }
    }

    private func store(_ line: Data, _ notify: inout Bool) {
        guard let envelope = try? PTYDaemonLineCodec.decode(EventEnvelope.self, fromLine: line) else {
            return
        }
        if envelope.event != nil {
            if let event = try? PTYDaemonLineCodec.decode(PTYDaemonEvent.self, fromLine: line) {
                events.append(event)
                notify = true
            }
        } else if let response = try? PTYDaemonLineCodec.decode(PTYDaemonResponse.self, fromLine: line) {
            responses[response.id] = response
            notify = true
        }
    }
}

private func firstLine(_ data: Data) throws -> Data {
    guard let newline = data.firstIndex(of: 0x0A) else {
        throw HelperTestError.timeout("first line")
    }
    return Data(data.prefix(through: newline))
}

private func helperExecutableURL() throws -> URL {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let candidates = [
        root.appendingPathComponent(".build/debug/\(PTYDaemonProtocol.helperName)"),
        root.appendingPathComponent(".build/arm64-apple-macosx/debug/\(PTYDaemonProtocol.helperName)"),
    ]
    for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
        return candidate
    }
    throw HelperTestError.missing(candidates.map(\.path))
}

private enum HelperTestError: Error, CustomStringConvertible {
    case missing([String])
    case timeout(String)

    var description: String {
        switch self {
        case .missing(let paths):
            "Missing built cocxyd helper at: \(paths.joined(separator: ", "))"
        case .timeout(let label):
            "Timed out waiting for \(label)"
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
