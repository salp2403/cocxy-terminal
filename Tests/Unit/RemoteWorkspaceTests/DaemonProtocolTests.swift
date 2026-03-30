// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonProtocolTests.swift - Tests for daemon JSON lines protocol.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("DaemonProtocol")
struct DaemonProtocolTests {

    // MARK: - Request Encoding

    @Test("Encode request contains proto version")
    func encodeRequestProto() throws {
        let req = DaemonRequest(id: "1", cmd: "ping")
        let json = try req.jsonLine()
        #expect(json.contains("\"proto\":1"))
    }

    @Test("Encode request contains command")
    func encodeRequestCmd() throws {
        let req = DaemonRequest(id: "1", cmd: "session.list")
        let json = try req.jsonLine()
        #expect(json.contains("\"cmd\":\"session.list\""))
    }

    @Test("Encode request with args")
    func encodeRequestWithArgs() throws {
        let req = DaemonRequest(id: "2", cmd: "session.create", args: ["title": "my-session"])
        let json = try req.jsonLine()
        #expect(json.contains("\"args\""))
        #expect(json.contains("my-session"))
    }

    @Test("Encode request ends with newline")
    func encodeRequestNewline() throws {
        let req = DaemonRequest(id: "1", cmd: "ping")
        let json = try req.jsonLine()
        #expect(json.hasSuffix("\n"))
    }

    @Test("Encode request produces valid JSON")
    func encodeRequestValidJSON() throws {
        let req = DaemonRequest(id: "1", cmd: "status")
        let json = try req.jsonLine()
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data(trimmed.utf8)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(parsed != nil)
        #expect(parsed?["id"] as? String == "1")
    }

    // MARK: - Response Decoding

    @Test("Decode success response")
    func decodeSuccess() throws {
        let line = #"{"ok":true,"id":"1","data":{"sessions":[]}}"#
        let resp = try DaemonResponse.parse(line)
        #expect(resp.ok)
        #expect(resp.id == "1")
        #expect(resp.data != nil)
    }

    @Test("Decode error response")
    func decodeError() throws {
        let line = #"{"ok":false,"id":"2","error":"not found"}"#
        let resp = try DaemonResponse.parse(line)
        #expect(!resp.ok)
        #expect(resp.error == "not found")
    }

    @Test("Decode pong response")
    func decodePong() throws {
        let line = #"{"ok":true,"id":"3","data":{"pong":true}}"#
        let resp = try DaemonResponse.parse(line)
        #expect(resp.ok)
        #expect(resp.data?["pong"] as? Bool == true)
    }

    @Test("Decode response without data")
    func decodeNoData() throws {
        let line = #"{"ok":true,"id":"4"}"#
        let resp = try DaemonResponse.parse(line)
        #expect(resp.ok)
        #expect(resp.data == nil)
    }

    @Test("Invalid JSON throws error")
    func invalidJSON() {
        #expect(throws: (any Error).self) {
            _ = try DaemonResponse.parse("not json")
        }
    }

    @Test("Unknown command error is parseable")
    func unknownCommand() throws {
        let line = #"{"ok":false,"id":"5","error":"unknown command"}"#
        let resp = try DaemonResponse.parse(line)
        #expect(!resp.ok)
        #expect(resp.error == "unknown command")
    }

    // MARK: - All Commands

    @Test("All daemon commands are defined")
    func allCommands() {
        let commands = DaemonCommand.allCases
        #expect(commands.count == 15)
    }

    @Test("Command raw values are correct")
    func commandRawValues() {
        #expect(DaemonCommand.sessionList.rawValue == "session.list")
        #expect(DaemonCommand.sessionCreate.rawValue == "session.create")
        #expect(DaemonCommand.sessionAttach.rawValue == "session.attach")
        #expect(DaemonCommand.sessionDetach.rawValue == "session.detach")
        #expect(DaemonCommand.sessionInput.rawValue == "session.input")
        #expect(DaemonCommand.sessionOutput.rawValue == "session.output")
        #expect(DaemonCommand.sessionKill.rawValue == "session.kill")
        #expect(DaemonCommand.forwardList.rawValue == "forward.list")
        #expect(DaemonCommand.forwardAdd.rawValue == "forward.add")
        #expect(DaemonCommand.forwardRemove.rawValue == "forward.remove")
        #expect(DaemonCommand.status.rawValue == "status")
        #expect(DaemonCommand.syncWatch.rawValue == "sync.watch")
        #expect(DaemonCommand.syncChanges.rawValue == "sync.changes")
        #expect(DaemonCommand.ping.rawValue == "ping")
        #expect(DaemonCommand.shutdown.rawValue == "shutdown")
    }
}
