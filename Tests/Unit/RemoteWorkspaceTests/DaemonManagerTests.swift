// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DaemonManagerTests.swift - Tests for daemon manager state machine.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("DaemonManager")
struct DaemonManagerTests {

    @Test("Initial state is notDeployed")
    @MainActor func initialState() {
        let executor = MockDeployExecutor()
        let deployer = DaemonDeployer(executor: executor)
        let manager = DaemonManagerImpl(deployer: deployer)
        #expect(manager.state == .notDeployed)
    }

    @Test("DaemonState equality")
    func stateEquality() {
        #expect(DaemonState.notDeployed == DaemonState.notDeployed)
        #expect(DaemonState.deploying == DaemonState.deploying)
        #expect(DaemonState.stopped == DaemonState.stopped)
        #expect(DaemonState.upgrading == DaemonState.upgrading)
        #expect(DaemonState.unreachable == DaemonState.unreachable)
        #expect(DaemonState.running(version: "1.0", uptime: 0) == DaemonState.running(version: "1.0", uptime: 0))
        #expect(DaemonState.running(version: "1.0", uptime: 0) != DaemonState.running(version: "2.0", uptime: 0))
    }

    @Test("DaemonProtocolError equality")
    func errorEquality() {
        #expect(DaemonProtocolError.invalidResponse == DaemonProtocolError.invalidResponse)
        #expect(DaemonProtocolError.connectionLost == DaemonProtocolError.connectionLost)
        #expect(DaemonProtocolError.timeout == DaemonProtocolError.timeout)
        #expect(DaemonProtocolError.daemonNotRunning == DaemonProtocolError.daemonNotRunning)
        #expect(DaemonProtocolError.encodingFailed == DaemonProtocolError.encodingFailed)
    }

    @Test("DaemonSessionInfo parsing from dict")
    func sessionInfoParsing() {
        let dict: [String: Any] = [
            "id": "sess-1",
            "title": "my-session",
            "pid": 12345,
            "age": 60.0,
            "status": "running"
        ]
        let info = DaemonSessionInfo.from(dict: dict)
        #expect(info?.id == "sess-1")
        #expect(info?.title == "my-session")
        #expect(info?.pid == 12345)
        #expect(info?.status == "running")
    }

    @Test("DaemonSessionInfo returns nil for invalid dict")
    func sessionInfoInvalid() {
        let dict: [String: Any] = ["foo": "bar"]
        let info = DaemonSessionInfo.from(dict: dict)
        #expect(info == nil)
    }

    @Test("FileChangeEvent parsing from dict")
    func fileChangeEventParsing() {
        let dict: [String: Any] = [
            "path": "/home/user/file.txt",
            "type": "modified"
        ]
        let event = FileChangeEvent.from(dict: dict)
        #expect(event?.path == "/home/user/file.txt")
        #expect(event?.type == .modified)
    }

    @Test("FileChangeEvent returns nil for invalid type")
    func fileChangeEventInvalidType() {
        let dict: [String: Any] = [
            "path": "/home/user/file.txt",
            "type": "invalid"
        ]
        let event = FileChangeEvent.from(dict: dict)
        #expect(event == nil)
    }

    @Test("All FileChangeEvent types are parseable")
    func allChangeTypes() {
        for type in ["modified", "created", "deleted"] {
            let dict: [String: Any] = ["path": "/test", "type": type]
            let event = FileChangeEvent.from(dict: dict)
            #expect(event != nil)
        }
    }
}
