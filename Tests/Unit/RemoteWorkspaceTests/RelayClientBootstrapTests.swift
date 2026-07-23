// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("RelayClientBootstrap")
struct RelayClientBootstrapTests {
    @Test("Generated command contains a complete authenticated relay client")
    func generatedCommand() throws {
        let channelID = UUID()
        let token = RelayToken(secret: Data(repeating: 0x2a, count: 32))
        let command = RelayClientBootstrap(
            channelID: channelID,
            remotePort: 9000
        ).shellCommand()
        let prefix = "base64.b64decode(\""
        let start = try #require(command.range(of: prefix)?.upperBound)
        let suffix = try #require(command[start...].firstIndex(of: "\""))
        let encoded = String(command[start..<suffix])
        let data = try #require(Data(base64Encoded: encoded))
        let script = try #require(String(data: data, encoding: .utf8))

        #expect(command.hasPrefix("python3 -c"))
        #expect(script.contains(channelID.uuidString))
        #expect(!command.contains(token.secret.base64EncodedString()))
        #expect(script.contains("getpass.getpass(\"Relay token: \""))
        #expect(script.contains("COCXY_RELAY_TOKEN"))
        #expect(script.contains("os.urandom(16)"))
        #expect(script.contains("struct.pack(\">I\", len(payload))"))
        #expect(script.contains("socket.create_connection((\"127.0.0.1\", 9000))"))
        #expect(script.contains("select.select"))
        #expect(script.contains("readers.remove(relay)"))
        #expect(script.contains("relay.shutdown(socket.SHUT_WR)"))
        #expect(!script.contains("if not data:\n                    break"))
    }

    @Test("Manager provisions a client command only for active channels")
    @MainActor func managerProvisioning() async throws {
        let forwarder = MockPortForwarder()
        let manager = RelayManagerImpl(
            tunnelManager: SSHTunnelManager(),
            forwarder: forwarder
        )
        #expect(manager.clientCommand(for: UUID()) == nil)
        let channel = try await manager.openChannel(
            config: RelayChannelConfig(name: "api", localPort: 3000, remotePort: 9000),
            profileID: UUID()
        )

        let command = try #require(manager.clientCommand(for: channel.id))
        #expect(command.contains("python3 -c"))
        #expect(manager.clientToken(for: channel.id) != nil)
        await manager.closeChannel(channelID: channel.id)
    }
}
