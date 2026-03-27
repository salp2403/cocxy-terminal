// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SSHSessionDetectorTests.swift - Tests for SSH session detection.

import XCTest
@testable import CocxyTerminal

final class SSHSessionDetectorTests: XCTestCase {

    // MARK: - Basic Detection

    func testDetectsSimpleSSH() {
        let result = SSHSessionDetector.detect(from: "ssh example.com")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "example.com")
        XCTAssertNil(result?.user)
        XCTAssertNil(result?.port)
    }

    func testDetectsUserAtHost() {
        let result = SSHSessionDetector.detect(from: "ssh root@server.example.com")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.user, "root")
        XCTAssertEqual(result?.host, "server.example.com")
    }

    func testDetectsPort() {
        let result = SSHSessionDetector.detect(from: "ssh -p 2222 user@host")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.port, 2222)
        XCTAssertEqual(result?.user, "user")
        XCTAssertEqual(result?.host, "host")
    }

    func testDetectsPortAfterHost() {
        let result = SSHSessionDetector.detect(from: "ssh user@host -p 2222")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.port, 2222)
    }

    func testDetectsIdentityFile() {
        let result = SSHSessionDetector.detect(from: "ssh -i ~/.ssh/id_rsa user@host")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.hasIdentityFile ?? false)
        XCTAssertEqual(result?.user, "user")
        XCTAssertEqual(result?.host, "host")
    }

    func testDetectsIPAddress() {
        let result = SSHSessionDetector.detect(from: "ssh admin@192.168.1.50")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.user, "admin")
        XCTAssertEqual(result?.host, "192.168.1.50")
    }

    func testDetectsLoginFlag() {
        let result = SSHSessionDetector.detect(from: "ssh -l deploy server.com")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.user, "deploy")
        XCTAssertEqual(result?.host, "server.com")
    }

    // MARK: - Flags

    func testDetectsAgentForwarding() {
        let result = SSHSessionDetector.detect(from: "ssh -A user@host")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.flags.contains("-A") ?? false)
    }

    func testDetectsPortForwarding() {
        let result = SSHSessionDetector.detect(from: "ssh -L 8080:localhost:80 user@host")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.flags.contains("-L") ?? false)
    }

    func testDetectsRemotePortForwarding() {
        let result = SSHSessionDetector.detect(from: "ssh -R 9090:localhost:3000 user@host")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.flags.contains("-R") ?? false)
    }

    func testDetectsDynamicForwarding() {
        let result = SSHSessionDetector.detect(from: "ssh -D 1080 user@host")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.flags.contains("-D") ?? false)
    }

    func testDetectsMultipleFlags() {
        let result = SSHSessionDetector.detect(from: "ssh -A -v -L 8080:localhost:80 user@host")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.flags.contains("-A") ?? false)
        XCTAssertTrue(result?.flags.contains("-v") ?? false)
        XCTAssertTrue(result?.flags.contains("-L") ?? false)
    }

    // MARK: - Edge Cases

    func testRejectsNonSSHCommand() {
        let result = SSHSessionDetector.detect(from: "git push origin main")
        XCTAssertNil(result)
    }

    func testRejectsEmptyString() {
        let result = SSHSessionDetector.detect(from: "")
        XCTAssertNil(result)
    }

    func testRejectsSSHWithoutHost() {
        let result = SSHSessionDetector.detect(from: "ssh -v")
        XCTAssertNil(result)
    }

    func testHandlesFullPath() {
        let result = SSHSessionDetector.detect(from: "/usr/bin/ssh user@host")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.user, "user")
        XCTAssertEqual(result?.host, "host")
    }

    func testHandlesQuotedArguments() {
        let result = SSHSessionDetector.detect(from: "ssh -o 'StrictHostKeyChecking=no' user@host")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.host, "host")
    }

    // MARK: - Display Titles

    func testDisplayTitle() {
        let info = SSHSessionInfo(
            user: "root", host: "server.com",
            port: nil, hasIdentityFile: false, flags: []
        )
        XCTAssertEqual(info.displayTitle, "root@server.com")
    }

    func testDisplayTitleWithoutUser() {
        let info = SSHSessionInfo(
            user: nil, host: "server.com",
            port: nil, hasIdentityFile: false, flags: []
        )
        XCTAssertEqual(info.displayTitle, "server.com")
    }

    func testDisplayTitleWithPort() {
        let info = SSHSessionInfo(
            user: "root", host: "server.com",
            port: 2222, hasIdentityFile: false, flags: []
        )
        XCTAssertEqual(info.displayTitleWithPort, "root@server.com:2222")
    }

    func testDisplayTitleWithDefaultPort() {
        let info = SSHSessionInfo(
            user: "root", host: "server.com",
            port: 22, hasIdentityFile: false, flags: []
        )
        XCTAssertEqual(info.displayTitleWithPort, "root@server.com",
                       "Default port 22 should not appear")
    }

    // MARK: - Process Detection

    func testIsSSHProcess() {
        XCTAssertTrue(SSHSessionDetector.isSSHProcess("ssh"))
        XCTAssertTrue(SSHSessionDetector.isSSHProcess("SSH"))
        XCTAssertTrue(SSHSessionDetector.isSSHProcess("/usr/bin/ssh"))
        XCTAssertTrue(SSHSessionDetector.isSSHProcess("sshpass"))
    }

    func testIsNotSSHProcess() {
        XCTAssertFalse(SSHSessionDetector.isSSHProcess("zsh"))
        XCTAssertFalse(SSHSessionDetector.isSSHProcess("node"))
        XCTAssertFalse(SSHSessionDetector.isSSHProcess("claude"))
    }

    // MARK: - Complex Commands

    func testComplexCommand() {
        let cmd = "ssh -i ~/.ssh/deploy_key -p 2222 -A -L 3000:localhost:3000 deploy@staging.example.com"
        let result = SSHSessionDetector.detect(from: cmd)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.user, "deploy")
        XCTAssertEqual(result?.host, "staging.example.com")
        XCTAssertEqual(result?.port, 2222)
        XCTAssertTrue(result?.hasIdentityFile ?? false)
        XCTAssertTrue(result?.flags.contains("-A") ?? false)
        XCTAssertTrue(result?.flags.contains("-L") ?? false)
    }
}
