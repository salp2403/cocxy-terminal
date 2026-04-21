// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// BrowserViewModelTests.swift - Tests for browser URL normalization and navigation.

import XCTest
import Combine
@testable import CocxyTerminal

@MainActor
final class BrowserViewModelTests: XCTestCase {

    // MARK: - URL Normalization

    func testNavigateWithHTTPSScheme() {
        let vm = BrowserViewModel()
        vm.navigate(to: "https://example.com")
        XCTAssertEqual(vm.urlString, "https://example.com")
    }

    func testNavigateWithHTTPScheme() {
        let vm = BrowserViewModel()
        vm.navigate(to: "http://example.com")
        XCTAssertEqual(vm.urlString, "http://example.com")
    }

    func testNavigateLocalhostAddsHTTP() {
        let vm = BrowserViewModel()
        vm.navigate(to: "localhost:3000")
        XCTAssertEqual(vm.urlString, "http://localhost:3000")
    }

    func testNavigate127AddsHTTP() {
        let vm = BrowserViewModel()
        vm.navigate(to: "127.0.0.1:8080")
        XCTAssertEqual(vm.urlString, "http://127.0.0.1:8080")
    }

    func testNavigateBareHostAddsHTTPS() {
        let vm = BrowserViewModel()
        vm.navigate(to: "example.com")
        XCTAssertEqual(vm.urlString, "https://example.com")
    }

    func testNavigateEmptyStringIsNoOp() {
        let vm = BrowserViewModel()
        let original = vm.urlString
        vm.navigate(to: "")
        XCTAssertEqual(vm.urlString, original)
    }

    func testNavigateWhitespaceOnlyIsNoOp() {
        let vm = BrowserViewModel()
        let original = vm.urlString
        vm.navigate(to: "   ")
        XCTAssertEqual(vm.urlString, original)
    }

    func testNavigateTrimsWhitespace() {
        let vm = BrowserViewModel()
        vm.navigate(to: "  https://example.com  ")
        XCTAssertEqual(vm.urlString, "https://example.com")
    }

    func testNavigateSetsCurrentURL() {
        let vm = BrowserViewModel()
        vm.navigate(to: "https://example.com/path")
        XCTAssertEqual(vm.currentURL?.absoluteString, "https://example.com/path")
    }

    // MARK: - Navigation Actions

    func testNavigationActionSubjectEmitsLoad() {
        let vm = BrowserViewModel()
        var received: BrowserViewModel.NavigationAction?
        let cancellable = vm.navigationActionSubject.sink { received = $0 }

        vm.navigate(to: "https://test.com")

        if case .load(let url) = received {
            XCTAssertEqual(url.absoluteString, "https://test.com")
        } else {
            XCTFail("Expected .load action")
        }
        cancellable.cancel()
    }

    func testGoBackEmitsAction() {
        let vm = BrowserViewModel()
        var received: BrowserViewModel.NavigationAction?
        let cancellable = vm.navigationActionSubject.sink { received = $0 }

        vm.goBack()

        if case .goBack = received {} else {
            XCTFail("Expected .goBack action")
        }
        cancellable.cancel()
    }

    func testGoForwardEmitsAction() {
        let vm = BrowserViewModel()
        var received: BrowserViewModel.NavigationAction?
        let cancellable = vm.navigationActionSubject.sink { received = $0 }

        vm.goForward()

        if case .goForward = received {} else {
            XCTFail("Expected .goForward action")
        }
        cancellable.cancel()
    }

    func testReloadEmitsAction() {
        let vm = BrowserViewModel()
        var received: BrowserViewModel.NavigationAction?
        let cancellable = vm.navigationActionSubject.sink { received = $0 }

        vm.reload()

        if case .reload = received {} else {
            XCTFail("Expected .reload action")
        }
        cancellable.cancel()
    }

    func testActivateProfilePublishesProfileIDAndReloadsCurrentURL() {
        let vm = BrowserViewModel()
        let profileID = UUID()
        vm.navigate(to: "https://example.com/profile")

        var received: BrowserViewModel.NavigationAction?
        let cancellable = vm.navigationActionSubject.sink { received = $0 }

        vm.activateProfile(profileID)

        XCTAssertEqual(vm.activeProfileID, profileID)
        if case .load(let url) = received {
            XCTAssertEqual(url.absoluteString, "https://example.com/profile")
        } else {
            XCTFail("Expected profile activation to reload the current URL")
        }
        cancellable.cancel()
    }

    func testActivateSameProfileDoesNotReload() {
        let vm = BrowserViewModel()
        let profileID = UUID()
        vm.activeProfileID = profileID

        var reloadCount = 0
        let cancellable = vm.navigationActionSubject.sink { _ in reloadCount += 1 }

        vm.activateProfile(profileID)

        XCTAssertEqual(reloadCount, 0)
        cancellable.cancel()
    }

    func testAddBrowserTabEmitsLoadForNewTabURL() {
        let vm = BrowserViewModel()
        var received: BrowserViewModel.NavigationAction?
        let expectedURL = URL(string: "https://docs.cocxy.dev")!
        let cancellable = vm.navigationActionSubject.sink { received = $0 }

        vm.addBrowserTab(url: expectedURL)

        if case .load(let url) = received {
            XCTAssertEqual(url, expectedURL)
        } else {
            XCTFail("Expected addBrowserTab to emit .load for the new tab")
        }
        cancellable.cancel()
    }

    func testSelectBrowserTabEmitsLoadForSelectedTab() {
        let vm = BrowserViewModel()
        let selectedURL = URL(string: "https://example.com/selected")!
        vm.addBrowserTab(url: selectedURL)

        guard let targetID = vm.activeTabID else {
            XCTFail("Expected an active browser tab after creation")
            return
        }

        var received: BrowserViewModel.NavigationAction?
        let cancellable = vm.navigationActionSubject.sink { received = $0 }

        vm.selectBrowserTab(targetID)

        if case .load(let url) = received {
            XCTAssertEqual(url, selectedURL)
        } else {
            XCTFail("Expected selectBrowserTab to emit .load for the selected tab")
        }
        cancellable.cancel()
    }

    func testCloseActiveBrowserTabLoadsReplacementTab() {
        let vm = BrowserViewModel()
        let originalID = vm.activeTabID
        let secondaryURL = URL(string: "https://example.com/secondary")!
        vm.addBrowserTab(url: secondaryURL)

        guard let secondaryID = vm.activeTabID,
              secondaryID != originalID else {
            XCTFail("Expected a distinct active tab after adding a second browser tab")
            return
        }

        var received: BrowserViewModel.NavigationAction?
        let cancellable = vm.navigationActionSubject.sink { received = $0 }

        vm.closeBrowserTab(secondaryID)

        if case .load(let url) = received {
            XCTAssertEqual(url.absoluteString, vm.currentURL?.absoluteString)
        } else {
            XCTFail("Expected closing the active tab to load the replacement tab")
        }
        cancellable.cancel()
    }

    // MARK: - Default State

    func testDefaultURLIsLocalhost3000() {
        let vm = BrowserViewModel()
        XCTAssertEqual(vm.urlString, "http://localhost:3000")
    }

    func testDefaultLoadingIsFalse() {
        let vm = BrowserViewModel()
        XCTAssertFalse(vm.isLoading)
    }

    func testDefaultCanGoBackIsFalse() {
        let vm = BrowserViewModel()
        XCTAssertFalse(vm.canGoBack)
    }
}
