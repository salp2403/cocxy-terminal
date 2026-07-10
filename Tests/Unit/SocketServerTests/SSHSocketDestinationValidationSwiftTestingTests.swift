// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("SSH socket destination validation")
struct SSHSocketDestinationValidationSwiftTestingTests {
    @Test(
        "rejects invalid destination before invoking UI provider",
        arguments: [
            "-oProxyCommand=/bin/true",
            "user@-oProxyCommand=/bin/true",
            "host with-space",
            "host\u{0007}",
            "first@second@host",
        ]
    )
    func rejectsInvalidDestinationBeforeProvider(_ destination: String) {
        let recorder = SSHSocketProviderRecorder()
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            sshProvider: { destination, port, identity in
                recorder.record(destination: destination, port: port, identity: identity)
                return ("unexpected", destination)
            }
        )
        let request = SocketRequest(
            id: "ssh-invalid",
            command: "ssh",
            params: ["destination": destination]
        )

        let response = handler.handleCommand(request)

        #expect(!response.success)
        #expect(response.error == "Invalid SSH destination (expected host or user@host)")
        #expect(recorder.calls.isEmpty)
    }

    @Test("canonicalizes bracketed IPv6 before invoking provider")
    func canonicalizesIPv6BeforeProvider() throws {
        let recorder = SSHSocketProviderRecorder()
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            sshProvider: { destination, port, identity in
                recorder.record(destination: destination, port: port, identity: identity)
                return ("tab-id", destination)
            }
        )
        let request = SocketRequest(
            id: "ssh-ipv6",
            command: "ssh",
            params: [
                "destination": "deploy@[2001:db8::10]",
                "port": "2222",
                "identity": "~/.ssh/deploy",
            ]
        )

        let response = handler.handleCommand(request)
        let call = try #require(recorder.calls.first)

        #expect(response.success)
        #expect(response.data?["destination"] == "deploy@2001:db8::10")
        #expect(call.destination == "deploy@2001:db8::10")
        #expect(call.port == 2222)
        #expect(call.identity == "~/.ssh/deploy")
    }
}

private final class SSHSocketProviderRecorder: @unchecked Sendable {
    struct Call: Equatable, Sendable {
        let destination: String
        let port: Int?
        let identity: String?
    }

    private let lock = NSLock()
    private var recordedCalls: [Call] = []

    var calls: [Call] {
        lock.withLock { recordedCalls }
    }

    func record(destination: String, port: Int?, identity: String?) {
        lock.withLock {
            recordedCalls.append(Call(destination: destination, port: port, identity: identity))
        }
    }
}
