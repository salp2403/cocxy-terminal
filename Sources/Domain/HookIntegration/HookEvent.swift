// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HookEvent.swift - Models for Claude Code lifecycle hook events.

import Foundation

// MARK: - Hook Event Type

/// The 12 lifecycle events Cocxy consumes from Claude Code hooks.
///
/// Each event maps to a specific phase in the agent's lifecycle.
/// Unknown event types fail decoding (forward compatibility via receiver layer).
///
/// - SeeAlso: ADR-008 (Agent Intelligence Architecture)
enum HookEventType: String, Codable, Sendable, CaseIterable {
    case sessionStart       = "SessionStart"
    case sessionEnd         = "SessionEnd"
    case stop               = "Stop"
    case userPromptSubmit   = "UserPromptSubmit"
    case preToolUse         = "PreToolUse"
    case postToolUse        = "PostToolUse"
    case postToolUseFailure = "PostToolUseFailure"
    case subagentStart      = "SubagentStart"
    case subagentStop       = "SubagentStop"
    case notification       = "Notification"
    case teammateIdle       = "TeammateIdle"
    case taskCompleted      = "TaskCompleted"
}

// MARK: - Hook Event

/// A lifecycle event received from Claude Code via command hooks.
///
/// Claude Code v2.1+ emits a flat JSON format via stdin to hook commands:
/// ```json
/// {
///   "session_id": "uuid",
///   "hook_event_name": "PostToolUse",
///   "tool_name": "Bash",
///   "tool_input": { "command": "ls" },
///   "tool_response": { "stdout": "..." },
///   "cwd": "/path/to/project"
/// }
/// ```
///
/// This struct decodes from Claude Code's real format using custom `init(from:)`.
///
/// - SeeAlso: ADR-008 Section 1.3
struct HookEvent: Codable, Sendable {
    /// The type of lifecycle event.
    let type: HookEventType

    /// Claude Code session ID (links events from the same session).
    let sessionId: String

    /// Timestamp when the event occurred.
    let timestamp: Date

    /// Type-specific event payload.
    let data: HookEventData

    /// Working directory from the hook event JSON.
    ///
    /// Carried per-event to avoid race conditions when multiple events
    /// arrive concurrently on the socket thread. Each event owns its CWD.
    let cwd: String?

    // MARK: - Custom Decoding (Claude Code v2.1+ format)

    private enum CodingKeys: String, CodingKey {
        // Claude Code real format keys (snake_case)
        case hookEventName = "hook_event_name"
        case sessionIdSnake = "session_id"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolResponse = "tool_response"
        case cwd
        // Subagent event keys
        case agentType = "agent_type"
        case agentId = "agent_id"
        // Task event keys
        case taskDescription = "task_description"
        // Legacy format keys (camelCase, backward compatibility)
        case type
        case sessionIdCamel = "sessionId"
        case timestamp
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try Claude Code's real format first (hook_event_name + session_id).
        if let hookEventName = try container.decodeIfPresent(String.self, forKey: .hookEventName),
           let eventType = HookEventType(rawValue: hookEventName) {
            self.type = eventType
            self.sessionId = try container.decode(String.self, forKey: .sessionIdSnake)
            self.timestamp = Date() // Claude Code doesn't send timestamp
            self.cwd = try? container.decode(String.self, forKey: .cwd)

            // Build data from flat fields.
            switch eventType {
            case .preToolUse, .postToolUse, .postToolUseFailure:
                let toolName = (try? container.decode(String.self, forKey: .toolName)) ?? "unknown"
                // tool_input can be complex nested JSON — extract file_path/command as strings.
                let toolInput = Self.extractToolInput(from: container)
                let result = Self.extractToolResult(from: container)
                let error = eventType == .postToolUseFailure ? result : nil
                self.data = .toolUse(ToolUseData(
                    toolName: toolName,
                    toolInput: toolInput,
                    result: eventType == .postToolUse ? result : nil,
                    error: error
                ))

            case .notification:
                self.data = .notification(NotificationData(
                    title: "Claude Code",
                    body: (try? container.decode(String.self, forKey: .toolName)) ?? "Notification"
                ))

            case .stop:
                self.data = .stop(StopData())

            case .sessionStart:
                let cwd = try? container.decode(String.self, forKey: .cwd)
                self.data = .sessionStart(SessionStartData(
                    model: nil,
                    agentType: "claude-code",
                    workingDirectory: cwd
                ))

            case .subagentStart, .subagentStop:
                let agentType = try? container.decode(String.self, forKey: .agentType)
                let agentId = (try? container.decode(String.self, forKey: .agentId))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                self.data = .subagent(SubagentData(
                    subagentId: agentId ?? "",
                    subagentType: agentType
                ))

            case .sessionEnd:
                self.data = .stop(StopData())

            case .taskCompleted:
                let desc = try? container.decode(String.self, forKey: .taskDescription)
                self.data = .taskCompleted(TaskCompletedData(taskDescription: desc))

            case .teammateIdle:
                self.data = .teammateIdle(TeammateIdleData())

            case .userPromptSubmit:
                self.data = .generic
            }
            return
        }

        // Fallback: legacy format (type + sessionId + timestamp + data).
        self.type = try container.decode(HookEventType.self, forKey: .type)
        // Legacy uses "sessionId" (camelCase); real format uses "session_id".
        let legacySessionId = try? container.decode(String.self, forKey: .sessionIdCamel)
        let snakeSessionId = try? container.decode(String.self, forKey: .sessionIdSnake)
        self.sessionId = legacySessionId ?? snakeSessionId ?? UUID().uuidString
        self.timestamp = (try? container.decode(Date.self, forKey: .timestamp)) ?? Date()
        self.data = (try? container.decode(HookEventData.self, forKey: .data)) ?? .generic
        self.cwd = try? container.decode(String.self, forKey: .cwd)
    }

    init(type: HookEventType, sessionId: String, timestamp: Date = Date(), data: HookEventData = .generic, cwd: String? = nil) {
        self.type = type
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.data = data
        self.cwd = cwd
    }

    // MARK: - Encodable (legacy format for tests and serialization)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(sessionId, forKey: .sessionIdCamel)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(data, forKey: .data)
    }

    // MARK: - Tool Input Extraction

    /// Extracts tool_input as a flat [String: String] from the potentially nested JSON.
    private static func extractToolInput(from container: KeyedDecodingContainer<CodingKeys>) -> [String: String]? {
        // Try as [String: String] first (simple case).
        if let simple = try? container.decode([String: String].self, forKey: .toolInput) {
            return simple
        }
        // Try as nested JSON, extract known keys.
        if let nested = try? container.decode([String: AnyCodableValue].self, forKey: .toolInput) {
            var result: [String: String] = [:]
            for (key, value) in nested {
                result[key] = value.stringValue
            }
            return result.isEmpty ? nil : result
        }
        return nil
    }

    /// Extracts tool result as a string summary from tool_response.
    private static func extractToolResult(from container: KeyedDecodingContainer<CodingKeys>) -> String? {
        // tool_response can be complex: { "stdout": "...", "stderr": "..." }
        // or { "type": "text", "file": { ... } }
        if let response = try? container.decode([String: AnyCodableValue].self, forKey: .toolResponse) {
            if let stdout = response["stdout"]?.stringValue, !stdout.isEmpty {
                return String(stdout.prefix(200))
            }
            if let type = response["type"]?.stringValue {
                return type
            }
            return "ok"
        }
        return nil
    }
}

// MARK: - AnyCodableValue

/// Helper for decoding mixed-type JSON values into strings.
enum AnyCodableValue: Codable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodableValue])
    case object([String: AnyCodableValue])
    case null

    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        case .array(let arr):
            let elements = arr.compactMap { $0.stringValue }
            return "[\(elements.joined(separator: ", "))]"
        case .object(let dict):
            let pairs = dict.compactMap { k, v -> String? in
                guard let vs = v.stringValue else { return nil }
                return "\(k): \(vs)"
            }
            return "{\(pairs.joined(separator: ", "))}"
        case .null: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let i = try? container.decode(Int.self) { self = .int(i); return }
        if let d = try? container.decode(Double.self) { self = .double(d); return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let arr = try? container.decode([AnyCodableValue].self) { self = .array(arr); return }
        if let obj = try? container.decode([String: AnyCodableValue].self) { self = .object(obj); return }
        if container.decodeNil() { self = .null; return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .array(let arr): try container.encode(arr)
        case .object(let obj): try container.encode(obj)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Hook Event Data

/// Type-discriminated payload for hook events.
enum HookEventData: Codable, Sendable {
    case sessionStart(SessionStartData)
    case stop(StopData)
    case toolUse(ToolUseData)
    case subagent(SubagentData)
    case notification(NotificationData)
    case taskCompleted(TaskCompletedData)
    case teammateIdle(TeammateIdleData)
    case generic

    // MARK: - Coding Keys

    private enum CodingKeys: String, CodingKey {
        case sessionStart, stop, toolUse, subagent
        case notification, taskCompleted, teammateIdle, generic
    }

    // MARK: - Decodable

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let value = try container.decodeIfPresent(SessionStartData.self, forKey: .sessionStart) {
            self = .sessionStart(value)
        } else if let value = try container.decodeIfPresent(StopData.self, forKey: .stop) {
            self = .stop(value)
        } else if let value = try container.decodeIfPresent(ToolUseData.self, forKey: .toolUse) {
            self = .toolUse(value)
        } else if let value = try container.decodeIfPresent(SubagentData.self, forKey: .subagent) {
            self = .subagent(value)
        } else if let value = try container.decodeIfPresent(NotificationData.self, forKey: .notification) {
            self = .notification(value)
        } else if let value = try container.decodeIfPresent(TaskCompletedData.self, forKey: .taskCompleted) {
            self = .taskCompleted(value)
        } else if let value = try container.decodeIfPresent(TeammateIdleData.self, forKey: .teammateIdle) {
            self = .teammateIdle(value)
        } else {
            self = .generic
        }
    }

    // MARK: - Encodable

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .sessionStart(let value): try container.encode(value, forKey: .sessionStart)
        case .stop(let value): try container.encode(value, forKey: .stop)
        case .toolUse(let value): try container.encode(value, forKey: .toolUse)
        case .subagent(let value): try container.encode(value, forKey: .subagent)
        case .notification(let value): try container.encode(value, forKey: .notification)
        case .taskCompleted(let value): try container.encode(value, forKey: .taskCompleted)
        case .teammateIdle(let value): try container.encode(value, forKey: .teammateIdle)
        case .generic: try container.encode(EmptyPayload(), forKey: .generic)
        }
    }
}

// MARK: - Data Structs

struct SessionStartData: Codable, Sendable, Equatable {
    let model: String?
    let agentType: String?
    let workingDirectory: String?

    init(model: String? = nil, agentType: String? = nil, workingDirectory: String? = nil) {
        self.model = model
        self.agentType = agentType
        self.workingDirectory = workingDirectory
    }
}

struct StopData: Codable, Sendable, Equatable {
    let lastMessage: String?
    let reason: String?

    init(lastMessage: String? = nil, reason: String? = nil) {
        self.lastMessage = lastMessage
        self.reason = reason
    }
}

struct ToolUseData: Codable, Sendable, Equatable {
    let toolName: String
    let toolInput: [String: String]?
    let result: String?
    let error: String?

    init(toolName: String, toolInput: [String: String]? = nil, result: String? = nil, error: String? = nil) {
        self.toolName = toolName
        self.toolInput = toolInput
        self.result = result
        self.error = error
    }
}

struct SubagentData: Codable, Sendable, Equatable {
    let subagentId: String
    let subagentType: String?

    init(subagentId: String, subagentType: String? = nil) {
        self.subagentId = subagentId
        self.subagentType = subagentType
    }
}

struct NotificationData: Codable, Sendable, Equatable {
    let title: String?
    let body: String?

    init(title: String? = nil, body: String? = nil) {
        self.title = title
        self.body = body
    }
}

struct TaskCompletedData: Codable, Sendable, Equatable {
    let taskDescription: String?

    init(taskDescription: String? = nil) {
        self.taskDescription = taskDescription
    }
}

struct TeammateIdleData: Codable, Sendable, Equatable {
    let teammateId: String?
    let reason: String?

    init(teammateId: String? = nil, reason: String? = nil) {
        self.teammateId = teammateId
        self.reason = reason
    }
}

private struct EmptyPayload: Codable, Sendable {}
