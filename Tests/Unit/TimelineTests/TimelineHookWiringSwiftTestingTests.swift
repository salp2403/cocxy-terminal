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

        try await Task.sleep(for: .milliseconds(100))

        let events = delegate.agentTimelineStore?.events(for: "timeline-live-edit")
        #expect(events?.count == 1)
        #expect(events?.first?.type == .userPrompt)
    }
}
