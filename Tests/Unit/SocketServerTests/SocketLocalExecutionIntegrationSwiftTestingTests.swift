// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SocketLocalExecutionIntegrationSwiftTestingTests.swift - Real notebook and workflow runs over the socket.

import Foundation
import Testing
@testable import CocxyTerminal

/// Drives `notebook-run` and `workflow-run` through real launchd-contained,
/// sandboxed bash, python and swift processes.
///
/// Every run pays for broker startup, sandbox setup and interpreter launch
/// under fixed budgets, so the outcome depends on machine load as much as on
/// the code under test. The canonical serial gate skips this suite and the
/// Bounded Process Containment CI lane runs it on every supported macOS image.
@Suite("Socket local execution integration", .serialized)
struct SocketLocalExecutionIntegrationSwiftTestingTests {

    @Test("notebook-run executes a local bash cell and writes its outputs")
    func notebookRunExecutesLocalBashCellAndWritesOutputs() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("source.cocxynb")
        let outputURL = directory.appendingPathComponent("result.cocxynb")

        try """
        ---
        cocxy-notebook: "1"
        title: "Executable"
        ---

        ```bash
        echo notebook-ok
        ```
        """.write(to: inputURL, atomically: true, encoding: .utf8)

        let response = makeHandler().handleCommand(SocketRequest(
            id: "notebook-run-1",
            command: "notebook-run",
            params: [
                "input": inputURL.path,
                "output": outputURL.path,
                "cwd": directory.path,
                "timeout": "15",
                "continue-on-failure": "false",
            ]
        ))

        #expect(response.success)
        #expect(response.data?["status"] == "completed")
        #expect(response.data?["executed-cells"] == "1")
        #expect(response.data?["input"] == inputURL.standardizedFileURL.path)
        #expect(response.data?["output"] == outputURL.standardizedFileURL.path)
        let rendered = try String(contentsOf: outputURL, encoding: .utf8)
        #expect(rendered.contains("```cocxy-output stdout\nnotebook-ok\n```"))
    }

    @Test(
        "notebook-run workspace sandbox blocks writes outside the working directory",
        .enabled(if: executableIsOnPath("sandbox-exec"), "sandbox-exec is not on PATH")
    )
    func notebookRunWorkspaceSandboxBlocksWritesOutsideWorkingDirectory() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let inputURL = workspace.appendingPathComponent("sandbox.cocxynb")
        let outputURL = workspace.appendingPathComponent("sandbox-result.cocxynb")
        let outsideURL = root.appendingPathComponent("outside.txt")

        try """
        ---
        cocxy-notebook: "1"
        title: "Sandbox"
        ---

        ```bash
        echo allowed > allowed.txt
        echo denied > ../outside.txt
        ```
        """.write(to: inputURL, atomically: true, encoding: .utf8)

        let response = makeHandler().handleCommand(SocketRequest(
            id: "notebook-run-sandbox",
            command: "notebook-run",
            params: [
                "input": inputURL.path,
                "output": outputURL.path,
                "cwd": workspace.path,
                "timeout": "15",
                "sandbox": "workspace",
            ]
        ))

        #expect(response.success, "\(response.error ?? "")")
        #expect(response.data?["status"] == "failed")
        #expect(response.data?["failed-cell-index"] == "0")
        #expect(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("allowed.txt").path))
        #expect(!FileManager.default.fileExists(atPath: outsideURL.path))
        let rendered = try String(contentsOf: outputURL, encoding: .utf8)
        #expect(rendered.contains("Operation not permitted"))
    }

    @Test(
        "notebook-run executes bash, python and swift cells, then exports Jupyter",
        .enabled(if: executableIsOnPath("python3"), "python3 is not on PATH"),
        .enabled(if: executableIsOnPath("swift"), "swift is not on PATH")
    )
    func notebookRunExecutesBashPythonAndSwiftCellsThenExportsJupyter() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("multi-language.cocxynb")
        let outputURL = directory.appendingPathComponent("multi-language-result.cocxynb")
        let jupyterURL = directory.appendingPathComponent("multi-language-result.ipynb")

        try """
        ---
        cocxy-notebook: "1"
        title: "Multi Language"
        ---

        # Smoke

        ```bash
        printf 'bash-ok\\n'
        ```

        ```python
        print("python-ok")
        ```

        ```swift
        print("swift-ok")
        ```
        """.write(to: inputURL, atomically: true, encoding: .utf8)

        let handler = makeHandler()
        let runResponse = handler.handleCommand(SocketRequest(
            id: "notebook-run-multi-language",
            command: "notebook-run",
            params: [
                "input": inputURL.path,
                "output": outputURL.path,
                "cwd": directory.path,
                "timeout": "45",
                "continue-on-failure": "false",
            ]
        ))

        #expect(runResponse.success, "\(runResponse.error ?? "")")
        #expect(runResponse.data?["status"] == "completed")
        #expect(runResponse.data?["executed-cells"] == "3")
        let rendered = try String(contentsOf: outputURL, encoding: .utf8)
        #expect(rendered.contains("```cocxy-output stdout\nbash-ok\n```"))
        #expect(rendered.contains("```cocxy-output stdout\npython-ok\n```"))
        #expect(rendered.contains("```cocxy-output stdout\nswift-ok\n```"))

        let exportResponse = handler.handleCommand(SocketRequest(
            id: "notebook-export-multi-language",
            command: "notebook-export",
            params: [
                "input": outputURL.path,
                "output": jupyterURL.path,
                "force": "false",
            ]
        ))

        #expect(exportResponse.success, "\(exportResponse.error ?? "")")
        let data = try Data(contentsOf: jupyterURL)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cells = try #require(json["cells"] as? [[String: Any]])
        #expect(cells.map { $0["cell_type"] as? String } == ["markdown", "code", "code", "code"])
        let codeOutputs = cells.dropFirst().compactMap { $0["outputs"] as? [[String: Any]] }
        try #require(codeOutputs.count == 3)
        #expect(codeOutputs[0].contains { (($0["text"] as? [String])?.joined() ?? "") == "bash-ok\n" })
        #expect(codeOutputs[1].contains { (($0["text"] as? [String])?.joined() ?? "") == "python-ok\n" })
        #expect(codeOutputs[2].contains { (($0["text"] as? [String])?.joined() ?? "") == "swift-ok\n" })
    }

    @Test("workflow-run executes a local workflow TOML")
    func workflowRunExecutesLocalWorkflowToml() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("workflow.toml")

        try """
        [workflow]
        id = "ci"
        steps = ["verify"]

        [step.verify]
        command = "echo workflow-ok"
        """.write(to: inputURL, atomically: true, encoding: .utf8)

        let response = makeHandler().handleCommand(SocketRequest(
            id: "workflow-run-1",
            command: "workflow-run",
            params: [
                "input": inputURL.path,
                "cwd": directory.path,
            ]
        ))

        #expect(response.success)
        #expect(response.data?["status"] == "completed")
        #expect(response.data?["workflow"] == "ci")
        #expect(response.data?["steps"] == "1")
        #expect(response.data?["stdout"] == "workflow-ok\n")
    }

    @Test("workflow-run executes five local steps in order")
    func workflowRunExecutesFiveLocalStepsInOrder() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("workflow.toml")
        let traceURL = directory.appendingPathComponent("workflow-order.txt")

        try """
        [workflow]
        id = "five-step"
        steps = ["prepare", "build", "test", "package", "report"]

        [step.prepare]
        command = "printf 'prepare\\n' >> workflow-order.txt && printf 'prepare\\n'"

        [step.build]
        command = "printf 'build\\n' >> workflow-order.txt && printf 'build\\n'"

        [step.test]
        command = "printf 'test\\n' >> workflow-order.txt && printf 'test\\n'"

        [step.package]
        command = "printf 'package\\n' >> workflow-order.txt && printf 'package\\n'"

        [step.report]
        command = "printf 'report\\n' >> workflow-order.txt && printf 'report\\n'"
        """.write(to: inputURL, atomically: true, encoding: .utf8)

        let response = makeHandler().handleCommand(SocketRequest(
            id: "workflow-run-five-step",
            command: "workflow-run",
            params: [
                "input": inputURL.path,
                "cwd": directory.path,
            ]
        ))

        #expect(response.success, "\(response.error ?? "")")
        #expect(response.data?["status"] == "completed")
        #expect(response.data?["workflow"] == "five-step")
        #expect(response.data?["steps"] == "5")
        #expect(response.data?["stdout"] == "prepare\nbuild\ntest\npackage\nreport\n")
        #expect(
            try String(contentsOf: traceURL, encoding: .utf8)
                == "prepare\nbuild\ntest\npackage\nreport\n"
        )
    }

    private func makeHandler() -> AppSocketCommandHandler {
        AppSocketCommandHandler(
            privilegedCommandAuthorizationProvider: { request in .internalTrusted(for: request) },
            tabManager: nil,
            hookEventReceiver: nil
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-notebook-tests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }
}

private func executableIsOnPath(_ executable: String) -> Bool {
    let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
    return path.split(separator: ":").contains { directory in
        FileManager.default.isExecutableFile(
            atPath: URL(fileURLWithPath: String(directory)).appendingPathComponent(executable).path
        )
    }
}
