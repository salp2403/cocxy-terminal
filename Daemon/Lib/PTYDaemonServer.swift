// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonServer.swift - JSONL command server for the local PTY daemon.

import Foundation
import CocxyShared
#if canImport(Darwin)
import Darwin
#endif

public final class PTYDaemonServer {
    private let writer: PTYDaemonLineWriter
    private let registry: SurfaceRegistry

    public init(output: FileHandle = .standardOutput) {
        self.writer = PTYDaemonLineWriter(handle: output)
        self.registry = SurfaceRegistry(writer: writer)
    }

    public func writeHelloResponse() {
        writer.write(PTYDaemonResponse(id: "hello", ok: true, hello: makeHello()))
    }

    public func runStdioLoop() {
        while let line = Self.readLineData(), line.isEmpty == false {
            let request: PTYDaemonRequest
            do {
                request = try PTYDaemonLineCodec.decode(PTYDaemonRequest.self, fromLine: line)
            } catch {
                writer.write(PTYDaemonResponse(id: "invalid", ok: false, error: "invalid request"))
                continue
            }

            let response = handle(request)
            writer.write(response)
            if request.command == .shutdown, response.ok {
                registry.closeAll()
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
                return PTYDaemonResponse(id: request.id, ok: true)
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
                let rows = payload.uint16("rows") ?? 24
                let columns = payload.uint16("columns") ?? 80
                return PTYDaemonResponse(
                    id: request.id,
                    ok: surface.resize(rows: rows, columns: columns)
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
                return PTYDaemonResponse(
                    id: request.id,
                    ok: surface.scroll(to: payload.int("lineNumber") ?? 0)
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

    static func readLineData() -> Data? {
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
}
