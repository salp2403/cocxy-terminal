// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("MainWindowController remote session attach")
@MainActor
struct RemoteSessionAttachSwiftTestingTests {
    @Test("daemon attach retains transport and detaches when its tab closes")
    func daemonAttachLifecycle() async throws {
        let defaultEngine = MockTerminalEngine()
        let inProcessBridge = try makeRemoteSessionTestBridge()
        let controller = MainWindowController(
            bridge: defaultEngine,
            terminalEngineFactory: { preference in
                preference == .inProcess ? inProcessBridge : nil
            }
        )
        let connection = RecordingRemoteSessionConnection()
        let viewModel = RemoteDaemonTerminalViewModel(
            sessionBridge: DaemonSessionBridge(
                connection: connection,
                activePollIntervalNanoseconds: 1_000_000,
                idlePollIntervalNanoseconds: 1_000_000
            )
        )

        let tabID = try await controller.openRemoteDaemonTerminal(
            viewModel: viewModel,
            action: .attach(sessionID: "remote-1"),
            title: "Remote Build"
        )
        let surfaceID = try #require(controller.tabSurfaceMap[tabID])

        #expect(controller.remoteDaemonTerminalViewModels[surfaceID] === viewModel)
        #expect(controller.terminalEngine(for: surfaceID) === inProcessBridge)
        #expect(controller.tabManager.tab(for: tabID)?.displayTitle == "Remote Build")
        #expect(connection.calls.contains {
            $0.command == DaemonCommand.sessionAttach.rawValue
                && $0.arguments == ["id": "remote-1"]
        })

        inProcessBridge.sendText("pwd\r", to: surfaceID)
        inProcessBridge.resize(
            surfaceID,
            to: TerminalSize(
                columns: 120,
                rows: 40,
                pixelWidth: 1_200,
                pixelHeight: 800
            )
        )
        try await waitForRemoteSessionCondition {
            connection.calls.contains {
                $0.command == DaemonCommand.sessionInput.rawValue
                    && $0.arguments?["data"] == Data("pwd\r".utf8).base64EncodedString()
            }
        }
        try await waitForRemoteSessionCondition {
            connection.calls.contains {
                $0.command == DaemonCommand.sessionResize.rawValue
                    && Int($0.arguments?["cols"] ?? "") != nil
                    && Int($0.arguments?["rows"] ?? "") != nil
            }
        }

        controller.performCloseTab(tabID)
        try await waitForRemoteSessionCondition {
            connection.calls.contains {
                $0.command == DaemonCommand.sessionDetach.rawValue
                    && $0.arguments == ["id": "remote-1"]
            }
        }

        #expect(controller.remoteDaemonTerminalViewModels[surfaceID] == nil)
        #expect(controller.tabSurfaceMap[tabID] == nil)
    }

    @Test("daemon create opens and attaches the returned session")
    func daemonCreateAndAttach() async throws {
        let defaultEngine = MockTerminalEngine()
        let inProcessBridge = try makeRemoteSessionTestBridge()
        let controller = MainWindowController(
            bridge: defaultEngine,
            terminalEngineFactory: { preference in
                preference == .inProcess ? inProcessBridge : nil
            }
        )
        let connection = RecordingRemoteSessionConnection()
        let viewModel = RemoteDaemonTerminalViewModel(
            sessionBridge: DaemonSessionBridge(
                connection: connection,
                activePollIntervalNanoseconds: 1_000_000,
                idlePollIntervalNanoseconds: 1_000_000
            )
        )

        let tabID = try await controller.openRemoteDaemonTerminal(
            viewModel: viewModel,
            action: .create(title: "Deploy"),
            title: "Deploy"
        )

        #expect(connection.calls.contains {
            $0.command == DaemonCommand.sessionCreate.rawValue
                && $0.arguments == ["title": "Deploy"]
        })
        #expect(connection.calls.contains {
            $0.command == DaemonCommand.sessionAttach.rawValue
                && $0.arguments == ["id": "created-session"]
        })
        #expect(controller.tabManager.tab(for: tabID)?.displayTitle == "Deploy")

        controller.performCloseTab(tabID)
    }

    @Test("invalid daemon session names fail before creating a tab")
    func invalidDaemonSessionNameRollsBackBeforeCreation() async throws {
        let defaultEngine = MockTerminalEngine()
        let inProcessBridge = try makeRemoteSessionTestBridge()
        let controller = MainWindowController(
            bridge: defaultEngine,
            terminalEngineFactory: { preference in
                preference == .inProcess ? inProcessBridge : nil
            }
        )
        let connection = RecordingRemoteSessionConnection()
        let viewModel = RemoteDaemonTerminalViewModel(
            sessionBridge: DaemonSessionBridge(connection: connection)
        )
        let initialTabIDs = controller.tabManager.tabs.map(\.id)

        do {
            _ = try await controller.openRemoteDaemonTerminal(
                viewModel: viewModel,
                action: .create(title: "invalid session"),
                title: "invalid session"
            )
            Issue.record("Expected invalid daemon session name to fail")
        } catch {
            #expect(error.localizedDescription.contains("1-128"))
        }

        #expect(controller.tabManager.tabs.map(\.id) == initialTabIDs)
        #expect(connection.calls.isEmpty)
        #expect(controller.remoteDaemonTerminalViewModels.isEmpty)
    }

    @Test("tmux attach sends the validated command to the new in-process tab")
    func tmuxAttachTabSendsCommand() async throws {
        let defaultEngine = MockTerminalEngine()
        let inProcessEngine = MockTerminalEngine()
        let controller = MainWindowController(
            bridge: defaultEngine,
            terminalEngineFactory: { preference in
                preference == .inProcess ? inProcessEngine : nil
            }
        )
        let command = "/usr/bin/ssh -t -- root@example.test 'tmux attach-session -t dev'"

        let tabID = try #require(controller.openRemoteTmuxAttachTab(
            command: command,
            title: "dev",
            delayNanoseconds: 0
        ))
        let surfaceID = try #require(controller.tabSurfaceMap[tabID])
        try await waitForRemoteSessionCondition {
            inProcessEngine.sentTexts.contains {
                $0.surface == surfaceID && $0.text == command + "\r"
            }
        }

        #expect(controller.terminalEngine(for: surfaceID) === inProcessEngine)
        #expect(defaultEngine.sentTexts.isEmpty)
        #expect(controller.tabManager.tab(for: tabID)?.displayTitle == "dev")
        controller.performCloseTab(tabID)
    }
}

@MainActor
private final class RecordingRemoteSessionConnection: DaemonSessionRPCSending {
    struct Call: Equatable {
        let command: String
        let arguments: [String: String]?
    }

    var isConnected = true
    private(set) var calls: [Call] = []

    func sendSessionRPC(
        cmd: String,
        args: [String: String]?
    ) async throws -> DaemonResponse {
        calls.append(Call(command: cmd, arguments: args))
        switch cmd {
        case DaemonCommand.sessionCreate.rawValue:
            return response(data: ["id": "created-session"])
        case DaemonCommand.sessionOutput.rawValue:
            return response(data: ["data": "", "mode": "snapshot"])
        default:
            return response(data: [:])
        }
    }

    private func response(data: [String: Any]) -> DaemonResponse {
        DaemonResponse(ok: true, id: "test", data: data, error: nil)
    }
}

@MainActor
private func makeRemoteSessionTestBridge() throws -> CocxyCoreBridge {
    let bridge = CocxyCoreBridge()
    try bridge.initialize(config: TerminalEngineConfig(
        fontFamily: "Menlo",
        fontSize: 14,
        themeName: "Test",
        shell: "/bin/zsh",
        workingDirectory: URL(fileURLWithPath: NSTemporaryDirectory()),
        windowPaddingX: 8,
        windowPaddingY: 4
    ))
    return bridge
}

@MainActor
private func waitForRemoteSessionCondition(
    timeoutNanoseconds: UInt64 = 15_000_000_000,
    condition: @escaping @MainActor () -> Bool
) async throws {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if condition() { return }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    #expect(condition())
}
