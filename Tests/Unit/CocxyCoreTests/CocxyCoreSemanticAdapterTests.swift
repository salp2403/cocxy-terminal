// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Combine
import Testing
import CocxyCoreKit
@testable import CocxyTerminal

@Suite("CocxyCoreSemanticAdapter")
@MainActor
struct CocxyCoreSemanticAdapterTests {

    @Test("Agent launch emits a SessionStart hook")
    func agentLaunchEmitsSessionStartHook() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)
        let surfaceID = makeSurfaceID("00000000-0000-0000-0000-000000000001")

        withSemanticEvent(type: .agentLaunched, detail: "Claude") { event in
            adapter.processSemanticEvent(event, for: surfaceID, cwd: "/tmp/project")
        }

        let hook = capture.hooks.last
        #expect(hook?.type == .sessionStart)
        #expect(hook?.cwd == "/tmp/project")
        if case .sessionStart(let data)? = hook?.data {
            #expect(data.agentType == "Claude")
            #expect(data.workingDirectory == nil)
        } else {
            Issue.record("Expected SessionStartData payload")
        }
    }

    @Test("Agent launch emits a timeline sessionStart event")
    func agentLaunchEmitsTimelineSessionStart() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)
        let surfaceID = makeSurfaceID("00000000-0000-0000-0000-000000000002")

        withSemanticEvent(type: .agentLaunched, detail: "Claude") { event in
            adapter.processSemanticEvent(event, for: surfaceID, cwd: nil)
        }

        let timeline = capture.timeline.last
        #expect(timeline?.type == .sessionStart)
        #expect(timeline?.summary == "Agent launched: Claude")
    }

    @Test("Timeline events inherit window metadata from the provider")
    func timelineEventsIncludeWindowMetadata() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)
        let surfaceID = makeSurfaceID("00000000-0000-0000-0000-000000000099")
        let windowID = WindowID()

        adapter.windowMetadataProvider = { candidateSurfaceID, cwd in
            #expect(candidateSurfaceID == surfaceID)
            #expect(cwd == "/tmp/project")
            return (windowID, "Window 3")
        }

        withSemanticEvent(type: .toolStarted, detail: "Read") { event in
            adapter.processSemanticEvent(event, for: surfaceID, cwd: "/tmp/project")
        }

        let timeline = capture.timeline.last
        #expect(timeline?.windowID == windowID)
        #expect(timeline?.windowLabel == "Window 3")
    }

    @Test("Session identifier provider overrides synthetic surface IDs")
    func sessionIdentifierProviderOverridesSyntheticID() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)
        let surfaceID = makeSurfaceID("00000000-0000-0000-0000-000000000111")
        let sessionID = UUID().uuidString

        adapter.sessionIdentifierProvider = { candidateSurfaceID, cwd in
            #expect(candidateSurfaceID == surfaceID)
            #expect(cwd == "/tmp/project")
            return sessionID
        }

        withSemanticEvent(type: .toolStarted, detail: "Read") { event in
            adapter.processSemanticEvent(event, for: surfaceID, cwd: "/tmp/project")
        }

        #expect(capture.hooks.last?.sessionId == sessionID)
        #expect(capture.timeline.last?.sessionId == sessionID)
    }

    @Test("Agent waiting emits a UserPromptSubmit hook")
    func agentWaitingEmitsUserPromptSubmitHook() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)

        withSemanticEvent(type: .agentWaiting, detail: nil) { event in
            adapter.processSemanticEvent(event, for: makeSurfaceID(), cwd: "/tmp/project")
        }

        #expect(capture.hooks.last?.type == .userPromptSubmit)
    }

    @Test("Agent waiting emits a waiting timeline entry")
    func agentWaitingEmitsTimeline() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)

        withSemanticEvent(type: .agentWaiting, detail: nil) { event in
            adapter.processSemanticEvent(event, for: makeSurfaceID(), cwd: nil)
        }

        #expect(capture.timeline.last?.type == .agentResponse)
        #expect(capture.timeline.last?.summary == "Waiting for input")
    }

    @Test("Tool started emits a PreToolUse hook")
    func toolStartedEmitsPreToolUseHook() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)

        withSemanticEvent(type: .toolStarted, detail: "Read") { event in
            adapter.processSemanticEvent(event, for: makeSurfaceID(), cwd: nil)
        }

        let hook = capture.hooks.last
        #expect(hook?.type == .preToolUse)
        if case .toolUse(let data)? = hook?.data {
            #expect(data.toolName == "Read")
        } else {
            Issue.record("Expected ToolUseData payload")
        }
    }

    @Test("Tool started emits a tool-use timeline entry")
    func toolStartedEmitsToolTimeline() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)

        withSemanticEvent(type: .toolStarted, detail: "Read") { event in
            adapter.processSemanticEvent(event, for: makeSurfaceID(), cwd: nil)
        }

        #expect(capture.timeline.last?.type == .toolUse)
        #expect(capture.timeline.last?.toolName == "Read")
        #expect(capture.timeline.last?.summary == "Tool started: Read")
    }

    @Test("Tool finished emits a PostToolUse hook")
    func toolFinishedEmitsPostToolUseHook() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)

        withSemanticEvent(type: .toolFinished, detail: "Write") { event in
            adapter.processSemanticEvent(event, for: makeSurfaceID(), cwd: nil)
        }

        let hook = capture.hooks.last
        #expect(hook?.type == .postToolUse)
        if case .toolUse(let data)? = hook?.data {
            #expect(data.toolName == "Write")
        } else {
            Issue.record("Expected ToolUseData payload")
        }
    }

    @Test("Agent error emits only a failure timeline event")
    func agentErrorEmitsFailureTimelineOnly() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)

        withSemanticEvent(type: .agentError, detail: "Boom") { event in
            adapter.processSemanticEvent(event, for: makeSurfaceID(), cwd: nil)
        }

        #expect(capture.hooks.isEmpty)
        #expect(capture.timeline.last?.type == .toolFailure)
        #expect(capture.timeline.last?.summary == "Boom")
        #expect(capture.timeline.last?.isError == true)
    }

    @Test("Prompt shown emits only a timeline entry")
    func promptShownEmitsOnlyTimeline() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)

        withSemanticEvent(type: .promptShown, detail: nil) { event in
            adapter.processSemanticEvent(event, for: makeSurfaceID(), cwd: nil)
        }

        #expect(capture.hooks.isEmpty)
        #expect(capture.timeline.last?.type == .agentResponse)
        #expect(capture.timeline.last?.summary == "Prompt shown")
    }

    @Test("Command finished summary carries the exit code")
    func commandFinishedIncludesExitCode() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)

        withSemanticEvent(
            type: .commandFinished,
            detail: nil,
            exitCode: 17
        ) { event in
            adapter.processSemanticEvent(event, for: makeSurfaceID(), cwd: nil)
        }

        #expect(capture.timeline.last?.summary == "Command finished (exit 17)")
    }

    @Test("File path detected stores the path on the timeline event")
    func filePathDetectedPublishesFilePath() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)
        let path = "/tmp/project/Sources/App.swift"

        withSemanticEvent(type: .filePathDetected, detail: path) { event in
            adapter.processSemanticEvent(event, for: makeSurfaceID(), cwd: nil)
        }

        #expect(capture.timeline.last?.filePath == path)
        #expect(capture.timeline.last?.summary == "File: App.swift")
    }

    @Test("Progress update emits an agent response timeline entry")
    func progressUpdatePublishesTimeline() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)

        withSemanticEvent(type: .progressUpdate, detail: "Uploading…") { event in
            adapter.processSemanticEvent(event, for: makeSurfaceID(), cwd: nil)
        }

        #expect(capture.timeline.last?.type == .agentResponse)
        #expect(capture.timeline.last?.summary == "Uploading…")
    }

    @Test("Process spawn does not emit hook events for generic subprocesses")
    func processSpawnDoesNotEmitHookForGenericSubprocesses() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)

        let event = cocxycore_process_event(
            event_type: ProcessEventType.childSpawned.rawValue,
            _pad: (0, 0, 0),
            pid: 321,
            parent_pid: 111,
            stream_id: 7,
            exit_code: -1,
            _pad2: 0
        )
        adapter.processProcessEvent(event, for: makeSurfaceID(), cwd: "/tmp/project")

        #expect(capture.hooks.isEmpty)
    }

    @Test("Process spawn emits a subagent-start timeline entry")
    func processSpawnEmitsTimeline() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)

        let event = cocxycore_process_event(
            event_type: ProcessEventType.childSpawned.rawValue,
            _pad: (0, 0, 0),
            pid: 321,
            parent_pid: 111,
            stream_id: 7,
            exit_code: -1,
            _pad2: 0
        )
        adapter.processProcessEvent(event, for: makeSurfaceID(), cwd: nil)

        #expect(capture.timeline.last?.type == .subagentStart)
        #expect(capture.timeline.last?.summary == "Subprocess spawned (PID 321)")
    }

    @Test("Process exit emits only a subagent-stop timeline entry")
    func processExitPublishesTimelineOnly() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)

        let event = cocxycore_process_event(
            event_type: ProcessEventType.childExited.rawValue,
            _pad: (0, 0, 0),
            pid: 444,
            parent_pid: 111,
            stream_id: 1,
            exit_code: 9,
            _pad2: 0
        )
        adapter.processProcessEvent(event, for: makeSurfaceID(), cwd: nil)

        #expect(capture.hooks.isEmpty)
        #expect(capture.timeline.last?.type == .subagentStop)
        #expect(capture.timeline.last?.summary == "Subprocess exited (PID 444, code 9)")
    }

    @Test("Session IDs stay stable across multiple events on the same surface")
    func sessionIDIsStablePerSurface() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)
        let surfaceID = makeSurfaceID("00000000-0000-0000-0000-00000000ABCD")

        withSemanticEvent(type: .agentLaunched, detail: "Claude") { event in
            adapter.processSemanticEvent(event, for: surfaceID, cwd: nil)
        }
        withSemanticEvent(type: .toolStarted, detail: "Read") { event in
            adapter.processSemanticEvent(event, for: surfaceID, cwd: nil)
        }

        #expect(capture.hooks.count == 2)
        #expect(capture.hooks[0].sessionId == capture.hooks[1].sessionId)
        #expect(capture.timeline[0].sessionId == capture.timeline[1].sessionId)
    }

    @Test("surfaceDestroyed clears the cached agent name")
    func surfaceDestroyedClearsAgentName() {
        let adapter = CocxyCoreSemanticAdapter()
        let capture = SemanticCapture(adapter: adapter)
        let surfaceID = makeSurfaceID("00000000-0000-0000-0000-00000000DCBA")

        withSemanticEvent(type: .agentLaunched, detail: "Claude") { event in
            adapter.processSemanticEvent(event, for: surfaceID, cwd: nil)
        }
        adapter.surfaceDestroyed(surfaceID)
        withSemanticEvent(type: .agentFinished, detail: nil) { event in
            adapter.processSemanticEvent(event, for: surfaceID, cwd: nil)
        }

        #expect(capture.timeline.last?.summary == "Agent finished: agent")
    }
}

@MainActor
private final class SemanticCapture {
    private(set) var hooks: [HookEvent] = []
    private(set) var timeline: [TimelineEvent] = []
    private var cancellables = Set<AnyCancellable>()

    init(adapter: CocxyCoreSemanticAdapter) {
        adapter.eventPublisher
            .sink { [weak self] in self?.hooks.append($0) }
            .store(in: &cancellables)
        adapter.timelinePublisher
            .sink { [weak self] in self?.timeline.append($0) }
            .store(in: &cancellables)
    }
}

private func makeSurfaceID(_ uuidString: String = "00000000-0000-0000-0000-000000000010") -> SurfaceID {
    SurfaceID(rawValue: UUID(uuidString: uuidString)!)
}

private func withSemanticEvent(
    type: SemanticEventType,
    detail: String?,
    exitCode: Int16 = -1,
    body: (cocxycore_semantic_event) -> Void
) {
    let bytes = detail.map { Array($0.utf8) } ?? []
    bytes.withUnsafeBufferPointer { buffer in
        let event = cocxycore_semantic_event(
            event_type: type.rawValue,
            source: SemanticSource.protocolV2.rawValue,
            exit_code: exitCode,
            row: 0,
            block_id: 0,
            confidence: 1.0,
            timestamp: 0,
            detail_ptr: buffer.baseAddress,
            detail_len: UInt16(bytes.count),
            _pad: 0,
            stream_id: 0
        )
        body(event)
    }
}

private enum SemanticEventType: UInt8 {
    case promptShown = 0
    case commandStarted = 1
    case commandFinished = 2
    case agentLaunched = 3
    case agentOutput = 4
    case agentWaiting = 5
    case agentError = 6
    case agentFinished = 7
    case toolStarted = 8
    case toolFinished = 9
    case filePathDetected = 10
    case errorDetected = 11
    case progressUpdate = 12
}

private enum SemanticSource: UInt8 {
    case shellMark = 0
    case protocolV2 = 1
}

private enum ProcessEventType: UInt8 {
    case childSpawned = 0
    case childExited = 1
}
