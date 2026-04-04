// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// QuickTerminalControllerTests.swift - Tests for the Quick Terminal controller (T-037).

import XCTest
@testable import CocxyTerminal

@MainActor
private final class QuickTerminalTestEngine: TerminalEngine {
    private(set) var createdSurfaceIDs: [SurfaceID] = []
    private(set) var destroyedSurfaceIDs: [SurfaceID] = []
    private(set) var workingDirectories: [URL?] = []

    func initialize(config: TerminalEngineConfig) throws {}

    func createSurface(
        in view: NativeTerminalView,
        workingDirectory: URL?,
        command: String?
    ) throws -> SurfaceID {
        let surfaceID = SurfaceID()
        createdSurfaceIDs.append(surfaceID)
        workingDirectories.append(workingDirectory)
        return surfaceID
    }

    func destroySurface(_ id: SurfaceID) {
        destroyedSurfaceIDs.append(id)
    }

    @discardableResult
    func sendKeyEvent(_ event: KeyEvent, to surface: SurfaceID) -> Bool { false }

    func sendText(_ text: String, to surface: SurfaceID) {}

    func sendPreeditText(_ text: String, to surface: SurfaceID) {}

    func resize(_ surface: SurfaceID, to size: TerminalSize) {}

    func tick() {}

    func setOutputHandler(
        for surface: SurfaceID,
        handler: @escaping @Sendable (Data) -> Void
    ) {}

    func setOSCHandler(
        for surface: SurfaceID,
        handler: @escaping @Sendable (OSCNotification) -> Void
    ) {}

    func scrollToSearchResult(surfaceID: SurfaceID, lineNumber: Int) {}
}

// MARK: - Quick Terminal Controller Tests

/// Tests for `QuickTerminalController`.
///
/// Covers:
/// - Toggle from hidden to visible.
/// - Toggle from visible to hidden.
/// - Show when already visible is no-op.
/// - Hide when already hidden is no-op.
/// - Reduce motion flag respected.
/// - Config values applied to panel.
/// - Hotkey keycode and modifier constants.
@MainActor
final class QuickTerminalControllerTests: XCTestCase {

    private var sut: QuickTerminalController!

    override func setUp() {
        super.setUp()
        sut = QuickTerminalController()
    }

    override func tearDown() {
        sut.tearDown()
        sut = nil
        super.tearDown()
    }

    // MARK: - 1. Initial state is hidden

    func testInitialStateIsHidden() {
        XCTAssertFalse(sut.isVisible,
                       "Controller must start in hidden state")
    }

    // MARK: - 2. Toggle from hidden to visible

    func testToggleFromHiddenToVisible() {
        sut.setup(bridge: nil, config: .defaults)
        sut.toggle()

        XCTAssertTrue(sut.isVisible,
                      "Toggle from hidden must make panel visible")
    }

    // MARK: - 3. Toggle from visible to hidden

    func testToggleFromVisibleToHidden() {
        sut.setup(bridge: nil, config: .defaults)
        sut.toggle()  // hidden -> visible
        sut.toggle()  // visible -> hidden

        XCTAssertFalse(sut.isVisible,
                       "Toggle from visible must hide the panel")
    }

    // MARK: - 4. Show when already visible is no-op

    func testShowWhenAlreadyVisibleIsNoOp() {
        sut.setup(bridge: nil, config: .defaults)
        sut.show()
        let firstShowState = sut.isVisible

        sut.show()
        let secondShowState = sut.isVisible

        XCTAssertTrue(firstShowState, "First show must make visible")
        XCTAssertTrue(secondShowState, "Second show must still be visible (no-op)")
    }

    // MARK: - 5. Hide when already hidden is no-op

    func testHideWhenAlreadyHiddenIsNoOp() {
        sut.setup(bridge: nil, config: .defaults)
        let initialState = sut.isVisible

        sut.hide()
        let afterHideState = sut.isVisible

        XCTAssertFalse(initialState, "Initial state must be hidden")
        XCTAssertFalse(afterHideState, "Hiding from hidden must be no-op")
    }

    // MARK: - 6. Config slide edge applied

    func testConfigSlideEdgeApplied() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: .defaults,
            quickTerminal: QuickTerminalConfig(
                enabled: true,
                hotkey: "cmd+grave",
                position: .bottom,
                heightPercentage: 40,
                hideOnDeactivate: true,
                workingDirectory: "~",
                animationDuration: 0.15,
                screen: .mouse
            ),
            keybindings: .defaults,
            sessions: .defaults
        )
        sut.setup(bridge: nil, config: config)

        XCTAssertEqual(sut.currentSlideEdge, .bottom,
                       "Slide edge must match config position")
    }

    // MARK: - 7. Config height percent applied

    func testConfigHeightPercentApplied() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: .defaults,
            quickTerminal: QuickTerminalConfig(
                enabled: true,
                hotkey: "cmd+grave",
                position: .top,
                heightPercentage: 60,
                hideOnDeactivate: true,
                workingDirectory: "~",
                animationDuration: 0.15,
                screen: .mouse
            ),
            keybindings: .defaults,
            sessions: .defaults
        )
        sut.setup(bridge: nil, config: config)

        XCTAssertEqual(sut.currentHeightPercent, 0.6, accuracy: 0.01,
                       "Height percent must match config value converted from percentage")
    }

    // MARK: - 8. Panel is nil before setup

    func testPanelIsNilBeforeSetup() {
        XCTAssertTrue(sut.isPanelNil,
                      "Panel must not exist before setup is called")
    }

    // MARK: - 9. Panel is created after setup

    func testPanelIsCreatedAfterSetup() {
        sut.setup(bridge: nil, config: .defaults)

        XCTAssertFalse(sut.isPanelNil,
                       "Panel must exist after setup is called")
    }

    // MARK: - 10. Hotkey keycode for grave accent

    func testHotkeyKeycodeForGraveAccent() {
        XCTAssertEqual(QuickTerminalController.graveAccentKeyCode, UInt16(50),
                       "Grave accent (`) must be keycode 50")
    }

    // MARK: - 11. Toggle count tracks correctly

    func testToggleCountTracksCorrectly() {
        sut.setup(bridge: nil, config: .defaults)

        sut.toggle()
        XCTAssertTrue(sut.isVisible)

        sut.toggle()
        XCTAssertFalse(sut.isVisible)

        sut.toggle()
        XCTAssertTrue(sut.isVisible)

        sut.toggle()
        XCTAssertFalse(sut.isVisible)
    }

    // MARK: - 12. Setup can be called multiple times safely

    func testSetupCanBeCalledMultipleTimesSafely() {
        sut.setup(bridge: nil, config: .defaults)
        sut.show()
        XCTAssertTrue(sut.isVisible)

        // Setup again with different config -- should reset state cleanly.
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: .defaults,
            quickTerminal: QuickTerminalConfig(
                enabled: true,
                hotkey: "cmd+grave",
                position: .left,
                heightPercentage: 50,
                hideOnDeactivate: true,
                workingDirectory: "~",
                animationDuration: 0.15,
                screen: .mouse
            ),
            keybindings: .defaults,
            sessions: .defaults
        )
        sut.setup(bridge: nil, config: config)

        XCTAssertFalse(sut.isVisible,
                       "Re-setup must reset visibility to hidden")
        XCTAssertEqual(sut.currentSlideEdge, .left,
                       "Re-setup must apply new config")
    }

    func testShowWithBridgeCreatesSurfaceOnlyOnce() {
        let engine = QuickTerminalTestEngine()
        sut.setup(bridge: engine, config: .defaults)

        sut.show()
        sut.hide()
        sut.show()

        XCTAssertEqual(
            engine.createdSurfaceIDs.count,
            1,
            "Quick terminal should keep its surface alive across hide/show toggles"
        )
    }

    func testTearDownDestroysCreatedSurface() {
        let engine = QuickTerminalTestEngine()
        sut.setup(bridge: engine, config: .defaults)
        sut.show()

        guard let createdSurfaceID = engine.createdSurfaceIDs.first else {
            XCTFail("show() should create a quick terminal surface")
            return
        }

        sut.tearDown()

        XCTAssertEqual(
            engine.destroyedSurfaceIDs,
            [createdSurfaceID],
            "tearDown must destroy the quick terminal surface when one was created"
        )
    }

    func testShowUsesConfiguredQuickTerminalWorkingDirectory() {
        let engine = QuickTerminalTestEngine()
        let config = CocxyConfig(
            general: .defaults,
            appearance: .defaults,
            terminal: .defaults,
            agentDetection: .defaults,
            notifications: .defaults,
            quickTerminal: QuickTerminalConfig(
                enabled: true,
                hotkey: "cmd+grave",
                position: .top,
                heightPercentage: 40,
                hideOnDeactivate: true,
                workingDirectory: "~/Projects",
                animationDuration: 0.15,
                screen: .mouse
            ),
            keybindings: .defaults,
            sessions: .defaults
        )

        sut.setup(bridge: engine, config: config)
        sut.show()

        guard let workingDirectory = engine.workingDirectories.first ?? nil else {
            XCTFail("show() should capture the configured quick terminal working directory")
            return
        }

        XCTAssertEqual(
            workingDirectory.path,
            (("~/Projects") as NSString).expandingTildeInPath,
            "Quick terminal must spawn from its configured working directory"
        )
    }
}
