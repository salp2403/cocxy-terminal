// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@MainActor
@Suite("Timeline hook wiring")
struct TimelineHookWiringSwiftTestingTests {
    @Test("FileChanged floods cannot evict user prompts from the timeline")
    func fileChangedFloodIsExcluded() async throws {
        let delegate = AppDelegate()
        let receiver = HookEventReceiverImpl()
        let engine = AgentDetectionEngineImpl(compiledConfigs: [], debounceInterval: 0)
        delegate.hookEventReceiver = receiver
        delegate.wireAgentDashboardAndTimeline(engine)

        for index in 0..<1_100 {
            receiver.receive(HookEvent(
                type: .fileChanged,
                sessionId: "timeline-live-edit",
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                data: .fileChanged(FileChangedData(
                    filePath: "/tmp/project/file-\(index).swift",
                    changeType: "change"
                ))
            ))
        }
        receiver.receive(HookEvent(
            type: .userPromptSubmit,
            sessionId: "timeline-live-edit",
            timestamp: Date(timeIntervalSince1970: 2_000)
        ))

        for _ in 0..<1_500 where delegate.agentTimelineStore?.events(for: "timeline-live-edit").isEmpty ?? true { try await Task.sleep(for: .milliseconds(10)) }
        try await Task.sleep(for: .milliseconds(100))

        let events = delegate.agentTimelineStore?.events(for: "timeline-live-edit")
        #expect(events?.count == 1)
        #expect(events?.first?.type == .userPrompt)
    }

    @Test("Hook timeline events resolve nested directories to the canonical project")
    func hookTimelineEventsCarryCanonicalProjectIdentity() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-timeline-project-\(UUID().uuidString)", isDirectory: true)
        let nested = root.appendingPathComponent("Sources", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let delegate = AppDelegate()
        let controller = MainWindowController(bridge: MockTerminalEngine())
        let tabID = controller.createTab(workingDirectory: nested)
        delegate.installWindowControllerForTesting(controller)
        let receiver = HookEventReceiverImpl()
        delegate.hookEventReceiver = receiver
        delegate.wireAgentDashboardAndTimeline(
            AgentDetectionEngineImpl(compiledConfigs: [], debounceInterval: 0)
        )

        receiver.receive(HookEvent(
            type: .userPromptSubmit,
            sessionId: "timeline-project",
            timestamp: Date(),
            cwd: nested.path
        ))
        for _ in 0..<1_500 where delegate.agentTimelineStore?.events(for: "timeline-project").first == nil { try await Task.sleep(for: .milliseconds(10)) }

        let event = delegate.agentTimelineStore?.events(for: "timeline-project").first
        #expect(event?.projectIdentity == ProjectID(rootURL: root))
        delegate.bindHookSession("timeline-project", to: tabID)
        #expect(
            delegate.timelineProjectIdentity(forSessionID: "timeline-project")
                == ProjectID(rootURL: root)
        )
    }
}
