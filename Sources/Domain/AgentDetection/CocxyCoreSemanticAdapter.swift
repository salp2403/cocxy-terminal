// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// CocxyCoreSemanticAdapter.swift - Bridges CocxyCore semantic events to agent detection.

import Foundation
import Combine
import CocxyCoreKit

// MARK: - CocxyCore Semantic Adapter

/// Converts CocxyCore's native semantic events into the formats that
/// Cocxy Terminal's agent detection, dashboard, and timeline systems expect.
///
/// CocxyCore's semantic layer detects agent state changes NATIVELY via
/// OSC 133 shell marks and pattern matching in the byte parser. These
/// events arrive with higher confidence and lower latency than hook-based
/// detection because they are parsed at the terminal engine level.
///
/// ## Integration approach
///
/// This adapter does NOT modify existing detection engine code. Instead, it:
/// 1. Converts semantic events to `HookEvent` format for the detection engine.
/// 2. Converts semantic events to `TimelineEvent` format for the timeline store.
/// 3. Publishes synthesized events through Combine publishers that existing
///    wiring can subscribe to.
///
/// The hook-based detection (`HookEventReceiver`) continues to work alongside
/// this adapter. When both sources report the same state, the detection engine's
/// debounce interval suppresses the duplicate. When CocxyCore detects faster
/// (which it should — it reads the byte stream directly), the hook event
/// becomes a no-op confirmation.
///
/// ## Event type mapping
///
/// | CocxyCore Semantic Event | Maps to HookEventType | DetectionSignal |
/// |---|---|---|
/// | PROMPT_SHOWN | — (OSCNotification) | promptDetected |
/// | COMMAND_STARTED | — (OSCNotification) | — |
/// | COMMAND_FINISHED | — (OSCNotification) | — |
/// | AGENT_LAUNCHED | .sessionStart | agentDetected |
/// | AGENT_WAITING | .teammateIdle | promptDetected (waitingInput) |
/// | AGENT_ERROR | .postToolUseFailure | errorDetected |
/// | AGENT_FINISHED | .stop | completionDetected |
/// | TOOL_STARTED | .preToolUse | outputReceived |
/// | TOOL_FINISHED | .postToolUse | outputReceived |
@MainActor
final class CocxyCoreSemanticAdapter {

    // MARK: - Publishers

    /// Publisher for synthesized hook events. Wire to the same sinks
    /// that consume `hookEventReceiver.eventPublisher`.
    var eventPublisher: AnyPublisher<HookEvent, Never> {
        eventSubject.eraseToAnyPublisher()
    }

    /// Publisher for timeline events. Wire to the timeline store.
    var timelinePublisher: AnyPublisher<TimelineEvent, Never> {
        timelineSubject.eraseToAnyPublisher()
    }

    // MARK: - Private

    private let eventSubject = PassthroughSubject<HookEvent, Never>()
    private let timelineSubject = PassthroughSubject<TimelineEvent, Never>()

    /// Resolves stable window metadata for a surface/cwd pair.
    /// Injected by AppDelegate so timeline events can participate in
    /// multi-window filtering and presentation.
    var windowMetadataProvider: ((SurfaceID, String?) -> (WindowID?, String?))?

    /// Resolves a real Cocxy session identifier for a surface.
    ///
    /// When available, timeline and hook events should use the owning tab's
    /// stable `SessionID` instead of a synthetic per-surface fallback.
    var sessionIdentifierProvider: ((SurfaceID, String?) -> String?)?

    /// Synthetic session ID per surface. CocxyCore doesn't have the CLI agent's
    /// session concept, so we create a stable ID per surface for routing.
    private var sessionIDs: [SurfaceID: String] = [:]

    /// Track the last detected agent name per surface for context.
    private var agentNames: [SurfaceID: String] = [:]

    // MARK: - Public API

    /// Process a semantic event from CocxyCore and emit corresponding
    /// hook/timeline events through the publishers.
    ///
    /// - Parameters:
    ///   - event: The raw semantic event from CocxyCore's callback.
    ///   - surfaceID: The surface that produced this event.
    ///   - cwd: Current working directory of the surface's tab, if known.
    func processSemanticEvent(
        _ event: cocxycore_semantic_event,
        for surfaceID: SurfaceID,
        cwd: String?
    ) {
        let sessionId = sessionID(for: surfaceID, cwd: cwd)
        let detail = extractDetail(from: event)
        let timestamp = Date()
        let (windowID, windowLabel) = windowMetadataProvider?(surfaceID, cwd) ?? (nil, nil)

        switch Int32(event.event_type) {
        // Shell integration events (0-2) are already handled by CocxyCoreBridge
        // as OSCNotifications. We only emit timeline events for them.
        case 0: // PROMPT_SHOWN
            emitTimeline(
                type: .agentResponse, sessionId: sessionId,
                summary: "Prompt shown", timestamp: timestamp,
                windowID: windowID, windowLabel: windowLabel
            )

        case 1: // COMMAND_STARTED
            emitTimeline(
                type: .agentResponse, sessionId: sessionId,
                summary: "Command started", timestamp: timestamp,
                windowID: windowID, windowLabel: windowLabel
            )

        case 2: // COMMAND_FINISHED
            let exitCode = event.exit_code >= 0 ? Int(event.exit_code) : nil
            let summary = exitCode.map { "Command finished (exit \($0))" } ?? "Command finished"
            emitTimeline(
                type: .agentResponse, sessionId: sessionId,
                summary: summary, timestamp: timestamp,
                windowID: windowID, windowLabel: windowLabel
            )

        // Agent-level events (3-7) → synthesize HookEvents for detection engine
        case 3: // AGENT_LAUNCHED
            let agentName = detail ?? "agent"
            agentNames[surfaceID] = agentName

            emitHookEvent(
                type: .sessionStart,
                sessionId: sessionId,
                cwd: cwd,
                data: .sessionStart(SessionStartData(agentType: agentName)),
                timestamp: timestamp
            )
            emitTimeline(
                type: .sessionStart, sessionId: sessionId,
                summary: "Agent launched: \(agentName)", timestamp: timestamp,
                windowID: windowID, windowLabel: windowLabel
            )

        case 4: // AGENT_OUTPUT
            emitHookEvent(
                type: .preToolUse,
                sessionId: sessionId,
                cwd: cwd,
                data: .toolUse(ToolUseData(
                    toolName: "output",
                    toolInput: nil,
                    result: nil
                )),
                timestamp: timestamp
            )

        case 5: // AGENT_WAITING
            emitHookEvent(
                type: .teammateIdle,
                sessionId: sessionId,
                cwd: cwd,
                data: .generic,
                timestamp: timestamp
            )
            emitTimeline(
                type: .agentResponse, sessionId: sessionId,
                summary: "Waiting for input", timestamp: timestamp,
                windowID: windowID, windowLabel: windowLabel
            )

        case 6: // AGENT_ERROR
            let errorMessage = detail ?? "Agent error"
            emitHookEvent(
                type: .postToolUseFailure,
                sessionId: sessionId,
                cwd: cwd,
                data: .toolUse(ToolUseData(
                    toolName: "agent",
                    toolInput: nil,
                    result: nil,
                    error: errorMessage
                )),
                timestamp: timestamp
            )
            emitTimeline(
                type: .toolFailure, sessionId: sessionId,
                summary: errorMessage,
                timestamp: timestamp, isError: true,
                windowID: windowID, windowLabel: windowLabel
            )

        case 7: // AGENT_FINISHED
            let agentName = agentNames[surfaceID] ?? "agent"
            emitHookEvent(
                type: .stop,
                sessionId: sessionId,
                cwd: cwd,
                data: .stop(StopData()),
                timestamp: timestamp
            )
            emitTimeline(
                type: .sessionEnd, sessionId: sessionId,
                summary: "Agent finished: \(agentName)", timestamp: timestamp,
                windowID: windowID, windowLabel: windowLabel
            )
            agentNames.removeValue(forKey: surfaceID)

        // Tool events (8-9) → synthesize tool-use HookEvents
        case 8: // TOOL_STARTED
            let toolName = detail ?? "unknown"
            emitHookEvent(
                type: .preToolUse,
                sessionId: sessionId,
                cwd: cwd,
                data: .toolUse(ToolUseData(
                    toolName: toolName,
                    toolInput: nil,
                    result: nil
                )),
                timestamp: timestamp
            )
            emitTimeline(
                type: .toolUse, sessionId: sessionId,
                toolName: toolName,
                summary: "Tool started: \(toolName)", timestamp: timestamp,
                windowID: windowID, windowLabel: windowLabel
            )

        case 9: // TOOL_FINISHED
            let toolName = detail ?? "unknown"
            emitHookEvent(
                type: .postToolUse,
                sessionId: sessionId,
                cwd: cwd,
                data: .toolUse(ToolUseData(
                    toolName: toolName,
                    toolInput: nil,
                    result: nil
                )),
                timestamp: timestamp
            )
            emitTimeline(
                type: .toolUse, sessionId: sessionId,
                toolName: toolName,
                summary: "Tool finished: \(toolName)", timestamp: timestamp,
                windowID: windowID, windowLabel: windowLabel
            )

        // Info events (10-13) → timeline only, no state change
        case 10: // FILE_PATH_DETECTED
            if let path = detail {
                emitTimeline(
                    type: .toolUse, sessionId: sessionId,
                    filePath: path,
                    summary: "File: \(URL(fileURLWithPath: path).lastPathComponent)",
                    timestamp: timestamp,
                    windowID: windowID, windowLabel: windowLabel
                )
            }

        case 11: // ERROR_DETECTED
            emitTimeline(
                type: .toolFailure, sessionId: sessionId,
                summary: detail ?? "Error detected",
                timestamp: timestamp, isError: true,
                windowID: windowID, windowLabel: windowLabel
            )

        case 12: // PROGRESS_UPDATE
            emitTimeline(
                type: .agentResponse, sessionId: sessionId,
                summary: detail ?? "Progress update", timestamp: timestamp,
                windowID: windowID, windowLabel: windowLabel
            )

        default:
            break
        }
    }

    /// Process a CocxyCore process event (child spawned/exited).
    ///
    /// Generic process tracking is best-effort and currently cannot
    /// distinguish a real "subagent" from an ordinary child process.
    /// We therefore emit timeline-only entries here and reserve hook-level
    /// subagent events for integrations that have explicit semantic metadata.
    func processProcessEvent(
        _ event: cocxycore_process_event,
        for surfaceID: SurfaceID,
        cwd: String?
    ) {
        let sessionId = sessionID(for: surfaceID, cwd: cwd)
        let timestamp = Date()
        let (windowID, windowLabel) = windowMetadataProvider?(surfaceID, cwd) ?? (nil, nil)

        switch Int32(event.event_type) {
        case 0: // CHILD_SPAWNED
            emitTimeline(
                type: .stateChange, sessionId: sessionId,
                summary: "Subprocess spawned (PID \(event.pid))",
                timestamp: timestamp,
                windowID: windowID, windowLabel: windowLabel
            )

        case 1: // CHILD_EXITED
            emitTimeline(
                type: .stateChange, sessionId: sessionId,
                summary: "Subprocess exited (PID \(event.pid), code \(event.exit_code))",
                timestamp: timestamp,
                windowID: windowID, windowLabel: windowLabel
            )

        default:
            break
        }
    }

    /// Clean up state for a destroyed surface.
    func surfaceDestroyed(_ surfaceID: SurfaceID) {
        sessionIDs.removeValue(forKey: surfaceID)
        agentNames.removeValue(forKey: surfaceID)
    }

    // MARK: - Private Helpers

    /// Get or create a stable session ID for a surface.
    private func sessionID(for surfaceID: SurfaceID, cwd: String?) -> String {
        if let resolved = sessionIdentifierProvider?(surfaceID, cwd), !resolved.isEmpty {
            sessionIDs[surfaceID] = resolved
            return resolved
        }

        if let existing = sessionIDs[surfaceID] {
            return existing
        }
        let id = "cocxycore-\(surfaceID.rawValue.uuidString.prefix(8))"
        sessionIDs[surfaceID] = id
        return id
    }

    /// Extract detail text from a semantic event.
    private func extractDetail(from event: cocxycore_semantic_event) -> String? {
        guard event.detail_len > 0, let ptr = event.detail_ptr else { return nil }
        return String(
            bytes: UnsafeBufferPointer(start: ptr, count: Int(event.detail_len)),
            encoding: .utf8
        )
    }

    /// Emit a synthesized HookEvent through the publisher.
    private func emitHookEvent(
        type: HookEventType,
        sessionId: String,
        cwd: String?,
        data: HookEventData,
        timestamp: Date
    ) {
        let event = HookEvent(
            type: type,
            sessionId: sessionId,
            timestamp: timestamp,
            data: data,
            cwd: cwd
        )
        eventSubject.send(event)
    }

    /// Emit a TimelineEvent through the publisher.
    private func emitTimeline(
        type: TimelineEventType,
        sessionId: String,
        toolName: String? = nil,
        filePath: String? = nil,
        summary: String,
        timestamp: Date,
        isError: Bool = false,
        windowID: WindowID? = nil,
        windowLabel: String? = nil
    ) {
        let event = TimelineEvent(
            id: UUID(),
            timestamp: timestamp,
            type: type,
            sessionId: sessionId,
            windowID: windowID,
            windowLabel: windowLabel,
            toolName: toolName,
            filePath: filePath,
            summary: summary,
            isError: isError
        )
        timelineSubject.send(event)
    }
}
