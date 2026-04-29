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

private final class RunningHelperProcess {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let lock = NSLock()
    private let lineSemaphore = DispatchSemaphore(value: 0)
    private var pending = Data()
    private var lines: [Data] = []
    private var isShutdown = false

    init() throws {
        process.executableURL = try helperExecutableURL()
        process.arguments = ["--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            self?.ingest(handle.availableData)
        }
    }

    deinit {
        shutdownIfNeeded()
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
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let event = popLine().flatMap({ try? PTYDaemonLineCodec.decode(PTYDaemonEvent.self, fromLine: $0) }),
               event.surfaceID == surfaceID,
               event.event == kind {
                return event
            }
            _ = lineSemaphore.wait(timeout: .now() + 0.05)
        }
        throw HelperTestError.timeout("event \(kind.rawValue)")
    }

    func waitForOutputText(
        surfaceID: String,
        containingUTF8 marker: String,
        timeout: TimeInterval
    ) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var accumulated = ""
        while Date() < deadline {
            if let event = popLine().flatMap({ try? PTYDaemonLineCodec.decode(PTYDaemonEvent.self, fromLine: $0) }),
               event.surfaceID == surfaceID,
               event.event == .surfaceOutput,
               let raw = event.bytesBase64,
               let data = Data(base64Encoded: raw),
               let text = String(data: data, encoding: .utf8) {
                accumulated += text
                if accumulated.contains(marker) {
                    return accumulated
                }
            }
            _ = lineSemaphore.wait(timeout: .now() + 0.05)
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
            if let line = popLine() {
                if let response = try? PTYDaemonLineCodec.decode(PTYDaemonResponse.self, fromLine: line),
                   response.id == id {
                    return response
                }
                lock.withLock { lines.append(line) }
            }
            _ = lineSemaphore.wait(timeout: .now() + 0.05)
        }
        throw HelperTestError.timeout("response \(id)")
    }

    private func ingest(_ data: Data) {
        guard data.isEmpty == false else { return }
        lock.withLock {
            pending.append(data)
            while let newline = pending.firstIndex(of: 0x0A) {
                lines.append(Data(pending.prefix(through: newline)))
                pending.removeSubrange(pending.startIndex...newline)
                lineSemaphore.signal()
            }
        }
    }

    private func popLine() -> Data? {
        lock.withLock {
            lines.isEmpty ? nil : lines.removeFirst()
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
