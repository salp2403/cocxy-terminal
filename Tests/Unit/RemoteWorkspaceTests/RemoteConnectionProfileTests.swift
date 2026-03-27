// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// RemoteConnectionProfileTests.swift - Tests for the remote connection profile model.

import Foundation
import Testing
@testable import CocxyTerminal

// MARK: - Remote Connection Profile Tests

@Suite("RemoteConnectionProfile")
struct RemoteConnectionProfileTests {

    // MARK: - Creation

    @Test func creationWithDefaultValues() {
        let profile = RemoteConnectionProfile(name: "dev-server", host: "example.com")

        #expect(profile.name == "dev-server")
        #expect(profile.host == "example.com")
        #expect(profile.user == nil)
        #expect(profile.port == nil)
        #expect(profile.identityFile == nil)
        #expect(profile.jumpHosts.isEmpty)
        #expect(profile.portForwards.isEmpty)
        #expect(profile.group == nil)
        #expect(profile.envVars.isEmpty)
        #expect(profile.keepAliveInterval == 60)
        #expect(profile.autoReconnect == true)
    }

    @Test func creationWithAllFields() {
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 8080, remotePort: 80
        )
        let profile = RemoteConnectionProfile(
            name: "production",
            host: "prod.example.com",
            user: "deploy",
            port: 2222,
            identityFile: "~/.ssh/deploy_key",
            jumpHosts: ["bastion.example.com"],
            portForwards: [forward],
            group: "production",
            envVars: ["ENV": "prod"],
            keepAliveInterval: 30,
            autoReconnect: false
        )

        #expect(profile.name == "production")
        #expect(profile.host == "prod.example.com")
        #expect(profile.user == "deploy")
        #expect(profile.port == 2222)
        #expect(profile.identityFile == "~/.ssh/deploy_key")
        #expect(profile.jumpHosts == ["bastion.example.com"])
        #expect(profile.portForwards.count == 1)
        #expect(profile.group == "production")
        #expect(profile.envVars["ENV"] == "prod")
        #expect(profile.keepAliveInterval == 30)
        #expect(profile.autoReconnect == false)
    }

    @Test func creationGeneratesUniqueIDs() {
        let profile1 = RemoteConnectionProfile(name: "a", host: "host-a")
        let profile2 = RemoteConnectionProfile(name: "b", host: "host-b")

        #expect(profile1.id != profile2.id)
    }

    // MARK: - Codable Round-trip

    @Test func codableRoundTrip() throws {
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 3000, remotePort: 3000
        )
        let original = RemoteConnectionProfile(
            name: "staging",
            host: "staging.example.com",
            user: "admin",
            port: 22,
            identityFile: "~/.ssh/id_ed25519",
            jumpHosts: ["bastion1", "bastion2"],
            portForwards: [forward],
            group: "staging",
            envVars: ["RAILS_ENV": "staging"],
            keepAliveInterval: 45,
            autoReconnect: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteConnectionProfile.self, from: data)

        #expect(original == decoded)
    }

    @Test func codableRoundTripWithMinimalFields() throws {
        let original = RemoteConnectionProfile(name: "minimal", host: "host.local")

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteConnectionProfile.self, from: data)

        #expect(original == decoded)
        #expect(decoded.user == nil)
        #expect(decoded.port == nil)
        #expect(decoded.identityFile == nil)
        #expect(decoded.jumpHosts.isEmpty)
    }

    @Test func codableRoundTripWithAllPortForwardTypes() throws {
        let forwards: [RemoteConnectionProfile.PortForward] = [
            .local(localPort: 8080, remotePort: 80),
            .local(localPort: 3000, remotePort: 3000, remoteHost: "db.internal"),
            .remote(remotePort: 9090, localPort: 9090),
            .remote(remotePort: 5432, localPort: 5432, localHost: "db.local"),
            .dynamic(localPort: 1080),
        ]
        let original = RemoteConnectionProfile(
            name: "all-forwards",
            host: "server.com",
            portForwards: forwards
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RemoteConnectionProfile.self, from: data)

        #expect(original == decoded)
        #expect(decoded.portForwards.count == 5)
    }

    // MARK: - Display Title

    @Test func displayTitleWithUserAndDefaultPort() {
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "root"
        )

        #expect(profile.displayTitle == "root@server.com")
    }

    @Test func displayTitleWithUserAndCustomPort() {
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "root", port: 2222
        )

        #expect(profile.displayTitle == "root@server.com:2222")
    }

    @Test func displayTitleWithoutUser() {
        let profile = RemoteConnectionProfile(name: "dev", host: "server.com")

        #expect(profile.displayTitle == "server.com")
    }

    @Test func displayTitleWithoutUserButWithPort() {
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", port: 2222
        )

        #expect(profile.displayTitle == "server.com:2222")
    }

    @Test func displayTitleIgnoresDefaultPort22() {
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "root", port: 22
        )

        #expect(profile.displayTitle == "root@server.com")
    }

    // MARK: - SSH Command Generation

    @Test func sshCommandMinimal() {
        let profile = RemoteConnectionProfile(name: "dev", host: "example.com")

        let command = profile.sshCommand
        #expect(command.hasPrefix("ssh "))
        #expect(command.hasSuffix("example.com"))
        #expect(command.contains("-o ServerAliveInterval=60"))
    }

    @Test func sshCommandWithUser() {
        let profile = RemoteConnectionProfile(
            name: "dev", host: "example.com", user: "deploy"
        )

        let command = profile.sshCommand
        #expect(command.hasSuffix("deploy@example.com"))
        #expect(command.contains("-o ServerAliveInterval=60"))
    }

    @Test func sshCommandWithPort() {
        let profile = RemoteConnectionProfile(
            name: "dev", host: "example.com", user: "deploy", port: 2222
        )

        let command = profile.sshCommand
        #expect(command.contains("-p 2222"))
        #expect(command.contains("deploy@example.com"))
    }

    @Test func sshCommandWithIdentityFile() {
        let profile = RemoteConnectionProfile(
            name: "dev",
            host: "example.com",
            user: "deploy",
            identityFile: "~/.ssh/deploy_key"
        )

        let command = profile.sshCommand
        #expect(command.contains("-i ~/.ssh/deploy_key"))
        #expect(command.contains("deploy@example.com"))
    }

    @Test func sshCommandWithJumpHosts() {
        let profile = RemoteConnectionProfile(
            name: "dev",
            host: "internal.server",
            user: "admin",
            jumpHosts: ["bastion1.com", "bastion2.com"]
        )

        let command = profile.sshCommand
        #expect(command.contains("-J bastion1.com,bastion2.com"))
    }

    @Test func sshCommandWithLocalPortForward() {
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 8080, remotePort: 80
        )
        let profile = RemoteConnectionProfile(
            name: "dev",
            host: "example.com",
            portForwards: [forward]
        )

        let command = profile.sshCommand
        #expect(command.contains("-L 8080:localhost:80"))
    }

    @Test func sshCommandWithRemotePortForward() {
        let forward = RemoteConnectionProfile.PortForward.remote(
            remotePort: 9090, localPort: 3000
        )
        let profile = RemoteConnectionProfile(
            name: "dev",
            host: "example.com",
            portForwards: [forward]
        )

        let command = profile.sshCommand
        #expect(command.contains("-R 9090:localhost:3000"))
    }

    @Test func sshCommandWithDynamicForward() {
        let forward = RemoteConnectionProfile.PortForward.dynamic(localPort: 1080)
        let profile = RemoteConnectionProfile(
            name: "dev",
            host: "example.com",
            portForwards: [forward]
        )

        let command = profile.sshCommand
        #expect(command.contains("-D 1080"))
    }

    @Test func sshCommandWithKeepAlive() {
        let profile = RemoteConnectionProfile(
            name: "dev",
            host: "example.com",
            keepAliveInterval: 30
        )

        let command = profile.sshCommand
        #expect(command.contains("-o ServerAliveInterval=30"))
    }

    @Test func sshCommandWithEnvironmentVariables() {
        let profile = RemoteConnectionProfile(
            name: "dev",
            host: "example.com",
            envVars: ["RAILS_ENV": "production"]
        )

        let command = profile.sshCommand
        #expect(command.contains("-o SendEnv=RAILS_ENV"))
    }

    @Test func sshCommandComplexProfile() {
        let forwards: [RemoteConnectionProfile.PortForward] = [
            .local(localPort: 3000, remotePort: 3000),
            .dynamic(localPort: 1080),
        ]
        let profile = RemoteConnectionProfile(
            name: "full",
            host: "prod.server.com",
            user: "deploy",
            port: 2222,
            identityFile: "~/.ssh/prod_key",
            jumpHosts: ["bastion.com"],
            portForwards: forwards,
            envVars: ["ENV": "prod"],
            keepAliveInterval: 45
        )

        let command = profile.sshCommand
        #expect(command.hasPrefix("ssh "))
        #expect(command.contains("-p 2222"))
        #expect(command.contains("-i ~/.ssh/prod_key"))
        #expect(command.contains("-J bastion.com"))
        #expect(command.contains("-L 3000:localhost:3000"))
        #expect(command.contains("-D 1080"))
        #expect(command.contains("-o ServerAliveInterval=45"))
        #expect(command.contains("-o SendEnv=ENV"))
        #expect(command.hasSuffix("deploy@prod.server.com"))
    }

    // MARK: - Control Path

    @Test func controlPathWithUserAndPort() {
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "root", port: 2222
        )
        let home = NSHomeDirectory()

        #expect(profile.controlPath == "\(home)/.config/cocxy/sockets/root@server.com:2222")
    }

    @Test func controlPathWithoutUser() {
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com"
        )
        let home = NSHomeDirectory()

        #expect(profile.controlPath == "\(home)/.config/cocxy/sockets/server.com:22")
    }

    @Test func controlPathDefaultsPort22() {
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "admin"
        )
        let home = NSHomeDirectory()

        #expect(profile.controlPath == "\(home)/.config/cocxy/sockets/admin@server.com:22")
    }

    @Test func controlPathIsAbsoluteNotTilde() {
        let profile = RemoteConnectionProfile(
            name: "dev", host: "server.com", user: "root"
        )

        #expect(!profile.controlPath.contains("~"))
        #expect(profile.controlPath.hasPrefix("/"))
    }

    // MARK: - Port Forward SSH Flags

    @Test func localForwardSSHFlag() {
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 8080, remotePort: 80
        )
        #expect(forward.sshFlag == "-L 8080:localhost:80")
    }

    @Test func localForwardSSHFlagWithCustomRemoteHost() {
        let forward = RemoteConnectionProfile.PortForward.local(
            localPort: 5432, remotePort: 5432, remoteHost: "db.internal"
        )
        #expect(forward.sshFlag == "-L 5432:db.internal:5432")
    }

    @Test func remoteForwardSSHFlag() {
        let forward = RemoteConnectionProfile.PortForward.remote(
            remotePort: 9090, localPort: 3000
        )
        #expect(forward.sshFlag == "-R 9090:localhost:3000")
    }

    @Test func remoteForwardSSHFlagWithCustomLocalHost() {
        let forward = RemoteConnectionProfile.PortForward.remote(
            remotePort: 5432, localPort: 5432, localHost: "db.local"
        )
        #expect(forward.sshFlag == "-R 5432:db.local:5432")
    }

    @Test func dynamicForwardSSHFlag() {
        let forward = RemoteConnectionProfile.PortForward.dynamic(localPort: 1080)
        #expect(forward.sshFlag == "-D 1080")
    }

    // MARK: - Equatable

    @Test func profilesWithSameIDAndFieldsAreEqual() {
        let id = UUID()
        let profile1 = RemoteConnectionProfile(
            id: id, name: "dev", host: "server.com", user: "root"
        )
        let profile2 = RemoteConnectionProfile(
            id: id, name: "dev", host: "server.com", user: "root"
        )
        #expect(profile1 == profile2)
    }

    @Test func profilesWithDifferentNamesAreNotEqual() {
        let id = UUID()
        let profile1 = RemoteConnectionProfile(id: id, name: "dev", host: "server.com")
        let profile2 = RemoteConnectionProfile(id: id, name: "staging", host: "server.com")
        #expect(profile1 != profile2)
    }
}
