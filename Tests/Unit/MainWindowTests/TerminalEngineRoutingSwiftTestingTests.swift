// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Foundation
import Testing
@testable import CocxyTerminal

@Suite("MainWindowController terminal engine routing")
@MainActor
struct TerminalEngineRoutingSwiftTestingTests {
    @Test("explicit daemon tab creates and destroys its surface on the factory engine")
    func explicitDaemonTabRoutesSurfaceLifecycleToFactoryEngine() {
        let defaultEngine = MockTerminalEngine()
        let daemonEngine = MockTerminalEngine()
        let controller = MainWindowController(
            bridge: defaultEngine,
            terminalEngineFactory: { preference in
                preference == .daemon ? daemonEngine : nil
            }
        )

        let tabID = controller.createTab(terminalEnginePreference: .daemon)

        #expect(controller.tabManager.tab(for: tabID)?.terminalEnginePreference == .daemon)
        #expect(defaultEngine.createSurfaceRequests.isEmpty)
        #expect(daemonEngine.createSurfaceRequests.count == 1)

        guard let surfaceID = controller.tabSurfaceMap[tabID] else {
            Issue.record("Expected daemon tab to have a surface")
            return
        }

        controller.performCloseTab(tabID)

        #expect(daemonEngine.destroyedSurfaces.contains(surfaceID))
        #expect(defaultEngine.destroyedSurfaces.isEmpty)
    }

    @Test("additional surfaces for an opted-in tab inherit that tab engine")
    func additionalSurfacesInheritTabEngine() {
        let defaultEngine = MockTerminalEngine()
        let daemonEngine = MockTerminalEngine()
        let controller = MainWindowController(
            bridge: defaultEngine,
            terminalEngineFactory: { preference in
                preference == .daemon ? daemonEngine : nil
            }
        )
        let tabID = controller.createTab(terminalEnginePreference: .daemon)
        let viewModel = TerminalViewModel(engine: daemonEngine)
        let surfaceView = TerminalHostViewFactory.make(viewModel: viewModel, engine: daemonEngine)

        controller.createAndWireSurface(
            for: tabID,
            in: surfaceView,
            viewModel: viewModel,
            workingDirectory: nil
        )

        #expect(daemonEngine.createSurfaceRequests.count == 2)
        #expect(defaultEngine.createSurfaceRequests.isEmpty)
        guard let routedSurface = daemonEngine.createSurfaceRequests.last?.surface else {
            Issue.record("Expected additional daemon surface")
            return
        }
        controller.terminalEngine(for: routedSurface).sendText("ping", to: routedSurface)
        #expect(daemonEngine.sentTexts.last?.surface == routedSurface)
        #expect(defaultEngine.sentTexts.isEmpty)
    }

    @Test("custom surface creation keeps normal tab routing and destruction")
    func customSurfaceCreationUsesSelectedEngine() {
        let defaultEngine = MockTerminalEngine()
        let inProcessEngine = MockTerminalEngine()
        let expectedSurfaceID = SurfaceID()
        let controller = MainWindowController(
            bridge: defaultEngine,
            terminalEngineFactory: { preference in
                preference == .inProcess ? inProcessEngine : nil
            }
        )

        let tabID = controller.createTab(
            terminalEnginePreference: .inProcess,
            surfaceCreator: { engine, _, _ in
                #expect(engine === inProcessEngine)
                return expectedSurfaceID
            }
        )

        #expect(controller.tabSurfaceMap[tabID] == expectedSurfaceID)
        #expect(defaultEngine.createSurfaceRequests.isEmpty)
        #expect(inProcessEngine.createSurfaceRequests.isEmpty)
        #expect(controller.terminalEngine(for: expectedSurfaceID) === inProcessEngine)

        controller.performCloseTab(tabID)

        #expect(inProcessEngine.destroyedSurfaces == [expectedSurfaceID])
        #expect(controller.remoteDaemonTerminalViewModels[expectedSurfaceID] == nil)
    }

    @Test("tab font updates route through the selected terminal engine")
    func tabFontUpdatesUseSelectedEngine() {
        let defaultEngine = MockTerminalEngine()
        let daemonEngine = MockTerminalEngine()
        let controller = MainWindowController(
            bridge: defaultEngine,
            terminalEngineFactory: { preference in
                preference == .daemon ? daemonEngine : nil
            }
        )
        let tabID = controller.createTab(terminalEnginePreference: .daemon)
        let baselineCount = daemonEngine.fontApplications.count

        controller.applyFontToTab(tabID, size: 19)

        #expect(daemonEngine.fontApplications.count == baselineCount + 1)
        #expect(daemonEngine.fontApplications.last?.family == AppearanceConfig.defaults.fontFamily)
        #expect(daemonEngine.fontApplications.last?.size == 19)
        #expect(defaultEngine.fontApplications.isEmpty)
    }

    @Test("global font reload updates routed defaults and live surfaces")
    func globalFontReloadUpdatesRoutedEngine() {
        let defaultEngine = MockTerminalEngine()
        let daemonEngine = MockTerminalEngine()
        let controller = MainWindowController(
            bridge: defaultEngine,
            terminalEngineFactory: { preference in
                preference == .daemon ? daemonEngine : nil
            }
        )
        _ = controller.createTab(terminalEnginePreference: .daemon)
        let baselineApplications = daemonEngine.fontApplications.count

        controller.applyEffectiveTerminalFonts(
            from: .defaults,
            defaultEngineAlreadyUpdated: true
        )

        #expect(defaultEngine.fontDefaultUpdates.isEmpty)
        #expect(defaultEngine.fontApplications.isEmpty)
        #expect(daemonEngine.fontDefaultUpdates.last?.family == AppearanceConfig.defaults.fontFamily)
        #expect(daemonEngine.fontDefaultUpdates.last?.size == AppearanceConfig.defaults.fontSize)
        #expect(daemonEngine.fontApplications.count == baselineApplications + 1)
        #expect(daemonEngine.fontApplications.last?.family == AppearanceConfig.defaults.fontFamily)
        #expect(daemonEngine.fontApplications.last?.size == AppearanceConfig.defaults.fontSize)
    }

    @Test("global font reload preserves project overrides without leaking them into defaults")
    func globalFontReloadPreservesProjectOverride() {
        let defaultEngine = MockTerminalEngine()
        let daemonEngine = MockTerminalEngine()
        let controller = MainWindowController(
            bridge: defaultEngine,
            terminalEngineFactory: { preference in
                preference == .daemon ? daemonEngine : nil
            }
        )
        let tabID = controller.createTab(terminalEnginePreference: .daemon)
        controller.tabManager.updateTab(id: tabID) { tab in
            tab.projectConfig = ProjectConfig(fontSize: 21)
        }
        let baselineApplications = daemonEngine.fontApplications.count

        controller.applyEffectiveTerminalFonts(
            from: .defaults,
            defaultEngineAlreadyUpdated: true
        )

        #expect(daemonEngine.fontDefaultUpdates.last?.family == AppearanceConfig.defaults.fontFamily)
        #expect(daemonEngine.fontDefaultUpdates.last?.size == AppearanceConfig.defaults.fontSize)
        #expect(daemonEngine.fontApplications.count == baselineApplications + 1)
        #expect(daemonEngine.fontApplications.last?.family == AppearanceConfig.defaults.fontFamily)
        #expect(daemonEngine.fontApplications.last?.size == 21)
        #expect(controller.tabViewModels[tabID]?.defaultFontSize == 21)
    }

    @Test("system tabs keep using the default bridge")
    func systemTabUsesDefaultBridge() {
        let defaultEngine = MockTerminalEngine()
        let daemonEngine = MockTerminalEngine()
        let controller = MainWindowController(
            bridge: defaultEngine,
            terminalEngineFactory: { preference in
                preference == .daemon ? daemonEngine : nil
            }
        )

        _ = controller.createTab(terminalEnginePreference: .system)

        #expect(defaultEngine.createSurfaceRequests.count == 1)
        #expect(daemonEngine.createSurfaceRequests.isEmpty)
    }

    @Test("surface-scoped CocxyCore bridge lookup uses the routed engine")
    func surfaceScopedCocxyCoreBridgeLookupUsesRoutedEngine() {
        let defaultBridge = CocxyCoreBridge()
        let routedBridge = CocxyCoreBridge()
        let controller = MainWindowController(bridge: defaultBridge)
        let tabID = controller.tabManager.tabs.first!.id
        let routedSurface = SurfaceID()

        controller.registerTerminalEngine(routedBridge, tabID: tabID, surfaceID: routedSurface)

        #expect(controller.cocxyCoreBridge(forSurface: routedSurface) === routedBridge)
        #expect(controller.cocxyCoreBridge(forSurface: SurfaceID()) === defaultBridge)
    }
}
