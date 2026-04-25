// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// MainWindowController+GitHubPane.swift - Wiring for the GitHub pane
// overlay (Cmd+Option+G) introduced in v0.1.84.
//
// Mirrors the `+Overlays.swift` patterns for the Code Review panel so
// both right-docked surfaces share a single mental model:
//   - toggle / show / dismiss trio with a matching @objc alias
//   - preferred vs effective width (preferred wins the user intent,
//     effective stays clamped by the container)
//   - dependency wiring happens in `configureGitHubPaneViewModel`
//   - layout cooperates with `layoutRightDockedAgentPanels` so the
//     pane dock with Dashboard / Code Review / Timeline cleanly.

import AppKit
import Combine
import Darwin
import Foundation
import SwiftUI

// MARK: - GitHub Pane overlay

@MainActor
extension MainWindowController {

    // MARK: Toggle / show / dismiss

    /// Show or hide the GitHub pane overlay. Called from the global
    /// Cmd+Option+G shortcut, the Command Palette entry, and the
    /// `cocxy github open` CLI verb.
    func toggleGitHubPane() {
        if isGitHubPaneVisible {
            dismissGitHubPane()
        } else {
            showGitHubPanePanel()
        }
    }

    /// `@objc` alias for menu bar and responder-chain invocations.
    /// Keeps the signature identical to
    /// `toggleCodeReviewAction(_ sender:)` so both shortcuts can be
    /// wired through the same KeybindingActionCatalog bridge.
    @objc func toggleGitHubPaneAction(_ sender: Any?) {
        toggleGitHubPane()
    }

    /// Attaches the pane to `overlayContainerView`. Idempotent — if
    /// the pane was already visible the hosting view is recycled so
    /// the previous bindings are cleared before the new layout.
    func showGitHubPanePanel() {
        guard let overlayContainer = overlayContainerView else { return }

        let viewModel = resolveGitHubPaneViewModel()

        gitHubPaneHostingView?.removeFromSuperview()
        let panelWidth = clampedGitHubPanePanelWidth(
            preferredGitHubPanePanelWidth,
            containerWidth: overlayContainer.bounds.width
        )
        gitHubPanePanelWidth = panelWidth

        let swiftUIView = makeGitHubPaneView(viewModel: viewModel, panelWidth: panelWidth)
        let hostingView = NSHostingView(rootView: swiftUIView)
        hostingView.wantsLayer = true
        let panelY = statusBarHostingView?.frame.height ?? 24
        hostingView.frame = NSRect(
            x: overlayContainer.bounds.width - panelWidth,
            y: panelY,
            width: panelWidth,
            height: max(0, overlayContainer.bounds.height - panelY)
        )
        hostingView.autoresizingMask = [.height, .minXMargin]

        gitHubPaneHostingView = hostingView
        overlayContainer.addSubview(hostingView)
        isGitHubPaneVisible = true
        viewModel.isVisible = true

        // Fire the first refresh so the pane never lands with stale
        // data after being shown again. The view model guards against
        // overlapping refreshes via its `refreshGeneration` counter.
        viewModel.refresh()

        layoutRightDockedAgentPanels()
    }

    /// Slides the pane off to the right and detaches it from the
    /// container. Matches the animation profile used by the Code
    /// Review dismissal so the two docked panels leave the screen
    /// with the same timing.
    func dismissGitHubPane() {
        guard let hostingView = gitHubPaneHostingView,
              let overlayContainer = overlayContainerView else {
            gitHubPaneHostingView?.removeFromSuperview()
            gitHubPaneHostingView = nil
            gitHubPaneViewModel?.isVisible = false
            isGitHubPaneVisible = false
            return
        }

        isGitHubPaneVisible = false
        gitHubPaneViewModel?.isVisible = false

        let targetX = overlayContainer.bounds.width
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = AnimationConfig.duration(AnimationConfig.overlaySlideOutDuration)
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            hostingView.animator().frame.origin.x = targetX
        }, completionHandler: {
            Task { @MainActor [weak self] in
                self?.gitHubPaneHostingView?.removeFromSuperview()
                self?.gitHubPaneHostingView = nil
                self?.layoutRightDockedAgentPanels()
                self?.focusActiveTerminalSurface()
            }
        })
    }

    // MARK: Width controls

    /// Adjusts the preferred pane width by `delta`. Used by the
    /// resize stepper so the preferred value survives shrink/grow
    /// cycles the container might clamp during windowed layout.
    func adjustGitHubPanePanelWidth(by delta: CGFloat) {
        setGitHubPanePanelWidth(preferredGitHubPanePanelWidth + delta)
    }

    /// Clamps and persists the new preferred width, then relays out
    /// the docked panels so the change becomes visible immediately.
    func setGitHubPanePanelWidth(_ proposed: CGFloat) {
        updatePreferredGitHubPanePanelWidth(proposed)
        if isGitHubPaneVisible {
            layoutRightDockedAgentPanels()
        } else {
            gitHubPanePanelWidth = preferredGitHubPanePanelWidth
        }
    }

    // MARK: View model resolution

    /// Returns the pane view model, creating it lazily on first use.
    /// Tests can preload an injected view model via
    /// `injectedGitHubPaneViewModel`.
    func resolveGitHubPaneViewModel() -> GitHubPaneViewModel {
        if let gitHubPaneViewModel {
            configureGitHubPaneViewModel(gitHubPaneViewModel)
            return gitHubPaneViewModel
        }

        if let injectedGitHubPaneViewModel {
            gitHubPaneViewModel = injectedGitHubPaneViewModel
            configureGitHubPaneViewModel(injectedGitHubPaneViewModel)
            return injectedGitHubPaneViewModel
        }

        // Default construction: one service per window. The actor
        // serialises calls internally, so multi-window doesn't amplify
        // subprocess parallelism beyond the macOS process pool limits.
        let service = GitHubService()
        let viewModel = GitHubPaneViewModel(service: service)
        gitHubPaneViewModel = viewModel
        configureGitHubPaneViewModel(viewModel)
        return viewModel
    }

    /// Attaches every provider the view model needs to reason about
    /// the active tab, the effective config, and outbound side
    /// effects. Called on first construction and again when the
    /// config service reloads so hot-swapped providers stay live.
    private func configureGitHubPaneViewModel(_ viewModel: GitHubPaneViewModel) {
        viewModel.workingDirectoryProvider = { [weak self] in
            self?.currentGitHubPaneWorkingDirectory()
        }
        viewModel.configProvider = { [weak self] in
            self?.currentGitHubPaneConfig() ?? .defaults
        }
        viewModel.onOpenURL = { url in
            NSWorkspace.shared.open(url)
        }
        viewModel.onStartAuthentication = { [weak self] workingDirectory in
            self?.startGitHubAuthentication(in: workingDirectory) ?? false
        }
        // `onCreatePullRequest` is wired by the Code Review integration
        // (Fase 10). Leaving it nil means the PR list works, but the
        // "Create PR" button in the review workflow panel is inert
        // until Fase 10 lands.

        // Merge handler (v0.1.86): the pane's PR row context menu
        // routes through here so multi-window workflows share the
        // same actor (GitHubService) and never run two `gh pr merge`
        // invocations against the same checkout in parallel.
        viewModel.mergePullRequestHandler = { [weak self] request, workingDirectory in
            guard let self else { throw GitHubCLIError.notAGitRepository(path: "") }
            return try await self.performCodeReviewMergePullRequest(
                request: request,
                workingDirectory: workingDirectory
            )
        }
    }

    // MARK: Clamp + sync helpers (called from layoutRightDockedAgentPanels)

    /// Computes the width the pane should render at given the current
    /// `overlayContainer` bounds. Never exceeds the container even if
    /// the user persisted a very wide preference on a previous session.
    func clampedGitHubPanePanelWidth(
        _ proposedWidth: CGFloat? = nil,
        containerWidth: CGFloat
    ) -> CGFloat {
        let requestedWidth = proposedWidth ?? gitHubPanePanelWidth
        let absoluteClamped = MainWindowController.clampStoredGitHubPanePanelWidth(requestedWidth)
        let containerMaximum = max(GitHubPaneView.minimumPanelWidth, containerWidth * 0.75)
        return min(absoluteClamped, containerMaximum)
    }

    /// Rebuilds the hosting view's SwiftUI root when the effective
    /// width changes at layout time. Keeps the view model binding
    /// intact; only the panelWidth argument changes so the SwiftUI
    /// diff is cheap.
    func syncGitHubPaneRootView(panelWidth: CGFloat) {
        guard isGitHubPaneVisible,
              let hostingView = gitHubPaneHostingView,
              let viewModel = gitHubPaneViewModel else {
            return
        }
        let view = makeGitHubPaneView(viewModel: viewModel, panelWidth: panelWidth)
        hostingView.rootView = view
    }

    private func makeGitHubPaneView(
        viewModel: GitHubPaneViewModel,
        panelWidth: CGFloat
    ) -> GitHubPaneView {
        GitHubPaneView(
            viewModel: viewModel,
            layout: .sidePanel,
            onDismiss: { [weak self] in
                self?.dismissGitHubPane()
            },
            panelWidth: panelWidth
        )
    }

    // MARK: Working directory resolver

    /// Returns the directory the pane should pass to `gh`. Prefers
    /// the worktree root so when the user opens a cocxy-managed
    /// worktree, `gh repo view` resolves to the origin repo through
    /// the worktree's `.git` file (handled by `gh` internally).
    func currentGitHubPaneWorkingDirectory() -> URL? {
        if let tabID = visibleTabID ?? tabManager.activeTabID,
           let tab = tabManager.tab(for: tabID) {
            if let worktreeRoot = tab.worktreeRoot {
                return worktreeRoot
            }
            return tab.workingDirectory
        }
        return nil
    }

    /// Returns the `[github]` config the pane should use for the
    /// currently visible tab. This keeps project `.cocxy.toml`
    /// overrides aligned with the rest of Cocxy's effective-config
    /// path instead of silently falling back to the global settings.
    func currentGitHubPaneConfig() -> GitHubConfig {
        let globalConfig = configService?.current ?? .defaults
        guard let tabID = visibleTabID ?? tabManager.activeTabID,
              let tab = tabManager.tab(for: tabID) else {
            return globalConfig.github
        }
        return Self.effectiveGitHubConfig(for: tab, globalConfig: globalConfig)
    }

    nonisolated static func effectiveGitHubConfig(
        for tab: Tab,
        globalConfig: CocxyConfig
    ) -> GitHubConfig {
        guard let projectConfig = tab.projectConfig else {
            return globalConfig.github
        }
        return globalConfig.applying(projectOverrides: projectConfig).github
    }

    nonisolated static let gitHubDeviceLoginURLString = "https://github.com/login/device"

    nonisolated static func gitHubAuthenticationCommand(browserOpenerPath: String?) -> String {
        guard let browserOpenerPath, !browserOpenerPath.isEmpty else {
            return "gh auth login\r"
        }
        return "BROWSER=\(shellQuoted(browserOpenerPath)) gh auth login\r"
    }

    nonisolated static func browserOpenerScript(cliPath: String) -> String {
        "#!/bin/sh\nexec \(shellQuoted(cliPath)) browser navigate \"$@\"\n"
    }

    nonisolated private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    /// Starts `gh auth login` in a real terminal tab. The GitHub CLI
    /// login flow is interactive and may open a browser/device-code
    /// prompt, so Cocxy must not run it through the background
    /// subprocess helper used by read-only pane refreshes.
    @discardableResult
    func startGitHubAuthentication(in workingDirectory: URL) -> Bool {
        let tabID = createTab(workingDirectory: workingDirectory)
        guard let surfaceID = tabSurfaceMap[tabID] else { return false }

        openInternalBrowser(to: Self.gitHubDeviceLoginURLString)
        let browserOpenerPath = installGitHubAuthBrowserOpenerScript()
        bridge.sendText(
            Self.gitHubAuthenticationCommand(browserOpenerPath: browserOpenerPath),
            to: surfaceID
        )
        window?.makeKeyAndOrderFront(nil)
        focusActiveTerminalSurface()
        return true
    }

    private func installGitHubAuthBrowserOpenerScript() -> String? {
        guard let cliPath = bundledCLIPath() else { return nil }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cocxy-browser-open-\(getpid()).sh")
        do {
            try Self.browserOpenerScript(cliPath: cliPath).write(
                to: scriptURL,
                atomically: true,
                encoding: .utf8
            )
            chmod(scriptURL.path, S_IRUSR | S_IWUSR | S_IXUSR)
            return scriptURL.path
        } catch {
            NSLog("[Cocxy] Failed to install internal browser opener: %@", String(describing: error))
            return nil
        }
    }

    private func bundledCLIPath() -> String? {
        let candidates = [
            Bundle.main.url(forResource: "cocxy", withExtension: nil)?.path,
            "/usr/local/bin/cocxy",
            "/opt/homebrew/bin/cocxy"
        ].compactMap { $0 }

        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    // MARK: - Code Review bridge (Fase 10)

    /// Entry point wired from
    /// `CodeReviewPanelViewModel.createPullRequestHandler`. Resolves
    /// the working directory the same way the GitHub pane does, hands
    /// the request off to the shared `GitHubService`, and returns the
    /// created PR's URL so the review panel can surface it as an
    /// info banner.
    func performCodeReviewCreatePullRequest(
        title: String,
        body: String?,
        baseBranch: String?,
        draft: Bool,
        workingDirectory explicitWorkingDirectory: URL? = nil
    ) async throws -> URL {
        guard let workingDirectory = explicitWorkingDirectory ?? currentGitHubPaneWorkingDirectory() else {
            throw GitHubCLIError.notAGitRepository(path: "")
        }
        let pr = try await sharedGitHubService().createPullRequest(
            title: title,
            body: body,
            baseBranch: baseBranch,
            draft: draft,
            at: workingDirectory
        )
        return pr.url
    }

    // MARK: - Merge bridge (v0.1.86)

    /// Routes a merge request from any surface (Code Review panel or
    /// GitHub pane) through the shared `GitHubService` so concurrent
    /// merges across windows serialise via the actor.
    ///
    /// Throws `GitHubCLIError.notAGitRepository` when the active tab
    /// has no resolvable working directory; the view layer maps that
    /// to a banner pointing the user at opening a git repo first.
    func performCodeReviewMergePullRequest(
        request: GitHubMergeRequest,
        workingDirectory explicitWorkingDirectory: URL? = nil
    ) async throws -> GitHubPullRequest {
        guard let workingDirectory = explicitWorkingDirectory ?? currentGitHubPaneWorkingDirectory() else {
            throw GitHubCLIError.notAGitRepository(path: "")
        }
        return try await sharedGitHubService().mergePullRequest(
            request: request,
            at: workingDirectory
        )
    }

    /// Resolves a typed `GitHubMergeability` snapshot for `number`. Used
    /// by the Code Review panel to decide whether the merge button
    /// should be enabled and what reason to surface in the chip
    /// tooltip when it is not.
    func performCodeReviewPullRequestMergeability(
        number: Int,
        workingDirectory explicitWorkingDirectory: URL? = nil
    ) async throws -> GitHubMergeability {
        guard let workingDirectory = explicitWorkingDirectory ?? currentGitHubPaneWorkingDirectory() else {
            throw GitHubCLIError.notAGitRepository(path: "")
        }
        return try await sharedGitHubService().pullRequestMergeability(
            number: number,
            at: workingDirectory
        )
    }

    /// Looks up the open PR that matches `branch`, returning `nil` when
    /// the branch has no associated PR upstream. The Code Review panel
    /// uses this to surface the merge button automatically when the
    /// user lands on a worktree whose branch already has a PR — no
    /// need to run `Create PR` first.
    func performCodeReviewPullRequestNumberLookup(
        forBranch branch: String,
        workingDirectory explicitWorkingDirectory: URL? = nil
    ) async throws -> Int? {
        guard let workingDirectory = explicitWorkingDirectory ?? currentGitHubPaneWorkingDirectory() else {
            return nil
        }
        return try await sharedGitHubService().pullRequestNumber(
            forBranch: branch,
            at: workingDirectory
        )
    }

    /// Returns the process-wide shared GitHubService, falling back to a
    /// fresh instance only when the AppDelegate has not been wired
    /// (test contexts where we synthesise a controller directly). Both
    /// the Code Review panel and the GitHub pane go through this so
    /// `gh` subprocess invocations serialise across surfaces and
    /// windows.
    private func sharedGitHubService() -> GitHubService {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            return type(of: appDelegate).sharedGitHubService
        }
        return GitHubService()
    }
}
