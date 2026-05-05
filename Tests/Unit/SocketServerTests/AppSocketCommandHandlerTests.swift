// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// AppSocketCommandHandlerTests.swift - Tests for the socket command dispatcher.

import Darwin
import XCTest
@testable import CocxyTerminal

// MARK: - App Socket Command Handler Tests

/// Tests for `AppSocketCommandHandler` covering all command groups:
/// - Tab operations (focus, close, new, rename, move)
/// - Config operations (get, set, path)
/// - Theme operations (list, set)
/// - Acknowledged commands (async UI actions)
///
/// Each test creates the handler on @MainActor so that the closure
/// providers can safely capture TabManager state.
final class AppSocketCommandHandlerTests: XCTestCase {

    private func temporaryDirectory(_ name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-app-socket-handler-tests", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Existing Handler Tests (moved from PreferencesViewTests)

    func test_unknownCommand_returnsFailure() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "test-1", command: "unknown-command", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertFalse(response.success)
        XCTAssertNotNil(response.error)
    }

    @MainActor
    func test_statusCommand_returnsRunning() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(id: "test-2", command: "status", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "running")
        XCTAssertEqual(response.data?["version"], CocxyVersion.current)
    }

    @MainActor
    func test_statusCommand_mergesCocxyCoreDiagnosticsWithoutOverwritingBaseStatus() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(
            tabManager: tabManager,
            hookEventReceiver: nil,
            statusDetailsProvider: {
                [
                    "web_running": "true",
                    "web_bind": "127.0.0.1",
                    "web_port": "7770",
                    "current_stream_id": "2",
                    "color_space": "srgb",
                    "wide_gamut": "true",
                    "high_contrast": "false"
                ]
            }
        )

        let response = handler.handleCommand(SocketRequest(id: "test-2b", command: "status", params: nil))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "running")
        XCTAssertEqual(response.data?["web_running"], "true")
        XCTAssertEqual(response.data?["current_stream_id"], "2")
        XCTAssertEqual(response.data?["color_space"], "srgb")
        XCTAssertEqual(response.data?["wide_gamut"], "true")
        XCTAssertEqual(response.data?["high_contrast"], "false")
    }

    @MainActor
    func test_statusCommand_canReturnLaunchWarmupSnapshot() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            tabCountProviderOverride: { 0 },
            statusDetailsProvider: {
                ["launch_status": "warming"]
            }
        )

        let response = handler.handleCommand(SocketRequest(id: "test-2c", command: "status", params: nil))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "running")
        XCTAssertEqual(response.data?["tabs"], "0")
        XCTAssertEqual(response.data?["launch_status"], "warming")
    }

    @MainActor
    func test_listTabsCommand_returnsTabInfo() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(id: "test-3", command: "list-tabs", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["count"], "1")
    }

    func test_hookEventCommand_withoutReceiver_returnsFailure() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "test-4", command: "hook-event", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertFalse(response.success)
    }

    func test_hookEventCommand_withMissingPayload_returnsFailure() {
        let receiver = HookEventReceiverImpl()
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: receiver)
        let request = SocketRequest(id: "test-5", command: "hook-event", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertFalse(response.success)
    }

    func test_hookEventCommand_withInvalidPayload_returnsFailure() {
        let receiver = HookEventReceiverImpl()
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: receiver)
        let request = SocketRequest(
            id: "test-6",
            command: "hook-event",
            params: ["payload": "not-valid-json"]
        )
        let response = handler.handleCommand(request)
        XCTAssertFalse(response.success)
    }

    func test_worktreeFocus_routesToWorktreeProvider() {
        let captured = LockedBox<(kind: String?, params: [String: String]?)>((nil, nil))
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            worktreeCLIProvider: { kind, params in
                captured.withValue { value in
                    value = (kind, params)
                }
                return (
                    success: true,
                    data: [
                        "id": params["id"] ?? "",
                        "status": "focused"
                    ]
                )
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "wt-focus-1",
            command: "worktree-focus",
            params: ["id": "abc123"]
        ))

        XCTAssertTrue(response.success)
        let snapshot = captured.withValue { $0 }
        XCTAssertEqual(snapshot.kind, "focus")
        XCTAssertEqual(snapshot.params?["id"], "abc123")
        XCTAssertEqual(response.data?["status"], "focused")
    }

    func test_worktreeCleanupMerged_routesToWorktreeProvider() {
        let captured = LockedBox<(kind: String?, params: [String: String]?)>((nil, nil))
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            worktreeCLIProvider: { kind, params in
                captured.withValue { value in
                    value = (kind, params)
                }
                return (
                    success: true,
                    data: [
                        "status": "dry-run",
                        "removed-count": "2",
                        "blocked-count": "0",
                        "skipped-count": "1"
                    ]
                )
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "wt-cleanup-1",
            command: "worktree-cleanup-merged",
            params: ["base-ref": "main", "dry-run": "true"]
        ))

        XCTAssertTrue(response.success)
        let snapshot = captured.withValue { $0 }
        XCTAssertEqual(snapshot.kind, "cleanup-merged")
        XCTAssertEqual(snapshot.params?["base-ref"], "main")
        XCTAssertEqual(snapshot.params?["dry-run"], "true")
        XCTAssertEqual(response.data?["removed-count"], "2")
    }

    @MainActor
    func test_pluginMarketplaceCommands_useInjectedLocalStores() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let repo = root.appendingPathComponent("sample-plugin", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try """
        name = "Sample Plugin"
        version = "1.0.0"
        author = "Dev"
        events = ["session-start"]
        capabilities = ["environment-read"]
        """.write(
            to: repo.appendingPathComponent(PluginManifest.marketplaceManifestFileName),
            atomically: true,
            encoding: .utf8
        )

        let pluginsDirectory = root.appendingPathComponent("plugins", isDirectory: true)
        let manager = PluginManager(pluginsDirectory: pluginsDirectory.path)
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            pluginManagerProvider: { manager },
            pluginSourceStoreProvider: {
                PluginSourceStore(fileURL: root.appendingPathComponent("sources.json"))
            },
            pluginInstallerProvider: {
                PluginInstaller(pluginsDirectory: pluginsDirectory)
            }
        )

        let addResponse = handler.handleCommand(SocketRequest(
            id: "plugin-source-add-1",
            command: "plugin-source-add",
            params: ["url": repo.path, "name": "Local sample"]
        ))
        XCTAssertTrue(addResponse.success)

        let sourceListResponse = handler.handleCommand(SocketRequest(
            id: "plugin-source-list-1",
            command: "plugin-source-list",
            params: nil
        ))
        XCTAssertTrue(sourceListResponse.success)
        XCTAssertEqual(sourceListResponse.data?["count"], "1")
        XCTAssertEqual(sourceListResponse.data?["source_0_name"], "Local sample")

        let installResponse = handler.handleCommand(SocketRequest(
            id: "plugin-install-1",
            command: "plugin-install",
            params: ["url": repo.path]
        ))
        XCTAssertTrue(installResponse.success)
        XCTAssertEqual(installResponse.data?["plugin"], "sample-plugin")

        let listResponse = handler.handleCommand(SocketRequest(
            id: "plugin-list-1",
            command: "plugin-list",
            params: nil
        ))
        XCTAssertTrue(listResponse.success)
        XCTAssertEqual(listResponse.data?["count"], "1")
        XCTAssertEqual(listResponse.data?["plugin_0_id"], "sample-plugin")

        let enableResponse = handler.handleCommand(SocketRequest(
            id: "plugin-enable-1",
            command: "plugin-enable",
            params: ["id": "sample-plugin"]
        ))
        XCTAssertTrue(enableResponse.success)

        let disableResponse = handler.handleCommand(SocketRequest(
            id: "plugin-disable-1",
            command: "plugin-disable",
            params: ["id": "sample-plugin"]
        ))
        XCTAssertTrue(disableResponse.success)

        let uninstallResponse = handler.handleCommand(SocketRequest(
            id: "plugin-uninstall-1",
            command: "plugin-uninstall",
            params: ["id": "sample-plugin"]
        ))
        XCTAssertTrue(uninstallResponse.success)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: pluginsDirectory.appendingPathComponent("sample-plugin").path
        ))
    }

    func test_reviewApprove_routesToGitHubProvider() {
        let captured = LockedBox<(kind: String?, params: [String: String]?)>((nil, nil))
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            githubCLIProvider: { kind, params in
                captured.withValue { value in
                    value = (kind, params)
                }
                return (
                    success: true,
                    data: ["summary": "Review approved for PR #42."]
                )
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "review-approve-1",
            command: "review-approve",
            params: ["pr": "42", "body": "Ship it"]
        ))

        XCTAssertTrue(response.success)
        let snapshot = captured.withValue { $0 }
        XCTAssertEqual(snapshot.kind, "review-approve")
        XCTAssertEqual(snapshot.params?["pr"], "42")
        XCTAssertEqual(snapshot.params?["body"], "Ship it")
        XCTAssertEqual(response.data?["summary"], "Review approved for PR #42.")
    }

    func test_tabConfigSave_routesNameCommandThemeAndEnvToProvider() {
        let captured = LockedBox<(name: String?, command: String?, theme: String?, env: [String: String])>(
            (nil, nil, nil, [:])
        )
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            tabConfigSaveProvider: { name, command, theme, environment in
                captured.withValue { value in
                    value = (name, command, theme, environment)
                }
                return (name: name, path: "/tmp/\(name).toml")
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "tab-config-save-1",
            command: "tab-config-save",
            params: [
                "name": "api",
                "command": "npm run dev",
                "theme": "Nord",
                "env.API_URL": "http://127.0.0.1:8080",
            ]
        ))

        XCTAssertTrue(response.success)
        let snapshot = captured.withValue { $0 }
        XCTAssertEqual(snapshot.name, "api")
        XCTAssertEqual(snapshot.command, "npm run dev")
        XCTAssertEqual(snapshot.theme, "Nord")
        XCTAssertEqual(snapshot.env, ["API_URL": "http://127.0.0.1:8080"])
        XCTAssertEqual(response.data?["path"], "/tmp/api.toml")
    }

    func test_tabConfigOpen_routesNameToProvider() {
        let captured = LockedBox<String?>(nil)
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            tabConfigOpenProvider: { name in
                captured.withValue { $0 = name }
                return (id: "tab-1", title: "api", path: "/tmp/api.toml")
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "tab-config-open-1",
            command: "tab-config-open",
            params: ["name": "api"]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(captured.withValue { $0 }, "api")
        XCTAssertEqual(response.data?["id"], "tab-1")
        XCTAssertEqual(response.data?["path"], "/tmp/api.toml")
    }

    func test_tabConfigExport_routesNameOutputAndForceToProvider() {
        let captured = LockedBox<(name: String?, output: String?, force: Bool?)>(
            (nil, nil, nil)
        )
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            tabConfigExportProvider: { name, output, force in
                captured.withValue { value in
                    value = (name, output, force)
                }
                return (name: name, path: output)
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "tab-config-export-1",
            command: "tab-config-export",
            params: [
                "name": "api",
                "output": "/tmp/shared-api.toml",
                "force": "true",
            ]
        ))

        XCTAssertTrue(response.success)
        let snapshot = captured.withValue { $0 }
        XCTAssertEqual(snapshot.name, "api")
        XCTAssertEqual(snapshot.output, "/tmp/shared-api.toml")
        XCTAssertEqual(snapshot.force, true)
        XCTAssertEqual(response.data?["path"], "/tmp/shared-api.toml")
    }

    func test_reviewRequestChanges_routesToGitHubProvider() {
        let captured = LockedBox<(kind: String?, params: [String: String]?)>((nil, nil))
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            githubCLIProvider: { kind, params in
                captured.withValue { value in
                    value = (kind, params)
                }
                return (
                    success: true,
                    data: ["summary": "Review changes requested for PR #42."]
                )
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "review-request-changes-1",
            command: "review-request-changes",
            params: ["pr": "42", "body": "Please fix the failing check."]
        ))

        XCTAssertTrue(response.success)
        let snapshot = captured.withValue { $0 }
        XCTAssertEqual(snapshot.kind, "review-request-changes")
        XCTAssertEqual(snapshot.params?["pr"], "42")
        XCTAssertEqual(snapshot.params?["body"], "Please fix the failing check.")
        XCTAssertEqual(response.data?["summary"], "Review changes requested for PR #42.")
    }

    func test_blockList_routesToBlockProviderWithClampedLimit() {
        let capturedLimit = LockedBox<UInt32?>(nil)
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            blockListProvider: { limit in
                capturedLimit.withValue { value in
                    value = limit
                }
                return ["content": "{\"count\":0,\"blocks\":[]}"]
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "block-list-1",
            command: "block-list",
            params: ["limit": "500"]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(capturedLimit.withValue { $0 }, 64)
        XCTAssertEqual(response.data?["content"], "{\"count\":0,\"blocks\":[]}")
    }

    func test_blockOutputs_routesToOutputProviderWithClampedLimit() {
        let capturedLimit = LockedBox<UInt32?>(nil)
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            blockOutputsProvider: { limit in
                capturedLimit.withValue { value in
                    value = limit
                }
                return ["output": "recent output", "limit": "\(limit)"]
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "block-outputs-1",
            command: "block-outputs",
            params: ["limit": "500"]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(capturedLimit.withValue { $0 }, 64)
        XCTAssertEqual(response.data?["output"], "recent output")
    }

    func test_blockCopy_routesToBlockProvider() {
        let captured = LockedBox<(id: UInt64?, field: String?)>((nil, nil))
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            blockCopyProvider: { id, field in
                captured.withValue { value in
                    value = (id, field)
                }
                return ["status": "copied", "id": "\(id)", "field": field]
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "block-copy-1",
            command: "block-copy",
            params: ["id": "42", "field": "command"]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(captured.withValue { $0.id }, 42)
        XCTAssertEqual(captured.withValue { $0.field }, "command")
        XCTAssertEqual(response.data?["status"], "copied")
    }

    func test_blockRerun_routesToBlockProvider() {
        let capturedID = LockedBox<UInt64?>(nil)
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            blockRerunProvider: { id in
                capturedID.withValue { value in
                    value = id
                }
                return ["status": "sent", "id": "\(id)"]
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "block-rerun-1",
            command: "block-rerun",
            params: ["id": "42"]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(capturedID.withValue { $0 }, 42)
        XCTAssertEqual(response.data?["status"], "sent")
    }

    func test_blockCopyRejectsInvalidFieldBeforeProvider() {
        let called = LockedBox(false)
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            blockCopyProvider: { _, _ in
                called.withValue { $0 = true }
                return ["status": "copied"]
            }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "block-copy-invalid-1",
            command: "block-copy",
            params: ["id": "42", "field": "env"]
        ))

        XCTAssertFalse(response.success)
        XCTAssertFalse(called.withValue { $0 })
        XCTAssertTrue(response.error?.contains("field") == true)
    }

    // MARK: - Group 1: Tab Operations

    // MARK: focus-tab

    @MainActor
    func test_focusTab_withValidID_activatesTab() {
        let tabManager = TabManager()
        let secondTab = tabManager.addTab()
        let firstTabID = tabManager.tabs[0].id.rawValue.uuidString
        XCTAssertTrue(secondTab.isActive)

        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "ft-1",
            command: "focus-tab",
            params: ["id": firstTabID]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "focused")
        XCTAssertEqual(tabManager.activeTabID, tabManager.tabs[0].id)
    }

    @MainActor
    func test_focusTab_withMissingID_returnsError() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(id: "ft-2", command: "focus-tab", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    @MainActor
    func test_focusTab_withInvalidUUID_returnsError() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "ft-3",
            command: "focus-tab",
            params: ["id": "not-a-uuid"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Invalid") == true)
    }

    @MainActor
    func test_focusTab_withNonexistentID_returnsError() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let nonexistentUUID = UUID().uuidString
        let request = SocketRequest(
            id: "ft-4",
            command: "focus-tab",
            params: ["id": nonexistentUUID]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("not found") == true)
    }

    @MainActor
    func test_focusTab_withNilTabManager_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "ft-5",
            command: "focus-tab",
            params: ["id": UUID().uuidString]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("not available") == true)
    }

    // MARK: close-tab

    @MainActor
    func test_closeTab_withValidID_removesTab() {
        let tabManager = TabManager()
        let secondTab = tabManager.addTab()
        XCTAssertEqual(tabManager.tabs.count, 2)

        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "ct-1",
            command: "close-tab",
            params: ["id": secondTab.id.rawValue.uuidString]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "closed")
        XCTAssertEqual(tabManager.tabs.count, 1)
    }

    @MainActor
    func test_closeTab_withMissingID_returnsError() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(id: "ct-2", command: "close-tab", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    @MainActor
    func test_closeTab_lastTab_cannotClose() {
        let tabManager = TabManager()
        XCTAssertEqual(tabManager.tabs.count, 1)
        let onlyTabID = tabManager.tabs[0].id.rawValue.uuidString

        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "ct-3",
            command: "close-tab",
            params: ["id": onlyTabID]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertEqual(response.error, "Cannot close the last remaining tab")
        XCTAssertEqual(tabManager.tabs.count, 1)
    }

    // MARK: new-tab

    @MainActor
    func test_newTab_withoutDir_createsTab() {
        let tabManager = TabManager()
        XCTAssertEqual(tabManager.tabs.count, 1)

        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(id: "nt-1", command: "new-tab", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.data?["id"])
        XCTAssertNotNil(response.data?["title"])
        XCTAssertEqual(tabManager.tabs.count, 2)
    }

    @MainActor
    func test_newTab_withDir_createsTabAtDirectory() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "nt-2",
            command: "new-tab",
            params: ["dir": "/tmp"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(tabManager.tabs.count, 2)
        // The new tab should be active.
        XCTAssertTrue(tabManager.tabs.last?.isActive == true)
    }

    @MainActor
    func test_newTab_withEnginePreference_persistsPreferenceOnTab() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "nt-engine",
            command: "new-tab",
            params: ["engine": "daemon"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(tabManager.tabs.count, 2)
        XCTAssertEqual(tabManager.tabs.last?.terminalEnginePreference, .daemon)
    }

    @MainActor
    func test_newTab_withInvalidEngine_returnsError() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "nt-engine-invalid",
            command: "new-tab",
            params: ["engine": "invalid"]
        )

        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertEqual(response.error, "Invalid engine. Use system, in-process, or daemon")
        XCTAssertEqual(tabManager.tabs.count, 1)
    }

    @MainActor
    func test_newTab_withNilTabManager_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "nt-3", command: "new-tab", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("not available") == true)
    }

    @MainActor
    func test_tabDuplicate_withProvider_returnsDuplicatedTabMetadata() {
        let expectedID = UUID().uuidString
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            tabDuplicateProvider: { (id: expectedID, title: "Duplicated Tab") }
        )
        let request = SocketRequest(id: "td-1", command: "tab-duplicate", params: nil)

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "duplicated")
        XCTAssertEqual(response.data?["id"], expectedID)
        XCTAssertEqual(response.data?["title"], "Duplicated Tab")
    }

    @MainActor
    func test_sessionRestore_withProviderSuccess_returnsRestored() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            sessionRestoreProvider: { name in
                XCTAssertEqual(name, "workbench")
                return true
            }
        )
        let request = SocketRequest(
            id: "sr-1",
            command: "session-restore",
            params: ["name": "workbench"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "restored")
        XCTAssertEqual(response.data?["name"], "workbench")
    }

    // MARK: tab-rename

    @MainActor
    func test_tabRename_withValidParams_renamesTab() {
        let tabManager = TabManager()
        let tabID = tabManager.tabs[0].id.rawValue.uuidString

        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "tr-1",
            command: "tab-rename",
            params: ["id": tabID, "name": "My Custom Name"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "renamed")
        XCTAssertEqual(tabManager.tabs[0].customTitle, "My Custom Name")
    }

    @MainActor
    func test_tabRename_withMissingID_returnsError() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "tr-2",
            command: "tab-rename",
            params: ["name": "Something"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    @MainActor
    func test_tabRename_withMissingName_returnsError() {
        let tabManager = TabManager()
        let tabID = tabManager.tabs[0].id.rawValue.uuidString
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "tr-3",
            command: "tab-rename",
            params: ["id": tabID]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    // MARK: tab-move

    @MainActor
    func test_tabMove_withValidPositions_movesTab() {
        let tabManager = TabManager()
        let firstTab = tabManager.tabs[0]
        tabManager.addTab()
        tabManager.addTab()
        XCTAssertEqual(tabManager.tabs.count, 3)

        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let firstTabID = firstTab.id.rawValue.uuidString
        let request = SocketRequest(
            id: "tm-1",
            command: "tab-move",
            params: ["id": firstTabID, "position": "2"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "moved")
        // The first tab should now be at index 2.
        XCTAssertEqual(tabManager.tabs[2].id, firstTab.id)
    }

    @MainActor
    func test_tabMove_withMissingID_returnsError() {
        let tabManager = TabManager()
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "tm-2",
            command: "tab-move",
            params: ["position": "1"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
    }

    @MainActor
    func test_tabMove_withMissingPosition_returnsError() {
        let tabManager = TabManager()
        let tabID = tabManager.tabs[0].id.rawValue.uuidString
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "tm-3",
            command: "tab-move",
            params: ["id": tabID]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
    }

    @MainActor
    func test_tabMove_withInvalidPosition_returnsError() {
        let tabManager = TabManager()
        let tabID = tabManager.tabs[0].id.rawValue.uuidString
        let handler = AppSocketCommandHandler(tabManager: tabManager, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "tm-4",
            command: "tab-move",
            params: ["id": tabID, "position": "abc"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
    }

    // MARK: - Group 2: Config Operations

    // MARK: config-path

    func test_configPath_returnsPath() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "cp-1", command: "config-path", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.data?["path"])
        XCTAssertTrue(response.data?["path"]?.contains("config.toml") == true)
    }

    // MARK: config-get

    func test_configGet_withValidKey_returnsValue() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "cg-1",
            command: "config-get",
            params: ["key": "appearance.theme"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.data?["key"])
        XCTAssertNotNil(response.data?["value"])
    }

    func test_configGet_withMissingKey_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "cg-2", command: "config-get", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    func test_configGet_withUnknownKey_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "cg-3",
            command: "config-get",
            params: ["key": "nonexistent.key"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Unknown") == true)
    }

    func test_configGet_generalShell_returnsShellPath() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "cg-4",
            command: "config-get",
            params: ["key": "general.shell"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["key"], "general.shell")
        // Default shell is /bin/zsh.
        XCTAssertNotNil(response.data?["value"])
    }

    func test_configGet_notesKeys_returnsDefaults() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "cg-notes",
            command: "config-get",
            params: ["key": "notes.enabled"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["key"], "notes.enabled")
        XCTAssertEqual(response.data?["value"], "\(NotesConfig.defaults.enabled)")
    }

    func test_configGet_completionKeys_returnsDefaults() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let response = handler.handleCommand(SocketRequest(
            id: "cg-completions",
            command: "config-get",
            params: ["key": "completions.inline-ai"]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["key"], "completions.inline-ai")
        XCTAssertEqual(response.data?["value"], "\(CompletionConfig.defaults.inlineAIEnabled)")
    }

    func test_configGet_rateLimitIndicatorKey_returnsDefault() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "cg-rate-limit",
            command: "config-get",
            params: ["key": "appearance.rate-limit-indicator-enabled"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["key"], "appearance.rate-limit-indicator-enabled")
        XCTAssertEqual(response.data?["value"], "\(AppearanceConfig.defaults.rateLimitIndicatorEnabled)")
    }

    func test_configGet_auroraEnabledKey_returnsDefault() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "cg-aurora-enabled",
            command: "config-get",
            params: ["key": "appearance.aurora-enabled"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["key"], "appearance.aurora-enabled")
        XCTAssertEqual(response.data?["value"], "\(AppearanceConfig.defaults.auroraEnabled)")
    }

    func test_configGet_quickSwitchModeKey_returnsDefault() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "cg-quickswitch-mode",
            command: "config-get",
            params: ["key": "appearance.quickswitch-mode"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["key"], "appearance.quickswitch-mode")
        XCTAssertEqual(response.data?["value"], AppearanceConfig.defaults.quickSwitchMode.rawValue)
    }

    func test_configGet_appLanguageKey_returnsDefault() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "cg-app-language",
            command: "config-get",
            params: ["key": "appearance.app-language"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["key"], "appearance.app-language")
        XCTAssertEqual(response.data?["value"], AppearanceConfig.defaults.appLanguage.rawValue)
    }

    func test_configList_includesNewNotesAndRateLimitKeys() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let response = handler.handleCommand(SocketRequest(id: "cl-new-keys", command: "config-list", params: nil))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["notes.enabled"], "\(NotesConfig.defaults.enabled)")
        XCTAssertEqual(response.data?["notes.shortcut"], NotesConfig.defaults.shortcut)
        XCTAssertEqual(response.data?["appearance.aurora-enabled"], "\(AppearanceConfig.defaults.auroraEnabled)")
        XCTAssertEqual(
            response.data?["appearance.rate-limit-indicator-enabled"],
            "\(AppearanceConfig.defaults.rateLimitIndicatorEnabled)"
        )
        XCTAssertEqual(
            response.data?["appearance.quickswitch-mode"],
            AppearanceConfig.defaults.quickSwitchMode.rawValue
        )
        XCTAssertEqual(response.data?["appearance.app-language"], AppearanceConfig.defaults.appLanguage.rawValue)
        XCTAssertEqual(response.data?["worktree.enabled"], "\(WorktreeConfig.defaults.enabled)")
        XCTAssertEqual(response.data?["worktree.on-close"], WorktreeConfig.defaults.onClose.rawValue)
        XCTAssertEqual(response.data?["experimental.pip-enabled"], "\(ExperimentalConfig.defaults.pipEnabled)")
        XCTAssertEqual(response.data?["experimental.pty-daemon"], "\(ExperimentalConfig.defaults.ptyDaemonEnabled)")
        XCTAssertEqual(response.data?["completions.inline-ai"], "\(CompletionConfig.defaults.inlineAIEnabled)")
        XCTAssertEqual(response.data?["completions.provider"], CompletionConfig.defaults.provider.rawValue)
        XCTAssertEqual(
            response.data?["completions.enabled-languages"],
            CompletionConfig.defaults.enabledLanguageIDs.joined(separator: ",")
        )
    }

    func test_configList_withFilterOnlyReturnsMatchingKeys() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let response = handler.handleCommand(SocketRequest(
            id: "cl-filter",
            command: "config-list",
            params: ["filter": "worktree."]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["count"], "9")
        XCTAssertEqual(response.data?["worktree.enabled"], "\(WorktreeConfig.defaults.enabled)")
        XCTAssertEqual(response.data?["worktree.on-close"], WorktreeConfig.defaults.onClose.rawValue)
        XCTAssertNil(response.data?["appearance.theme"])
        XCTAssertNil(response.data?["experimental.pip-enabled"])
    }

    func test_configList_withCompletionFilterOnlyReturnsCompletionKeys() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let response = handler.handleCommand(SocketRequest(
            id: "cl-completions",
            command: "config-list",
            params: ["filter": "completions."]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["count"], "5")
        XCTAssertEqual(response.data?["completions.inline-ai"], "\(CompletionConfig.defaults.inlineAIEnabled)")
        XCTAssertEqual(response.data?["completions.provider"], CompletionConfig.defaults.provider.rawValue)
        XCTAssertEqual(response.data?["completions.idle-delay-seconds"], "\(CompletionConfig.defaults.idleDelaySeconds)")
        XCTAssertNil(response.data?["worktree.enabled"])
    }

    // MARK: config-set

    func test_configSet_withMissingKey_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "cs-1",
            command: "config-set",
            params: ["value": "something"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    func test_configSet_withMissingValue_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "cs-2",
            command: "config-set",
            params: ["key": "appearance.theme"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    func test_configSet_withValidParams_returnsAcknowledged() {
        let didReload = LockedBox(false)
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            configReloadProvider: {
                didReload.withValue { $0 = true }
                return true
            }
        )
        let request = SocketRequest(
            id: "cs-3",
            command: "config-set",
            params: ["key": "appearance.theme", "value": "dracula"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "updated")
        XCTAssertTrue(didReload.withValue { $0 })
    }

    func test_configSet_reportsReloadFailure() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            configReloadProvider: { false }
        )
        let request = SocketRequest(
            id: "cs-reload-failure",
            command: "config-set",
            params: ["key": "appearance.theme", "value": "dracula"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertEqual(response.error, "Configuration was written but could not be reloaded")
    }

    func test_configTOMLUpdater_insertsMissingFieldInsideExistingSection() {
        let toml = """
        [appearance]
        theme = "dracula"

        [terminal]
        scrollback-lines = 10000
        """

        let updated = AppSocketConfigTOMLUpdater.updateTomlValue(
            in: toml,
            section: "appearance",
            field: "quickswitch-mode",
            newValue: "tabs-only"
        )

        XCTAssertTrue(updated.contains("quickswitch-mode = \"tabs-only\""))
        XCTAssertLessThan(
            updated.range(of: "quickswitch-mode = \"tabs-only\"")!.lowerBound,
            updated.range(of: "[terminal]")!.lowerBound
        )
        XCTAssertGreaterThan(
            updated.range(of: "quickswitch-mode = \"tabs-only\"")!.lowerBound,
            updated.range(of: "[appearance]")!.lowerBound
        )
    }

    func test_configTOMLUpdater_appendsMissingSection() {
        let updated = AppSocketConfigTOMLUpdater.updateTomlValue(
            in: "[general]\nshell = \"/bin/zsh\"",
            section: "experimental",
            field: "pip-enabled",
            newValue: "true"
        )

        XCTAssertTrue(updated.contains("\n[experimental]\npip-enabled = true"))
    }

    func test_configTOMLUpdater_escapesInsertedStringValues() {
        let updated = AppSocketConfigTOMLUpdater.updateTomlValue(
            in: "[worktree]",
            section: "worktree",
            field: "base-path",
            newValue: "/tmp/quoted \"folder\" \\ suffix"
        )

        XCTAssertTrue(updated.contains("base-path = \"/tmp/quoted \\\"folder\\\" \\\\ suffix\""))
    }

    func test_configTOMLUpdater_rendersStringArrayValues() {
        let updated = AppSocketConfigTOMLUpdater.updateTomlValue(
            in: "[completions]",
            section: "completions",
            field: "enabled-languages",
            renderedValue: AppSocketConfigTOMLUpdater.renderedStringArrayValue(["python", "swift"])
        )

        XCTAssertTrue(updated.contains("enabled-languages = [\"python\", \"swift\"]"))
    }

    // MARK: - Group 3: Theme Operations

    // MARK: theme-list

    @MainActor func test_themeList_returnsAvailableThemes() {
        let engine = ThemeEngineImpl()
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil, themeEngineProvider: { engine })
        let request = SocketRequest(id: "tl-1", command: "theme-list", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertNotNil(response.data?["count"])
        // There should be at least the 6 built-in themes.
        if let countStr = response.data?["count"], let count = Int(countStr) {
            XCTAssertGreaterThanOrEqual(count, 6)
        }
    }

    @MainActor func test_themeList_includesBuiltInThemeNames() {
        let engine = ThemeEngineImpl()
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil, themeEngineProvider: { engine })
        let request = SocketRequest(id: "tl-2", command: "theme-list", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        // Built-in themes are indexed as theme_0, theme_1, etc.
        let allValues = response.data?.values.joined(separator: ",") ?? ""
        XCTAssertTrue(allValues.contains("Catppuccin Mocha"))
        XCTAssertTrue(allValues.contains("Dracula"))
    }

    // MARK: theme-set

    func test_themeSet_withMissingName_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "ts-1", command: "theme-set", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    @MainActor func test_themeSet_withValidName_returnsSuccess() {
        let engine = ThemeEngineImpl()
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil, themeEngineProvider: { engine })
        let request = SocketRequest(
            id: "ts-2",
            command: "theme-set",
            params: ["name": "Dracula"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "applied")
    }

    func test_themeSet_withInvalidName_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "ts-3",
            command: "theme-set",
            params: ["name": "Nonexistent Theme That Does Not Exist"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("not found") == true)
    }

    // MARK: - Group 4: Acknowledged Commands

    func test_notifyCommand_dispatchesAndReturnsNotificationSent() {
        let dispatchedTitle = LockedBox<String?>(nil)
        let dispatchedBody = LockedBox<String?>(nil)
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            notifyDispatcher: { title, body in
                dispatchedTitle.withValue { $0 = title }
                dispatchedBody.withValue { $0 = body }
            }
        )
        let request = SocketRequest(
            id: "ack-1",
            command: "notify",
            params: ["message": "Build done"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "notification sent")
        XCTAssertEqual(dispatchedTitle.withValue { $0 }, "Cocxy")
        XCTAssertEqual(dispatchedBody.withValue { $0 }, "Build done")
    }

    func test_notifyCommand_withCustomTitle() {
        let dispatchedTitle = LockedBox<String?>(nil)
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            notifyDispatcher: { title, _ in
                dispatchedTitle.withValue { $0 = title }
            }
        )
        let request = SocketRequest(
            id: "ack-1b",
            command: "notify",
            params: ["title": "Deploy", "message": "Success"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(dispatchedTitle.withValue { $0 }, "Deploy")
    }

    func test_notifyCommand_withoutMessage_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(
            id: "ack-1c",
            command: "notify",
            params: nil
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("message") == true)
    }

    // MARK: - V4 Commands: Without Providers Return Error

    func test_splitCommand_withoutProvider_returnsError() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "v4-1", command: "split", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertFalse(response.success)
    }

    func test_splitCommand_withProvider_returnsCreated() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            splitCreateProvider: { _ in true }
        )
        let request = SocketRequest(id: "v4-2", command: "split", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "created")
    }

    func test_splitListCommand_withProvider_returnsPanes() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            splitInfoProvider: { [
                (leafID: "leaf-1", terminalID: "term-1", isFocused: true),
                (leafID: "leaf-2", terminalID: "term-2", isFocused: false)
            ] }
        )
        let request = SocketRequest(id: "v4-3", command: "split-list", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["count"], "2")
    }

    func test_dashboardToggleCommand_withProvider_returnsToggled() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            dashboardToggleProvider: { true }
        )
        let request = SocketRequest(id: "v4-4", command: "dashboard-toggle", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "toggled")
        XCTAssertEqual(response.data?["visible"], "true")
    }

    func test_dashboardStatusCommand_withProvider_returnsStatus() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            dashboardStatusProvider: { [
                "visible": "true",
                "session_count": "3",
                "active_count": "1"
            ] }
        )
        let request = SocketRequest(id: "v4-5", command: "dashboard-status", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["session_count"], "3")
    }

    func test_timelineShowCommand_withProvider_returnsEvents() throws {
        let event = TimelineEvent(
            type: .toolUse,
            sessionId: "session-1",
            summary: "Read: Sources/App.swift"
        )
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            timelineQueryProvider: { tabID in
                XCTAssertNil(tabID)
                return TimelineQueryResult(
                    tabID: nil,
                    sessionIDs: ["session-1"],
                    events: [event]
                )
            }
        )
        let request = SocketRequest(id: "v4-6", command: "timeline-show", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["count"], "1")
        XCTAssertEqual(response.data?["sessionCount"], "1")

        let eventsString = try XCTUnwrap(response.data?["events"])
        let eventsData = try XCTUnwrap(eventsString.data(using: .utf8))
        let decoded = try JSONDecoder().decode([TimelineEvent].self, from: eventsData)
        XCTAssertEqual(decoded, [event])
    }

    func test_searchCommand_withQueryProvider_returnsResults() throws {
        let result = SearchResult(
            id: UUID(),
            lineNumber: 42,
            column: 7,
            matchText: "needle",
            contextBefore: "find ",
            contextAfter: " in haystack"
        )
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            searchProvider: { query, regex, caseSensitive, tabID in
                XCTAssertEqual(query, "needle")
                XCTAssertTrue(regex)
                XCTAssertFalse(caseSensitive)
                XCTAssertNil(tabID)
                return SearchCommandResult(
                    tabID: nil,
                    lineCount: 120,
                    results: [result]
                )
            }
        )
        let request = SocketRequest(
            id: "v4-7",
            command: "search",
            params: [
                "query": "needle",
                "regex": "true",
                "caseSensitive": "false"
            ]
        )
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["count"], "1")
        XCTAssertEqual(response.data?["lines"], "120")

        let resultsString = try XCTUnwrap(response.data?["results"])
        let resultsData = try XCTUnwrap(resultsString.data(using: .utf8))
        let decoded = try JSONDecoder().decode([SearchResult].self, from: resultsData)
        XCTAssertEqual(decoded, [result])
    }

    func test_searchCommand_withoutQuery_withProvider_returnsToggled() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            searchToggleProvider: { }
        )
        let request = SocketRequest(id: "v4-7-toggle", command: "search", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "toggled")
    }

    func test_sendCommand_withProvider_returnsSent() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            sendTextProvider: { _ in true }
        )
        let request = SocketRequest(id: "v4-8", command: "send", params: ["text": "ls"])
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "sent")
    }

    func test_sendKeyCommand_withProvider_returnsSent() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            sendKeyProvider: { _ in true }
        )
        let request = SocketRequest(id: "v4-9", command: "send-key", params: ["key": "enter"])
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "sent")
    }

    func test_hooksCommand_returnsData() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "v4-10", command: "hooks", params: nil)
        let response = handler.handleCommand(request)
        // hooks reads settings.json — succeeds even without provider
        XCTAssertTrue(response.success)
    }

    func test_hookHandlerCommand_returnsReady() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "v4-11", command: "hook-handler", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ready")
    }

    func test_timelineExportCommand_withProvider_returnsExported() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            timelineExportProvider: { tabID, format in
                XCTAssertNil(tabID)
                XCTAssertEqual(format, "json")
                return "[]".data(using: .utf8)
            }
        )
        let request = SocketRequest(
            id: "v4-12", command: "timeline-export",
            params: ["format": "json"]
        )
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "exported")
    }

    func test_sshCommand_withProvider_returnsConnected() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            sshProvider: { destination, port, identity in
                ("tab-id", destination)
            }
        )
        let request = SocketRequest(
            id: "ssh-1", command: "ssh",
            params: ["destination": "user@host", "port": "2222"]
        )
        let response = handler.handleCommand(request)
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "connected")
        XCTAssertEqual(response.data?["destination"], "user@host")
    }

    func test_sshCommand_withoutProvider_returnsFailure() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let request = SocketRequest(id: "ssh-2", command: "ssh", params: ["destination": "host"])
        let response = handler.handleCommand(request)
        XCTAssertFalse(response.success)
    }

    func test_sshCommand_withoutDestination_returnsFailure() {
        let handler = AppSocketCommandHandler(
            tabManager: nil, hookEventReceiver: nil,
            sshProvider: { _, _, _ in ("id", "title") }
        )
        let request = SocketRequest(id: "ssh-3", command: "ssh", params: nil)
        let response = handler.handleCommand(request)
        XCTAssertFalse(response.success)
    }

    func test_webStatusCommand_withProvider_returnsStructuredStatus() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            webStatusProvider: {
                [
                    "status": "running",
                    "running": "true",
                    "bind": "127.0.0.1",
                    "port": "7770",
                    "connections": "2"
                ]
            }
        )
        let response = handler.handleCommand(SocketRequest(id: "web-1", command: "web-status", params: nil))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "running")
        XCTAssertEqual(response.data?["connections"], "2")
    }

    func test_webStartCommand_withoutProvider_returnsFailure() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let response = handler.handleCommand(SocketRequest(id: "web-2", command: "web-start", params: nil))
        XCTAssertFalse(response.success)
    }

    func test_streamListCommand_withProvider_returnsData() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            streamListProvider: {
                ["count": "2", "current_stream_id": "1", "stream_0_id": "1", "stream_1_id": "2"]
            }
        )
        let response = handler.handleCommand(SocketRequest(id: "core-1", command: "stream-list", params: nil))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["count"], "2")
        XCTAssertEqual(response.data?["current_stream_id"], "1")
    }

    func test_protocolSendCommand_requiresTypeAndJson() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            protocolSendProvider: { _, _ in ["status": "sent"] }
        )
        let response = handler.handleCommand(SocketRequest(id: "core-2", command: "protocol-send", params: ["type": "agent.status"]))
        XCTAssertFalse(response.success)
    }

    func test_streamCurrentCommand_withProvider_returnsSelectedStream() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            streamCurrentProvider: { streamID in
                ["status": "current", "stream_id": "\(streamID)"]
            }
        )
        let response = handler.handleCommand(SocketRequest(id: "core-2b", command: "stream-current", params: ["id": "9"]))
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["stream_id"], "9")
    }

    func test_protocolCapabilitiesCommand_withProvider_returnsSent() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            protocolCapabilitiesProvider: {
                ["status": "sent", "message": "terminal.capabilities"]
            }
        )
        let response = handler.handleCommand(SocketRequest(id: "core-2c", command: "protocol-capabilities", params: nil))
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["message"], "terminal.capabilities")
    }

    func test_coreResetCommand_withProvider_returnsReset() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            coreResetProvider: {
                ["status": "reset"]
            }
        )
        let response = handler.handleCommand(SocketRequest(id: "core-reset-1", command: "core-reset", params: nil))
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "reset")
    }

    func test_coreSignalCommand_requiresSignal() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            coreSignalProvider: { _ in ["status": "sent"] }
        )
        let response = handler.handleCommand(SocketRequest(id: "core-signal-1", command: "core-signal", params: nil))
        XCTAssertFalse(response.success)
    }

    func test_coreSignalCommand_acceptsNamedSignal() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            coreSignalProvider: { signal in
                ["status": "sent", "signal": "\(signal)"]
            }
        )
        let response = handler.handleCommand(
            SocketRequest(id: "core-signal-2", command: "core-signal", params: ["signal": "term"])
        )
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["signal"], "\(SIGTERM)")
    }

    func test_coreProcessCommand_withProvider_returnsData() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            coreProcessProvider: { ["content": "{\"alive\":true}"] }
        )
        let response = handler.handleCommand(SocketRequest(id: "core-process-1", command: "core-process", params: nil))
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["content"], "{\"alive\":true}")
    }

    func test_coreModesCommand_withProvider_returnsData() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            coreModesProvider: { ["content": "{\"cursorVisible\":true}"] }
        )
        let response = handler.handleCommand(SocketRequest(id: "core-modes-1", command: "core-modes", params: nil))
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["content"], "{\"cursorVisible\":true}")
    }

    func test_coreSearchCommand_withProvider_returnsData() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            coreSearchProvider: { ["content": "{\"gpuActive\":true}"] }
        )
        let response = handler.handleCommand(SocketRequest(id: "core-search-1", command: "core-search", params: nil))
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["content"], "{\"gpuActive\":true}")
    }

    func test_coreLigaturesCommand_withProvider_returnsData() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            coreLigaturesProvider: { ["content": "{\"enabled\":true}"] }
        )
        let response = handler.handleCommand(SocketRequest(id: "core-ligatures-1", command: "core-ligatures", params: nil))
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["content"], "{\"enabled\":true}")
    }

    func test_coreProtocolCommand_withProvider_returnsData() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            coreProtocolProvider: { ["content": "{\"observed\":true}"] }
        )
        let response = handler.handleCommand(SocketRequest(id: "core-protocol-1", command: "core-protocol", params: nil))
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["content"], "{\"observed\":true}")
    }

    func test_coreSemanticCommand_clampsLimitAndReturnsData() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            coreSemanticProvider: { limit in
                ["content": "{\"limit\":\(limit)}"]
            }
        )
        let response = handler.handleCommand(
            SocketRequest(id: "core-semantic-1", command: "core-semantic", params: ["limit": "999"])
        )
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["content"], "{\"limit\":64}")
    }

    func test_protocolViewportCommand_withProvider_returnsViewportMessage() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            protocolViewportProvider: { requestID in
                var data = ["status": "sent", "message": "terminal.viewport"]
                if let requestID {
                    data["request_id"] = requestID
                }
                return data
            }
        )
        let response = handler.handleCommand(SocketRequest(id: "core-2d", command: "protocol-viewport", params: ["request_id": "req-1"]))
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["request_id"], "req-1")
    }

    func test_imageListCommand_withProvider_returnsData() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            imageListProvider: {
                ["count": "1", "image_0_id": "7"]
            }
        )
        let response = handler.handleCommand(SocketRequest(id: "core-2e", command: "image-list", params: nil))
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["image_0_id"], "7")
    }

    func test_imageDeleteCommand_requiresID() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            imageDeleteProvider: { _ in ["status": "deleted"] }
        )
        let response = handler.handleCommand(SocketRequest(id: "core-2f", command: "image-delete", params: nil))
        XCTAssertFalse(response.success)
    }

    func test_imageDeleteCommand_withProvider_returnsDeletedImage() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            imageDeleteProvider: { imageID in
                ["status": "deleted", "image_id": "\(imageID)"]
            }
        )
        let response = handler.handleCommand(SocketRequest(id: "core-2g", command: "image-delete", params: ["id": "12"]))
        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["image_id"], "12")
    }

    func test_imageClearCommand_withProvider_returnsCleared() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            imageClearProvider: {
                ["status": "cleared", "removed": "3"]
            }
        )
        let response = handler.handleCommand(SocketRequest(id: "core-3", command: "image-clear", params: nil))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["removed"], "3")
    }

    func test_notebookImport_convertsJupyterToCocxyMarkdown() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("source.ipynb")
        let outputURL = directory.appendingPathComponent("result.cocxynb")

        try """
        {
          "nbformat": 4,
          "nbformat_minor": 5,
          "metadata": {
            "kernelspec": {
              "display_name": "Python 3",
              "language": "python",
              "name": "python3"
            },
            "cocxy": {
              "title": "Imported"
            }
          },
          "cells": [
            {
              "cell_type": "markdown",
              "metadata": {},
              "source": ["# Intro\\n", "Local notebook"]
            },
            {
              "cell_type": "code",
              "metadata": {},
              "source": ["print('hello')"],
              "execution_count": null,
              "outputs": [
                {
                  "output_type": "stream",
                  "name": "stdout",
                  "text": ["done\\n"]
                }
              ]
            }
          ]
        }
        """.write(to: inputURL, atomically: true, encoding: .utf8)

        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let response = handler.handleCommand(SocketRequest(
            id: "notebook-import-1",
            command: "notebook-import",
            params: [
                "input": inputURL.path,
                "output": outputURL.path,
                "force": "false",
            ]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "imported")
        XCTAssertEqual(response.data?["input"], inputURL.standardizedFileURL.path)
        XCTAssertEqual(response.data?["output"], outputURL.standardizedFileURL.path)
        let rendered = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(rendered.contains("cocxy-notebook: \"1\""))
        XCTAssertTrue(rendered.contains("title: \"Imported\""))
        XCTAssertTrue(rendered.contains("# Intro"))
        XCTAssertTrue(rendered.contains("```python\nprint('hello')\n```"))
        XCTAssertTrue(rendered.contains("```cocxy-output stdout\ndone\n```"))
    }

    func test_notebookExport_convertsCocxyMarkdownToJupyter() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("source.cocxynb")
        let outputURL = directory.appendingPathComponent("result.ipynb")

        try """
        ---
        cocxy-notebook: "1"
        title: "Round Trip"
        ---

        # Intro

        ```bash
        echo hello
        ```

        ```cocxy-output stdout
        hello
        ```
        """.write(to: inputURL, atomically: true, encoding: .utf8)

        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let response = handler.handleCommand(SocketRequest(
            id: "notebook-export-1",
            command: "notebook-export",
            params: [
                "input": inputURL.path,
                "output": outputURL.path,
                "force": "false",
            ]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "exported")
        let data = try Data(contentsOf: outputURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["nbformat"] as? Int, 4)
        let cells = try XCTUnwrap(json?["cells"] as? [[String: Any]])
        XCTAssertEqual(cells.count, 2)
        XCTAssertEqual(cells[0]["cell_type"] as? String, "markdown")
        XCTAssertEqual(cells[1]["cell_type"] as? String, "code")
        let outputs = try XCTUnwrap(cells[1]["outputs"] as? [[String: Any]])
        XCTAssertEqual(outputs.first?["output_type"] as? String, "stream")
        XCTAssertEqual(outputs.first?["name"] as? String, "stdout")
        XCTAssertEqual((outputs.first?["text"] as? [String])?.joined(), "hello\n")
    }

    func test_notebookImport_refusesExistingOutputWithoutForce() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("source.ipynb")
        let outputURL = directory.appendingPathComponent("result.cocxynb")

        try """
        {"nbformat":4,"nbformat_minor":5,"metadata":{},"cells":[]}
        """.write(to: inputURL, atomically: true, encoding: .utf8)
        try "existing".write(to: outputURL, atomically: true, encoding: .utf8)

        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let response = handler.handleCommand(SocketRequest(
            id: "notebook-import-2",
            command: "notebook-import",
            params: [
                "input": inputURL.path,
                "output": outputURL.path,
                "force": "false",
            ]
        ))

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("already exists") == true)
        XCTAssertEqual(try String(contentsOf: outputURL, encoding: .utf8), "existing")
    }

    func test_notebookRun_executesLocalBashCellAndWritesOutputs() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("source.cocxynb")
        let outputURL = directory.appendingPathComponent("result.cocxynb")

        try """
        ---
        cocxy-notebook: "1"
        title: "Executable"
        ---

        ```bash
        echo notebook-ok
        ```
        """.write(to: inputURL, atomically: true, encoding: .utf8)

        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let response = handler.handleCommand(SocketRequest(
            id: "notebook-run-1",
            command: "notebook-run",
            params: [
                "input": inputURL.path,
                "output": outputURL.path,
                "cwd": directory.path,
                "timeout": "15",
                "continue-on-failure": "false",
            ]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "completed")
        XCTAssertEqual(response.data?["executed-cells"], "1")
        XCTAssertEqual(response.data?["input"], inputURL.standardizedFileURL.path)
        XCTAssertEqual(response.data?["output"], outputURL.standardizedFileURL.path)
        let rendered = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(rendered.contains("```cocxy-output stdout\nnotebook-ok\n```"))
    }

    func test_notebookRun_executesLocalBashPythonAndSwiftCellsThenExportsJupyter() throws {
        try requireExecutableOnPath("python3")
        try requireExecutableOnPath("swift")

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("multi-language.cocxynb")
        let outputURL = directory.appendingPathComponent("multi-language-result.cocxynb")
        let jupyterURL = directory.appendingPathComponent("multi-language-result.ipynb")

        try """
        ---
        cocxy-notebook: "1"
        title: "Multi Language"
        ---

        # Smoke

        ```bash
        printf 'bash-ok\\n'
        ```

        ```python
        print("python-ok")
        ```

        ```swift
        print("swift-ok")
        ```
        """.write(to: inputURL, atomically: true, encoding: .utf8)

        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let runResponse = handler.handleCommand(SocketRequest(
            id: "notebook-run-multi-language",
            command: "notebook-run",
            params: [
                "input": inputURL.path,
                "output": outputURL.path,
                "cwd": directory.path,
                "timeout": "45",
                "continue-on-failure": "false",
            ]
        ))

        XCTAssertTrue(runResponse.success, runResponse.error ?? "")
        XCTAssertEqual(runResponse.data?["status"], "completed")
        XCTAssertEqual(runResponse.data?["executed-cells"], "3")
        let rendered = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(rendered.contains("```cocxy-output stdout\nbash-ok\n```"))
        XCTAssertTrue(rendered.contains("```cocxy-output stdout\npython-ok\n```"))
        XCTAssertTrue(rendered.contains("```cocxy-output stdout\nswift-ok\n```"))

        let exportResponse = handler.handleCommand(SocketRequest(
            id: "notebook-export-multi-language",
            command: "notebook-export",
            params: [
                "input": outputURL.path,
                "output": jupyterURL.path,
                "force": "false",
            ]
        ))

        XCTAssertTrue(exportResponse.success, exportResponse.error ?? "")
        let data = try Data(contentsOf: jupyterURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let cells = try XCTUnwrap(json["cells"] as? [[String: Any]])
        XCTAssertEqual(cells.map { $0["cell_type"] as? String }, ["markdown", "code", "code", "code"])
        let codeOutputs = cells.dropFirst().compactMap { $0["outputs"] as? [[String: Any]] }
        XCTAssertEqual(codeOutputs.count, 3)
        XCTAssertTrue(codeOutputs[0].contains { (($0["text"] as? [String])?.joined() ?? "") == "bash-ok\n" })
        XCTAssertTrue(codeOutputs[1].contains { (($0["text"] as? [String])?.joined() ?? "") == "python-ok\n" })
        XCTAssertTrue(codeOutputs[2].contains { (($0["text"] as? [String])?.joined() ?? "") == "swift-ok\n" })
    }

    func test_workflowRun_executesLocalWorkflowToml() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("workflow.toml")

        try """
        [workflow]
        id = "ci"
        steps = ["verify"]

        [step.verify]
        command = "echo workflow-ok"
        """.write(to: inputURL, atomically: true, encoding: .utf8)

        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let response = handler.handleCommand(SocketRequest(
            id: "workflow-run-1",
            command: "workflow-run",
            params: [
                "input": inputURL.path,
                "cwd": directory.path,
            ]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "completed")
        XCTAssertEqual(response.data?["workflow"], "ci")
        XCTAssertEqual(response.data?["steps"], "1")
        XCTAssertEqual(response.data?["stdout"], "workflow-ok\n")
    }

    func test_workflowRun_executesFiveLocalStepsInOrder() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appendingPathComponent("workflow.toml")
        let traceURL = directory.appendingPathComponent("workflow-order.txt")

        try """
        [workflow]
        id = "five-step"
        steps = ["prepare", "build", "test", "package", "report"]

        [step.prepare]
        command = "printf 'prepare\\n' >> workflow-order.txt && printf 'prepare\\n'"

        [step.build]
        command = "printf 'build\\n' >> workflow-order.txt && printf 'build\\n'"

        [step.test]
        command = "printf 'test\\n' >> workflow-order.txt && printf 'test\\n'"

        [step.package]
        command = "printf 'package\\n' >> workflow-order.txt && printf 'package\\n'"

        [step.report]
        command = "printf 'report\\n' >> workflow-order.txt && printf 'report\\n'"
        """.write(to: inputURL, atomically: true, encoding: .utf8)

        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let response = handler.handleCommand(SocketRequest(
            id: "workflow-run-five-step",
            command: "workflow-run",
            params: [
                "input": inputURL.path,
                "cwd": directory.path,
            ]
        ))

        XCTAssertTrue(response.success, response.error ?? "")
        XCTAssertEqual(response.data?["status"], "completed")
        XCTAssertEqual(response.data?["workflow"], "five-step")
        XCTAssertEqual(response.data?["steps"], "5")
        XCTAssertEqual(response.data?["stdout"], "prepare\nbuild\ntest\npackage\nreport\n")
        XCTAssertEqual(
            try String(contentsOf: traceURL, encoding: .utf8),
            "prepare\nbuild\ntest\npackage\nreport\n"
        )
    }

    func test_skillList_returnsLocalSkillsAsJSONContent() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeSkill(id: "review-pr", name: "Review PR", summary: "Review a local diff.", in: directory)

        let registry = SkillRegistry(
            directories: [SkillDirectory(url: directory, source: .builtIn)]
        )
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            skillRegistryProvider: { registry }
        )

        let response = handler.handleCommand(SocketRequest(
            id: "skill-list-1",
            command: "skill-list",
            params: nil
        ))

        XCTAssertTrue(response.success)
        let content = try XCTUnwrap(response.data?["content"])
        let data = try XCTUnwrap(content.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["count"] as? Int, 1)
        let skills = try XCTUnwrap(json["skills"] as? [[String: Any]])
        XCTAssertEqual(skills.first?["id"] as? String, "review-pr")
        XCTAssertEqual(skills.first?["source"] as? String, "built-in")
    }

    func test_skillMarketplaceCommands_installAndListLocalSkills() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceRoot = directory.appendingPathComponent("source", isDirectory: true)
        let skillsRoot = directory.appendingPathComponent("skills", isDirectory: true)
        try writeSkill(id: "local-review", name: "Local Review", summary: "Local skill.", in: sourceRoot)

        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            skillRegistryProvider: {
                SkillRegistry(directories: [SkillDirectory(url: skillsRoot, source: .user)])
            },
            skillSourceStoreProvider: {
                SkillSourceStore(fileURL: directory.appendingPathComponent("skill-sources.json"))
            },
            skillInstallerProvider: {
                SkillMarketplaceInstaller(skillsDirectory: skillsRoot)
            }
        )

        let addResponse = handler.handleCommand(SocketRequest(
            id: "skill-source-add-1",
            command: "skill-source-add",
            params: ["url": sourceRoot.path, "name": "Local skills"]
        ))
        XCTAssertTrue(addResponse.success)

        let sourceListResponse = handler.handleCommand(SocketRequest(
            id: "skill-source-list-1",
            command: "skill-source-list",
            params: nil
        ))
        XCTAssertTrue(sourceListResponse.success)
        XCTAssertEqual(sourceListResponse.data?["count"], "1")
        XCTAssertEqual(sourceListResponse.data?["source_0_name"], "Local skills")

        let installResponse = handler.handleCommand(SocketRequest(
            id: "skill-install-1",
            command: "skill-install",
            params: ["url": sourceRoot.appendingPathComponent("local-review", isDirectory: true).path]
        ))
        XCTAssertTrue(installResponse.success)
        XCTAssertEqual(installResponse.data?["skill"], "local-review")

        let listResponse = handler.handleCommand(SocketRequest(
            id: "skill-list-1",
            command: "skill-list",
            params: nil
        ))
        XCTAssertTrue(listResponse.success)
        let content = try XCTUnwrap(listResponse.data?["content"])
        let data = try XCTUnwrap(content.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["count"] as? Int, 1)

        let uninstallResponse = handler.handleCommand(SocketRequest(
            id: "skill-uninstall-1",
            command: "skill-uninstall",
            params: ["id": "local-review"]
        ))
        XCTAssertTrue(uninstallResponse.success)
        XCTAssertEqual(uninstallResponse.data?["status"], "uninstalled")
    }

    func test_v4Commands_withoutProviders_returnFailure() {
        let handler = AppSocketCommandHandler(tabManager: nil, hookEventReceiver: nil)
        let commands = [
            "split", "split-list", "split-focus", "split-close", "split-resize",
            "dashboard-show", "dashboard-hide", "dashboard-toggle", "dashboard-status",
            "timeline-show", "timeline-export", "search", "send", "send-key", "ssh",
            "web-start", "web-stop", "web-status",
            "stream-list", "stream-current", "protocol-capabilities",
            "protocol-viewport", "protocol-send",
            "core-reset", "core-signal", "core-process", "core-modes", "core-search",
            "core-ligatures", "core-protocol", "core-selection", "core-font-metrics",
            "core-preedit", "core-semantic",
            "image-list", "image-delete", "image-clear"
        ]
        for command in commands {
            let request = SocketRequest(id: "nil-\(command)", command: command, params: nil)
            let response = handler.handleCommand(request)
            XCTAssertFalse(
                response.success,
                "Command '\(command)' without provider should return failure"
            )
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-notebook-tests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return url
    }

    private func requireExecutableOnPath(_ executable: String) throws {
        guard Self.executableOnPath(executable) != nil else {
            throw XCTSkip("\(executable) is not available on PATH for local execution smoke.")
        }
    }

    private static func executableOnPath(_ executable: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in path.split(separator: ":").map(String.init) {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(executable).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func writeSkill(id: String, name: String, summary: String, in root: URL) throws {
        let directory = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try """
        ---
        id: \(id)
        name: \(name)
        description: \(summary)
        ---
        # \(name)

        Use only local repository evidence.
        """.write(to: directory.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    }
}
