// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// EditableRemoteProfileModels.swift - Mutable remote-profile form models.

import Foundation

struct EditablePortForward: Identifiable {
    let id = UUID()
    var type: ForwardTypeOption = .local
    var localPort: String = ""
    var remotePort: String = ""
    var localHost: String = "localhost"
    var remoteHost: String = "localhost"
    var remoteBindHost: String = RemoteConnectionProfile.PortForward.remoteLoopbackBindHost

    init() {}

    init(from forward: RemoteConnectionProfile.PortForward) {
        switch forward {
        case let .local(localPort, remotePort, remoteHost):
            type = .local
            self.localPort = String(localPort)
            self.remotePort = String(remotePort)
            self.remoteHost = remoteHost
        case let .remote(remotePort, localPort, localHost, remoteBindHost):
            type = .remote
            self.localPort = String(localPort)
            self.remotePort = String(remotePort)
            self.localHost = localHost
            self.remoteBindHost = remoteBindHost
        case let .dynamic(localPort):
            type = .dynamic
            self.localPort = String(localPort)
        }
    }

    var isValid: Bool { toPortForward() != nil }

    func toPortForward() -> RemoteConnectionProfile.PortForward? {
        let trimmedLocalPort = localPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let localPort = Int(trimmedLocalPort), (1...65_535).contains(localPort) else {
            return nil
        }

        switch type {
        case .local:
            let targetHost = remoteHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedRemotePort = remotePort.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !targetHost.isEmpty,
                  let remotePort = Int(trimmedRemotePort),
                  (1...65_535).contains(remotePort) else { return nil }
            return .local(
                localPort: localPort,
                remotePort: remotePort,
                remoteHost: targetHost
            )
        case .remote:
            let targetHost = localHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let bindHost = remoteBindHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedRemotePort = remotePort.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !targetHost.isEmpty,
                  bindHost == RemoteConnectionProfile.PortForward.remoteLoopbackBindHost,
                  let remotePort = Int(trimmedRemotePort),
                  (1...65_535).contains(remotePort) else { return nil }
            return .remote(
                remotePort: remotePort,
                localPort: localPort,
                localHost: targetHost,
                remoteBindHost: bindHost
            )
        case .dynamic:
            return .dynamic(localPort: localPort)
        }
    }
}

struct EditableKeyValue: Identifiable {
    let id = UUID()
    var key: String = ""
    var value: String = ""
}
