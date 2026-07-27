// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonServer.swift - JSONL command server for the local PTY daemon.

import Foundation
import CocxyShared
#if canImport(Darwin)
import Darwin
#endif

public final class PTYDaemonServer {
    private static let maximumRequestLineBytes = 16 * 1_024 * 1_024
    private static let inputReadBufferBytes = 64 * 1_024
    private let writer: PTYDaemonLineWriter
    private let registry: SurfaceRegistry
    private var inputBuffer = Data()

    public init(output: FileHandle = .standardOutput) {
        self.writer = PTYDaemonLineWriter(handle: output)
        self.registry = SurfaceRegistry(writer: writer)
    }

    public func writeHelloResponse() {
        writer.write(PTYDaemonResponse(id: "hello", ok: true, hello: makeHello()))
    }

    public func runStdioLoop() {
        defer { _ = registry.closeAll() }

        while let line = readLineData(), line.isEmpty == false {
            let request: PTYDaemonRequest
            do {
                request = try PTYDaemonLineCodec.decode(PTYDaemonRequest.self, fromLine: line)
            } catch {
                writer.write(PTYDaemonResponse(id: "invalid", ok: false, error: "invalid request"))
                continue
            }

            let response = handle(request)
            guard writer.write(response) else { return }
            if request.command == .shutdown {
                return
            }
        }
        registry.closeAll()
    }

    func handle(_ request: PTYDaemonRequest) -> PTYDaemonResponse {
        let payload = request.payload ?? [:]
        do {
            switch request.command {
            case .hello:
                return PTYDaemonResponse(id: request.id, ok: true, hello: makeHello())
            case .shutdown:
                let didCloseAll = registry.closeAll()
                return PTYDaemonResponse(
                    id: request.id,
                    ok: didCloseAll,
                    error: didCloseAll ? nil : "one or more terminal surfaces did not terminate cleanly"
                )
            case .surfaceCreate:
                let surface = try registry.create(payload: payload)
                return PTYDaemonResponse(id: request.id, ok: true, surfaceID: surface.surfaceID)
            case .surfaceAttach:
                let surface = try requireSurface(payload)
                return PTYDaemonResponse(id: request.id, ok: surface.attach(), surfaceID: surface.surfaceID)
            case .surfaceWrite:
                let surface = try requireSurface(payload)
                guard let raw = payload.nonEmpty("bytesBase64"),
                      let data = Data(base64Encoded: raw) else {
                    throw PTYDaemonSurfaceError.invalidPayload("surface_write requires valid bytesBase64")
                }
                return PTYDaemonResponse(id: request.id, ok: surface.write(bytes: data))
            case .surfaceResize:
                let surface = try requireSurface(payload)
                let dimensions = try PTYDaemonSurface.validatedDimensions(payload: payload)
                return PTYDaemonResponse(
                    id: request.id,
                    ok: surface.resize(rows: dimensions.rows, columns: dimensions.columns)
                )
            case .surfaceClose:
                return PTYDaemonResponse(id: request.id, ok: registry.close(id: payload["surfaceID"]))
            case .surfaceFrameSubscribe:
                let surface = try requireSurface(payload)
                return PTYDaemonResponse(id: request.id, ok: true, frame: surface.subscribeFrame())
            case .surfaceSignal:
                let surface = try requireSurface(payload)
                guard let signal = payload.int32("signal") else {
                    throw PTYDaemonSurfaceError.invalidPayload("surface_signal requires signal")
                }
                surface.signal(signal)
                return PTYDaemonResponse(id: request.id, ok: true)
            case .surfaceKey:
                let surface = try requireSurface(payload)
                return PTYDaemonResponse(id: request.id, ok: surface.handleKey(payload: payload))
            case .surfacePreedit:
                let surface = try requireSurface(payload)
                surface.setPreedit(payload["text"] ?? "")
                return PTYDaemonResponse(id: request.id, ok: true)
            case .surfaceFocus:
                let surface = try requireSurface(payload)
                surface.notifyFocus(payload.bool("focused") ?? false)
                return PTYDaemonResponse(id: request.id, ok: true)
            case .surfaceSearch:
                let surface = try requireSurface(payload)
                let results = surface.search(
                    query: payload["query"] ?? "",
                    caseSensitive: payload.bool("caseSensitive") ?? false,
                    useRegex: payload.bool("useRegex") ?? false,
                    maxResults: payload.int("maxResults") ?? 50
                )
                return PTYDaemonResponse(id: request.id, ok: true, searchResults: results)
            case .surfaceScroll:
                let surface = try requireSurface(payload)
                if let deltaRows = payload.int("deltaRows") {
                    let ok = surface.scroll(by: deltaRows)
                    return PTYDaemonResponse(
                        id: request.id,
                        ok: ok,
                        frame: ok ? surface.makeFrame() : nil
                    )
                }
                let ok = surface.scroll(to: payload.int("lineNumber") ?? 0)
                return PTYDaemonResponse(
                    id: request.id,
                    ok: ok,
                    frame: ok ? surface.makeFrame() : nil
                )
            case .surfaceProcess:
                let surface = try requireSurface(payload)
                return PTYDaemonResponse(id: request.id, ok: true, process: surface.processRegistration())
            }
        } catch {
            return PTYDaemonResponse(id: request.id, ok: false, error: String(describing: error))
        }
    }

    private func makeHello() -> PTYDaemonHello {
        PTYDaemonHello(
            version: helperVersion(),
            pid: Int32(ProcessInfo.processInfo.processIdentifier),
            capabilities: [
                PTYDaemonProtocol.jsonLinesCapability,
                PTYDaemonProtocol.terminalSurfaceCapability,
                PTYDaemonProtocol.terminalEngineCapability,
                PTYDaemonProtocol.terminalHostRendererCapability,
            ]
        )
    }

    private func helperVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? "dev"
    }

    private func requireSurface(_ payload: [String: String]) throws -> PTYDaemonSurface {
        guard let surface = registry.surface(id: payload["surfaceID"]) else {
            throw PTYDaemonSurfaceError.missingSurface
        }
        return surface
    }

    private func readLineData() -> Data? {
        while true {
            if let newline = inputBuffer.firstIndex(of: 0x0A) {
                let lineLength = inputBuffer.distance(
                    from: inputBuffer.startIndex,
                    to: newline
                ) + 1
                if lineLength > Self.maximumRequestLineBytes {
                    inputBuffer.removeSubrange(inputBuffer.startIndex...newline)
                    return Data("oversized request\n".utf8)
                }
                let line = Data(inputBuffer[inputBuffer.startIndex...newline])
                inputBuffer.removeSubrange(inputBuffer.startIndex...newline)
                return line
            }

            if inputBuffer.count > Self.maximumRequestLineBytes {
                return discardOversizedLine()
            }

            var chunk = [UInt8](repeating: 0, count: Self.inputReadBufferBytes)
            let count = Darwin.read(STDIN_FILENO, &chunk, chunk.count)
            if count > 0 {
                inputBuffer.append(contentsOf: chunk.prefix(count))
                continue
            }
            if count == -1, errno == EINTR { continue }
            guard inputBuffer.isEmpty == false else { return nil }
            let remainder = inputBuffer
            inputBuffer.removeAll(keepingCapacity: false)
            return remainder
        }
    }

    private func discardOversizedLine() -> Data? {
        inputBuffer.removeAll(keepingCapacity: false)
        var chunk = [UInt8](repeating: 0, count: Self.inputReadBufferBytes)

        while true {
            let count = Darwin.read(STDIN_FILENO, &chunk, chunk.count)
            if count > 0 {
                let bytes = chunk.prefix(count)
                if let newlineOffset = bytes.firstIndex(of: 0x0A) {
                    let remainderStart = bytes.index(after: newlineOffset)
                    inputBuffer.append(contentsOf: bytes[remainderStart...])
                    return Data("oversized request\n".utf8)
                }
                continue
            }
            if count == -1, errno == EINTR { continue }
            return nil
        }
    }
}
