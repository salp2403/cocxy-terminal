// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("CocxyDRemoteCLIRelay", .serialized)
struct CocxyDRemoteCLIRelaySwiftTestingTests {

    @Test("signs and validates command relay request")
    func signsAndValidatesRelayRequest() throws {
        let token = RelayToken(secret: Data(repeating: 7, count: 32))
        let relay = CocxyDRemoteCLIRelay(token: token)
        let request = try relay.makeSignedRequest(
            command: "status",
            arguments: ["--json"],
            timestamp: 1_778_693_000
        )

        #expect(relay.validate(request))
    }

    @Test("rejects tampered relay request")
    func rejectsTamperedRelayRequest() throws {
        let token = RelayToken(secret: Data(repeating: 8, count: 32))
        let relay = CocxyDRemoteCLIRelay(token: token)
        var request = try relay.makeSignedRequest(command: "status", arguments: [], timestamp: 1)
        request.arguments = ["--changed"]

        #expect(!relay.validate(request))
    }

    @Test("reverse forward arguments disable ControlMaster socket reuse")
    func reverseForwardArgumentsDisableControlMasterReuse() {
        let args = CocxyDRemoteCLIRelay.reverseForwardArguments(localPort: 55000, remotePort: 54000)

        #expect(args.contains("-R"))
        #expect(args.contains("54000:127.0.0.1:55000"))
        #expect(args.contains("-S"))
        #expect(args.contains("none"))
    }

    @Test("relay environment exposes authenticated local socket")
    func relayEnvironmentExposesAuthenticatedSocket() {
        let env = CocxyDRemoteCLIRelay.environment(localPort: 55000, tokenID: "relay-1")

        #expect(env["COCXY_RELAY_URL"] == "tcp://127.0.0.1:55000")
        #expect(env["COCXY_RELAY_TOKEN_ID"] == "relay-1")
    }
}
