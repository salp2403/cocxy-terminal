// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPProcess.swift - Process boundary helpers for local language servers.

import Foundation

protocol LSPProcessManaging: LSPTransporting {
    var isRunning: Bool { get }
    var onOutputData: ((Data) -> Void)? { get set }

    func start() throws
    func stop()
}

struct LSPProcessConfiguration: Equatable, Sendable {
    let executablePath: String
    let arguments: [String]
    let environment: [String: String]
    let workingDirectoryURL: URL?

    init(
        executablePath: String,
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectoryURL: URL? = nil
    ) {
        self.executablePath = executablePath
        self.arguments = arguments
        self.environment = LSPProcessEnvironment.sanitized(from: environment)
        self.workingDirectoryURL = workingDirectoryURL
    }
}

enum LSPProcessError: Error, Equatable {
    case alreadyRunning
    case executableNotFound(String)
    case notRunning
    case stdinUnavailable
}

final class LSPProcess: LSPProcessManaging, @unchecked Sendable {
    private let configuration: LSPProcessConfiguration
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    var onOutputData: ((Data) -> Void)? {
        didSet {
            installOutputHandler()
        }
    }

    var isRunning: Bool {
        process?.isRunning == true
    }

    init(configuration: LSPProcessConfiguration) {
        self.configuration = configuration
    }

    deinit {
        stop()
    }

    func start() throws {
        guard !isRunning else {
            throw LSPProcessError.alreadyRunning
        }

        guard FileManager.default.isExecutableFile(atPath: configuration.executablePath) else {
            throw LSPProcessError.executableNotFound(configuration.executablePath)
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: configuration.executablePath)
        process.arguments = configuration.arguments
        process.environment = configuration.environment
        process.currentDirectoryURL = configuration.workingDirectoryURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
        installOutputHandler()
    }

    func stop() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil

        if process?.isRunning == true {
            process?.terminate()
            process?.waitUntilExit()
        }

        try? inputPipe?.fileHandleForWriting.close()
        try? outputPipe?.fileHandleForReading.close()
        try? errorPipe?.fileHandleForReading.close()

        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
    }

    func send(_ frame: Data) throws {
        guard isRunning else {
            throw LSPProcessError.notRunning
        }
        guard let inputPipe else {
            throw LSPProcessError.stdinUnavailable
        }

        try inputPipe.fileHandleForWriting.write(contentsOf: frame)
    }

    private func installOutputHandler() {
        outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else { return }
            self?.onOutputData?(data)
        }
    }
}

enum LSPProcessEnvironment {
    private static let allowedExactKeys: Set<String> = [
        "PATH",
        "HOME",
        "TMPDIR",
        "DEVELOPER_DIR",
        "SDKROOT",
        "TOOLCHAINS",
        "SHELL",
        "USER",
        "LOGNAME",
        "LANG",
        "XDG_CONFIG_HOME",
        "XDG_CACHE_HOME",
        "XDG_DATA_HOME",
        "JAVA_HOME",
        "GOPATH",
        "GOROOT",
        "CARGO_HOME",
        "RUSTUP_HOME",
        "NODE_PATH",
        "NPM_CONFIG_PREFIX",
        "PYENV_ROOT",
        "RBENV_ROOT",
        "GEM_HOME",
        "GEM_PATH",
        "COMPOSER_HOME",
    ]

    private static let blockedFragments = [
        "secret",
        "token",
        "password",
        "credential",
        "private_key",
        "apikey",
        "api_key",
    ]

    static func sanitized(from environment: [String: String]) -> [String: String] {
        environment.reduce(into: [:]) { result, pair in
            let key = pair.key
            let lowercaseKey = key.lowercased()

            guard allowedExactKeys.contains(key) || key.hasPrefix("LC_") else {
                return
            }

            guard !blockedFragments.contains(where: { lowercaseKey.contains($0) }) else {
                return
            }

            result[key] = pair.value
        }
    }
}
