// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonHelperIntegrationSwiftTestingTests.swift - Real cocxyd smoke tests.

import Foundation
import Testing
import CocxyShared

@Suite("PTY daemon helper integration")
struct PTYDaemonHelperIntegrationSwiftTestingTests {

    @Test("built cocxyd helper reports IPC-only capabilities")
    func helperHelloReportsIPCOnlyCapabilities() throws {
        let response = try runHelper(arguments: ["--hello"])
        let decoded = try PTYDaemonLineCodec.decode(PTYDaemonResponse.self, fromLine: response)

        #expect(decoded.ok == true)
        #expect(decoded.hello?.capabilities == [PTYDaemonProtocol.jsonLinesCapability])
        #expect(decoded.hello?.supportsTerminalSurfaces == false)
        #expect(decoded.hello?.supportsTerminalHostRenderer == false)
        #expect(decoded.hello?.supportsTerminalEngineAdapter == false)
    }

    @Test("surface commands fail closed until helper advertises terminal-surface capability")
    func surfaceCommandsFailClosedUntilCapabilityShips() throws {
        let request = PTYDaemonRequest(
            id: "surface-create-smoke",
            command: .surfaceCreate,
            payload: ["command": "/bin/zsh"]
        )
        let response = try runHelper(arguments: ["--stdio"], stdin: PTYDaemonLineCodec.encode(request))
        let decoded = try PTYDaemonLineCodec.decode(PTYDaemonResponse.self, fromLine: response)

        #expect(decoded.id == request.id)
        #expect(decoded.ok == false)
        #expect(decoded.error?.contains(PTYDaemonProtocol.terminalSurfaceCapability) == true)
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

    private func helperExecutableURL() throws -> URL {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidates = [
            root.appendingPathComponent(".build/debug/\(PTYDaemonProtocol.helperName)"),
            root.appendingPathComponent(".build/arm64-apple-macosx/debug/\(PTYDaemonProtocol.helperName)"),
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        throw HelperLookupError.missing(candidates.map(\.path))
    }

    private enum HelperLookupError: Error, CustomStringConvertible {
        case missing([String])

        var description: String {
            switch self {
            case .missing(let paths):
                "Missing built cocxyd helper at: \(paths.joined(separator: ", "))"
            }
        }
    }
}
