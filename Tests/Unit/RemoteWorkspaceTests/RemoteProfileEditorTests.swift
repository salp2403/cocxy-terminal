// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

private enum RemoteProfileEditorTestError: Error, LocalizedError {
    case diskFull

    var errorDescription: String? { "disk full" }
}

@Suite("Remote profile editor")
struct RemoteProfileEditorTests {
    @Test("Only local and remote forwards are creatable")
    func creatableForwardTypes() {
        #expect(ForwardTypeOption.creatableCases == [.local, .remote])
        #expect(!ForwardTypeOption.creatableCases.contains(.dynamic))
    }

    @Test("Editable forwards reject invalid ports and retain legacy dynamic entries")
    func editableForwardValidation() {
        var forward = EditablePortForward()
        forward.type = .local
        forward.localPort = "65536"
        forward.remotePort = "443"
        #expect(forward.toPortForward() == nil)

        forward.localPort = "8443"
        forward.remotePort = "0"
        #expect(forward.toPortForward() == nil)

        forward.remotePort = "443"
        forward.remoteHost = "   "
        #expect(forward.toPortForward() == nil)

        forward.type = .dynamic
        forward.localPort = "1080"
        #expect(forward.toPortForward() == .dynamic(localPort: 1_080))
    }

    @Test("Switching forward direction does not reinterpret a hidden target host")
    func switchingForwardDirectionPreservesHosts() {
        var forward = EditablePortForward(
            from: .local(localPort: 8_080, remotePort: 5432, remoteHost: "db.internal")
        )

        forward.type = .remote
        #expect(
            forward.toPortForward()
                == .remote(remotePort: 5432, localPort: 8_080, localHost: "localhost")
        )

        forward.localHost = "127.0.0.2"
        forward.type = .local
        #expect(
            forward.toPortForward()
                == .local(localPort: 8_080, remotePort: 5432, remoteHost: "db.internal")
        )

        forward.type = .remote
        #expect(
            forward.toPortForward()
                == .remote(remotePort: 5432, localPort: 8_080, localHost: "127.0.0.2")
        )
    }

    @Test("Saving preserves disabled dynamic forwards, custom hosts, and SSH policy")
    @MainActor func savingLegacyProfile() throws {
        let profile = RemoteConnectionProfile(
            id: UUID(),
            name: "Legacy",
            host: "legacy.example",
            portForwards: [
                .dynamic(localPort: 1_080),
                .local(localPort: 8_080, remotePort: 80, remoteHost: "web.internal"),
                .remote(remotePort: 9_000, localPort: 9_001, localHost: "127.0.0.2"),
            ],
            strictHostKeyChecking: "yes",
            knownHostsFile: "/tmp/known-hosts",
            batchMode: true
        )
        let viewModel = RemoteProfileEditorViewModel(profile: profile)
        var savedProfile: RemoteConnectionProfile?
        viewModel.onSave = { savedProfile = $0 }

        #expect(viewModel.save())

        let saved = try #require(savedProfile)
        #expect(saved.id == profile.id)
        #expect(saved.portForwards == profile.portForwards)
        #expect(saved.strictHostKeyChecking == "yes")
        #expect(saved.knownHostsFile == "/tmp/known-hosts")
        #expect(saved.batchMode == true)
    }

    @Test("Invalid ports and duplicate environment keys block save")
    @MainActor func validatesPortAndEnvironment() throws {
        let viewModel = RemoteProfileEditorViewModel()
        viewModel.name = "Dev"
        viewModel.host = "dev.internal"
        viewModel.port = "70000"
        #expect(!viewModel.isValid)
        #expect(!viewModel.save())

        viewModel.port = "22"
        viewModel.environmentVariables = [
            EditableKeyValue(key: "MODE", value: "first"),
            EditableKeyValue(key: " MODE ", value: "last"),
        ]
        var savedProfile: RemoteConnectionProfile?
        viewModel.onSave = { savedProfile = $0 }
        #expect(!viewModel.isValid)
        #expect(viewModel.duplicateEnvironmentVariableIDs.count == 2)
        #expect(!viewModel.save())
        #expect(savedProfile == nil)

        viewModel.environmentVariables[1].key = "REGION"
        #expect(viewModel.isValid)
        #expect(viewModel.save())
        #expect(try #require(savedProfile).envVars == ["MODE": "first", "REGION": "last"])
    }

    @Test("Incomplete forwards and environment rows cannot disappear during save")
    @MainActor func incompleteRowsBlockSave() {
        let viewModel = RemoteProfileEditorViewModel()
        viewModel.name = "Dev"
        viewModel.host = "dev.internal"
        viewModel.portForwards = [EditablePortForward()]
        viewModel.environmentVariables = [EditableKeyValue(key: "", value: "production")]
        var saveCount = 0
        viewModel.onSave = { _ in saveCount += 1 }

        #expect(!viewModel.isValid)
        #expect(viewModel.invalidPortForwardIDs.count == 1)
        #expect(viewModel.invalidEnvironmentVariableIDs.count == 1)
        #expect(!viewModel.save())
        #expect(saveCount == 0)

        viewModel.portForwards[0].localPort = "8080"
        viewModel.portForwards[0].remotePort = "80"
        viewModel.environmentVariables[0].key = "MODE"
        #expect(viewModel.isValid)
        #expect(viewModel.save())
        #expect(saveCount == 1)
    }

    @Test("Persistence failure remains visible and does not report save success")
    @MainActor func persistenceFailure() {
        let viewModel = RemoteProfileEditorViewModel()
        viewModel.name = "Dev"
        viewModel.host = "dev.internal"
        viewModel.onSave = { _ in throw RemoteProfileEditorTestError.diskFull }

        #expect(!viewModel.save())
        #expect(viewModel.saveErrorMessage == "disk full")
    }
}
