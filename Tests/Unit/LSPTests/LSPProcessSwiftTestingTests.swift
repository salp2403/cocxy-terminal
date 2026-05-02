// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// LSPProcessSwiftTestingTests.swift - Process/Pipe lifecycle boundaries.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("LSP process lifecycle")
struct LSPProcessSwiftTestingTests {
    @Test("process configuration sanitizes environment and preserves args")
    func configurationSanitizesEnvironment() {
        let configuration = LSPProcessConfiguration(
            executablePath: "/usr/bin/sourcekit-lsp",
            arguments: ["--stdio"],
            environment: [
                "PATH": "/usr/bin",
                "HOME": "/Users/dev",
                "GITHUB_TOKEN": "secret",
            ]
        )

        #expect(configuration.executablePath == "/usr/bin/sourcekit-lsp")
        #expect(configuration.arguments == ["--stdio"])
        #expect(configuration.environment["PATH"] == "/usr/bin")
        #expect(configuration.environment["HOME"] == "/Users/dev")
        #expect(configuration.environment["GITHUB_TOKEN"] == nil)
    }

    @Test("process starts and stops a local subprocess")
    func processStartsAndStops() throws {
        let process = LSPProcess(configuration: LSPProcessConfiguration(
            executablePath: "/bin/cat",
            arguments: [],
            environment: ["PATH": "/bin:/usr/bin"]
        ))

        try process.start()
        #expect(process.isRunning)

        process.stop()
        #expect(process.isRunning == false)
    }

    @Test("process delivers stdout data through output handler")
    func processDeliversStdoutData() throws {
        let process = LSPProcess(configuration: LSPProcessConfiguration(
            executablePath: "/bin/cat",
            arguments: [],
            environment: ["PATH": "/bin:/usr/bin"]
        ))
        let message = LSPMessage.notification(method: "initialized", params: .object([:]))
        let frame = try LSPFraming.encode(message)
        let lock = NSLock()
        let semaphore = DispatchSemaphore(value: 0)
        var received = Data()

        process.onOutputData = { data in
            lock.lock()
            received.append(data)
            lock.unlock()
            semaphore.signal()
        }

        try process.start()
        defer { process.stop() }
        try process.send(frame)

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            lock.lock()
            let snapshot = received
            lock.unlock()
            if (try? LSPFraming.decodeMessages(from: snapshot)) == [message] {
                return
            }
            _ = semaphore.wait(timeout: .now() + 0.05)
        }

        Issue.record("Expected cat subprocess to echo one framed LSP message")
    }

    @Test("starting an already running process throws")
    func startingAlreadyRunningProcessThrows() throws {
        let process = LSPProcess(configuration: LSPProcessConfiguration(
            executablePath: "/bin/cat",
            arguments: [],
            environment: ["PATH": "/bin:/usr/bin"]
        ))

        try process.start()
        defer { process.stop() }

        #expect(throws: LSPProcessError.alreadyRunning) {
            try process.start()
        }
    }

    @Test("missing executable path throws before launch")
    func missingExecutableThrows() {
        let process = LSPProcess(configuration: LSPProcessConfiguration(
            executablePath: "/tmp/cocxy-missing-lsp-server",
            arguments: [],
            environment: [:]
        ))

        #expect(throws: LSPProcessError.executableNotFound("/tmp/cocxy-missing-lsp-server")) {
            try process.start()
        }
    }
}
