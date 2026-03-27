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
