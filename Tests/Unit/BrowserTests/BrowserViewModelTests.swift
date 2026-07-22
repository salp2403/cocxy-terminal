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

    func testNavigateUsesLastExplicitURLWhenAddressBarContainsStaleURL() {
        let vm = BrowserViewModel()
        vm.navigate(to: "http://localhost:3000/http://cocxy.dev/")
        XCTAssertEqual(vm.urlString, "http://cocxy.dev/")
    }

    func testRepairedEditableURLInputPreservesSingleExplicitURL() {
        XCTAssertEqual(
            BrowserViewModel.repairedEditableURLInput(" http://localhost:3000/ "),
            "http://localhost:3000/"
        )
    }

    func testRepairedEditableURLInputPreservesRedirectParameters() {
        XCTAssertEqual(
            BrowserViewModel.repairedEditableURLInput("https://example.com/?next=http://cocxy.dev/"),
            "https://example.com/?next=http://cocxy.dev/"
        )
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

    func testRemoteBrowserProfileStateIsLocalByDefault() {
        let vm = BrowserViewModel()

        let state = vm.getState()

        XCTAssertNil(vm.activeRemoteBrowserProfile)
        XCTAssertEqual(state["browserRoute"], "local")
        XCTAssertNil(state["remoteBrowserProfileID"])
        XCTAssertNil(state["remoteRouting"])
    }

    func testAttachRemoteBrowserProfileUpdatesStateWithoutNavigation() {
        let vm = BrowserViewModel()
        let remote = RemoteBrowserProfile(
            connectionProfileID: UUID(),
            name: "Remote Dev",
            host: "dev.internal",
            user: "said",
            sshPort: 2222,
            localForwardedPorts: [5173: 55173],
            socksPort: 1080,
            httpConnectPort: 18080,
            proxyHealth: .active
        )
        var reloadCount = 0
        let cancellable = vm.navigationActionSubject.sink { _ in reloadCount += 1 }

        vm.attachRemoteBrowserProfile(remote)

        let state = vm.getState()
        XCTAssertEqual(vm.activeRemoteBrowserProfile, remote)
        XCTAssertEqual(reloadCount, 0)
        XCTAssertEqual(state["browserRoute"], "remote")
        XCTAssertEqual(state["remoteBrowserProfileID"], remote.id.uuidString)
        XCTAssertEqual(state["remoteConnectionProfileID"], remote.connectionProfileID.uuidString)
        XCTAssertEqual(state["remoteDisplayTitle"], "Remote Dev (said@dev.internal:2222)")
        XCTAssertEqual(state["remoteHost"], "dev.internal")
        XCTAssertEqual(state["remoteProxyHealth"], "active")
        XCTAssertEqual(state["remoteSOCKSPort"], "1080")
        XCTAssertEqual(state["remoteHTTPConnectPort"], "18080")
        XCTAssertEqual(state["remoteRouting"], "health=active socks=127.0.0.1:1080 http-connect=127.0.0.1:18080 forwards=5173->55173")

        vm.clearRemoteBrowserProfile()

        XCTAssertNil(vm.activeRemoteBrowserProfile)
        XCTAssertEqual(vm.getState()["browserRoute"], "local")
        cancellable.cancel()
    }

    func testOpenRemoteForwardAttachesProfileAndNavigatesLocalMapping() {
        let vm = BrowserViewModel()
        let remote = RemoteBrowserProfile(
            connectionProfileID: UUID(),
            name: "Remote Dev",
            host: "dev.internal",
            localForwardedPorts: [3000: 53000],
            proxyHealth: .active
        )
        var received: BrowserViewModel.NavigationAction?
        let cancellable = vm.navigationActionSubject.sink { received = $0 }

        let route = vm.openRemoteForward(remote, remotePort: 3000, path: "dashboard")

        XCTAssertEqual(vm.activeRemoteBrowserProfile, remote)
        XCTAssertEqual(route?.remoteAddress, "dev.internal:3000")
        XCTAssertEqual(route?.localURL.absoluteString, "http://127.0.0.1:53000/dashboard")
        XCTAssertEqual(vm.currentURL?.absoluteString, "http://127.0.0.1:53000/dashboard")
        XCTAssertEqual(vm.getState()["browserRoute"], "remote")
        if case .load(let url) = received {
            XCTAssertEqual(url.absoluteString, "http://127.0.0.1:53000/dashboard")
        } else {
            XCTFail("Expected opening a remote forward to load the mapped local URL")
        }
        cancellable.cancel()
    }

    func testOpenRemoteForwardWithoutMappingDoesNotNavigateOrAttach() {
        let vm = BrowserViewModel()
        let originalURL = vm.urlString
        let remote = RemoteBrowserProfile(
            connectionProfileID: UUID(),
            name: "Remote Dev",
            host: "dev.internal",
            localForwardedPorts: [:],
            proxyHealth: .active
        )
        var reloadCount = 0
        let cancellable = vm.navigationActionSubject.sink { _ in reloadCount += 1 }

        let route = vm.openRemoteForward(remote, remotePort: 3000)

        XCTAssertNil(route)
        XCTAssertNil(vm.activeRemoteBrowserProfile)
        XCTAssertEqual(vm.urlString, originalURL)
        XCTAssertEqual(reloadCount, 0)
        XCTAssertEqual(vm.remoteBrowserNotice?.kind, .missingForward)
        XCTAssertEqual(vm.remoteBrowserNotice?.routeRequest?.remotePort, 3000)
        XCTAssertEqual(vm.getState()["remoteNotice"], "missingForward")
        XCTAssertEqual(vm.getState()["remoteNoticePort"], "3000")
        cancellable.cancel()
    }

    func testOpenRemoteBrokeredRouteInstallsCapabilityBeforeHostReload() {
        let vm = BrowserViewModel()
        let connectionProfileID = UUID()
        let remote = RemoteBrowserProfile(
            connectionProfileID: connectionProfileID,
            name: "Remote Dev",
            host: "dev.internal"
        )
        let capability = RemoteBrowserProxyCapability(
            id: UUID(),
            ownerWindowID: WindowID(),
            profileID: connectionProfileID,
            remotePort: 3000,
            localProxyPort: 53_000,
            credentials: ProxyCredentials(password: "route-secret"),
            expiresAt: Date().addingTimeInterval(60)
        )
        var navigationActionCount = 0
        let cancellable = vm.navigationActionSubject.sink { _ in navigationActionCount += 1 }

        XCTAssertNil(vm.openRemoteBrokeredRoute(
            remote,
            capability: capability,
            scheme: "file"
        ))

        let route = vm.openRemoteBrokeredRoute(
            remote,
            capability: capability,
            path: "dashboard"
        )

        let expectedURL = "http://\(capability.browserHost):3000/dashboard"
        XCTAssertEqual(route?.localURL.absoluteString, expectedURL)
        XCTAssertEqual(vm.currentURL?.absoluteString, expectedURL)
        XCTAssertEqual(vm.activeRemoteBrowserProxyCapability, capability)
        XCTAssertEqual(vm.activeRemoteBrowserProfile?.socksPort, 53_000)
        XCTAssertEqual(vm.activeRemoteBrowserProfile?.localForwardedPorts, [:])
        XCTAssertEqual(vm.activeRemoteBrowserProfile?.proxyHealth, .active)
        XCTAssertEqual(navigationActionCount, 0)
        XCTAssertFalse(vm.getState().values.contains("route-secret"))
        XCTAssertTrue(vm.allowsNavigationForActiveRemoteRoute(route?.localURL))
        XCTAssertFalse(vm.allowsNavigationForActiveRemoteRoute(
            URL(string: "http://localhost:3000/")
        ))
        XCTAssertFalse(vm.allowsNavigationForActiveRemoteRoute(
            URL(string: "https://example.com/")
        ))
        XCTAssertTrue(vm.allowsDevelopmentServerTrust(host: capability.browserHost))
        XCTAssertFalse(vm.allowsDevelopmentServerTrust(host: "localhost"))
        vm.navigate(to: "http://localhost:3000/bypass")
        XCTAssertEqual(vm.currentURL?.absoluteString, expectedURL)
        XCTAssertEqual(navigationActionCount, 0)

        let renewedCapability = RemoteBrowserProxyCapability(
            id: UUID(),
            ownerWindowID: capability.ownerWindowID,
            profileID: connectionProfileID,
            remotePort: 3000,
            localProxyPort: 53_001,
            credentials: ProxyCredentials(password: "renewed-route-secret"),
            expiresAt: Date().addingTimeInterval(120)
        )
        XCTAssertTrue(vm.refreshRemoteBrowserProxyCapability(renewedCapability))
        XCTAssertEqual(vm.currentURL?.absoluteString, expectedURL)
        XCTAssertEqual(vm.activeRemoteBrowserProxyCapability, renewedCapability)

        vm.clearRemoteBrowserProfile()

        XCTAssertEqual(vm.currentURL?.absoluteString, "about:blank")
        XCTAssertNil(vm.activeRemoteBrowserProxyCapability)
        XCTAssertNil(vm.activeRemoteBrowserProfile)
        XCTAssertTrue(vm.allowsDevelopmentServerTrust(host: "localhost"))
        XCTAssertEqual(navigationActionCount, 0)
        cancellable.cancel()
    }

    func testFailedBrokeredRouteKeepsDeadProxyConfigurationAndUsesRetryCallback() {
        let vm = BrowserViewModel()
        let connectionProfileID = UUID()
        let capability = RemoteBrowserProxyCapability(
            id: UUID(),
            ownerWindowID: WindowID(),
            profileID: connectionProfileID,
            remotePort: 5173,
            localProxyPort: 55_173,
            credentials: ProxyCredentials(password: "route-secret"),
            expiresAt: Date().addingTimeInterval(60)
        )
        let remote = RemoteBrowserProfile(
            connectionProfileID: connectionProfileID,
            name: "Remote Dev",
            host: "dev.internal"
        )
        XCTAssertNotNil(vm.openRemoteBrokeredRoute(remote, capability: capability))
        var retriedRequest: RemoteBrowserRouteRequest?
        vm.onRetryRemoteBrowserRoute = { retriedRequest = $0 }

        vm.markRemoteBrowserProxyFailed("listener stopped")

        XCTAssertEqual(vm.activeRemoteBrowserProxyCapability, capability)
        XCTAssertEqual(vm.activeRemoteBrowserProfile?.proxyHealth, .failed)
        XCTAssertEqual(vm.remoteBrowserNotice?.kind, .proxyFailed)
        XCTAssertEqual(vm.remoteBrowserNotice?.detail, "listener stopped")
        XCTAssertNil(vm.retryRemoteBrowserNotice())
        XCTAssertEqual(retriedRequest?.remotePort, 5173)
    }

    func testSelectingLocalTabRevokesBrokeredRouteBeforeLoadingIt() throws {
        let vm = BrowserViewModel()
        let localTabID = try XCTUnwrap(vm.browserTabs.first?.id)
        vm.addBrowserTab(url: URL(string: "http://localhost:4000")!)
        let connectionProfileID = UUID()
        let remote = RemoteBrowserProfile(
            connectionProfileID: connectionProfileID,
            name: "Remote Dev",
            host: "dev.internal"
        )
        let capability = RemoteBrowserProxyCapability(
            id: UUID(),
            ownerWindowID: WindowID(),
            profileID: connectionProfileID,
            remotePort: 3000,
            localProxyPort: 53_000,
            credentials: ProxyCredentials(password: "route-secret"),
            expiresAt: Date().addingTimeInterval(60)
        )
        XCTAssertNotNil(vm.openRemoteBrokeredRoute(remote, capability: capability))
        var loadedURL: URL?
        let cancellable = vm.navigationActionSubject.sink { action in
            if case .load(let url) = action { loadedURL = url }
        }

        vm.selectBrowserTab(localTabID)

        XCTAssertNil(vm.activeRemoteBrowserProxyCapability)
        XCTAssertNil(vm.activeRemoteBrowserProfile)
        XCTAssertEqual(vm.currentURL, BrowserTab.defaultURL)
        XCTAssertEqual(loadedURL, BrowserTab.defaultURL)

        XCTAssertNotNil(vm.openRemoteBrokeredRoute(remote, capability: capability))
        vm.activateProfile(UUID())
        XCTAssertNil(vm.activeRemoteBrowserProxyCapability)
        XCTAssertNil(vm.activeRemoteBrowserProfile)
        XCTAssertEqual(vm.currentURL?.absoluteString, "about:blank")
        XCTAssertEqual(loadedURL?.absoluteString, "about:blank")
        cancellable.cancel()
    }

    func testRemoteProxyFailureUpdatesNoticeAndState() {
        let vm = BrowserViewModel()
        let remote = RemoteBrowserProfile(
            connectionProfileID: UUID(),
            name: "Remote Dev",
            host: "dev.internal",
            localForwardedPorts: [3000: 53000],
            proxyHealth: .active
        )

        XCTAssertNotNil(vm.openRemoteForward(remote, remotePort: 3000))
        XCTAssertNil(vm.remoteBrowserNotice)

        vm.updateRemoteBrowserProxyState(.failing(
            profileID: remote.connectionProfileID,
            reason: "probe failed"
        ))

        XCTAssertEqual(vm.activeRemoteBrowserProfile?.proxyHealth, .failed)
        XCTAssertEqual(vm.remoteBrowserNotice?.kind, .proxyFailed)
        XCTAssertEqual(vm.remoteBrowserNotice?.routeRequest?.remotePort, 3000)
        XCTAssertEqual(vm.getState()["remoteProxyHealth"], "failed")
        XCTAssertEqual(vm.getState()["remoteNotice"], "proxyFailed")

        vm.updateRemoteBrowserProxyState(.active(
            profileID: remote.connectionProfileID,
            socksPort: 1080,
            httpPort: 18080
        ))

        XCTAssertEqual(vm.activeRemoteBrowserProfile?.proxyHealth, .active)
        XCTAssertEqual(vm.activeRemoteBrowserProfile?.socksPort, 1080)
        XCTAssertEqual(vm.activeRemoteBrowserProfile?.httpConnectPort, 18080)
        XCTAssertNil(vm.remoteBrowserNotice)
    }

    func testRemoteNavigationFailureRecordsActionableNotice() {
        let vm = BrowserViewModel()
        let remote = RemoteBrowserProfile(
            connectionProfileID: UUID(),
            name: "Remote Dev",
            host: "dev.internal",
            localForwardedPorts: [5173: 55173],
            proxyHealth: .active
        )
        _ = vm.openRemoteForward(remote, remotePort: 5173, path: "app")
        let failedURL = URL(string: "http://127.0.0.1:55173/app")!
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)

        vm.recordRemoteBrowserNavigationFailure(error: error, failedURL: failedURL)

        XCTAssertEqual(vm.remoteBrowserNotice?.kind, .navigationFailed)
        XCTAssertEqual(vm.remoteBrowserNotice?.routeRequest?.remotePort, 5173)
        XCTAssertEqual(vm.remoteBrowserNotice?.failedURLString, "http://127.0.0.1:55173/app")
        XCTAssertEqual(vm.getState()["remoteNotice"], "navigationFailed")

        vm.recordRemoteBrowserNavigationSucceeded(url: failedURL)

        XCTAssertNil(vm.remoteBrowserNotice)
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

    // MARK: - DOM Grab

    func testToggleDOMGrabModePublishesEnableAction() {
        let vm = BrowserViewModel()
        var received: BrowserViewModel.NavigationAction?
        let cancellable = vm.navigationActionSubject.sink { received = $0 }

        vm.toggleDOMGrabMode()

        XCTAssertTrue(vm.isDOMGrabActive)
        if case .setDOMGrabAuthorization(let authorizationID) = received {
            XCTAssertEqual(authorizationID, vm.domGrabAuthorizationID)
            XCTAssertNotNil(authorizationID)
        } else {
            XCTFail("Expected DOM grab toggle to emit an exact one-shot grant")
        }
        cancellable.cancel()
    }

    func testHandleDOMGrabPayloadForwardsPayloadAndDisablesSingleShotMode() throws {
        let vm = BrowserViewModel()
        let payload = BrowserDOMGrabPayload(
            selector: "button.primary",
            pageURL: URL(string: "https://cocxy.dev")!,
            pageTitle: "Cocxy",
            visibleText: "Download"
        )

        var forwarded: BrowserDOMGrabPayload?
        var actions: [BrowserViewModel.NavigationAction] = []
        vm.onDOMGrabPayload = { forwarded = $0 }
        let cancellable = vm.navigationActionSubject.sink { actions.append($0) }

        vm.setDOMGrabMode(true)
        let authorizationID = try XCTUnwrap(vm.domGrabAuthorizationID)
        vm.handleDOMGrabPayload(payload, authorizationID: authorizationID)

        XCTAssertEqual(forwarded, payload)
        XCTAssertFalse(vm.isDOMGrabActive)
        guard actions.count == 2 else {
            XCTFail("Expected enable and disable actions")
            cancellable.cancel()
            return
        }
        if case .setDOMGrabAuthorization(let installedID) = actions[0] {
            XCTAssertEqual(installedID, authorizationID)
        } else {
            XCTFail("Expected first action to install the exact DOM-grab grant")
        }
        if case .setDOMGrabAuthorization(nil) = actions[1] {} else {
            XCTFail("Expected second action to revoke DOM grab")
        }
        cancellable.cancel()
    }

    func testHandleDOMGrabPayloadRejectsInactiveMode() {
        let vm = BrowserViewModel()
        let payload = BrowserDOMGrabPayload(
            selector: "button.primary",
            pageURL: URL(string: "https://cocxy.dev")!,
            pageTitle: "Cocxy",
            visibleText: "Download"
        )
        var forwarded: [BrowserDOMGrabPayload] = []
        vm.onDOMGrabPayload = { forwarded.append($0) }

        let handled = vm.handleDOMGrabPayload(payload, authorizationID: UUID())

        XCTAssertFalse(handled)
        XCTAssertTrue(forwarded.isEmpty)
        XCTAssertFalse(vm.isDOMGrabActive)
    }

    func testHandleDOMGrabPayloadConsumesAuthorizationBeforeCallback() throws {
        let vm = BrowserViewModel()
        let payload = BrowserDOMGrabPayload(
            selector: "button.primary",
            pageURL: URL(string: "https://cocxy.dev")!,
            pageTitle: "Cocxy",
            visibleText: "Download"
        )
        var forwarded: [BrowserDOMGrabPayload] = []
        var authorizationID: UUID?
        vm.onDOMGrabPayload = { received in
            forwarded.append(received)
            if forwarded.count == 1, let authorizationID {
                vm.handleDOMGrabPayload(received, authorizationID: authorizationID)
            }
        }
        vm.setDOMGrabMode(true)
        authorizationID = vm.domGrabAuthorizationID

        let handled = vm.handleDOMGrabPayload(
            payload,
            authorizationID: try XCTUnwrap(authorizationID)
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(forwarded, [payload])
        XCTAssertFalse(vm.isDOMGrabActive)
    }

    func testDOMGrabRejectsStaleGrantWithoutConsumingCurrentGrant() throws {
        let vm = BrowserViewModel()
        let payload = BrowserDOMGrabPayload(
            selector: "button.primary",
            pageURL: URL(string: "https://cocxy.dev")!,
            pageTitle: "Cocxy",
            visibleText: "Download"
        )
        var forwarded: [BrowserDOMGrabPayload] = []
        vm.onDOMGrabPayload = { forwarded.append($0) }

        vm.setDOMGrabMode(true)
        let staleID = try XCTUnwrap(vm.domGrabAuthorizationID)
        vm.revokeDOMGrabAuthorization()
        vm.setDOMGrabMode(true)
        let currentID = try XCTUnwrap(vm.domGrabAuthorizationID)

        XCTAssertNotEqual(staleID, currentID)
        XCTAssertFalse(vm.handleDOMGrabPayload(payload, authorizationID: staleID))
        XCTAssertTrue(vm.isDOMGrabActive)
        XCTAssertEqual(vm.domGrabAuthorizationID, currentID)
        XCTAssertTrue(vm.handleDOMGrabPayload(payload, authorizationID: currentID))
        XCTAssertEqual(forwarded, [payload])
    }

    func testDOMGrabRevokesForMainFrameNavigationOnly() throws {
        let vm = BrowserViewModel()
        vm.setDOMGrabMode(true)
        let authorizationID = try XCTUnwrap(vm.domGrabAuthorizationID)

        vm.revokeDOMGrabAuthorizationForNavigation(isMainFrame: false)
        XCTAssertTrue(vm.isDOMGrabActive)
        XCTAssertEqual(vm.domGrabAuthorizationID, authorizationID)

        vm.revokeDOMGrabAuthorizationForNavigation(isMainFrame: true)
        XCTAssertFalse(vm.isDOMGrabActive)
        XCTAssertNil(vm.domGrabAuthorizationID)
    }

    func testDOMGrabCannotArmUntilMainFrameNavigationCompletes() throws {
        let vm = BrowserViewModel()

        let generation = try XCTUnwrap(
            vm.revokeDOMGrabAuthorizationForNavigation(isMainFrame: true)
        )
        vm.setDOMGrabMode(true)
        XCTAssertFalse(vm.isDOMGrabActive)
        XCTAssertNil(vm.domGrabAuthorizationID)

        vm.completeDOMGrabNavigation(generation: generation)
        vm.setDOMGrabMode(true)
        XCTAssertTrue(vm.isDOMGrabActive)
        XCTAssertNotNil(vm.domGrabAuthorizationID)
    }

    func testStaleNavigationCompletionCannotUnlockNewerNavigation() throws {
        let vm = BrowserViewModel()
        let firstGeneration = try XCTUnwrap(
            vm.revokeDOMGrabAuthorizationForNavigation(isMainFrame: true)
        )
        let secondGeneration = try XCTUnwrap(
            vm.revokeDOMGrabAuthorizationForNavigation(isMainFrame: true)
        )

        vm.completeDOMGrabNavigation(generation: firstGeneration)
        vm.setDOMGrabMode(true)
        XCTAssertFalse(vm.isDOMGrabActive)
        XCTAssertNil(vm.domGrabAuthorizationID)

        vm.completeDOMGrabNavigation(generation: secondGeneration)
        vm.setDOMGrabMode(true)
        XCTAssertTrue(vm.isDOMGrabActive)
        XCTAssertNotNil(vm.domGrabAuthorizationID)
    }

    func testDOMGrabRevokesAcrossNavigationTabAndProfileChanges() throws {
        let vm = BrowserViewModel()

        vm.setDOMGrabMode(true)
        vm.navigate(to: "https://cocxy.dev")
        XCTAssertFalse(vm.isDOMGrabActive)

        vm.setDOMGrabMode(true)
        vm.reload()
        XCTAssertFalse(vm.isDOMGrabActive)

        vm.setDOMGrabMode(true)
        vm.selectBrowserTab(try XCTUnwrap(vm.activeTabID))
        XCTAssertFalse(vm.isDOMGrabActive)

        vm.setDOMGrabMode(true)
        vm.addBrowserTab()
        XCTAssertFalse(vm.isDOMGrabActive)

        vm.setDOMGrabMode(true)
        vm.activeProfileID = UUID()
        XCTAssertFalse(vm.isDOMGrabActive)
    }

    func testDOMGrabEnableFailureRevokesOnlyMatchingGrant() throws {
        let vm = BrowserViewModel()
        vm.setDOMGrabMode(true)
        let authorizationID = try XCTUnwrap(vm.domGrabAuthorizationID)

        vm.handleDOMGrabWebKitUpdate(authorizationID: UUID(), applied: false)
        XCTAssertEqual(vm.domGrabAuthorizationID, authorizationID)

        vm.handleDOMGrabWebKitUpdate(authorizationID: authorizationID, applied: true)
        XCTAssertEqual(vm.domGrabAuthorizationID, authorizationID)

        vm.handleDOMGrabWebKitUpdate(authorizationID: authorizationID, applied: false)
        XCTAssertFalse(vm.isDOMGrabActive)
        XCTAssertNil(vm.domGrabAuthorizationID)
    }

    func testDOMGrabAuthorizationExpiresAndRevokesWebKitGrant() async throws {
        let vm = BrowserViewModel()
        vm.setDOMGrabMode(true, lifetime: 0.02)
        XCTAssertNotNil(vm.domGrabAuthorizationID)

        try await Task.sleep(for: .milliseconds(80))

        XCTAssertFalse(vm.isDOMGrabActive)
        XCTAssertNil(vm.domGrabAuthorizationID)
    }

    func testStaleDOMGrabExpirationCannotRevokeReplacementGrant() async throws {
        let vm = BrowserViewModel()
        vm.setDOMGrabMode(true, lifetime: 0.02)
        let staleID = try XCTUnwrap(vm.domGrabAuthorizationID)
        vm.revokeDOMGrabAuthorization()
        vm.setDOMGrabMode(true, lifetime: 0.3)
        let replacementID = try XCTUnwrap(vm.domGrabAuthorizationID)

        try await Task.sleep(for: .milliseconds(80))

        XCTAssertNotEqual(staleID, replacementID)
        XCTAssertTrue(vm.isDOMGrabActive)
        XCTAssertEqual(vm.domGrabAuthorizationID, replacementID)
        vm.revokeDOMGrabAuthorization()
    }

    func testDOMGrabAuthorizationScriptCarriesExactGrant() {
        let authorizationID = UUID()
        let enableScript = BrowserDOMGrabWebKitSupport.setAuthorizationScript(authorizationID)
        let disableScript = BrowserDOMGrabWebKitSupport.setAuthorizationScript(nil)

        XCTAssertTrue(enableScript.contains("cocxyDOMGrab.enable"))
        XCTAssertTrue(enableScript.contains(authorizationID.uuidString.lowercased()))
        XCTAssertTrue(disableScript.contains("cocxyDOMGrab.disable"))
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
