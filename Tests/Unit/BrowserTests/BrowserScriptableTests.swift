// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserScriptableTests.swift - Tests for browser scriptable API commands.

import XCTest
import Combine
@testable import CocxyTerminal

// MARK: - Browser Scriptable Tests

/// Tests for the browser scriptable API covering:
/// - BrowserViewModel scriptable methods (getState, getTabList, evaluateJavaScript).
/// - CLICommandName enum cases for browser commands.
/// - AppSocketCommandHandler browser command dispatch.
@MainActor
final class BrowserScriptableTests: XCTestCase {

    private var viewModel: BrowserViewModel!

    override func setUp() {
        super.setUp()
        viewModel = BrowserViewModel()
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - CLICommandName Browser Cases

    func test_browserCommandNames_allExist() {
        let expectedCommands = [
            "browser-navigate",
            "browser-back",
            "browser-forward",
            "browser-reload",
            "browser-get-state",
            "browser-state-save",
            "browser-state-load",
            "browser-eval",
            "browser-add-script",
            "browser-add-style",
            "browser-init-script-add",
            "browser-init-scripts-list",
            "browser-get-text",
            "browser-list-tabs",
            "browser-snapshot",
            "browser-context",
            "browser-click",
            "browser-dblclick",
            "browser-hover",
            "browser-focus",
            "browser-fill",
            "browser-upload",
            "browser-type",
            "browser-press",
            "browser-keydown",
            "browser-keyup",
            "browser-check",
            "browser-uncheck",
            "browser-select",
            "browser-scroll",
            "browser-scroll-into-view",
            "browser-get-html",
            "browser-get-value",
            "browser-get-attr",
            "browser-get-title",
            "browser-get-count",
            "browser-get-box",
            "browser-get-styles",
            "browser-is-visible",
            "browser-is-enabled",
            "browser-is-checked",
            "browser-find-role",
            "browser-find-text",
            "browser-find-label",
            "browser-find-placeholder",
            "browser-find-alt",
            "browser-find-title",
            "browser-find-testid",
            "browser-find-first",
            "browser-find-last",
            "browser-find-nth",
            "browser-screenshot",
            "browser-console",
            "browser-wait",
            "browser-cookies-list",
            "browser-cookies-set",
            "browser-cookies-delete",
            "browser-network",
            "browser-frames",
            "browser-downloads",
            "browser-dialogs",
            "browser-dialog-accept",
            "browser-dialog-dismiss",
            "browser-storage-list",
            "browser-storage-get",
            "browser-storage-set",
            "browser-storage-delete",
            "browser-import-preview",
            "browser-import-run"
        ]
        for command in expectedCommands {
            XCTAssertNotNil(
                CLICommandName(rawValue: command),
                "CLICommandName should contain '\(command)'"
            )
        }
    }

    func test_browserCommandNames_areIncludedInCaseIterable() {
        let allRawValues = CLICommandName.allCases.map(\.rawValue)
        XCTAssertTrue(allRawValues.contains("browser-navigate"))
        XCTAssertTrue(allRawValues.contains("browser-state-save"))
        XCTAssertTrue(allRawValues.contains("browser-state-load"))
        XCTAssertTrue(allRawValues.contains("browser-eval"))
        XCTAssertTrue(allRawValues.contains("browser-add-script"))
        XCTAssertTrue(allRawValues.contains("browser-add-style"))
        XCTAssertTrue(allRawValues.contains("browser-init-script-add"))
        XCTAssertTrue(allRawValues.contains("browser-init-scripts-list"))
        XCTAssertTrue(allRawValues.contains("browser-list-tabs"))
        XCTAssertTrue(allRawValues.contains("browser-snapshot"))
        XCTAssertTrue(allRawValues.contains("browser-context"))
        XCTAssertTrue(allRawValues.contains("browser-click"))
        XCTAssertTrue(allRawValues.contains("browser-dblclick"))
        XCTAssertTrue(allRawValues.contains("browser-hover"))
        XCTAssertTrue(allRawValues.contains("browser-focus"))
        XCTAssertTrue(allRawValues.contains("browser-fill"))
        XCTAssertTrue(allRawValues.contains("browser-upload"))
        XCTAssertTrue(allRawValues.contains("browser-type"))
        XCTAssertTrue(allRawValues.contains("browser-press"))
        XCTAssertTrue(allRawValues.contains("browser-keydown"))
        XCTAssertTrue(allRawValues.contains("browser-keyup"))
        XCTAssertTrue(allRawValues.contains("browser-check"))
        XCTAssertTrue(allRawValues.contains("browser-uncheck"))
        XCTAssertTrue(allRawValues.contains("browser-select"))
        XCTAssertTrue(allRawValues.contains("browser-scroll"))
        XCTAssertTrue(allRawValues.contains("browser-scroll-into-view"))
        XCTAssertTrue(allRawValues.contains("browser-get-html"))
        XCTAssertTrue(allRawValues.contains("browser-get-value"))
        XCTAssertTrue(allRawValues.contains("browser-get-attr"))
        XCTAssertTrue(allRawValues.contains("browser-get-title"))
        XCTAssertTrue(allRawValues.contains("browser-get-count"))
        XCTAssertTrue(allRawValues.contains("browser-get-box"))
        XCTAssertTrue(allRawValues.contains("browser-get-styles"))
        XCTAssertTrue(allRawValues.contains("browser-is-visible"))
        XCTAssertTrue(allRawValues.contains("browser-is-enabled"))
        XCTAssertTrue(allRawValues.contains("browser-is-checked"))
        XCTAssertTrue(allRawValues.contains("browser-find-role"))
        XCTAssertTrue(allRawValues.contains("browser-find-text"))
        XCTAssertTrue(allRawValues.contains("browser-find-label"))
        XCTAssertTrue(allRawValues.contains("browser-find-placeholder"))
        XCTAssertTrue(allRawValues.contains("browser-find-alt"))
        XCTAssertTrue(allRawValues.contains("browser-find-title"))
        XCTAssertTrue(allRawValues.contains("browser-find-testid"))
        XCTAssertTrue(allRawValues.contains("browser-find-first"))
        XCTAssertTrue(allRawValues.contains("browser-find-last"))
        XCTAssertTrue(allRawValues.contains("browser-find-nth"))
        XCTAssertTrue(allRawValues.contains("browser-screenshot"))
        XCTAssertTrue(allRawValues.contains("browser-console"))
        XCTAssertTrue(allRawValues.contains("browser-wait"))
        XCTAssertTrue(allRawValues.contains("browser-cookies-list"))
        XCTAssertTrue(allRawValues.contains("browser-cookies-set"))
        XCTAssertTrue(allRawValues.contains("browser-cookies-delete"))
        XCTAssertTrue(allRawValues.contains("browser-network"))
        XCTAssertTrue(allRawValues.contains("browser-frames"))
        XCTAssertTrue(allRawValues.contains("browser-downloads"))
        XCTAssertTrue(allRawValues.contains("browser-dialogs"))
        XCTAssertTrue(allRawValues.contains("browser-dialog-accept"))
        XCTAssertTrue(allRawValues.contains("browser-dialog-dismiss"))
        XCTAssertTrue(allRawValues.contains("browser-storage-list"))
        XCTAssertTrue(allRawValues.contains("browser-storage-get"))
        XCTAssertTrue(allRawValues.contains("browser-storage-set"))
        XCTAssertTrue(allRawValues.contains("browser-storage-delete"))
        XCTAssertTrue(allRawValues.contains("browser-import-preview"))
        XCTAssertTrue(allRawValues.contains("browser-import-run"))
    }

    // MARK: - BrowserViewModel.getState

    func test_getState_returnsURLAfterNavigation() {
        viewModel.navigate(to: "https://example.com")
        let state = viewModel.getState()
        XCTAssertEqual(state["url"], "https://example.com")
    }

    func test_getState_returnsEmptyURLWhenNoNavigation() {
        let freshVM = BrowserViewModel()
        let state = freshVM.getState()
        // No navigation happened yet, currentURL is nil.
        XCTAssertEqual(state["url"], "")
    }

    func test_getState_returnsTabCount() {
        let state = viewModel.getState()
        XCTAssertEqual(state["tabCount"], "1")
    }

    func test_getState_returnsLoadingState() {
        let state = viewModel.getState()
        XCTAssertEqual(state["isLoading"], "false")
    }

    func test_getState_returnsNavigationCapabilities() {
        let state = viewModel.getState()
        XCTAssertEqual(state["canGoBack"], "false")
        XCTAssertEqual(state["canGoForward"], "false")
    }

    func test_getState_returnsActiveTabID() {
        let state = viewModel.getState()
        XCTAssertNotNil(state["activeTabID"])
        XCTAssertFalse(state["activeTabID"]!.isEmpty)
    }

    func test_getState_reflectsTitle() {
        viewModel.updateActiveTabTitle("Test Page")
        let state = viewModel.getState()
        XCTAssertEqual(state["title"], "Test Page")
    }

    // MARK: - BrowserViewModel.getTabList

    func test_getTabList_returnsOneTabByDefault() {
        let tabs = viewModel.getTabList()
        XCTAssertEqual(tabs.count, 1)
    }

    func test_getTabList_returnsAllTabs() {
        viewModel.addBrowserTab(url: URL(string: "https://github.com")!)
        let tabs = viewModel.getTabList()
        XCTAssertEqual(tabs.count, 2)
    }

    func test_getTabList_containsRequiredKeys() {
        let tabs = viewModel.getTabList()
        let firstTab = tabs[0]
        XCTAssertNotNil(firstTab["id"])
        XCTAssertNotNil(firstTab["url"])
        XCTAssertNotNil(firstTab["title"])
        XCTAssertNotNil(firstTab["isActive"])
    }

    func test_getTabList_marksActiveTabCorrectly() {
        viewModel.addBrowserTab()
        let tabs = viewModel.getTabList()
        let activeTabs = tabs.filter { $0["isActive"] == "true" }
        XCTAssertEqual(activeTabs.count, 1, "Exactly one tab should be active")
    }

    func test_getTabList_tabURLMatchesNavigatedURL() {
        let customURL = URL(string: "https://swift.org")!
        viewModel.addBrowserTab(url: customURL)
        let tabs = viewModel.getTabList()
        let lastTab = tabs.last!
        XCTAssertEqual(lastTab["url"], "https://swift.org")
    }

    // MARK: - BrowserViewModel.evaluateJavaScript

    func test_evaluateJavaScript_emitsEvaluateJSAction() {
        var receivedAction: BrowserViewModel.NavigationAction?
        let cancellable = viewModel.navigationActionSubject
            .sink { receivedAction = $0 }

        viewModel.evaluateJavaScript("document.title")

        if case .evaluateJS(let script) = receivedAction {
            XCTAssertEqual(script, "document.title")
        } else {
            XCTFail("Expected .evaluateJS action, got \(String(describing: receivedAction))")
        }
        cancellable.cancel()
    }

    func test_evaluateJavaScript_preservesScriptContent() {
        var receivedScript: String?
        let cancellable = viewModel.navigationActionSubject
            .sink { action in
                if case .evaluateJS(let script) = action {
                    receivedScript = script
                }
            }

        let complexScript = "document.querySelectorAll('a').length"
        viewModel.evaluateJavaScript(complexScript)

        XCTAssertEqual(receivedScript, complexScript)
        cancellable.cancel()
    }

    // MARK: - AppSocketCommandHandler Browser Commands

    func test_browserNavigate_withURL_returnsSuccess() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bn-1",
            command: "browser-navigate",
            params: ["url": "https://example.com"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "navigated")
        XCTAssertEqual(viewModel.urlString, "https://example.com")
    }

    func test_browserNavigate_withMissingURL_returnsError() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bn-2",
            command: "browser-navigate",
            params: nil
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    func test_browserNavigate_withNilBrowserVM_returnsError() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: nil
        )
        let request = SocketRequest(
            id: "bn-3",
            command: "browser-navigate",
            params: ["url": "https://example.com"]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("not available") == true)
    }

    func test_browserNavigate_withProviderOverride_usesDynamicBrowserViewModel() {
        let providedViewModel: BrowserViewModel? = viewModel
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModelProviderOverride: { providedViewModel }
        )
        let request = SocketRequest(
            id: "bn-4",
            command: "browser-navigate",
            params: ["url": "https://cocxy.dev"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(viewModel.urlString, "https://cocxy.dev")
    }

    func test_browserNavigate_usesNavigationProviderWhenPanelMustBeOpened() {
        let providedViewModel: BrowserViewModel? = viewModel
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: nil,
            browserNavigationViewModelProviderOverride: {
                return providedViewModel
            }
        )
        let request = SocketRequest(
            id: "bn-5",
            command: "browser-navigate",
            params: ["url": "https://github.com/login/device"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(viewModel.urlString, "https://github.com/login/device")
    }

    func test_browserBack_returnsSuccess() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bb-1", command: "browser-back", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "acknowledged")
    }

    func test_browserForward_returnsSuccess() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bf-1", command: "browser-forward", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "acknowledged")
    }

    func test_browserReload_returnsSuccess() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "br-1", command: "browser-reload", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "acknowledged")
    }

    func test_browserGetState_returnsCurrentState() {
        viewModel.navigate(to: "https://example.com")
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bgs-1", command: "browser-get-state", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["url"], "https://example.com")
        XCTAssertNotNil(response.data?["tabCount"])
    }

    func test_browserGetState_withNilBrowserVM_returnsError() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: nil
        )
        let request = SocketRequest(id: "bgs-2", command: "browser-get-state", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("not available") == true)
    }

    func test_browserStateSave_writesStateSnapshotFile() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempURL)
        }
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("document.cookie"))
            XCTAssertTrue(script.contains("window.localStorage"))
            XCTAssertTrue(script.contains("window.sessionStorage"))
            return .success("""
            {"version":"1","url":"https://example.com","origin":"https://example.com","title":"Home","cookies":[{"name":"sid","value":"abc"}],"localStorage":[{"key":"theme","value":"dark"}],"sessionStorage":[{"key":"draft","value":"hello"}]}
            """)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )

        let response = handler.handleCommand(SocketRequest(
            id: "bstate-save-1",
            command: "browser-state-save",
            params: ["path": tempURL.path]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "saved")
        XCTAssertEqual(response.data?["path"], tempURL.path)
        let savedData = try Data(contentsOf: tempURL)
        let saved = try XCTUnwrap(JSONSerialization.jsonObject(with: savedData) as? [String: Any])
        XCTAssertEqual(saved["url"] as? String, "https://example.com")
        XCTAssertNotNil(saved["localStorage"])
        XCTAssertNotNil(saved["sessionStorage"])
    }

    func test_browserStateLoad_appliesSavedStateFile() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let savedState = """
        {"version":"1","url":"https://example.com","origin":"https://example.com","title":"Home","cookies":[{"name":"sid","value":"abc"}],"localStorage":[{"key":"theme","value":"dark"}],"sessionStorage":[{"key":"draft","value":"hello"}]}
        """
        try savedState.data(using: .utf8)?.write(to: tempURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tempURL)
        }
        var appliedScript = ""
        viewModel.scriptEvaluator = { script, _ in
            appliedScript = script
            return .success(#"{"status":"loaded","cookies":"1","localStorage":"1","sessionStorage":"1"}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )

        let response = handler.handleCommand(SocketRequest(
            id: "bstate-load-1",
            command: "browser-state-load",
            params: ["path": tempURL.path]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "loaded")
        XCTAssertEqual(response.data?["cookies"], "1")
        XCTAssertEqual(response.data?["localStorage"], "1")
        XCTAssertEqual(response.data?["sessionStorage"], "1")
        XCTAssertTrue(appliedScript.contains("document.cookie"))
        XCTAssertTrue(appliedScript.contains("window.localStorage.setItem"))
        XCTAssertTrue(appliedScript.contains("window.sessionStorage.setItem"))
    }

    func test_browserEval_withScript_returnsSuccess() {
        viewModel.scriptEvaluator = { script, _ in
            BrowserScriptEvaluationResult.success("eval:\(script)")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "be-1",
            command: "browser-eval",
            params: ["script": "document.title"]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "evaluated")
        XCTAssertEqual(response.data?["result"], "eval:document.title")
    }

    func test_browserAddScript_dispatchesInlineScriptInjection() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("document.createElement('script')"))
            XCTAssertTrue(script.contains("data-cocxy-added-script"))
            XCTAssertTrue(script.contains("window.__cocxySmoke = 1"))
            return .success(#"{"status":"added","type":"script","id":"cocxy-script-1"}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )

        let response = handler.handleCommand(SocketRequest(
            id: "badd-script-1",
            command: "browser-add-script",
            params: ["script": "window.__cocxySmoke = 1"]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "added")
        XCTAssertEqual(response.data?["type"], "script")
        XCTAssertEqual(response.data?["id"], "cocxy-script-1")
    }

    func test_browserAddStyle_dispatchesInlineStyleInjection() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("document.createElement('style')"))
            XCTAssertTrue(script.contains("data-cocxy-added-style"))
            XCTAssertTrue(script.contains("body { background: rgb(1, 2, 3); }"))
            return .success(#"{"status":"added","type":"style","id":"cocxy-style-1"}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )

        let response = handler.handleCommand(SocketRequest(
            id: "badd-style-1",
            command: "browser-add-style",
            params: ["css": "body { background: rgb(1, 2, 3); }"]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "added")
        XCTAssertEqual(response.data?["type"], "style")
        XCTAssertEqual(response.data?["id"], "cocxy-style-1")
    }

    func test_browserInitScriptAdd_recordsAndInstallsScript() {
        viewModel.initScriptInstaller = { script, _ in
            XCTAssertEqual(script, "window.__initSmoke = true;")
            return .success("installed")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )

        let response = handler.handleCommand(SocketRequest(
            id: "binit-add-1",
            command: "browser-init-script-add",
            params: ["script": "window.__initSmoke = true;"]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "added")
        XCTAssertEqual(response.data?["installed"], "true")
        XCTAssertEqual(response.data?["length"], "26")
        XCTAssertEqual(viewModel.initScripts.count, 1)
    }

    func test_browserInitScriptsList_returnsRegisteredScripts() {
        _ = viewModel.addInitScript("window.__first = 1;")
        _ = viewModel.addInitScript("window.__second = 2;")
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )

        let response = handler.handleCommand(SocketRequest(
            id: "binit-list-1",
            command: "browser-init-scripts-list",
            params: nil
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["count"], "2")
        XCTAssertEqual(response.data?["script_0_length"], "19")
        XCTAssertEqual(response.data?["script_1_length"], "20")
        XCTAssertNotNil(response.data?["script_0_id"])
        XCTAssertNotNil(response.data?["script_1_id"])
    }

    func test_browserDialogs_returnsPendingDialogMetadata() {
        _ = viewModel.recordJavaScriptDialog(
            kind: .prompt,
            message: "Deploy now?",
            defaultText: "main",
            url: "https://example.com/deploy",
            completion: { _ in }
        )
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )

        let response = handler.handleCommand(SocketRequest(
            id: "bdialogs-1",
            command: "browser-dialogs",
            params: nil
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["count"], "1")
        XCTAssertEqual(response.data?["dialog_0_type"], "prompt")
        XCTAssertEqual(response.data?["dialog_0_state"], "pending")
        XCTAssertEqual(response.data?["dialog_0_message"], "Deploy now?")
        XCTAssertEqual(response.data?["dialog_0_defaultText"], "main")
        XCTAssertEqual(response.data?["dialog_0_url"], "https://example.com/deploy")
        XCTAssertNotNil(response.data?["dialog_0_id"])
    }

    func test_browserDialogAccept_resolvesPromptWithText() {
        var resolution: BrowserDialogResolution?
        let dialog = viewModel.recordJavaScriptDialog(
            kind: .prompt,
            message: "Name?",
            defaultText: "Said",
            url: "https://example.com",
            completion: { resolution = $0 }
        )
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )

        let response = handler.handleCommand(SocketRequest(
            id: "bdialog-accept-1",
            command: "browser-dialog-accept",
            params: [
                "id": dialog.id.uuidString,
                "promptText": "Cocxy"
            ]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "accepted")
        XCTAssertEqual(response.data?["id"], dialog.id.uuidString)
        XCTAssertEqual(response.data?["type"], "prompt")
        XCTAssertEqual(resolution, .accept(promptText: "Cocxy"))
        XCTAssertEqual(viewModel.browserDialogs.first?.state, .accepted)
    }

    func test_browserDialogDismiss_resolvesConfirmAsDismissed() {
        var resolution: BrowserDialogResolution?
        let dialog = viewModel.recordJavaScriptDialog(
            kind: .confirm,
            message: "Delete item?",
            completion: { resolution = $0 }
        )
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )

        let response = handler.handleCommand(SocketRequest(
            id: "bdialog-dismiss-1",
            command: "browser-dialog-dismiss",
            params: ["id": dialog.id.uuidString]
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "dismissed")
        XCTAssertEqual(response.data?["id"], dialog.id.uuidString)
        XCTAssertEqual(response.data?["type"], "confirm")
        XCTAssertEqual(resolution, .dismiss)
        XCTAssertEqual(viewModel.browserDialogs.first?.state, .dismissed)
    }

    func test_browserEval_withMissingScript_returnsError() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "be-2",
            command: "browser-eval",
            params: nil
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("Missing") == true)
    }

    func test_browserEval_withOversizedScript_returnsError() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let oversizedScript = String(repeating: "x", count: 10_001)
        let request = SocketRequest(
            id: "be-3",
            command: "browser-eval",
            params: ["script": oversizedScript]
        )
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("exceeds") == true)
    }

    func test_browserEval_withExactMaxSize_returnsSuccess() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let maxScript = String(repeating: "x", count: 10_000)
        let request = SocketRequest(
            id: "be-4",
            command: "browser-eval",
            params: ["script": maxScript]
        )
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
    }

    func test_browserGetText_returnsSuccess() {
        viewModel.scriptEvaluator = { script, _ in
            BrowserScriptEvaluationResult.success(script.contains("innerText") ? "page text" : "")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bgt-1", command: "browser-get-text", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "evaluated")
        XCTAssertEqual(response.data?["text"], "page text")
    }

    func test_browserGetText_withNilBrowserVM_returnsError() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: nil
        )
        let request = SocketRequest(id: "bgt-2", command: "browser-get-text", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("not available") == true)
    }

    func test_browserListTabs_returnsTabData() {
        viewModel.addBrowserTab(url: URL(string: "https://github.com")!)
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "blt-1", command: "browser-list-tabs", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["count"], "2")
        XCTAssertNotNil(response.data?["tab_0_id"])
        XCTAssertNotNil(response.data?["tab_0_url"])
        XCTAssertNotNil(response.data?["tab_1_url"])
    }

    func test_browserListTabs_withNilBrowserVM_returnsError() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: nil
        )
        let request = SocketRequest(id: "blt-2", command: "browser-list-tabs", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("not available") == true)
    }

    func test_browserSnapshot_returnsHybridSnapshotAndConsoleSummary() {
        viewModel.recordConsoleEntry(level: "log", message: "ready")
        viewModel.recordConsoleEntry(level: "error", message: "failed")
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("cocxyRef"))
            XCTAssertTrue(script.contains("cocxyStableRefBase"))
            XCTAssertTrue(script.contains("accessibility"))
            XCTAssertTrue(script.contains("network"))
            XCTAssertTrue(script.contains("visual"))
            return .success(#"{"accessibility":[{"ref":"b1","role":"button","name":"Save"}],"dom":[{"tag":"button","ref":"b1","visible":"true"}],"visual":{"viewportWidth":"1024","viewportHeight":"768"},"page":{"url":"https://example.com","title":"Example","readyState":"complete"},"network":{"resourceCount":"2","resources":[{"url":"https://example.com/app.js"}]}}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bs-1", command: "browser-snapshot", params: nil)

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "captured")
        XCTAssertEqual(response.data?["snapshot"], #"[{"name":"Save","ref":"b1","role":"button"}]"#)
        XCTAssertEqual(response.data?["dom"], #"[{"ref":"b1","tag":"button","visible":"true"}]"#)
        XCTAssertEqual(response.data?["visual"], #"{"viewportHeight":"768","viewportWidth":"1024"}"#)
        XCTAssertEqual(response.data?["page"], #"{"readyState":"complete","title":"Example","url":"https:\/\/example.com"}"#)
        XCTAssertEqual(response.data?["network"], #"{"resourceCount":"2","resources":[{"url":"https:\/\/example.com\/app.js"}]}"#)
        XCTAssertEqual(response.data?["accessibilityCount"], "1")
        XCTAssertEqual(response.data?["domCount"], "1")
        XCTAssertEqual(response.data?["consoleCount"], "2")
        XCTAssertEqual(response.data?["consoleErrors"], "1")
        XCTAssertEqual(response.data?["console_error_0"], "failed")
    }

    func test_browserContext_returnsAgentReadyContextPack() {
        viewModel.recordConsoleEntry(level: "log", message: "ready")
        viewModel.recordConsoleEntry(level: "error", message: "failed")
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("capturedAt"))
            XCTAssertTrue(script.contains("targetRef = \"card-1\""))
            XCTAssertTrue(script.contains("const around = 2"))
            XCTAssertTrue(script.contains("const networkTail = 3"))
            XCTAssertTrue(script.contains("cocxyResolveStableRef"))
            XCTAssertTrue(script.contains("sanitizeHTML(element)"))
            XCTAssertTrue(script.contains("cloneNode(true)"))
            XCTAssertTrue(script.contains("formControl && name === 'value'"))
            XCTAssertTrue(script.contains("if (isSensitiveValueElement(element)) { return '[redacted]'; }"))
            XCTAssertTrue(script.contains("tag === 'textarea'"))
            XCTAssertFalse(script.contains("html: String(element.outerHTML"))
            return .success(#"{"status":"ok","capturedAt":"2026-05-16T12:00:00Z","page":{"url":"https://example.com","origin":"https://example.com","title":"Example","readyState":"complete","favicon":"https://example.com/favicon.ico"},"visual":{"viewportWidth":"1024","viewportHeight":"768","scrollX":"0","scrollY":"12"},"focused":{"present":"true","ref":"field-1"},"target":{"present":"true","ref":"card-1","name":"Card"},"dom":[{"ref":"card-1","tag":"section","name":"Card"}],"network":{"resourceCount":"2","entries":[{"url":"https://example.com/app.js","initiatorType":"script","duration":"5","transferSize":"12"}]}}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bctx-1",
            command: "browser-context",
            params: ["target": "card-1", "around": "2", "console": "1", "network": "3"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["url"], "https://example.com")
        XCTAssertEqual(response.data?["title"], "Example")
        XCTAssertEqual(response.data?["favicon"], "https://example.com/favicon.ico")
        XCTAssertEqual(response.data?["targetRef"], "card-1")
        XCTAssertEqual(response.data?["focusedRef"], "field-1")
        XCTAssertEqual(response.data?["domCount"], "1")
        XCTAssertEqual(response.data?["around"], "2")
        XCTAssertEqual(response.data?["networkTail"], "3")
        XCTAssertEqual(response.data?["consoleTail"], "1")
        XCTAssertEqual(response.data?["consoleCount"], "1")
        XCTAssertEqual(response.data?["consoleErrors"], "1")
        XCTAssertTrue(response.data?["page"]?.contains(#""title":"Example""#) == true)
        XCTAssertTrue(response.data?["dom"]?.contains(#""ref":"card-1""#) == true)
        XCTAssertTrue(response.data?["network"]?.contains("app.js") == true)
        XCTAssertTrue(response.data?["console"]?.contains("failed") == true)
        XCTAssertFalse(response.data?["console"]?.contains("ready") == true)
    }

    func test_browserClick_reresolvesStableRefWhenDataAttributeIsMissing() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains(#"data-cocxy-ref="id-save""#))
            XCTAssertTrue(script.contains("cocxyResolveStableRef(ref)"))
            XCTAssertTrue(script.contains("cocxyStableRefForElement"))
            XCTAssertTrue(script.contains("data-testid"))
            return .success(#"{"status":"clicked","ref":"id-save","actionable":"true","reason":"ok","attempts":"1","elapsedMs":"8","before":"{}","after":"{}","diff":"{\"changed\":\"false\",\"count\":\"0\"}","explanation":"Action clicked on id-save completed; no observable DOM summary change."}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bc-stable-ref-1", command: "browser-click", params: ["ref": "id-save"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "clicked")
        XCTAssertEqual(response.data?["ref"], "id-save")
        XCTAssertEqual(response.data?["actionable"], "true")
    }

    func test_browserClick_dispatchesElementRefClickScript() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains(#"data-cocxy-ref="b1""#))
            XCTAssertTrue(script.contains(".click()"))
            return .success("clicked")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bc-1", command: "browser-click", params: ["ref": "b1"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "clicked")
        XCTAssertEqual(response.data?["ref"], "b1")
    }

    func test_browserClick_usesAutoWaitActionabilityWithDefaultTimeout() {
        var receivedTimeout: TimeInterval?
        viewModel.scriptEvaluator = { script, timeout in
            receivedTimeout = timeout
            XCTAssertTrue(script.contains("waitForCocxyActionable"))
            XCTAssertTrue(script.contains("document.readyState"))
            XCTAssertTrue(script.contains("pointerEvents"))
            XCTAssertTrue(script.contains("5000"))
            XCTAssertTrue(script.contains("summarizeState"))
            XCTAssertTrue(script.contains("diffStates"))
            XCTAssertTrue(script.contains("[redacted]"))
            return .success(#"{"status":"clicked","ref":"b1","actionable":"true","reason":"ok","attempts":"2","elapsedMs":"64","before":"{\"target\":{\"name\":\"Save\"}}","after":"{\"target\":{\"name\":\"Saved\"}}","diff":"{\"changed\":\"true\",\"count\":\"1\"}","explanation":"Action clicked on b1 completed with 1 observable change(s); first change: target.name."}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bc-autowait-1", command: "browser-click", params: ["ref": "b1"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(receivedTimeout, 6)
        XCTAssertEqual(response.data?["status"], "clicked")
        XCTAssertEqual(response.data?["ref"], "b1")
        XCTAssertEqual(response.data?["actionable"], "true")
        XCTAssertEqual(response.data?["reason"], "ok")
        XCTAssertEqual(response.data?["attempts"], "2")
        XCTAssertEqual(response.data?["elapsedMs"], "64")
        XCTAssertEqual(response.data?["before"], #"{"target":{"name":"Save"}}"#)
        XCTAssertEqual(response.data?["after"], #"{"target":{"name":"Saved"}}"#)
        XCTAssertEqual(response.data?["diff"], #"{"changed":"true","count":"1"}"#)
        XCTAssertEqual(
            response.data?["explanation"],
            "Action clicked on b1 completed with 1 observable change(s); first change: target.name."
        )
    }

    func test_browserClick_timeoutParamControlsAutoWaitBudget() {
        var receivedTimeout: TimeInterval?
        viewModel.scriptEvaluator = { script, timeout in
            receivedTimeout = timeout
            XCTAssertTrue(script.contains("1250"))
            return .success(#"{"status":"timeout","ref":"b1","actionable":"false","reason":"not-visible","attempts":"25","elapsedMs":"1250"}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bc-autowait-2",
            command: "browser-click",
            params: ["ref": "b1", "timeout": "1250"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(receivedTimeout, 2.25)
        XCTAssertEqual(response.data?["status"], "timeout")
        XCTAssertEqual(response.data?["reason"], "not-visible")
        XCTAssertEqual(response.data?["actionable"], "false")
    }

    func test_browserClick_capturesActionScreenshotEvidenceWhenRequested() throws {
        let evidenceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: evidenceDir)
        }
        viewModel.scriptEvaluator = { _, _ in
            .success(#"{"status":"clicked","ref":"b1","actionable":"true"}"#)
        }
        viewModel.screenshotCapturer = { outputPath, _ in
            guard let outputPath else {
                return .failure("missing output path")
            }
            XCTAssertTrue(outputPath.hasPrefix(evidenceDir.path))
            try? Data([0x89, 0x50, 0x4E, 0x47]).write(to: URL(fileURLWithPath: outputPath))
            return .file(path: outputPath, byteCount: 4)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bc-evidence-1",
            command: "browser-click",
            params: ["ref": "b1", "screenshotDir": evidenceDir.path]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "clicked")
        XCTAssertEqual(response.data?["screenshotStatus"], "captured")
        XCTAssertEqual(response.data?["screenshotBytes"], "4")
        let screenshotPath = try XCTUnwrap(response.data?["screenshotPath"])
        XCTAssertTrue(screenshotPath.hasPrefix(evidenceDir.path))
        XCTAssertTrue(screenshotPath.hasSuffix(".png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: screenshotPath))
    }

    func test_browserDblClick_dispatchesElementRefDoubleClickScript() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains(#"data-cocxy-ref="b1""#))
            XCTAssertTrue(script.contains("dblclick"))
            XCTAssertTrue(script.contains("MouseEvent"))
            return .success("dblclicked")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bdc-1", command: "browser-dblclick", params: ["ref": "b1"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "dblclicked")
        XCTAssertEqual(response.data?["ref"], "b1")
    }

    func test_browserHover_dispatchesElementRefHoverScript() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains(#"data-cocxy-ref="b1""#))
            XCTAssertTrue(script.contains("mouseover"))
            XCTAssertTrue(script.contains("mousemove"))
            return .success("hovered")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bh-1", command: "browser-hover", params: ["ref": "b1"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "hovered")
        XCTAssertEqual(response.data?["ref"], "b1")
    }

    func test_browserFocus_dispatchesElementRefFocusScript() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains(#"data-cocxy-ref="i1""#))
            XCTAssertTrue(script.contains(".focus"))
            XCTAssertTrue(script.contains("activeElement"))
            return .success("focused")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bfocus-1", command: "browser-focus", params: ["ref": "i1"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "focused")
        XCTAssertEqual(response.data?["ref"], "i1")
    }

    func test_browserFill_dispatchesInputScriptWithEscapedText() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains(#"data-cocxy-ref="i1""#))
            XCTAssertTrue(script.contains("waitForCocxyActionable"))
            XCTAssertTrue(script.contains("hello"))
            XCTAssertTrue(script.contains("InputEvent"))
            return .success("filled")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bf-3",
            command: "browser-fill",
            params: ["ref": "i1", "text": "hello"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "filled")
        XCTAssertEqual(response.data?["ref"], "i1")
    }

    func test_browserUpload_readsLocalFileAndDispatchesInputDropScript() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        let fileURL = root.appendingPathComponent("fixture.txt")
        try Data("cocxy upload fixture".utf8).write(to: fileURL)

        viewModel.scriptEvaluator = { script, timeout in
            XCTAssertEqual(timeout, 4)
            XCTAssertTrue(script.contains(#"data-cocxy-ref="file-1""#))
            XCTAssertTrue(script.contains("new File"))
            XCTAssertTrue(script.contains("DataTransfer"))
            XCTAssertTrue(script.contains("drop"))
            XCTAssertTrue(script.contains("fixture.txt"))
            return .success(#"{"status":"uploaded","ref":"file-1","fileName":"fixture.txt","bytes":"20"}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bupload-1",
            command: "browser-upload",
            params: ["ref": "file-1", "path": fileURL.path, "timeout": "3000"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "uploaded")
        XCTAssertEqual(response.data?["ref"], "file-1")
        XCTAssertEqual(response.data?["fileName"], "fixture.txt")
        XCTAssertEqual(response.data?["bytes"], "20")
    }

    func test_browserType_dispatchesInsertTextScript() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains(#"data-cocxy-ref="i1""#))
            XCTAssertTrue(script.contains("hello"))
            XCTAssertTrue(script.contains("insertText"))
            return .success("typed")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "btype-1",
            command: "browser-type",
            params: ["ref": "i1", "text": "hello"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "typed")
        XCTAssertEqual(response.data?["ref"], "i1")
    }

    func test_browserType_withoutRefReturnsAgentSafeActionPayload() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertFalse(script.contains(#"data-cocxy-ref="i1""#))
            XCTAssertTrue(script.contains("document.activeElement"))
            XCTAssertTrue(script.contains("summarizeState"))
            XCTAssertTrue(script.contains("diffStates"))
            return .success(#"{"status":"typed","ref":"active","actionable":"true","reason":"ok","before":"{\"target\":{\"value\":\"\"}}","after":"{\"target\":{\"value\":\"hello\"}}","diff":"{\"changed\":\"true\",\"count\":\"1\"}","explanation":"Action typed on active completed with 1 observable change(s); first change: target.value."}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "btype-active-1",
            command: "browser-type",
            params: ["text": "hello"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "typed")
        XCTAssertEqual(response.data?["ref"], "active")
        XCTAssertEqual(response.data?["before"], #"{"target":{"value":""}}"#)
        XCTAssertEqual(response.data?["after"], #"{"target":{"value":"hello"}}"#)
        XCTAssertEqual(response.data?["diff"], #"{"changed":"true","count":"1"}"#)
        XCTAssertEqual(
            response.data?["explanation"],
            "Action typed on active completed with 1 observable change(s); first change: target.value."
        )
    }

    func test_browserPress_dispatchesKeyDownAndUpScript() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("KeyboardEvent"))
            XCTAssertTrue(script.contains("keydown"))
            XCTAssertTrue(script.contains("keyup"))
            XCTAssertTrue(script.contains("Enter"))
            XCTAssertTrue(script.contains("summarizeState"))
            XCTAssertTrue(script.contains("diffStates"))
            return .success(#"{"status":"pressed","ref":"active","actionable":"true","reason":"ok","before":"{\"activeRef\":\"input-1\"}","after":"{\"activeRef\":\"input-1\"}","diff":"{\"changed\":\"false\",\"count\":\"0\"}","explanation":"Action pressed on active completed; no observable DOM summary change."}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bpress-1", command: "browser-press", params: ["key": "Enter"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "pressed")
        XCTAssertEqual(response.data?["key"], "Enter")
        XCTAssertEqual(response.data?["ref"], "active")
        XCTAssertEqual(response.data?["before"], #"{"activeRef":"input-1"}"#)
        XCTAssertEqual(response.data?["after"], #"{"activeRef":"input-1"}"#)
        XCTAssertEqual(response.data?["diff"], #"{"changed":"false","count":"0"}"#)
        XCTAssertEqual(
            response.data?["explanation"],
            "Action pressed on active completed; no observable DOM summary change."
        )
    }

    func test_browserKeyDown_dispatchesKeyDownScript() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("KeyboardEvent"))
            XCTAssertTrue(script.contains("keydown"))
            XCTAssertFalse(script.contains("keyup"))
            return .success("keydown")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bkd-1", command: "browser-keydown", params: ["key": "Shift"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "keydown")
        XCTAssertEqual(response.data?["key"], "Shift")
    }

    func test_browserKeyUp_dispatchesKeyUpScript() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("KeyboardEvent"))
            XCTAssertTrue(script.contains("keyup"))
            return .success("keyup")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bku-1", command: "browser-keyup", params: ["key": "Shift"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "keyup")
        XCTAssertEqual(response.data?["key"], "Shift")
    }

    func test_browserCheck_dispatchesCheckboxStateScript() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains(#"data-cocxy-ref="agree-1""#))
            XCTAssertTrue(script.contains(".checked = true"))
            XCTAssertTrue(script.contains("change"))
            return .success("checked")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bcheck-1", command: "browser-check", params: ["ref": "agree-1"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "checked")
        XCTAssertEqual(response.data?["ref"], "agree-1")
    }

    func test_browserUncheck_dispatchesCheckboxStateScript() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains(#"data-cocxy-ref="agree-1""#))
            XCTAssertTrue(script.contains(".checked = false"))
            XCTAssertTrue(script.contains("change"))
            return .success("unchecked")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "buncheck-1", command: "browser-uncheck", params: ["ref": "agree-1"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "unchecked")
        XCTAssertEqual(response.data?["ref"], "agree-1")
    }

    func test_browserSelect_dispatchesSelectValueScript() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains(#"data-cocxy-ref="country-1""#))
            XCTAssertTrue(script.contains("option.value"))
            XCTAssertTrue(script.contains("Honduras"))
            return .success("selected")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bselect-1",
            command: "browser-select",
            params: ["ref": "country-1", "value": "Honduras"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "selected")
        XCTAssertEqual(response.data?["ref"], "country-1")
        XCTAssertEqual(response.data?["value"], "Honduras")
    }

    func test_browserScroll_dispatchesWindowScrollScript() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("window.scrollBy"))
            XCTAssertTrue(script.contains("120"))
            XCTAssertTrue(script.contains("-24"))
            XCTAssertTrue(script.contains("summarizeState"))
            XCTAssertTrue(script.contains("diffStates"))
            return .success(#"{"status":"scrolled","ref":"page","actionable":"true","reason":"ok","before":"{\"scroll\":{\"y\":\"0\"}}","after":"{\"scroll\":{\"y\":\"24\"}}","diff":"{\"changed\":\"true\",\"count\":\"1\"}","explanation":"Action scrolled on page completed with 1 observable change(s); first change: scroll.y."}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bscroll-1", command: "browser-scroll", params: ["x": "120", "y": "-24"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "scrolled")
        XCTAssertEqual(response.data?["x"], "120")
        XCTAssertEqual(response.data?["y"], "-24")
        XCTAssertEqual(response.data?["ref"], "page")
        XCTAssertEqual(response.data?["before"], #"{"scroll":{"y":"0"}}"#)
        XCTAssertEqual(response.data?["after"], #"{"scroll":{"y":"24"}}"#)
        XCTAssertEqual(response.data?["diff"], #"{"changed":"true","count":"1"}"#)
        XCTAssertEqual(
            response.data?["explanation"],
            "Action scrolled on page completed with 1 observable change(s); first change: scroll.y."
        )
    }

    func test_browserScrollIntoView_dispatchesElementScrollScript() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains(#"data-cocxy-ref="footer-1""#))
            XCTAssertTrue(script.contains("scrollIntoView"))
            return .success("scrolled")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bsiv-1",
            command: "browser-scroll-into-view",
            params: ["ref": "footer-1"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "scrolled")
        XCTAssertEqual(response.data?["ref"], "footer-1")
    }

    func test_browserGetHTML_returnsDocumentHTML() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("document.documentElement.outerHTML"))
            return .success("<html><body>ready</body></html>")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bhtml-1", command: "browser-get-html", params: nil)

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["html"], "<html><body>ready</body></html>")
    }

    func test_browserGetHTML_withRefReturnsElementHTML() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("cocxyResolveStableRef"))
            XCTAssertTrue(script.contains("card-1"))
            XCTAssertTrue(script.contains("outerHTML"))
            return .success("<section data-cocxy-ref=\"card-1\">ready</section>")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bhtml-2",
            command: "browser-get-html",
            params: ["ref": "card-1"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["ref"], "card-1")
        XCTAssertEqual(response.data?["html"], "<section data-cocxy-ref=\"card-1\">ready</section>")
    }

    func test_browserGetValue_returnsElementValue() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("cocxyResolveStableRef"))
            XCTAssertTrue(script.contains("i1"))
            XCTAssertTrue(script.contains("isContentEditable"))
            XCTAssertTrue(script.contains(".value"))
            return .success("hello")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bvalue-1", command: "browser-get-value", params: ["ref": "i1"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["ref"], "i1")
        XCTAssertEqual(response.data?["value"], "hello")
    }

    func test_browserGetAttr_returnsElementAttribute() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("cocxyResolveStableRef"))
            XCTAssertTrue(script.contains("link-1"))
            XCTAssertTrue(script.contains("getAttribute"))
            XCTAssertTrue(script.contains("href"))
            return .success(#"{"status":"ok","value":"https://cocxy.dev"}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "battr-1",
            command: "browser-get-attr",
            params: ["ref": "link-1", "name": "href"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["ref"], "link-1")
        XCTAssertEqual(response.data?["name"], "href")
        XCTAssertEqual(response.data?["value"], "https://cocxy.dev")
    }

    func test_browserGetTitle_returnsDocumentTitle() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("document.title"))
            return .success("Cocxy")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "btitle-1", command: "browser-get-title", params: nil)

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["title"], "Cocxy")
    }

    func test_browserGetCount_returnsSelectorCount() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("querySelectorAll"))
            XCTAssertTrue(script.contains(".item"))
            return .success("3")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bcount-1", command: "browser-get-count", params: ["selector": ".item"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["selector"], ".item")
        XCTAssertEqual(response.data?["count"], "3")
    }

    func test_browserGetBox_returnsElementBoundingBox() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("cocxyResolveStableRef"))
            XCTAssertTrue(script.contains("card-1"))
            XCTAssertTrue(script.contains("getBoundingClientRect"))
            return .success(#"{"status":"ok","x":"1","y":"2","width":"300","height":"40"}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bbox-1", command: "browser-get-box", params: ["ref": "card-1"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["ref"], "card-1")
        XCTAssertEqual(response.data?["width"], "300")
        XCTAssertEqual(response.data?["height"], "40")
    }

    func test_browserGetStyles_returnsComputedStyles() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("cocxyResolveStableRef"))
            XCTAssertTrue(script.contains("card-1"))
            XCTAssertTrue(script.contains("getComputedStyle"))
            XCTAssertTrue(script.contains("color"))
            return .success(#"{"status":"ok","styles":"{\"color\":\"rgb(1, 2, 3)\"}"}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bstyles-1",
            command: "browser-get-styles",
            params: ["ref": "card-1", "names": "color"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["ref"], "card-1")
        XCTAssertEqual(response.data?["styles"], #"{"color":"rgb(1, 2, 3)"}"#)
    }

    func test_browserIsVisible_returnsVisibilityPredicate() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("cocxyResolveStableRef"))
            XCTAssertTrue(script.contains("card-1"))
            XCTAssertTrue(script.contains("getBoundingClientRect"))
            return .success(#"{"status":"ok","visible":"true","reason":"visible"}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bvisible-1", command: "browser-is-visible", params: ["ref": "card-1"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["ref"], "card-1")
        XCTAssertEqual(response.data?["visible"], "true")
    }

    func test_browserIsEnabled_returnsEnabledPredicate() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("cocxyResolveStableRef"))
            XCTAssertTrue(script.contains("button-1"))
            XCTAssertTrue(script.contains("disabled"))
            return .success(#"{"status":"ok","enabled":"false","reason":"disabled"}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "benabled-1", command: "browser-is-enabled", params: ["ref": "button-1"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["ref"], "button-1")
        XCTAssertEqual(response.data?["enabled"], "false")
    }

    func test_browserIsChecked_returnsCheckedPredicate() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("cocxyResolveStableRef"))
            XCTAssertTrue(script.contains("agree-1"))
            XCTAssertTrue(script.contains("checked"))
            return .success(#"{"status":"ok","checked":"true"}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bchecked-1", command: "browser-is-checked", params: ["ref": "agree-1"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["ref"], "agree-1")
        XCTAssertEqual(response.data?["checked"], "true")
    }

    func test_browserFindRole_returnsMatchingRefs() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("roleFor"))
            XCTAssertTrue(script.contains("button"))
            XCTAssertTrue(script.contains("Save"))
            return .success(#"[{"ref":"b1","role":"button","name":"Save"}]"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bfind-role-1",
            command: "browser-find-role",
            params: ["role": "button", "name": "Save"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["count"], "1")
        XCTAssertEqual(response.data?["ref_0"], "b1")
        XCTAssertEqual(response.data?["name_0"], "Save")
    }

    func test_browserFindText_returnsMatchingRefs() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("textFor"))
            XCTAssertTrue(script.contains("Deploy"))
            return .success(#"[{"ref":"e1","role":"button","name":"Deploy"}]"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bfind-text-1", command: "browser-find-text", params: ["text": "Deploy"])

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["count"], "1")
        XCTAssertEqual(response.data?["ref_0"], "e1")
    }

    func test_browserFindTestID_returnsMatchingRefs() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("data-testid"))
            XCTAssertTrue(script.contains("submit-button"))
            return .success(#"[{"ref":"submit-1","role":"button","name":"Submit"}]"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bfind-testid-1",
            command: "browser-find-testid",
            params: ["id": "submit-button"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["count"], "1")
        XCTAssertEqual(response.data?["ref_0"], "submit-1")
    }

    func test_browserFindNth_returnsOneIndexedSelectorMatch() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("querySelectorAll"))
            XCTAssertTrue(script.contains(".row"))
            XCTAssertTrue(script.contains("nthIndex"))
            return .success(#"[{"ref":"row-2","role":"div","name":"Second"}]"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bfind-nth-1",
            command: "browser-find-nth",
            params: ["index": "1", "selector": ".row"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["count"], "1")
        XCTAssertEqual(response.data?["ref_0"], "row-2")
    }

    func test_browserScreenshot_returnsDataURLOrOutputPath() {
        viewModel.screenshotCapturer = { outputPath, _ in
            XCTAssertNil(outputPath)
            return .dataURL("data:image/png;base64,AAA=", byteCount: 3)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bss-1", command: "browser-screenshot", params: nil)

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "captured")
        XCTAssertEqual(response.data?["dataURL"], "data:image/png;base64,AAA=")
    }

    func test_browserScreenshot_withOversizedInlineDataURLReturnsHelpfulError() {
        viewModel.screenshotCapturer = { outputPath, _ in
            XCTAssertNil(outputPath)
            return .dataURL(
                "data:image/png;base64,\(String(repeating: "A", count: 70_000))",
                byteCount: 52_500
            )
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bss-oversized-1", command: "browser-screenshot", params: nil)

        let response = handler.handleCommand(request)

        XCTAssertFalse(response.success)
        XCTAssertTrue(response.error?.contains("--output") == true)
    }

    func test_browserConsole_returnsBufferedConsoleEntries() {
        viewModel.recordConsoleEntry(level: "log", message: "ready")
        viewModel.recordConsoleEntry(level: "error", message: "failed")
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bcns-1", command: "browser-console", params: nil)

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["count"], "2")
        XCTAssertEqual(response.data?["entry_0_level"], "log")
        XCTAssertEqual(response.data?["entry_1_message"], "failed")
    }

    func test_browserWait_returnsFoundWhenSelectorAppears() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("querySelector"))
            XCTAssertTrue(script.contains("#ready"))
            return .success("found")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bwait-1",
            command: "browser-wait",
            params: ["selector": "#ready", "timeout": "100"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "found")
        XCTAssertEqual(response.data?["selector"], "#ready")
    }

    func test_browserCookiesList_parsesDocumentCookiePairs() {
        viewModel.scriptEvaluator = { _, _ in .success("sid=abc; theme=dark") }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bcl-1", command: "browser-cookies-list", params: nil)

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["count"], "2")
        XCTAssertEqual(response.data?["cookie_0_name"], "sid")
        XCTAssertEqual(response.data?["cookie_0_value"], "abc")
        XCTAssertEqual(response.data?["cookie_1_name"], "theme")
    }

    func test_browserCookiesSet_andDeleteWriteDocumentCookie() {
        var scripts: [String] = []
        viewModel.scriptEvaluator = { script, _ in
            scripts.append(script)
            return .success("ok")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )

        let setResponse = handler.handleCommand(SocketRequest(
            id: "bcs-1",
            command: "browser-cookies-set",
            params: ["name": "sid", "value": "abc", "path": "/", "same-site": "Lax"]
        ))
        let deleteResponse = handler.handleCommand(SocketRequest(
            id: "bcd-1",
            command: "browser-cookies-delete",
            params: ["name": "sid", "path": "/"]
        ))

        XCTAssertTrue(setResponse.success)
        XCTAssertEqual(setResponse.data?["status"], "set")
        XCTAssertTrue(deleteResponse.success)
        XCTAssertEqual(deleteResponse.data?["status"], "deleted")
        XCTAssertTrue(scripts.first?.contains("sid=abc") == true)
        XCTAssertTrue(scripts.last?.contains("Max-Age=0") == true)
    }

    func test_browserStorageList_returnsStorageEntries() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("window.localStorage"))
            XCTAssertTrue(script.contains("JSON.stringify"))
            return .success(#"[{"key":"theme","value":"dark"},{"key":"token","value":"abc"}]"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bstorage-list-1",
            command: "browser-storage-list",
            params: ["area": "local"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["area"], "local")
        XCTAssertEqual(response.data?["count"], "2")
        XCTAssertEqual(response.data?["key_0"], "theme")
        XCTAssertEqual(response.data?["value_1"], "abc")
    }

    func test_browserStorageGet_returnsSessionStorageValue() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("window.sessionStorage"))
            XCTAssertTrue(script.contains("getItem"))
            XCTAssertTrue(script.contains("draft"))
            return .success(#"{"status":"ok","value":"hello"}"#)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bstorage-get-1",
            command: "browser-storage-get",
            params: ["area": "session", "key": "draft"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["area"], "session")
        XCTAssertEqual(response.data?["key"], "draft")
        XCTAssertEqual(response.data?["value"], "hello")
    }

    func test_browserStorageSetAndDeleteDispatchesStorageMutationScripts() {
        var scripts: [String] = []
        viewModel.scriptEvaluator = { script, _ in
            scripts.append(script)
            return .success("ok")
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )

        let setResponse = handler.handleCommand(SocketRequest(
            id: "bstorage-set-1",
            command: "browser-storage-set",
            params: ["area": "local", "key": "theme", "value": "dark"]
        ))
        let deleteResponse = handler.handleCommand(SocketRequest(
            id: "bstorage-delete-1",
            command: "browser-storage-delete",
            params: ["area": "local", "key": "theme"]
        ))

        XCTAssertTrue(setResponse.success)
        XCTAssertEqual(setResponse.data?["status"], "set")
        XCTAssertEqual(setResponse.data?["area"], "local")
        XCTAssertEqual(setResponse.data?["key"], "theme")
        XCTAssertTrue(deleteResponse.success)
        XCTAssertEqual(deleteResponse.data?["status"], "deleted")
        XCTAssertEqual(deleteResponse.data?["key"], "theme")
        XCTAssertEqual(scripts.count, 2)
        XCTAssertTrue(scripts[0].contains("setItem"))
        XCTAssertTrue(scripts[1].contains("removeItem"))
    }

    func test_browserNetwork_filtersAndTailsPerformanceEntries() {
        viewModel.scriptEvaluator = { _, _ in
            .success("""
            [
              {"url":"https://example.com/style.css","method":"GET","initiatorType":"link","duration":4.5,"transferSize":100},
              {"url":"https://example.com/api/users","method":"XHR","initiatorType":"fetch","duration":12.25,"transferSize":2048}
            ]
            """)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(
            id: "bnw-1",
            command: "browser-network",
            params: ["filter": "api", "tail": "1"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["count"], "1")
        XCTAssertEqual(response.data?["entry_0_url"], "https://example.com/api/users")
        XCTAssertEqual(response.data?["entry_0_method"], "XHR")
        XCTAssertEqual(response.data?["entry_0_transferSize"], "2048")
    }

    func test_browserFrames_returnsFrameTree() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("window.frames"))
            XCTAssertTrue(script.contains("document.querySelectorAll('iframe')"))
            return .success("""
            [
              {"path":"main","name":"","url":"https://example.com","title":"Home","isMain":"true","sameOrigin":"true"},
              {"path":"0","name":"preview","url":"https://example.com/frame","title":"Preview","isMain":"false","sameOrigin":"true"}
            ]
            """)
        }
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let response = handler.handleCommand(SocketRequest(
            id: "bframes-1",
            command: "browser-frames",
            params: nil
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["count"], "2")
        XCTAssertEqual(response.data?["frame_0_path"], "main")
        XCTAssertEqual(response.data?["frame_0_title"], "Home")
        XCTAssertEqual(response.data?["frame_1_name"], "preview")
        XCTAssertEqual(response.data?["frame_1_url"], "https://example.com/frame")
    }

    func test_browserDownloads_returnsTrackedDownloads() {
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        viewModel.addDownload(DownloadItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000111")!,
            fileName: "report.pdf",
            sourceURL: "https://example.com/report.pdf",
            totalBytes: 1_000,
            receivedBytes: 1_000,
            state: .completed,
            localPath: "/tmp/report.pdf",
            startedAt: startedAt
        ))
        viewModel.addDownload(DownloadItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000222")!,
            fileName: "assets.zip",
            sourceURL: "https://example.com/assets.zip",
            totalBytes: 2_000,
            receivedBytes: 500,
            state: .downloading(progress: 0.25),
            localPath: nil,
            startedAt: startedAt
        ))
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )

        let response = handler.handleCommand(SocketRequest(
            id: "bdownloads-1",
            command: "browser-downloads",
            params: nil
        ))

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "ok")
        XCTAssertEqual(response.data?["count"], "2")
        XCTAssertEqual(response.data?["download_0_fileName"], "report.pdf")
        XCTAssertEqual(response.data?["download_0_state"], "completed")
        XCTAssertEqual(response.data?["download_0_progress"], "1")
        XCTAssertEqual(response.data?["download_0_localPath"], "/tmp/report.pdf")
        XCTAssertEqual(response.data?["download_1_state"], "downloading")
        XCTAssertEqual(response.data?["download_1_progress"], "0.25")
        XCTAssertEqual(response.data?["download_1_receivedBytes"], "500")
    }

    func test_browserImportPreview_routesToImportProvider() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserImportProvider: { kind, params in
                XCTAssertEqual(kind, "preview")
                XCTAssertEqual(params["source"], "chrome")
                XCTAssertEqual(params["domain-whitelist"], "example.com")
                return (true, ["status": "previewed", "cookies": "2"])
            }
        )
        let request = SocketRequest(
            id: "bip-1",
            command: "browser-import-preview",
            params: ["source": "chrome", "domain-whitelist": "example.com"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "previewed")
        XCTAssertEqual(response.data?["cookies"], "2")
    }

    func test_browserImportRun_routesToImportProvider() {
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserImportProvider: { kind, params in
                XCTAssertEqual(kind, "run")
                XCTAssertEqual(params["source"], "firefox")
                return (true, ["status": "imported", "history": "3", "cookies": "1"])
            }
        )
        let request = SocketRequest(
            id: "bir-1",
            command: "browser-import-run",
            params: ["source": "firefox"]
        )

        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "imported")
        XCTAssertEqual(response.data?["history"], "3")
        XCTAssertEqual(response.data?["cookies"], "1")
    }

    // MARK: - Browser Navigation Actions Emitted by Handler

    func test_browserBack_emitsGoBackAction() {
        var receivedAction: BrowserViewModel.NavigationAction?
        let cancellable = viewModel.navigationActionSubject
            .sink { receivedAction = $0 }

        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "ba-1", command: "browser-back", params: nil)
        _ = handler.handleCommand(request)

        if case .goBack = receivedAction {} else {
            XCTFail("Expected .goBack action, got \(String(describing: receivedAction))")
        }
        cancellable.cancel()
    }

    func test_browserForward_emitsGoForwardAction() {
        var receivedAction: BrowserViewModel.NavigationAction?
        let cancellable = viewModel.navigationActionSubject
            .sink { receivedAction = $0 }

        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bf-2", command: "browser-forward", params: nil)
        _ = handler.handleCommand(request)

        if case .goForward = receivedAction {} else {
            XCTFail("Expected .goForward action, got \(String(describing: receivedAction))")
        }
        cancellable.cancel()
    }

    func test_browserReload_emitsReloadAction() {
        var receivedAction: BrowserViewModel.NavigationAction?
        let cancellable = viewModel.navigationActionSubject
            .sink { receivedAction = $0 }

        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "br-2", command: "browser-reload", params: nil)
        _ = handler.handleCommand(request)

        if case .reload = receivedAction {} else {
            XCTFail("Expected .reload action, got \(String(describing: receivedAction))")
        }
        cancellable.cancel()
    }
}
