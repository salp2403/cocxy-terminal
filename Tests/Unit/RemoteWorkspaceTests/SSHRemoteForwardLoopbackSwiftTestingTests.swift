// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// SSHRemoteForwardLoopbackSwiftTestingTests.swift - Exact reverse-forward bind coverage.

import Testing
@testable import CocxyTerminal

extension SSHMultiplexerTests {
    @Test func remoteForwardSendsExactLoopbackBind() throws {
        let executor = MockProcessExecutor()
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com", user: "root")
        let forward = RemoteConnectionProfile.PortForward.remote(
            remotePort: 9090,
            localPort: 3000,
            localHost: "127.0.0.1",
            remoteBindHost: "127.0.0.1"
        )

        try multiplexer.forwardPort(forward, on: profile, executor: executor)

        let call = try #require(executor.executedCommands.first)
        #expect(call.arguments.contains("-R"))
        #expect(call.arguments.contains("127.0.0.1:9090:127.0.0.1:3000"))
    }

    @Test func remoteForwardRejectsWildcardAndIPv6BindsWithoutExecutingSSH() {
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")

        for bindHost in ["0.0.0.0", "::", "::1", "localhost"] {
            let executor = MockProcessExecutor()
            let forward = RemoteConnectionProfile.PortForward.remote(
                remotePort: 9090,
                localPort: 3000,
                remoteBindHost: bindHost
            )
            #expect(throws: SSHMultiplexerError.self) {
                try multiplexer.forwardPort(forward, on: profile, executor: executor)
            }
            #expect(executor.executedCommands.isEmpty)
        }
    }
}
