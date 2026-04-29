// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// main.swift - Local PTY daemon helper entrypoint.

import CocxyShared
#if canImport(Darwin)
import Darwin
#endif
import Foundation

#if canImport(Darwin)
_ = signal(SIGPIPE, SIG_IGN)
#endif

private func helperVersion() -> String {
    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        ?? "dev"
}

private func makeHello() -> PTYDaemonHello {
    PTYDaemonHello(
        version: helperVersion(),
        pid: Int32(ProcessInfo.processInfo.processIdentifier),
        capabilities: [PTYDaemonProtocol.jsonLinesCapability]
    )
}

private func writeResponse(_ response: PTYDaemonResponse) {
    guard let data = try? PTYDaemonLineCodec.encode(response) else { return }
    FileHandle.standardOutput.write(data)
}

private func runStdioLoop() {
    while let line = readLineData(), line.isEmpty == false {
        let request: PTYDaemonRequest
        do {
            request = try PTYDaemonLineCodec.decode(PTYDaemonRequest.self, fromLine: line)
        } catch {
            writeResponse(PTYDaemonResponse(id: "invalid", ok: false, error: "invalid request"))
            continue
        }

        switch request.command {
        case .hello:
            writeResponse(PTYDaemonResponse(id: request.id, ok: true, hello: makeHello()))
        case .shutdown:
            writeResponse(PTYDaemonResponse(id: request.id, ok: true))
            return
        case .surfaceCreate,
             .surfaceAttach,
             .surfaceWrite,
             .surfaceResize,
             .surfaceClose,
             .surfaceFrameSubscribe,
             .surfaceSignal,
             .surfaceKey,
             .surfacePreedit,
             .surfaceFocus,
             .surfaceSearch,
             .surfaceScroll,
             .surfaceProcess:
            writeResponse(
                PTYDaemonResponse(
                    id: request.id,
                    ok: false,
                    error: "\(request.command.rawValue) requires \(PTYDaemonProtocol.terminalSurfaceCapability)"
                )
            )
        }
    }
}

let arguments = Set(CommandLine.arguments.dropFirst())
if arguments.contains("--stdio") {
    runStdioLoop()
} else if arguments.contains("--hello") {
    let response = PTYDaemonResponse(id: "hello", ok: true, hello: makeHello())
    writeResponse(response)
} else {
    FileHandle.standardError.write(
        "Usage: cocxyd --stdio | --hello\n".data(using: .utf8)!
    )
    exit(64)
}

private func readLineData() -> Data? {
    var buffer = Data()
    var byte: UInt8 = 0

    while true {
        let count = read(STDIN_FILENO, &byte, 1)
        if count <= 0 {
            return buffer.isEmpty ? nil : buffer
        }
        buffer.append(byte)
        if byte == 0x0A {
            return buffer
        }
    }
}
