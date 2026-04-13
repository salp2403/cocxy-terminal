// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// HookEventNormalizer.swift - Canonicalizes non-Claude hook payloads.

import CryptoKit
import Foundation

enum HookEventNormalizer {

    static func normalizeEventName(_ raw: String, source: AgentSource) -> String {
        switch source {
        case .claudeCode, .codex:
            return raw
        case .geminiCLI:
            switch raw {
            case "BeforeTool":
                return "PreToolUse"
            case "AfterTool":
                return "PostToolUse"
            case "SessionEnd":
                return "Stop"
            default:
                return raw
            }
        case .kiro:
            switch raw {
            case "preToolUse":
                return "PreToolUse"
            case "postToolUse":
                return "PostToolUse"
            case "agentSpawn":
                return "SessionStart"
            case "stop":
                return "Stop"
            case "userPromptSubmit":
                return "UserPromptSubmit"
            default:
                return raw
            }
        case .unknown:
            return raw
        }
    }

    static func normalizePayload(
        _ data: Data,
        environment: [String: String]
    ) throws -> Data {
        guard !data.isEmpty else { return data }

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard var payload = jsonObject as? [String: Any] else {
            return data
        }

        let source = AgentSource.detect(environment: environment, payload: payload)

        if let rawEventName = payload["hook_event_name"] as? String {
            payload["hook_event_name"] = normalizeEventName(rawEventName, source: source)
        }

        if payload["session_id"] == nil,
           let sessionID = AgentSource.resolveSessionID(from: environment) {
            payload["session_id"] = sessionID
        }

        if payload["session_id"] == nil,
           let sessionID = fallbackSessionID(
               source: source,
               payload: payload,
               environment: environment
           ) {
            payload["session_id"] = sessionID
        }

        if payload["agent_type"] == nil,
           (payload["hook_event_name"] as? String) == "SessionStart",
           let agentType = source.configAgentName {
            payload["agent_type"] = agentType
        }

        if payload["cwd"] == nil, let pwd = environment["PWD"], !pwd.isEmpty {
            payload["cwd"] = pwd
        }

        return try JSONSerialization.data(withJSONObject: payload, options: [])
    }

    private static func fallbackSessionID(
        source: AgentSource,
        payload: [String: Any],
        environment: [String: String]
    ) -> String? {
        guard source == .kiro || source == .unknown else {
            return nil
        }

        let cwd = (payload["cwd"] as? String) ?? environment["PWD"] ?? ""
        let termSessionID = environment["TERM_SESSION_ID"] ?? ""
        let parentPID = environment["PPID"] ?? ""
        let seed = [source.rawValue, cwd, termSessionID, parentPID]
            .filter { !$0.isEmpty }
            .joined(separator: "|")

        guard !seed.isEmpty else {
            return nil
        }

        let digest = SHA256.hash(data: Data(seed.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
        return "\(source.rawValue)-\(digest)"
    }
}
