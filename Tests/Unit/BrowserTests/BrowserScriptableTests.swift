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
            "browser-eval",
            "browser-get-text",
            "browser-list-tabs",
            "browser-snapshot",
            "browser-click",
            "browser-fill",
            "browser-screenshot",
            "browser-console",
            "browser-wait",
            "browser-cookies-list",
            "browser-cookies-set",
            "browser-cookies-delete",
            "browser-network",
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
        XCTAssertTrue(allRawValues.contains("browser-eval"))
        XCTAssertTrue(allRawValues.contains("browser-list-tabs"))
        XCTAssertTrue(allRawValues.contains("browser-snapshot"))
        XCTAssertTrue(allRawValues.contains("browser-click"))
        XCTAssertTrue(allRawValues.contains("browser-fill"))
        XCTAssertTrue(allRawValues.contains("browser-screenshot"))
        XCTAssertTrue(allRawValues.contains("browser-console"))
        XCTAssertTrue(allRawValues.contains("browser-wait"))
        XCTAssertTrue(allRawValues.contains("browser-cookies-list"))
        XCTAssertTrue(allRawValues.contains("browser-cookies-set"))
        XCTAssertTrue(allRawValues.contains("browser-cookies-delete"))
        XCTAssertTrue(allRawValues.contains("browser-network"))
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

    func test_browserSnapshot_returnsAccessibilityTreeJSON() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains("cocxyRef"))
            return .success(#"[{"ref":"b1","role":"button","name":"Save"}]"#)
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
        XCTAssertEqual(response.data?["snapshot"], #"[{"ref":"b1","role":"button","name":"Save"}]"#)
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

    func test_browserFill_dispatchesInputScriptWithEscapedText() {
        viewModel.scriptEvaluator = { script, _ in
            XCTAssertTrue(script.contains(#"data-cocxy-ref="i1""#))
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
