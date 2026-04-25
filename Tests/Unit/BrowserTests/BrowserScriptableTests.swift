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
            "browser-list-tabs"
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
        let handler = AppSocketCommandHandler(
            tabManager: nil,
            hookEventReceiver: nil,
            browserViewModel: viewModel
        )
        let request = SocketRequest(id: "bgt-1", command: "browser-get-text", params: nil)
        let response = handler.handleCommand(request)

        XCTAssertTrue(response.success)
        XCTAssertEqual(response.data?["status"], "evaluated")
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
