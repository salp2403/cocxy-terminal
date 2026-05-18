// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentTeamGraphPerformanceBenchmarks.swift - Opt-in Team Graph visual update smoke.

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import CocxyTerminal

private enum AgentTeamGraphBenchmarkConfiguration {
    static let isEnabled =
        ProcessInfo.processInfo.environment["COCXY_RUN_AGENT_TEAMS_GRAPH_BENCHMARKS"] == "1"
    static let artifactRoot =
        ProcessInfo.processInfo.environment["COCXY_AGENT_TEAMS_GRAPH_PERF_ARTIFACT_ROOT"]
    static let frameBudgetMs = 16.0
    static let measuredUpdateCount = 48
    static let warmupUpdateCount = 8
}

@Suite(
    "Agent Teams graph performance benchmarks",
    .serialized,
    .enabled(
        if: AgentTeamGraphBenchmarkConfiguration.isEnabled,
        Comment("Set COCXY_RUN_AGENT_TEAMS_GRAPH_BENCHMARKS=1 to run the Team Graph visual benchmark.")
    )
)
@MainActor
struct AgentTeamGraphPerformanceBenchmarks {

    @Test("12-node TeamGraphView visual updates stay below the 16ms frame budget")
    func twelveNodeTeamGraphViewVisualUpdatesStayBelowFrameBudget() throws {
        var graph = try makeTwelveNodeGraph()
        let localizer = AppLocalizer(languagePreference: .english)
        let hostingView = NSHostingView(rootView: TeamGraphView(graph: graph, localizer: localizer))
        hostingView.frame = NSRect(x: 0, y: 0, width: 520, height: 420)
        let container = NSView(frame: hostingView.frame)
        container.addSubview(hostingView)

        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        var measuredFrameTimes: [Double] = []
        let totalUpdates = AgentTeamGraphBenchmarkConfiguration.warmupUpdateCount
            + AgentTeamGraphBenchmarkConfiguration.measuredUpdateCount

        for updateIndex in 0..<totalUpdates {
            try applyVisualUpdate(index: updateIndex, to: &graph)

            let startedAt = DispatchTime.now().uptimeNanoseconds
            hostingView.rootView = TeamGraphView(graph: graph, localizer: localizer)
            hostingView.needsLayout = true
            hostingView.needsDisplay = true
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
            let elapsedMs = millisecondsSince(startedAt)

            if updateIndex >= AgentTeamGraphBenchmarkConfiguration.warmupUpdateCount {
                measuredFrameTimes.append(elapsedMs)
            }
        }

        let maxFrameMs = measuredFrameTimes.max() ?? .infinity
        let averageFrameMs = average(measuredFrameTimes)
        let p95FrameMs = percentile(measuredFrameTimes, percentile: 0.95)
        let passed = measuredFrameTimes.count == AgentTeamGraphBenchmarkConfiguration.measuredUpdateCount
            && maxFrameMs < AgentTeamGraphBenchmarkConfiguration.frameBudgetMs

        try writeSummary(
            passed: passed,
            updateCount: measuredFrameTimes.count,
            maxFrameMs: maxFrameMs,
            averageFrameMs: averageFrameMs,
            p95FrameMs: p95FrameMs
        )

        print("Agent Teams graph 12-node max update render time: \(formatMilliseconds(maxFrameMs))")
        print("Agent Teams graph 12-node p95 update render time: \(formatMilliseconds(p95FrameMs))")
        print("Agent Teams graph 12-node average update render time: \(formatMilliseconds(averageFrameMs))")

        #expect(
            measuredFrameTimes.count == AgentTeamGraphBenchmarkConfiguration.measuredUpdateCount,
            Comment("Measured \(measuredFrameTimes.count) Team Graph updates.")
        )
        #expect(
            maxFrameMs < AgentTeamGraphBenchmarkConfiguration.frameBudgetMs,
            Comment("Measured max Team Graph update render time: \(formatMilliseconds(maxFrameMs))")
        )
    }

    private func makeTwelveNodeGraph() throws -> AgentTeamGraph {
        let config = try AgentTeamConfig.from(
            teammates: [
                "Plan",
                "Build",
                "Review",
                "Test",
                "Docs",
                "Security",
                "Release",
                "Browser",
                "Cells",
                "Remote",
                "Polish",
            ].joined(separator: ", "),
            teamID: "perf-team",
            provider: .codex
        )
        var graph = AgentTeamGraph(config: config, now: Date(timeIntervalSince1970: 1_000))
        for (index, node) in graph.nodes.enumerated() {
            try graph.updateStatus(
                nodeID: node.id,
                status: [.starting, .working, .waiting, .finished][index % 4],
                now: Date(timeIntervalSince1970: TimeInterval(1_000 + index))
            )
            if index % 2 == 0 {
                try graph.setPermissions(
                    nodeID: node.id,
                    permissions: [.fileRead, .fileWrite, .exec],
                    now: Date(timeIntervalSince1970: TimeInterval(1_100 + index))
                )
            }
            if index % 3 == 0 {
                try graph.recordTouchedFile(
                    nodeID: node.id,
                    path: "/tmp/cocxy/team-graph/\(node.id)/file-\(index).swift",
                    now: Date(timeIntervalSince1970: TimeInterval(1_200 + index))
                )
            }
        }
        return graph
    }

    private func applyVisualUpdate(index: Int, to graph: inout AgentTeamGraph) throws {
        let nodeIDs = graph.nodes.map(\.id)
        let nodeID = nodeIDs[index % nodeIDs.count]
        let statuses: [AgentTeamStatus] = [.starting, .working, .waiting, .finished, .error]
        try graph.updateStatus(
            nodeID: nodeID,
            status: statuses[index % statuses.count],
            now: Date(timeIntervalSince1970: TimeInterval(2_000 + index))
        )

        if index % 2 == 0 {
            try graph.setPermissions(
                nodeID: nodeID,
                permissions: [.fileRead, .fileWrite, .network, .exec],
                now: Date(timeIntervalSince1970: TimeInterval(2_100 + index))
            )
        }

        if index % 3 == 0 {
            try graph.recordTouchedFile(
                nodeID: nodeID,
                path: "/tmp/cocxy/team-graph/\(nodeID)/update-\(index).swift",
                now: Date(timeIntervalSince1970: TimeInterval(2_200 + index))
            )
        }
    }

    private func writeSummary(
        passed: Bool,
        updateCount: Int,
        maxFrameMs: Double,
        averageFrameMs: Double,
        p95FrameMs: Double
    ) throws {
        guard let artifactRoot = AgentTeamGraphBenchmarkConfiguration.artifactRoot else {
            return
        }

        let artifactURL = URL(fileURLWithPath: artifactRoot, isDirectory: true)
        try FileManager.default.createDirectory(at: artifactURL, withIntermediateDirectories: true)
        let summaryURL = artifactURL.appendingPathComponent("summary.txt")
        let status = passed ? "ok" : "failed"
        let maxFrameStatus = maxFrameMs < AgentTeamGraphBenchmarkConfiguration.frameBudgetMs ? "ok" : "fail"
        let updatesStatus = updateCount == AgentTeamGraphBenchmarkConfiguration.measuredUpdateCount ? "ok" : "fail"
        let summary = """
        status=\(status)
        result=agent-teams-graph-performance-\(status)
        nodeCount=12
        frameBudgetMs=16
        maxFrameMs=\(maxFrameStatus)
        updates=\(updatesStatus)
        updateCount=\(updateCount)
        warmupCount=\(AgentTeamGraphBenchmarkConfiguration.warmupUpdateCount)
        maxFrameMsValue=\(formatDecimal(maxFrameMs))
        p95FrameMsValue=\(formatDecimal(p95FrameMs))
        averageFrameMsValue=\(formatDecimal(averageFrameMs))
        renderSurface=NSHostingView<TeamGraphView>
        """
        try summary.write(to: summaryURL, atomically: true, encoding: .utf8)
    }
}

private func millisecondsSince(_ startedAt: UInt64) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000.0
}

private func average(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return .infinity }
    return values.reduce(0, +) / Double(values.count)
}

private func percentile(_ values: [Double], percentile: Double) -> Double {
    guard !values.isEmpty else { return .infinity }
    let sorted = values.sorted()
    let index = min(
        sorted.count - 1,
        max(0, Int((Double(sorted.count - 1) * percentile).rounded(.up)))
    )
    return sorted[index]
}

private func formatMilliseconds(_ value: Double) -> String {
    "\(formatDecimal(value))ms"
}

private func formatDecimal(_ value: Double) -> String {
    String(format: "%.3f", value)
}
