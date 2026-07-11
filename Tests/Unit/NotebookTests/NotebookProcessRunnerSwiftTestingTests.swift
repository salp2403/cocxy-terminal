// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// NotebookProcessRunnerSwiftTestingTests.swift - Notebook process-tree lifecycle coverage.

import Darwin
import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Notebook process runner", .serialized)
struct NotebookProcessRunnerSwiftTestingTests {
    @Test("starts the kernel in a dedicated POSIX session and preserves normal output")
    func startsDedicatedSession() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let result = try NotebookProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: [
                "python3",
                "-c",
                "import os, sys; print(os.getpid(), os.getpgrp(), os.getsid(0)); sys.stderr.write('warn\\n')",
            ],
            workingDirectory: workspace,
            timeoutSeconds: 10
        )

        let identifiers = result.stdout
            .split(whereSeparator: { $0.isWhitespace })
            .compactMap { Int32($0) }
        #expect(result.exitCode == 0)
        #expect(identifiers.count == 3)
        #expect(Set(identifiers).count == 1)
        #expect(result.stderr == "warn\n")
    }

    @Test("preserves a nonzero exit code and both output streams")
    func preservesNonzeroExitResult() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let result = try NotebookProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-c", "printf 'out\\n'; printf 'err\\n' >&2; exit 7"],
            workingDirectory: workspace,
            timeoutSeconds: 10
        )

        #expect(result.exitCode == 7)
        #expect(result.stdout == "out\n")
        #expect(result.stderr == "err\n")
    }

    @Test("preserves workspace sandbox execution and temporary cleanup")
    func preservesWorkspaceSandbox() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else { return }
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let document = NotebookDocument(cells: [
            .code(language: "bash", source: "printf 'sandbox-ok\\n'"),
        ])

        let summary = try NotebookExecutor().execute(
            document,
            workingDirectory: workspace,
            timeoutSeconds: 10,
            sandbox: .workspace
        )

        #expect(summary.results.map(\.exitCode) == [0])
        #expect(summary.results.map(\.stdout) == ["sandbox-ok\n"])
        #expect(!FileManager.default.fileExists(
            atPath: workspace.appendingPathComponent(".cocxy-notebook-tmp").path
        ))
    }

    @Test("executes normal Bash, Python, and Swift notebook kernels")
    func executesNormalKernelMatrix() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/swift") else { return }
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let document = NotebookDocument(cells: [
            .code(language: "bash", source: "printf 'bash-ok\\n'"),
            .code(language: "python", source: "print('python-ok')"),
            .code(language: "swift", source: #"print("swift-ok")"#),
        ])

        let summary = try NotebookExecutor().execute(
            document,
            workingDirectory: workspace,
            timeoutSeconds: 30,
            sandbox: .none,
            stopOnFailure: true
        )

        #expect(summary.failedCellIndex == nil)
        #expect(summary.results.map(\.exitCode) == [0, 0, 0])
        #expect(summary.results.map(\.stdout) == [
            "bash-ok\n",
            "python-ok\n",
            "swift-ok\n",
        ])
    }

    @Test("cleans background children after normal parent exit for every kernel")
    func cleansBackgroundChildrenAfterNormalParentExit() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/swift") else { return }
        for language in ["bash", "python", "swift"] {
            try await verifyNormalParentExitCleanup(language: language)
        }
    }

    @Test("timeout kills a signal-resistant child and grandchild in a detached session")
    func timeoutKillsCompleteProcessTree() async throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let files = NotebookTreeFixtureFiles(workspace: workspace)
        let source = notebookPythonTreeSource(files: files)
        let executor = NotebookExecutor()
        let document = NotebookDocument(cells: [.code(language: "python", source: source)])
        let task = Task.detached {
            try executor.execute(
                document,
                workingDirectory: workspace,
                timeoutSeconds: 2,
                sandbox: .workspace
            )
        }
        var identities: [NotebookTestProcessIdentity] = []
        defer {
            task.cancel()
            identities.forEach(notebookBestEffortTerminate)
        }

        do {
            try await notebookWaitForFile(files.ready, timeoutSeconds: 1)
        } catch {
            task.cancel()
            _ = try? await task.value
            throw error
        }
        do {
            identities = try [files.parentPID, files.childPID, files.grandchildPID]
                .map(notebookReadProcessIdentity)
        } catch {
            task.cancel()
            _ = try? await task.value
            throw error
        }
        #expect(getsid(identities[0].pid) > 0)
        #expect(getsid(identities[1].pid) == identities[1].pid)
        #expect(getsid(identities[2].pid) == identities[1].pid)

        let summary = try await task.value

        #expect(summary.results.count == 1)
        #expect(summary.results[0].exitCode == 124)
        #expect(summary.results[0].stderr.contains("Command timed out after 2 seconds."))
        for identity in identities {
            await notebookExpectProcessGone(identity)
        }
    }

    @Test("task cancellation tears down the complete process tree before throwing")
    func cancellationKillsCompleteProcessTree() async throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let files = NotebookTreeFixtureFiles(workspace: workspace)
        let source = notebookPythonTreeSource(files: files)
        let executor = NotebookExecutor()
        let document = NotebookDocument(cells: [.code(language: "python", source: source)])
        let task = Task.detached {
            try executor.execute(
                document,
                workingDirectory: workspace,
                timeoutSeconds: nil,
                sandbox: .none
            )
        }
        var identities: [NotebookTestProcessIdentity] = []
        defer {
            task.cancel()
            identities.forEach(notebookBestEffortTerminate)
        }

        do {
            try await notebookWaitForFile(files.ready, timeoutSeconds: 2)
        } catch {
            task.cancel()
            _ = try? await task.value
            throw error
        }
        do {
            identities = try [files.parentPID, files.childPID, files.grandchildPID]
                .map(notebookReadProcessIdentity)
        } catch {
            task.cancel()
            _ = try? await task.value
            throw error
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected notebook execution cancellation")
        } catch is CancellationError {
            // Expected after process-tree teardown.
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }

        for identity in identities {
            await notebookExpectProcessGone(identity)
        }
    }

    @Test("a timed-out execution cannot signal a concurrent notebook session")
    func concurrentExecutionsRemainIsolated() async throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let firstPID = workspace.appendingPathComponent("first.pid")
        let secondPID = workspace.appendingPathComponent("second.pid")
        let secondRelease = workspace.appendingPathComponent("second.release")
        let firstSource = notebookSignalResistantPythonChild(pidFile: firstPID)
        let secondSource = """
        import os, time
        with open(\(notebookPythonLiteral(secondPID.path)), "w") as handle:
            handle.write(str(os.getpid()))
            handle.flush()
        while not os.path.exists(\(notebookPythonLiteral(secondRelease.path))):
            time.sleep(0.005)
        print("second-ok")
        """
        let runner = NotebookProcessRunner()
        let firstTask = Task.detached {
            try runner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["python3", "-c", firstSource],
                workingDirectory: workspace,
                timeoutSeconds: 2
            )
        }
        let secondTask = Task.detached {
            try runner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["python3", "-c", secondSource],
                workingDirectory: workspace,
                timeoutSeconds: 10
            )
        }
        var identities: [NotebookTestProcessIdentity] = []
        defer {
            firstTask.cancel()
            secondTask.cancel()
            _ = FileManager.default.createFile(atPath: secondRelease.path, contents: Data())
            identities.forEach(notebookBestEffortTerminate)
        }

        do {
            try await notebookWaitForFile(firstPID, timeoutSeconds: 1)
            try await notebookWaitForFile(secondPID, timeoutSeconds: 1)
            identities = try [firstPID, secondPID].map(notebookReadProcessIdentity)
        } catch {
            firstTask.cancel()
            secondTask.cancel()
            _ = FileManager.default.createFile(atPath: secondRelease.path, contents: Data())
            _ = try? await firstTask.value
            _ = try? await secondTask.value
            throw error
        }
        #expect(identities[0].pid != identities[1].pid)
        #expect(getsid(identities[0].pid) == identities[0].pid)
        #expect(getsid(identities[1].pid) == identities[1].pid)

        let firstResult = try await firstTask.value

        #expect(firstResult.exitCode == 124)
        #expect(notebookCurrentProcessIdentity(identities[1].pid) == identities[1])
        _ = FileManager.default.createFile(atPath: secondRelease.path, contents: Data())
        let secondResult = try await secondTask.value
        #expect(secondResult.exitCode == 0)
        #expect(secondResult.stdout == "second-ok\n")
        for identity in identities {
            await notebookExpectProcessGone(identity)
        }
    }

    @Test("retains bounded stdout and stderr while continuing to drain both pipes")
    func boundsCapturedOutput() throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let emittedBytes = NotebookProcessRunner.maximumRetainedBytesPerStream + 128 * 1_024
        let source = """
        import sys
        sys.stdout.buffer.write(b"\\xff" * \(emittedBytes))
        sys.stderr.write("e" * \(emittedBytes))
        """

        let result = try NotebookProcessRunner().run(
            executableURL: URL(fileURLWithPath: "/usr/bin/env"),
            arguments: ["python3", "-c", source],
            workingDirectory: workspace,
            timeoutSeconds: 10
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout.utf8.count <= NotebookProcessRunner.maximumRetainedBytesPerStream)
        #expect(result.stderr.utf8.count <= NotebookProcessRunner.maximumRetainedBytesPerStream)
        #expect(result.stdout.contains("Output truncated at"))
        #expect(result.stderr.contains("Output truncated at"))
    }

    private func verifyNormalParentExitCleanup(language: String) async throws {
        let workspace = try notebookProcessTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let childPID = workspace.appendingPathComponent("child.pid")
        let ready = workspace.appendingPathComponent("parent.ready")
        let release = workspace.appendingPathComponent("parent.release")
        let childSource = notebookSignalResistantPythonChild(pidFile: childPID)
        let source = notebookParentSource(
            language: language,
            childSource: childSource,
            childPID: childPID,
            ready: ready,
            release: release
        )
        let executor = NotebookExecutor()
        let document = NotebookDocument(cells: [.code(language: language, source: source)])
        let task = Task.detached {
            try executor.execute(
                document,
                workingDirectory: workspace,
                timeoutSeconds: 30,
                sandbox: .none
            )
        }
        var identity: NotebookTestProcessIdentity?
        defer {
            task.cancel()
            _ = FileManager.default.createFile(atPath: release.path, contents: Data())
            if let identity { notebookBestEffortTerminate(identity) }
        }

        do {
            try await notebookWaitForFile(ready, timeoutSeconds: 15)
        } catch {
            task.cancel()
            _ = try? await task.value
            throw error
        }
        do {
            identity = try notebookReadProcessIdentity(childPID)
        } catch {
            task.cancel()
            _ = FileManager.default.createFile(atPath: release.path, contents: Data())
            _ = try? await task.value
            throw error
        }
        _ = FileManager.default.createFile(atPath: release.path, contents: Data())

        let summary = try await task.value

        #expect(summary.failedCellIndex == nil)
        #expect(summary.results.count == 1)
        #expect(summary.results[0].exitCode == 0)
        #expect(summary.results[0].stdout == "\(language)-parent-exited\n")
        if let identity {
            await notebookExpectProcessGone(identity)
        }
    }
}

private struct NotebookTreeFixtureFiles {
    let parentPID: URL
    let childPID: URL
    let grandchildPID: URL
    let ready: URL

    init(workspace: URL) {
        parentPID = workspace.appendingPathComponent("parent.pid")
        childPID = workspace.appendingPathComponent("child.pid")
        grandchildPID = workspace.appendingPathComponent("grandchild.pid")
        ready = workspace.appendingPathComponent("tree.ready")
    }
}

private struct NotebookTestProcessIdentity: Equatable {
    let pid: pid_t
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}

private enum NotebookProcessTestError: Error {
    case timedOut(String)
    case invalidProcessID(String)
    case processNotRunning(pid_t)
}

private func notebookSignalResistantPythonChild(pidFile: URL) -> String {
    """
    import os, signal, time
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    with open(\(notebookPythonLiteral(pidFile.path)), "w") as handle:
        handle.write(str(os.getpid()))
        handle.flush()
    while True:
        time.sleep(60)
    """
}

private func notebookParentSource(
    language: String,
    childSource: String,
    childPID: URL,
    ready: URL,
    release: URL
) -> String {
    switch language {
    case "bash":
        return """
        /usr/bin/python3 -c \(notebookShellQuoted(childSource)) &
        while [ ! -s \(notebookShellQuoted(childPID.path)) ]; do :; done
        : > \(notebookShellQuoted(ready.path))
        while [ ! -e \(notebookShellQuoted(release.path)) ]; do :; done
        printf 'bash-parent-exited\\n'
        """
    case "python":
        return """
        import os, subprocess, sys, time
        subprocess.Popen(
            [sys.executable, "-c", \(notebookPythonLiteral(childSource))],
            stdin=subprocess.DEVNULL
        )
        while not (
            os.path.exists(\(notebookPythonLiteral(childPID.path)))
            and os.path.getsize(\(notebookPythonLiteral(childPID.path))) > 0
        ):
            time.sleep(0.005)
        open(\(notebookPythonLiteral(ready.path)), "w").close()
        while not os.path.exists(\(notebookPythonLiteral(release.path))):
            time.sleep(0.005)
        print("python-parent-exited")
        """
    case "swift":
        return """
        import Foundation
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        child.arguments = ["-c", \(String(reflecting: childSource))]
        child.standardInput = FileHandle.nullDevice
        child.standardOutput = FileHandle.standardOutput
        child.standardError = FileHandle.standardError
        try child.run()
        while !FileManager.default.fileExists(atPath: \(String(reflecting: childPID.path))) {
            usleep(5_000)
        }
        FileManager.default.createFile(atPath: \(String(reflecting: ready.path)), contents: Data())
        while !FileManager.default.fileExists(atPath: \(String(reflecting: release.path))) {
            usleep(5_000)
        }
        print("swift-parent-exited")
        """
    default:
        return ""
    }
}

private func notebookPythonTreeSource(files: NotebookTreeFixtureFiles) -> String {
    let grandchildSource = """
    import os, signal, time
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    with open(\(notebookPythonLiteral(files.grandchildPID.path)), "w") as handle:
        handle.write(str(os.getpid()))
        handle.flush()
    while True:
        time.sleep(60)
    """
    let childSource = """
    import os, signal, subprocess, sys, time
    os.setsid()
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    with open(\(notebookPythonLiteral(files.childPID.path)), "w") as handle:
        handle.write(str(os.getpid()))
        handle.flush()
    subprocess.Popen([sys.executable, "-c", \(notebookPythonLiteral(grandchildSource))])
    while not (
        os.path.exists(\(notebookPythonLiteral(files.grandchildPID.path)))
        and os.path.getsize(\(notebookPythonLiteral(files.grandchildPID.path))) > 0
    ):
        time.sleep(0.005)
    open(\(notebookPythonLiteral(files.ready.path)), "w").close()
    while True:
        time.sleep(60)
    """
    return """
    import os, signal, subprocess, sys, time
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    with open(\(notebookPythonLiteral(files.parentPID.path)), "w") as handle:
        handle.write(str(os.getpid()))
        handle.flush()
    subprocess.Popen([sys.executable, "-c", \(notebookPythonLiteral(childSource))])
    while True:
        time.sleep(60)
    """
}

private func notebookPythonLiteral(_ value: String) -> String {
    let data = try! JSONSerialization.data(
        withJSONObject: value,
        options: [.fragmentsAllowed, .withoutEscapingSlashes]
    )
    return String(decoding: data, as: UTF8.self)
}

private func notebookShellQuoted(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

private func notebookProcessTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("cocxy-notebook-process-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func notebookWaitForFile(_ url: URL, timeoutSeconds: TimeInterval) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds
        + UInt64(timeoutSeconds * 1_000_000_000)
    while !FileManager.default.fileExists(atPath: url.path) {
        guard DispatchTime.now().uptimeNanoseconds < deadline else {
            throw NotebookProcessTestError.timedOut(url.path)
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

private func notebookReadProcessIdentity(_ url: URL) throws -> NotebookTestProcessIdentity {
    let contents = try String(contentsOf: url, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let pid = pid_t(contents), pid > 0 else {
        throw NotebookProcessTestError.invalidProcessID(contents)
    }
    guard let identity = notebookCurrentProcessIdentity(pid) else {
        throw NotebookProcessTestError.processNotRunning(pid)
    }
    return identity
}

private func notebookCurrentProcessIdentity(_ pid: pid_t) -> NotebookTestProcessIdentity? {
    var info = proc_bsdinfo()
    let expectedSize = Int32(MemoryLayout.size(ofValue: info))
    let result = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, expectedSize)
    guard result == expectedSize else { return nil }
    return NotebookTestProcessIdentity(
        pid: pid,
        startSeconds: UInt64(info.pbi_start_tvsec),
        startMicroseconds: UInt64(info.pbi_start_tvusec)
    )
}

private func notebookExpectProcessGone(_ identity: NotebookTestProcessIdentity) async {
    let deadline = DispatchTime.now().uptimeNanoseconds + 2_000_000_000
    while notebookCurrentProcessIdentity(identity.pid) == identity {
        if DispatchTime.now().uptimeNanoseconds >= deadline {
            Issue.record("Notebook descendant \(identity.pid) remained alive after teardown")
            return
        }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
}

private func notebookBestEffortTerminate(_ identity: NotebookTestProcessIdentity) {
    guard notebookCurrentProcessIdentity(identity.pid) == identity else { return }
    _ = kill(identity.pid, SIGKILL)
}
