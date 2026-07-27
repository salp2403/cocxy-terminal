// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentSensitiveDataPolicy.swift - One-shot Agent data egress and safe transcript tombstones.

import CryptoKit
import Foundation

enum AgentSensitiveDataPolicy {
    static let terminalOutputToolID = "read_terminal_output"
    static let omittedTerminalOutput = "[terminal output omitted after approved one-time use]"

    static func omittedTerminalOutputMessage(from message: AgentMessage) throws -> AgentMessage {
        guard message.role == .tool,
              message.toolName == terminalOutputToolID,
              let toolCallID = message.toolCallID
        else {
            throw AgentToolApprovalError.identityUnavailable
        }
        let result = AgentToolResult.success(
            callID: toolCallID,
            toolID: terminalOutputToolID,
            content: .object([
                "output": .string(omittedTerminalOutput),
            ])
        )
        let data = try AgentToolProtocolCodec.encode(result)
        guard let content = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return AgentMessage(
            id: message.id,
            role: message.role,
            content: content,
            createdAt: message.createdAt,
            toolName: message.toolName,
            toolCallID: message.toolCallID,
            threadID: message.threadID,
            parentMessageID: message.parentMessageID
        )
    }

    static func isSafeOmittedTerminalOutput(_ message: AgentMessage) -> Bool {
        guard message.role == .tool,
              message.toolName == terminalOutputToolID,
              message.sensitiveDataConsent == nil,
              message.toolCalls.isEmpty,
              message.imageAttachments.isEmpty,
              message.toolCallID != nil,
              let canonical = try? omittedTerminalOutputMessage(from: message)
        else {
            return false
        }
        return message.content.utf8.elementsEqual(canonical.content.utf8)
    }

    static func consent(
        toolCallID: String,
        provider: AgentProviderKind,
        contextDigest: String,
        encodedToolResult: String
    ) -> AgentSensitiveDataConsent {
        AgentSensitiveDataConsent(
            toolCallID: toolCallID,
            provider: provider,
            contextDigest: contextDigest,
            payloadDigest: payloadDigest(
                toolCallID: toolCallID,
                provider: provider,
                contextDigest: contextDigest,
                encodedToolResult: encodedToolResult
            )
        )
    }

    static func validatesConsent(
        _ consent: AgentSensitiveDataConsent,
        for message: AgentMessage,
        provider: AgentProviderKind
    ) -> Bool {
        guard message.role == .tool,
              message.toolName == terminalOutputToolID,
              let toolCallID = message.toolCallID,
              consent.toolCallID == toolCallID,
              consent.provider == provider,
              !consent.contextDigest.isEmpty,
              !consent.payloadDigest.isEmpty else {
            return false
        }
        return consent.payloadDigest == payloadDigest(
            toolCallID: toolCallID,
            provider: provider,
            contextDigest: consent.contextDigest,
            encodedToolResult: message.content
        )
    }

    private static func payloadDigest(
        toolCallID: String,
        provider: AgentProviderKind,
        contextDigest: String,
        encodedToolResult: String
    ) -> String {
        var payload = Data()
        for part in [
            "cocxy-agent-sensitive-terminal-output-v1",
            toolCallID,
            provider.rawValue,
            contextDigest,
            encodedToolResult,
        ] {
            let data = Data(part.utf8)
            payload.append(contentsOf: String(data.count).utf8)
            payload.append(0x3A)
            payload.append(data)
            payload.append(0)
        }
        return SHA256.hash(data: payload)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
