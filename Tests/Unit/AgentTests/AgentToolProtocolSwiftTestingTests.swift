// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AgentToolProtocolSwiftTestingTests.swift - JSON protocol contracts for Agent tools.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("Agent tool protocol")
struct AgentToolProtocolSwiftTestingTests {

    @Test("call envelope round-trips versioned JSON arguments")
    func callEnvelopeRoundTrips() throws {
        let envelope = AgentToolCallEnvelope(call: AgentToolCall(
            id: "call-1",
            toolID: "grep",
            arguments: [
                "pattern": .string("AgentModeConfig"),
                "caseSensitive": .bool(false),
                "limit": .number(20),
                "paths": .array([.string("Sources"), .string("Tests")]),
            ]
        ))

        let data = try AgentToolProtocolCodec.encode(envelope)
        let decoded = try AgentToolProtocolCodec.decodeCallEnvelope(from: data)

        #expect(decoded == envelope)
    }

    @Test("unsupported protocol version is rejected")
    func unsupportedProtocolVersionRejected() throws {
        let data = Data("""
        {"version":2,"call":{"id":"call-1","toolID":"read_file","arguments":{"path":"README.md"}}}
        """.utf8)

        #expect(throws: AgentToolProtocolError.unsupportedVersion(2)) {
            _ = try AgentToolProtocolCodec.decodeCallEnvelope(from: data)
        }
    }

    @Test("tool call resolves registry capability into permission invocation")
    func toolCallResolvesIntoPermissionInvocation() throws {
        let registry = AgentToolRegistry.minimumBuiltIns()
        let call = AgentToolCall(
            id: "call-run",
            toolID: "run_command",
            arguments: ["command": .string("swift test --filter AgentToolProtocolSwiftTestingTests")]
        )

        #expect(try call.invocation(using: registry) == AgentToolInvocation(
            toolID: "run_command",
            capability: .command,
            command: "swift test --filter AgentToolProtocolSwiftTestingTests"
        ))
    }

    @Test("unknown tool and missing command arguments fail before permission evaluation")
    func invalidCallsFailBeforePermissionEvaluation() throws {
        let registry = AgentToolRegistry.minimumBuiltIns()
        let unknown = AgentToolCall(id: "call-unknown", toolID: "remote_shell", arguments: [:])
        let missingCommand = AgentToolCall(id: "call-missing", toolID: "run_command", arguments: [:])

        #expect(throws: AgentToolProtocolError.unknownToolID("remote_shell")) {
            _ = try unknown.invocation(using: registry)
        }
        #expect(throws: AgentToolProtocolError.missingRequiredArgument(toolID: "run_command", argument: "command")) {
            _ = try missingCommand.invocation(using: registry)
        }
    }

    @Test("tool result failure encodes structured error payload")
    func toolResultFailureEncodesStructuredErrorPayload() throws {
        let result = AgentToolResult.failure(
            callID: "call-1",
            toolID: "run_command",
            code: "permission_denied",
            message: "Command requires approval"
        )

        let data = try AgentToolProtocolCodec.encode(result)
        let decoded = try JSONDecoder().decode(AgentToolResult.self, from: data)

        #expect(decoded == result)
        #expect(decoded.status == .failure)
        #expect(decoded.error?.code == "permission_denied")
    }
}
