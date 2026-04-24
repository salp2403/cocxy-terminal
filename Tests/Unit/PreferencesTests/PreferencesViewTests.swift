// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// PreferencesViewTests.swift - Tests for PreferencesView and its sections.

import XCTest
@testable import CocxyTerminal

// MARK: - Preferences Section Tests

final class PreferencesSectionTests: XCTestCase {

    // MARK: - PreferencesSection Enum

    func test_allSections_hasNineCases() {
        // v0.1.81 introduced the Worktrees section bringing the total
        // from 7 to 8; v0.1.84 added the GitHub section for the new
        // inline pane, bringing it to 9. Keeping the test explicit
        // about the number pins the invariant: adding a section
        // without an accompanying UI breaks this assertion and forces
        // the author to review every sidebar list that relies on
        // `allCases`.
        XCTAssertEqual(PreferencesSection.allCases.count, 9)
    }

    func test_worktreesSection_hasTitleAndIcon() {
        let section = PreferencesSection.worktrees
        XCTAssertEqual(section.title, "Worktrees")
        XCTAssertEqual(section.iconName, "arrow.triangle.branch")
    }

    func test_worktreesSection_appearsBeforeAbout() {
        let allCases = PreferencesSection.allCases
        guard let worktreesIndex = allCases.firstIndex(of: .worktrees),
              let aboutIndex = allCases.firstIndex(of: .about) else {
            XCTFail("worktrees and about sections must exist")
            return
        }
        XCTAssertLessThan(worktreesIndex, aboutIndex,
                         "Worktrees section must appear before About")
    }

    func test_sectionIDs_areUnique() {
        let ids = PreferencesSection.allCases.map(\.id)
        let uniqueIDs = Set(ids)
        XCTAssertEqual(ids.count, uniqueIDs.count,
                       "Duplicate section IDs found")
    }

    func test_generalSection_hasTitleAndIcon() {
        let section = PreferencesSection.general
        XCTAssertEqual(section.title, "General")
        XCTAssertEqual(section.iconName, "gear")
    }

    func test_appearanceSection_hasTitleAndIcon() {
        let section = PreferencesSection.appearance
        XCTAssertEqual(section.title, "Appearance")
        XCTAssertEqual(section.iconName, "paintbrush")
    }

    func test_agentDetectionSection_hasTitleAndIcon() {
        let section = PreferencesSection.agentDetection
        XCTAssertEqual(section.title, "Agent Detection")
        XCTAssertEqual(section.iconName, "brain.head.profile")
    }

    func test_notificationsSection_hasTitleAndIcon() {
        let section = PreferencesSection.notifications
        XCTAssertEqual(section.title, "Notifications")
        XCTAssertEqual(section.iconName, "bell")
    }

    func test_aboutSection_hasTitleAndIcon() {
        let section = PreferencesSection.about
        XCTAssertEqual(section.title, "About")
        XCTAssertEqual(section.iconName, "info.circle")
    }

    func test_terminalSection_hasTitleAndIcon() {
        let section = PreferencesSection.terminal
        XCTAssertEqual(section.title, "Terminal")
        XCTAssertEqual(section.iconName, "terminal")
    }

    func test_keybindingsSection_hasTitleAndIcon() {
        let section = PreferencesSection.keybindings
        XCTAssertEqual(section.title, "Keybindings")
        XCTAssertEqual(section.iconName, "keyboard")
    }

    func test_sectionID_matchesRawValue() {
        for section in PreferencesSection.allCases {
            XCTAssertEqual(section.id, section.rawValue)
        }
    }

    func test_terminalSection_appearsBeforeAbout() {
        let allCases = PreferencesSection.allCases
        guard let terminalIndex = allCases.firstIndex(of: .terminal),
              let aboutIndex = allCases.firstIndex(of: .about) else {
            XCTFail("terminal and about sections must exist")
            return
        }
        XCTAssertLessThan(terminalIndex, aboutIndex,
                         "Terminal section must appear before About")
    }

    func test_keybindingsSection_appearsBeforeAbout() {
        let allCases = PreferencesSection.allCases
        guard let keybindingsIndex = allCases.firstIndex(of: .keybindings),
              let aboutIndex = allCases.firstIndex(of: .about) else {
            XCTFail("keybindings and about sections must exist")
            return
        }
        XCTAssertLessThan(keybindingsIndex, aboutIndex,
                         "Keybindings section must appear before About")
    }
}

// MARK: - Tab Position Tests

final class TabPositionTests: XCTestCase {

    // MARK: - Raw Values

    func test_tabPositionLeft_hasRawValueLeft() {
        XCTAssertEqual(TabPosition.left.rawValue, "left")
    }

    func test_tabPositionTop_hasRawValueTop() {
        XCTAssertEqual(TabPosition.top.rawValue, "top")
    }

    func test_tabPositionHidden_hasRawValueHidden() {
        XCTAssertEqual(TabPosition.hidden.rawValue, "hidden")
    }

    // MARK: - Init from Raw Value

    func test_tabPosition_initFromValidRawValues() {
        XCTAssertEqual(TabPosition(rawValue: "left"), .left)
        XCTAssertEqual(TabPosition(rawValue: "top"), .top)
        XCTAssertEqual(TabPosition(rawValue: "hidden"), .hidden)
    }

    func test_tabPosition_initFromInvalidRawValue_returnsNil() {
        XCTAssertNil(TabPosition(rawValue: "bottom"))
        XCTAssertNil(TabPosition(rawValue: "right"))
        XCTAssertNil(TabPosition(rawValue: ""))
    }

    // MARK: - ViewModel Mapping

    @MainActor
    func test_viewModel_tabPositionLeft_mapsToLeftRawValue() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: AppearanceConfig(
                theme: "catppuccin-mocha", lightTheme: "catppuccin-latte",
                fontFamily: "JetBrainsMono Nerd Font",
                fontSize: 14, tabPosition: .left, windowPadding: 8,
                windowPaddingX: nil, windowPaddingY: nil,
                backgroundOpacity: 1.0, backgroundBlurRadius: 0
            ),
            terminal: .defaults, agentDetection: .defaults,
            notifications: .defaults, quickTerminal: .defaults,
            keybindings: .defaults, sessions: .defaults
        )
        let viewModel = PreferencesViewModel(config: config)
        XCTAssertEqual(viewModel.tabPosition, "left")
    }

    @MainActor
    func test_viewModel_tabPositionTop_mapsToTopRawValue() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: AppearanceConfig(
                theme: "catppuccin-mocha", lightTheme: "catppuccin-latte",
                fontFamily: "JetBrainsMono Nerd Font",
                fontSize: 14, tabPosition: .top, windowPadding: 8,
                windowPaddingX: nil, windowPaddingY: nil,
                backgroundOpacity: 1.0, backgroundBlurRadius: 0
            ),
            terminal: .defaults, agentDetection: .defaults,
            notifications: .defaults, quickTerminal: .defaults,
            keybindings: .defaults, sessions: .defaults
        )
        let viewModel = PreferencesViewModel(config: config)
        XCTAssertEqual(viewModel.tabPosition, "top")
    }

    @MainActor
    func test_viewModel_tabPositionHidden_mapsToHiddenRawValue() {
        let config = CocxyConfig(
            general: .defaults,
            appearance: AppearanceConfig(
                theme: "catppuccin-mocha", lightTheme: "catppuccin-latte",
                fontFamily: "JetBrainsMono Nerd Font",
                fontSize: 14, tabPosition: .hidden, windowPadding: 8,
                windowPaddingX: nil, windowPaddingY: nil,
                backgroundOpacity: 1.0, backgroundBlurRadius: 0
            ),
            terminal: .defaults, agentDetection: .defaults,
            notifications: .defaults, quickTerminal: .defaults,
            keybindings: .defaults, sessions: .defaults
        )
        let viewModel = PreferencesViewModel(config: config)
        XCTAssertEqual(viewModel.tabPosition, "hidden")
    }

    // MARK: - Apply Tab Position with NSSplitView

    @MainActor
    func test_applyTabPosition_left_showsSidebar_andToolbar() {
        let splitView = NSSplitView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        splitView.isVertical = true
        let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        let terminal = NSView(frame: NSRect(x: 241, y: 0, width: 759, height: 600))
        splitView.addSubview(sidebar)
        splitView.addSubview(terminal)

        let strip = NSView()

        applyTabPositionForTest(.left, sidebar: sidebar, strip: strip, splitView: splitView)

        // AppKit keeps a couple of points for the divider, so assert the
        // sidebar is visibly open instead of pinning an exact pixel width.
        XCTAssertGreaterThanOrEqual(sidebar.frame.width, 200,
                                    "Sidebar should be visibly open for .left")
        XCTAssertFalse(strip.isHidden, "Toolbar strip should stay visible for .left")
    }

    @MainActor
    func test_applyTabPosition_top_collapsesSidebar_showsStrip() {
        let splitView = NSSplitView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        splitView.isVertical = true
        let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        let terminal = NSView(frame: NSRect(x: 241, y: 0, width: 759, height: 600))
        splitView.addSubview(sidebar)
        splitView.addSubview(terminal)

        let strip = NSView()

        applyTabPositionForTest(.top, sidebar: sidebar, strip: strip, splitView: splitView)

        // Sidebar should be collapsed to zero width (the actual fix for the gap bug).
        XCTAssertEqual(sidebar.frame.width, 0,
                       "Sidebar width should be 0 for .top to prevent visual gap")
        XCTAssertFalse(strip.isHidden, "Strip should be visible for .top")
    }

    @MainActor
    func test_applyTabPosition_hidden_collapsesSidebar_hidesStrip() {
        let splitView = NSSplitView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        splitView.isVertical = true
        let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 600))
        let terminal = NSView(frame: NSRect(x: 241, y: 0, width: 759, height: 600))
        splitView.addSubview(sidebar)
        splitView.addSubview(terminal)

        let strip = NSView()

        applyTabPositionForTest(.hidden, sidebar: sidebar, strip: strip, splitView: splitView)

        // Sidebar should be collapsed to zero width.
        XCTAssertEqual(sidebar.frame.width, 0,
                       "Sidebar width should be 0 for .hidden to prevent visual gap")
        XCTAssertTrue(strip.isHidden, "Strip should be hidden for .hidden")
    }

    @MainActor
    func test_applyTabPosition_left_restoresSidebarWidth() {
        let sidebarWidth: CGFloat = 240
        let splitView = NSSplitView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        splitView.isVertical = true
        let sidebar = NSView(frame: NSRect(x: 0, y: 0, width: sidebarWidth, height: 600))
        let terminal = NSView(frame: NSRect(x: 241, y: 0, width: 759, height: 600))
        splitView.addSubview(sidebar)
        splitView.addSubview(terminal)

        let strip = NSView()

        // First collapse it.
        applyTabPositionForTest(.top, sidebar: sidebar, strip: strip, splitView: splitView)
        // Then restore it.
        applyTabPositionForTest(.left, sidebar: sidebar, strip: strip, splitView: splitView)

        XCTAssertEqual(sidebar.frame.width, sidebarWidth, accuracy: 1.0,
                       "Sidebar should be restored to 240pt when tab position is .left")
    }

    // MARK: - Test Helper

    /// Mirrors the logic of MainWindowController.applyTabPosition
    /// so we can test NSSplitView behavior in isolation.
    @MainActor
    private func applyTabPositionForTest(
        _ position: TabPosition,
        sidebar: NSView,
        strip: NSView,
        splitView: NSSplitView
    ) {
        let sidebarWidth: CGFloat = 240

        switch position {
        case .left:
            sidebar.isHidden = false
            strip.isHidden = false
            if sidebar.frame.width < 1 {
                splitView.setPosition(sidebarWidth, ofDividerAt: 0)
            }
        case .top:
            sidebar.isHidden = true
            strip.isHidden = false
            splitView.setPosition(0, ofDividerAt: 0)
        case .hidden:
            sidebar.isHidden = true
            strip.isHidden = true
            splitView.setPosition(0, ofDividerAt: 0)
        }

        splitView.adjustSubviews()
    }
}
