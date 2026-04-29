// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PTYDaemonReadiness.swift - Local PTY daemon readiness and fallback policy.

import Foundation
import CocxyShared

enum PTYDaemonReadiness: Equatable {
    case disabled
    case helperMissing
    case helperUnhealthy(String)
    case helperVersionMismatch(actual: String, expected: String)
    case helperHealthyButSurfaceBridgeUnavailable(PTYDaemonHello)
    case terminalSurfaceBridgeAvailable(PTYDaemonHello)

    var shouldUseInProcessEngine: Bool {
        switch self {
        case .terminalSurfaceBridgeAvailable:
            return false
        case .disabled,
             .helperMissing,
             .helperUnhealthy,
             .helperVersionMismatch,
             .helperHealthyButSurfaceBridgeUnavailable:
            return true
        }
    }

    var diagnostic: String {
        switch self {
        case .disabled:
            return "PTY daemon disabled; using in-process CocxyCore bridge."
        case .helperMissing:
            return "PTY daemon requested but bundled helper is missing; using in-process CocxyCore bridge."
        case .helperUnhealthy(let reason):
            return "PTY daemon requested but helper handshake failed (\(reason)); using in-process CocxyCore bridge."
        case .helperVersionMismatch(let actual, let expected):
            return "PTY daemon helper version \(actual) does not match app version \(expected); using in-process CocxyCore bridge."
        case .helperHealthyButSurfaceBridgeUnavailable:
            return "PTY daemon helper is healthy but does not expose the complete terminal engine capability set; using in-process CocxyCore bridge."
        case .terminalSurfaceBridgeAvailable:
            return "PTY daemon helper exposes terminal-surface-v1 and terminal-engine-v1; using experimental PTYDaemonClient TerminalEngine adapter."
        }
    }
}

struct PTYDaemonHelperLocator {
    var bundle: Bundle = .main
    var fileManager: FileManager = .default

    func executableURL() -> URL? {
        let candidates: [URL?] = [
            bundle.executableURL?
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("LaunchServices", isDirectory: true)
                .appendingPathComponent("\(PTYDaemonProtocol.helperName).app", isDirectory: true)
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("MacOS", isDirectory: true)
                .appendingPathComponent(PTYDaemonProtocol.helperName, isDirectory: false),
            bundle.url(forResource: PTYDaemonProtocol.helperName, withExtension: nil),
            bundle.executableURL?
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources", isDirectory: true)
                .appendingPathComponent(PTYDaemonProtocol.helperName, isDirectory: false),
            bundle.executableURL?
                .deletingLastPathComponent()
                .appendingPathComponent(PTYDaemonProtocol.helperName, isDirectory: false)
        ]

        return candidates.compactMap { $0 }.first { url in
            fileManager.isExecutableFile(atPath: url.path)
        }
    }
}

struct PTYDaemonReadinessResolver {
    var handshake: (URL) -> Result<PTYDaemonHello, Error>
    var expectedHelperVersion: String?

    init(
        expectedHelperVersion: String? = PTYDaemonReadinessResolver.defaultExpectedHelperVersion(),
        handshake: @escaping (URL) -> Result<PTYDaemonHello, Error> = { url in
            Result { try PTYDaemonHandshake().probe(executableURL: url) }
        }
    ) {
        self.expectedHelperVersion = expectedHelperVersion
        self.handshake = handshake
    }

    func resolve(config: ExperimentalConfig, helperURL: URL?) -> PTYDaemonReadiness {
        guard config.ptyDaemonEnabled else { return .disabled }
        guard let helperURL else { return .helperMissing }

        switch handshake(helperURL) {
        case .success(let hello):
            if let expectedHelperVersion,
               expectedHelperVersion != "dev",
               hello.version != expectedHelperVersion
            {
                return .helperVersionMismatch(actual: hello.version, expected: expectedHelperVersion)
            }
            if hello.supportsTerminalEngineAdapter {
                return .terminalSurfaceBridgeAvailable(hello)
            }
            return .helperHealthyButSurfaceBridgeUnavailable(hello)
        case .failure(let error):
            return .helperUnhealthy(String(describing: error))
        }
    }

    static func defaultExpectedHelperVersion(bundle: Bundle = .main) -> String? {
        bundle.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? bundle.infoDictionary?["CFBundleVersion"] as? String
    }
}

struct PTYDaemonHandshake {
    enum HandshakeError: Error, Equatable {
        case launchFailed(String)
        case timeout
        case emptyResponse
        case invalidResponse(String)
    }

    var timeoutSeconds: TimeInterval = 2

    func probe(executableURL: URL) throws -> PTYDaemonHello {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["--stdio"]

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }

        do {
            try process.run()
        } catch {
            throw HandshakeError.launchFailed(String(describing: error))
        }

        let request = PTYDaemonRequest(id: UUID().uuidString, command: .hello)
        input.fileHandleForWriting.write(try PTYDaemonLineCodec.encode(request))
        input.fileHandleForWriting.closeFile()

        if group.wait(timeout: .now() + timeoutSeconds) == .timedOut {
            process.terminate()
            throw HandshakeError.timeout
        }

        let responseData = output.fileHandleForReading.readDataToEndOfFile()
        guard responseData.isEmpty == false else { throw HandshakeError.emptyResponse }

        let firstLine: Data
        if let newlineIndex = responseData.firstIndex(of: 0x0A) {
            firstLine = responseData.prefix(through: newlineIndex)
        } else {
            throw HandshakeError.invalidResponse("missing newline")
        }

        let response = try PTYDaemonLineCodec.decode(PTYDaemonResponse.self, fromLine: firstLine)
        guard response.ok, let hello = response.hello else {
            throw HandshakeError.invalidResponse(response.error ?? "missing hello")
        }
        return hello
    }
}
