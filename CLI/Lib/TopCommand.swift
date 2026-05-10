// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation

#if canImport(Darwin)
import Darwin
#endif

public enum CLITopMode: Equatable {
    case interactive(intervalSeconds: TimeInterval)
    case once
    case json
}

struct CLITopProcessMetrics: Codable, Equatable {
    let cpuPercent: String
    let memoryRSS: String
}

struct CLITopTab: Codable, Equatable {
    let index: Int
    let id: String
    let title: String
    let active: Bool
    let pid: String
    let cpu: String
    let memory: String
    let agentState: String
}

struct CLITopSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: String
    let status: String
    let version: String
    let tabCount: Int
    let activeTabID: String?
    let activeAgentState: String
    let tabs: [CLITopTab]

    static func make(
        statusData: [String: String],
        tabData: [String: String],
        generatedAt: Date = Date(),
        activeMetrics: CLITopProcessMetrics? = nil
    ) -> CLITopSnapshot {
        let count = Int(tabData["count"] ?? "") ?? 0
        let activePID = statusData["child_pid"] ?? "n/a"
        let activeAgentState = Self.agentState(from: statusData)
        let activeTabID = (0..<count).compactMap { index -> String? in
            guard tabData["tab_\(index)_active"] == "true" else { return nil }
            return tabData["tab_\(index)_id"]
        }.first

        let tabs = (0..<count).map { index in
            let id = tabData["tab_\(index)_id"] ?? ""
            let title = tabData["tab_\(index)_title"] ?? "Untitled"
            let active = tabData["tab_\(index)_active"] == "true"
            return CLITopTab(
                index: index + 1,
                id: id,
                title: title,
                active: active,
                pid: active ? activePID : "n/a",
                cpu: active ? activeMetrics?.cpuPercent ?? "n/a" : "n/a",
                memory: active ? activeMetrics?.memoryRSS ?? "n/a" : "n/a",
                agentState: active ? activeAgentState : "unknown"
            )
        }

        return CLITopSnapshot(
            schemaVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: generatedAt),
            status: statusData["status"] ?? "unknown",
            version: statusData["version"] ?? "unknown",
            tabCount: Int(statusData["tabs"] ?? "") ?? count,
            activeTabID: activeTabID,
            activeAgentState: activeAgentState,
            tabs: tabs
        )
    }

    private static func agentState(from statusData: [String: String]) -> String {
        if let state = statusData["semantic_state_name"], !state.isEmpty {
            return state
        }
        if statusData["semantic_agent_blocks"].flatMap(Int.init) ?? 0 > 0 {
            return "agent"
        }
        if statusData["process_alive"] == "true" {
            return "running"
        }
        return "unknown"
    }
}

enum CLITopRenderer {
    static func render(_ snapshot: CLITopSnapshot, selectedIndex: Int = 0) -> String {
        var lines: [String] = []
        lines.append("Cocxy top - \(snapshot.status)  version \(snapshot.version)  tabs \(snapshot.tabCount)")
        lines.append("Updated \(snapshot.generatedAt)")
        lines.append("")
        lines.append([
            pad("#", 3),
            pad("A", 1),
            pad("PID", 7),
            pad("CPU%", 7),
            pad("MEM", 9),
            pad("AGENT", 14),
            "TITLE"
        ].joined(separator: " "))

        if snapshot.tabs.isEmpty {
            lines.append("No open tabs.")
        } else {
            for (offset, tab) in snapshot.tabs.enumerated() {
                let selector = offset == selectedIndex ? ">" : " "
                let title = tab.title.replacingOccurrences(of: "\n", with: " ")
                lines.append([
                    selector + pad("\(tab.index)", 2),
                    pad(tab.active ? "*" : " ", 1),
                    pad(tab.pid, 7),
                    pad(tab.cpu, 7),
                    pad(tab.memory, 9),
                    pad(tab.agentState, 14),
                    title
                ].joined(separator: " "))
            }
        }

        lines.append("")
        lines.append("q quit | up/down select | Enter focus tab | k close tab")
        return lines.joined(separator: "\n")
    }

    static func renderJSON(_ snapshot: CLITopSnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(snapshot), as: UTF8.self)
    }

    private static func pad(_ value: String, _ width: Int) -> String {
        if value.count >= width { return value }
        return value + String(repeating: " ", count: width - value.count)
    }
}

struct CLITopProcessMetricsSampler {
    func sample(pid: String?) -> CLITopProcessMetrics? {
        guard let pid, Int(pid) != nil else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "%cpu=", "-o", "rss=", "-p", pid]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let fields = String(decoding: data, as: UTF8.self)
                .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            guard fields.count >= 2 else { return nil }
            let rssKiB = Int(fields[1]) ?? 0
            return CLITopProcessMetrics(
                cpuPercent: String(fields[0]),
                memoryRSS: Self.formatRSS(kibibytes: rssKiB)
            )
        } catch {
            return nil
        }
    }

    private static func formatRSS(kibibytes: Int) -> String {
        if kibibytes <= 0 { return "n/a" }
        let mib = Double(kibibytes) / 1024.0
        if mib >= 1024 {
            return String(format: "%.1fG", mib / 1024.0)
        }
        return String(format: "%.1fM", mib)
    }
}

struct CLITopCommand {
    let socketClient: SocketClient
    let metricsSampler: CLITopProcessMetricsSampler

    init(
        socketClient: SocketClient,
        metricsSampler: CLITopProcessMetricsSampler = CLITopProcessMetricsSampler()
    ) {
        self.socketClient = socketClient
        self.metricsSampler = metricsSampler
    }

    func run(mode: CLITopMode) -> CLIResult {
        switch mode {
        case .json:
            return snapshotResult(json: true)
        case .once:
            return snapshotResult(json: false)
        case .interactive(let intervalSeconds):
            if CLITopTerminal.isInteractive {
                return CLITopInteractiveSession(command: self, intervalSeconds: intervalSeconds).run()
            }
            return snapshotResult(json: false)
        }
    }

    func snapshot() throws -> CLITopSnapshot {
        let statusResponse = try socketClient.send(
            CLISocketRequest(id: UUID().uuidString, command: "status", params: nil)
        )
        guard statusResponse.success, let statusData = statusResponse.data else {
            throw CLIError.serverError(statusResponse.error ?? "Unable to read status")
        }

        let listTabsResponse = try socketClient.send(
            CLISocketRequest(id: UUID().uuidString, command: "list-tabs", params: nil)
        )
        guard listTabsResponse.success, let tabData = listTabsResponse.data else {
            throw CLIError.serverError(listTabsResponse.error ?? "Unable to list tabs")
        }

        return CLITopSnapshot.make(
            statusData: statusData,
            tabData: tabData,
            activeMetrics: metricsSampler.sample(pid: statusData["child_pid"])
        )
    }

    func focus(tabID: String) throws {
        let response = try socketClient.send(
            CLISocketRequest(id: UUID().uuidString, command: "focus-tab", params: ["id": tabID])
        )
        guard response.success else {
            throw CLIError.serverError(response.error ?? "Unable to focus tab")
        }
    }

    func close(tabID: String) throws {
        let response = try socketClient.send(
            CLISocketRequest(id: UUID().uuidString, command: "close-tab", params: ["id": tabID])
        )
        guard response.success else {
            throw CLIError.serverError(response.error ?? "Unable to close tab")
        }
    }

    private func snapshotResult(json: Bool) -> CLIResult {
        do {
            let snapshot = try snapshot()
            let output = json ? try CLITopRenderer.renderJSON(snapshot) : CLITopRenderer.render(snapshot)
            return CLIResult(exitCode: 0, stdout: output, stderr: "")
        } catch let error as CLIError {
            return CLIResult(exitCode: 1, stdout: "", stderr: OutputFormatter.formatError(error))
        } catch {
            return CLIResult(exitCode: 1, stdout: "", stderr: "Error: \(error.localizedDescription)")
        }
    }
}

enum CLITopTerminal {
    static var isInteractive: Bool {
        #if canImport(Darwin)
        return isatty(STDIN_FILENO) == 1 && isatty(STDOUT_FILENO) == 1
        #else
        return false
        #endif
    }
}

struct CLITopInteractiveSession {
    let command: CLITopCommand
    let intervalSeconds: TimeInterval

    func run() -> CLIResult {
        #if canImport(Darwin)
        var original = termios()
        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            return command.run(mode: .once)
        }

        var raw = original
        raw.c_lflag &= ~(UInt(ECHO) | UInt(ICANON))
        withUnsafeMutableBytes(of: &raw.c_cc) { buffer in
            buffer[Int(VMIN)] = 0
            buffer[Int(VTIME)] = 0
        }

        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else {
            return command.run(mode: .once)
        }
        let flags = fcntl(STDIN_FILENO, F_GETFL, 0)
        _ = fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK)
        defer {
            _ = tcsetattr(STDIN_FILENO, TCSANOW, &original)
            _ = fcntl(STDIN_FILENO, F_SETFL, flags)
            writeStdout("\u{001B}[?25h")
        }

        var selectedIndex = 0
        var lastError: String?
        writeStdout("\u{001B}[?25l")

        while true {
            do {
                let snapshot = try command.snapshot()
                if !snapshot.tabs.isEmpty {
                    selectedIndex = min(max(selectedIndex, 0), snapshot.tabs.count - 1)
                } else {
                    selectedIndex = 0
                }

                var output = "\u{001B}[2J\u{001B}[H" + CLITopRenderer.render(snapshot, selectedIndex: selectedIndex)
                if let lastError {
                    output += "\n\n\(lastError)"
                }
                writeStdout(output)

                let deadline = Date().addingTimeInterval(intervalSeconds)
                while Date() < deadline {
                    if let action = readAction() {
                        switch action {
                        case .quit:
                            return CLIResult(exitCode: 0, stdout: "", stderr: "")
                        case .up:
                            selectedIndex = max(0, selectedIndex - 1)
                        case .down:
                            selectedIndex += 1
                        case .focus:
                            if let id = snapshot.tabs[safe: selectedIndex]?.id {
                                try command.focus(tabID: id)
                            }
                        case .close:
                            if let id = snapshot.tabs[safe: selectedIndex]?.id {
                                try command.close(tabID: id)
                                selectedIndex = max(0, selectedIndex - 1)
                            }
                        }
                        lastError = nil
                        break
                    }
                    usleep(50_000)
                }
            } catch let error as CLIError {
                lastError = OutputFormatter.formatError(error)
                usleep(250_000)
            } catch {
                lastError = "Error: \(error.localizedDescription)"
                usleep(250_000)
            }
        }
        #else
        return command.run(mode: .once)
        #endif
    }

    #if canImport(Darwin)
    private enum Action {
        case quit
        case up
        case down
        case focus
        case close
    }

    private func readAction() -> Action? {
        var buffer = [UInt8](repeating: 0, count: 8)
        let bufferCount = buffer.count
        let count = buffer.withUnsafeMutableBytes {
            read(STDIN_FILENO, $0.baseAddress, bufferCount)
        }
        guard count > 0 else { return nil }
        let bytes = Array(buffer.prefix(count))

        if bytes == [UInt8(ascii: "q")] { return .quit }
        if bytes == [UInt8(ascii: "k")] { return .close }
        if bytes == [13] || bytes == [10] { return .focus }
        if bytes == [UInt8(ascii: "j")] { return .down }
        if bytes == [27, 91, 65] { return .up }
        if bytes == [27, 91, 66] { return .down }
        return nil
    }

    private func writeStdout(_ text: String) {
        FileHandle.standardOutput.write(Data(text.utf8))
    }
    #endif
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
