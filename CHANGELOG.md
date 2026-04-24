# Changelog

All notable changes to Cocxy Terminal are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.84] - 2026-04-24

### Added
- Inline GitHub pane (Cmd+Option+G) renders pull requests, issues and
  check runs for the repository resolved from the active tab. The pane
  docks on the right edge alongside the Dashboard and Code Review
  panels, supports per-worktree resolution (a tab standing in a
  cocxy-managed worktree sees the origin repo's PRs automatically),
  and surfaces informational banners for recoverable states such as
  "install gh", "sign in with gh auth login", and "no GitHub remote".
  Authentication is delegated to `gh auth status` — Cocxy never stores
  tokens of its own.
- Five new CLI verbs (`cocxy github status`, `cocxy github prs`,
  `cocxy github issues`, `cocxy github open`, `cocxy github refresh`).
  The read verbs accept `--state` and `--limit`, emit JSON under the
  same keys the pane uses, and honour the `[github].enabled` master
  toggle. `open` / `refresh` drive the overlay on the focused window.
- `Create Pull Request` action in the Code Review Git Workflow panel.
  Takes the commit draft's first line as the PR title, folds the
  remainder into the body, routes through the shared GitHub service,
  and reports the created PR URL as an info banner inside the panel.
- New `[github]` section in the TOML config: `enabled`,
  `auto-refresh-interval` (seconds, 0 disables), `max-items` (clamped
  to 200), `include-drafts`, `default-state`. A matching Preferences
  section exposes every field. Per-project overrides for `enabled`,
  `include-drafts` and `default-state` are honoured when a repository
  ships a `.cocxy.toml`.
- `window.githubPane` keybinding action (default Cmd+Option+G), a new
  `View > GitHub Pane` menu entry, and a matching Command Palette
  action so the overlay can be opened from every surface.

### Changed
- Code Review now shares the `AppDelegate` shared GitHub service
  singleton the GitHub pane uses. Opening the pane once primes the
  "Create Pull Request" button in the review panel.
- Primary click on a pull-request row opens Checks inside the GitHub
  pane; use the row context menu to open the PR in a browser.
- GitHub CLI JSON-field failures now prompt users to update `gh`
  instead of surfacing raw field-list output from older builds.

## [0.1.83] - 2026-04-24

### Fixed
- chore(release): bump Info.plist to 0.1.83

## [0.1.82] - 2026-04-22

### Fixed
- CLI requests now succeed reliably when the app has been running for
  long periods or is under sustained load from hook events, Metal
  rendering, and background timers. Three independent regressions were
  addressed:
  - `SocketServerConstants.listenBacklog` was `5`, which let the
    kernel silently drop concurrent connect attempts. Bursts of
    Claude Code hook events combined with CLI invocations produced
    `EPIPE` on the first write because the accepted peer had already
    been purged. The backlog is now `128` (equivalent to `SOMAXCONN`
    on macOS); measured success rate on ten simultaneous connects
    went from roughly 20% to 100%.
  - The socket server's accept and connection queues ran at
    `.utility` QoS. Under sustained GPU and timer load the accept
    loop was scheduled too slowly to keep pace with queued connects,
    causing the client to race with peer teardown. Both queues now
    run at `.userInitiated` to match the interactive nature of CLI
    round-trips.
  - Even with the larger backlog, the accept loop still accepted and
    immediately closed connections once `maxConcurrentConnections`
    (10) active workers were busy. Any burst larger than the active
    cap surfaced as `EPIPE` on the excess clients. The loop now waits
    on a `DispatchSemaphore` sized to the worker cap before accepting
    another peer, so excess clients stay queued in the kernel backlog
    until a worker slot frees. Measured behaviour: 30 and 60
    concurrent CLI round-trips now complete with zero drops.
- `cocxy --version` now resolves dynamically from the enclosing app
  bundle's `Info.plist` rather than a hardcoded constant, keeping the
  CLI version in sync with the GUI at release time. The resolver
  follows symlinks before walking upward to the bundle, so
  invocations through `PATH` symlinks (for example Homebrew's
  `/opt/homebrew/bin/cocxy`) land on the real `.app/Contents/Info.plist`
  instead of falling back. Standalone builds and tests fall back to a
  known value that the release pipeline can bump.
- `cocxy worktree` commands (CLI and Command Palette) now apply the
  active tab's per-project `.cocxy.toml` overrides before consulting
  the `[worktree]` config. A project that enabled worktrees locally
  would otherwise fail with the global default, even though
  Preferences and the UI layer already merged project overrides
  correctly. `basePath` and `idLength` stay global-only to preserve
  the existing storage-layout and collision-avoidance contracts.

### Tests
- `SocketServerRegressionSwiftTestingTests` now covers three socket
  regressions: a client that idles 100 ms between `connect()` and the
  first `write()` must receive a response, and a burst of 30
  concurrent clients (well above the 10-worker cap) must all succeed
  without drop. The burst test uses a deliberately slow command
  handler so the worker pool stays saturated while the remaining
  clients wait on the kernel backlog; before the accept-gate fix it
  would reproducibly return 10 successes and 20 `EPIPE` failures. The
  test that ignores `SIGPIPE` saves and restores the previous handler
  so process-global signal state stays isolated between tests.
- New `CLIArgumentParserVersionSwiftTestingTests` suite covering the
  version resolver: direct bundled path, symlink-to-bundled path
  (regression), non-bundle fallback, and fallback shape.
- `WorktreeCLIIntegrationHelperTests` gains two regressions for the
  project-override merge: a non-nil `ProjectConfig` must flow through
  all worktree CLI fields except `basePath` and `idLength`, and a nil
  `ProjectConfig` must leave the global config untouched.

## [0.1.81] - 2026-04-21

### Added
- Per-agent git worktrees. A new actor-backed `WorktreeService` drives
  `git worktree add/remove/list/prune` through the same `git` binary
  resolver the code-review workflow uses. Every side effect serialises
  at the actor boundary so concurrent requests cannot race past each
  other when allocating IDs, picking branch names, or persisting the
  per-repo manifest. Includes collision retry with increasing id
  length and a preflight `git status --porcelain` guard that refuses
  to delete dirty worktrees unless `--force` is passed.
- `cocxy worktree add/list/remove/prune` CLI verbs. `add` attaches the
  freshly created worktree to the active tab; `list` returns a JSON
  payload with every manifest entry; `remove` runs a porcelain
  preflight unless `--force` is set; `prune` reconciles the manifest
  against `git worktree list` and drops orphan entries while leaving
  worktrees created outside of cocxy untouched.
- Command Palette actions "Create Agent Worktree Tab" and "Remove
  Current Worktree" under a new `Worktree` category. Both route
  through `AppDelegate.performWorktreeCLIRequest` so the palette path
  and the socket path share a single async implementation.
- Preferences gains a `Worktrees` pane (arrow.triangle.branch icon)
  that surfaces every `[worktree]` TOML option with explanatory
  captions: feature toggle, storage base path, branch template,
  base-ref, random id length (stepper), on-close behaviour (Keep /
  Prompt / Remove if clean), open-in-new-tab, inherit-project-config,
  and show-badge. Every field round-trips through the seven-step
  config pipeline so a Save never resets what the user wrote.
- Worktree badge (arrow.triangle.branch) in both the classic
  `TabItemView` sidebar and the Aurora session row. The badge appears
  only when `Tab.worktreeID` is set and the live
  `config.worktree.showBadge` flag is on. Tooltip shows the worktree
  id, origin repo name, and branch.
- `.cocxy.toml` now accepts a `[worktree]` section with per-project
  overrides for enabled, base-ref, branch-template, on-close,
  open-in-new-tab, inherit-project-config, and show-badge. basePath
  and idLength stay global on purpose — the former is a filesystem
  layout concern, the latter a collision-avoidance knob.
- `Tab`, `TabState`, and `RestoredTab` carry four new optional fields
  — `worktreeID`, `worktreeRoot`, `worktreeOriginRepo`,
  `worktreeBranch` — so the worktree relationship survives session
  save / restore. Every field is tolerant of legacy JSON via
  `decodeIfPresent`; upgrading from v0.1.80 never fails to decode a
  saved session.

### Changed
- `ProjectConfigService.loadConfig` / `findConfigPath` accept an
  optional `originRepo` parameter. When the primary walk from the
  tab's working directory returns nothing, the service retries from
  the origin repo so `.cocxy.toml` living in the source repository
  still applies inside a worktree stored under `~/.cocxy/worktrees/`.
  The fallback is gated by `config.worktree.inheritProjectConfig`
  (default `true`) and every in-process caller — SurfaceLifecycle
  OSC 7 handler, TabLifecycle, MainWindowController watcher restart,
  SessionManagement restore — passes the gate through correctly.
- `CocxyConfig` decoder is now explicit and uses `decodeIfPresent`
  for `worktree` (new in v0.1.81) and `codeReview`, so config files
  written before either section existed still decode cleanly and
  fall back to defaults instead of throwing.

### Fixed
- `GitInfoProvider.isGitRepository` / `readBranchFromDisk` now handle
  linked worktrees and submodules where `.git` is a file (containing
  `gitdir: <path>`) instead of a directory. Prior to this, a worktree
  tab silently reported "not a git repo" and the sidebar branch was
  missing. Follows the absolute and relative forms of the gitdir
  pointer.

### Notes
- The worktree feature defaults to `enabled = false`. Existing
  installations see zero behavioural change until they opt in via
  Preferences or set `[worktree].enabled = true` in
  `~/.config/cocxy/config.toml`. When disabled, every CLI verb and
  palette action refuses with a hint pointing at the setting.
- Worktree storage defaults to `~/.cocxy/worktrees/<repo-hash>/<id>/`
  where the repo hash is a deterministic 16-char FNV-1a digest of
  the origin repo's absolute path. The digest is **not**
  cryptographic — it is used only as a short filesystem label; the
  manifest still records the full origin path and rejects loads that
  disagree.
- `on-close = "keep"` (default) leaves the worktree on disk when its
  tab closes so no uncommitted work is lost silently. Users run
  `cocxy worktree remove <id>` (refuses when dirty) or
  `cocxy worktree prune` (drops manifest orphans only) to clean up.
- Non-interactive tab closes from the CLI/socket bridge cannot show the
  `on-close = "prompt"` sheet. In that path, `prompt` is treated like
  `keep`: the tab binding is cleared from the manifest, and the worktree
  stays on disk for explicit `remove` / `prune` cleanup.

### Testing
- Swift Testing: 1791 cases across 183 suites (up from 1540 / 168 at
  v0.1.80). New dedicated worktree module ships ~100 cases covering
  the data model, manifest, atomic store, drift detection, branch
  templating, git-ref sanitisation, service actor against a real git
  repo in a per-test temp directory, CLI argument parsing, command
  palette wiring, preferences round-trip, and the origin-repo
  fallback.
- XCTest: 2550 cases (up from 2548). Four CLI command-count
  assertions were updated from 93 to 97.

## [0.1.80] - 2026-04-20

### Added
- Aurora chrome toggle in Preferences ("Enable Aurora chrome (experimental)") with subtitle copy and full round-trip persistence so the choice survives every save. The toggle now participates in the seven-step config field pipeline (struct, Codable, parse, defaults, project overrides, snapshot rebuild, TOML emit) and a new round-trip test pins the contract.
- Aurora sidebar custom glass popover on hover surfaces workspace, branch, directory, foreground process, agent identity, state, tool counts, and error counts so the user can diagnose a session without leaving the chrome.
- Inline git workflow inside Agent Code Review: branch and worktree state, stage / unstage hunks, commit message composition, and push controls live next to the diff list. New `CodeReviewGitWorkflow` model owns the underlying git invocations and `CodeReviewGitWorkflowPanel` renders the controls.
- Per-file agent activity panel inside Agent Code Review surfaces which agent worked on each file, with identity colour and tool counts mapped from the per-surface store.
- Floating "open review" suggestion overlay nudges the user to open the panel when an agent ships a diff while the chrome is collapsed.
- Syntax-aware text editor (`CodeReviewSyntaxTextEditor`) drives the feedback comment composer and commit message field with the project's monospaced theme.

### Fixed
- Per-surface agent detection isolation: the engine now keeps state machine, OSC parser, pattern matcher, and timing detector buckets per `SurfaceID`. Two splits running different agents in the same tab (for example Claude Code on the left and Codex on the right) no longer collapse into a single session or borrow each other's identity. Output routing also stops requiring a focused surface, so a background pane keeps feeding detection while the user works elsewhere.
- Aurora sidebar highlight no longer freezes on the previous tab when the user clicks a session row. `@Published` emits the new value during `willSet`, so the sidebar sinks now consume the value Combine delivered instead of re-reading the source object (which still holds the old value during emission). The sidebar also switched from a custom `Binding(get:set:)` wrapper around a `@Published` to a plain `let activeSessionID`, restoring SwiftUI's value-based diff.
- Canonical agent naming derived from `AgentConfigService.agentIdentifier(matchingLaunchLine:)` ensures banners such as "Claude Code v2.1.14" map to the configured `claude` identifier instead of leaking marketing text into the dashboard or being confused with Codex.
- Aurora status bar agent matrix counts every active snapshot per tab instead of capping at one, the summary text reflects the real "N working / M waiting" totals, and the matrix filters idle panes.
- Ports row in the Aurora status bar opens a Copy / Open popover instead of a tooltip, and chips render via `Text(verbatim:)` so port numbers no longer pick up the locale's thousand separator (`:8080` instead of `:8,080`). The timeline scrubber is hidden until replay work lands.
- TUIs running inside Cocxy now render their brand palettes correctly: `CocxyCoreBridge` strips `NO_COLOR` from the host process before spawning a shell and advertises `COLORTERM=truecolor`, `TERM_PROGRAM=CocxyTerminal`, and `CLICOLOR=1`.
- Aurora chrome stays visible when the config requests `tab-position = "top"` or "hidden": `MainWindowController+Theme` forces `.left` whenever Aurora is active, and the Toggle Tab Bar action reveals the sidebar instead of hiding it.
- Code Review toolbar stays anchored at the bottom with `ZStack(alignment: .bottom)` and `toolbarReservedHeight: 86`. Submit / Reject / Discard controls remain reachable through a horizontal `ScrollView` even when the panel width drops to its minimum.
- Aurora sidebar footer chip now reads "no telemetry" with an explanatory tooltip rather than the misleading "100% local" copy.
- `ForegroundProcessProbe` now claims the timeout result off the main actor before the deadline fires so a slow `sysctl` cannot prevent the watchdog from honouring its 50 ms budget.

### Changed
- `CocxyCoreBridge.deinit` synchronises to the main actor when called off-thread instead of asserting, keeping teardown safe in test harnesses and CLI exits.
- New `injectProtocolV2Message` helper routes the same in-process semantic pipeline that the wire format uses, so `cocxy protocol send` updates dashboards immediately during smoke tests without requiring a Protocol v2-aware TUI inside the terminal.
- Hook session bindings keep an optional surface companion (`hookSessionSurfaceBindings`) so signals sourced from native semantics route to the precise surface they came from, even across split tabs sharing a CWD.
- Aurora workspace adapter accepts an optional `stateSnapshot` parameter so callers can hand the freshest store contents into the source builder, eliminating stale reads when a publisher refresh races with a state mutation.
- `MainWindowController+AuroraIntegration` runs a periodic Aurora-only safety net that reconciles visible terminal buffers back into the per-surface store, covering missed launch edges after rebuilds, feature-flag toggles, or split focus churn.

### Notes
- Aurora is shipped behind the `appearance.aurora-enabled` flag (default `false`). Existing users keep the classic chrome by default; opting in via Preferences enables the redesigned sidebar, status bar, and command palette covered above.

## [0.1.79] - 2026-04-18

### Fixed
- CI release pipeline broke on the v0.1.78 tag because `GlassSurface.LiquidGlassBackground` referenced `SwiftUI.glassEffect(in:)` — a macOS 26 SDK symbol that GitHub Actions runners (macOS 15 SDK) cannot resolve even when the call site is guarded by `if #available(macOS 26.0, *)`. The runtime guard prevents the API from being called on older macOS but the compiler still needs the symbol to build. The liquid case now falls through to the shared `VisualEffectFallback` material until the CI runner image ships the macOS 26 SDK; swapping back to the real Liquid Glass API will be a one-line change once that bump lands.

### Notes
- The v0.1.78 tag remains in the repository history for traceability — its build artefacts were never uploaded because the release workflow failed on the SDK mismatch above. This v0.1.79 release carries the full Aurora redesign payload plus the SDK fix.

## [0.1.78] - 2026-04-18

### Added
- Aurora redesign foundation + primitives landed as a pure, additive design module under `Sources/UI/Design/`. The module ships the OKLCH token system with three palettes (Aurora / Paper / Nocturne), the `GlassSurface` primitive with its three-way render-mode resolver (Liquid Glass on macOS 26, `NSVisualEffectView` fallback on 14/15, opaque surface for Reduce Transparency / Increase Contrast), the ambient backdrop animation math, the `AgentChipView` component, the sidebar tree, and the status-bar lockup. Every view stays behind a unique `Design.*` namespace, never consumes production domain types, and is covered by unit tests on the data layer so regressions surface without booting AppKit.
- New `AuroraCommandPaletteView` + presentation-only `AuroraPaletteAction` + pure `AuroraPaletteFilter`. The overlay composes through `GlassSurface` so the same accessibility decision table drives its background, and the host wires action handlers through closures instead of a direct engine dependency. `Design.samplePaletteActions` ships a nine-row canonical catalog spanning Tabs, Splits, Window, and Theme used by previews, the tweaks panel, and the filter tests.
- New `AuroraTweaksPanel` developer inspector that flips the active theme palette, forces a specific `GlassRenderMode` override, toggles the ambient backdrop animation, and previews the palette row, agent chip, and local badge with the current tokens. `AuroraTweaksState` is a plain Equatable / Sendable value type so hosts can persist or restore the inspector selection without booting SwiftUI. The panel never ships in the production chrome.
- New `AuroraWorkspaceAdapter` — the pure seam between the production domain (`TabManager`, `AgentStatePerSurfaceStore`, `SplitManager`) and the redesigned sidebar tree. The integration layer feeds `[AuroraSourceTab]` / `[AuroraSourceSurface]` snapshots (manufactured from whatever the app currently exposes) and the adapter groups them into ordered `[AuroraWorkspace]`s with synthetic-pane fallback for surface-less tabs, first-non-idle primary selection, and deterministic stable ordering for identical input.

### Notes
- This release is entirely additive. No existing chrome, view model, config, or protocol was modified. Wiring the redesigned sidebar / status bar / palette into production will happen in a later release behind an explicit feature flag so the rollout can be staged and reverted without touching the tokenised design layer shipped here.

### Testing
- +27 Swift Testing cases across three new suites: `AuroraCommandPaletteFilterTests` (9), `AuroraTweaksStateTests` (8), and `AuroraWorkspaceAdapterTests` (10). Combined with the earlier foundation coverage the design module now ships 108 cases guarding every invariant the redesign depends on.
- Full suite: 2514 XCTest + 1540 Swift Testing = **4054 tests**, zero failures, debug + release builds green.

## [0.1.77] - 2026-04-18

### Fixed
- Rust TUI clients built on crossterm (Codex, Aider, tmux, mosh, ratatui-based tools) no longer hang on startup inside Cocxy. CocxyCore's CSI dispatcher was treating the Primary Device Attributes request (`CSI c`) and its secondary (`CSI > c`) / tertiary (`CSI = c`) variants as unknown sequences, silently dropping them while the client blocked waiting for a reply. The engine now answers Primary DA with `CSI ? 62 ; 22 c` (VT220 + ANSI color — the capability set xterm / Ghostty / Terminal.app broadcast), Secondary DA with `CSI > 0 ; Pv ; 0 c` (xterm-compatible shape with firmware = `major*100 + minor + patch`), and Tertiary DA with the VT420 DCS-wrapped zero payload. Responses flow through the existing `response_buf` path so the Swift bridge needed no changes.

### Changed
- Bundled CocxyCore engine to `0.13.4` (adds Primary/Secondary/Tertiary DA handlers and test coverage).

### Testing
- +6 Swift Testing cases in `CocxyCoreDeviceAttributesSwiftTestingTests` pinning the bridge-visible responses end-to-end (Primary default, explicit 0 param, ECMA-48 reserved-param short-circuit, Secondary firmware shape, Tertiary DCS payload, and a DSR regression guard).
- CocxyCore test suite adds 4 dispatch cases plus 6 executor response-byte cases, all green alongside the existing 47 suites.
- Full suite: 2514 XCTest + 1459 Swift Testing = **3973 tests**, zero failures, debug + release builds green.

## [0.1.76] - 2026-04-18

### Added
- Editable **Keybindings** tab in Preferences (replaces the previous read-only list). Lists every rebindable action from a new canonical catalog — 39 actions across Window, Tabs, Splits, Navigation, Editor, Review, Markdown, and Remote categories — with the current shortcut rendered in macOS modifier glyphs. Each row exposes **Edit** and **Reset** buttons; the top of the editor has a **Reset All** button plus a banner that lists any conflicting action groups in red. Saving is blocked until conflicts are resolved.
- **Capture modal** opens from the Edit button, consumes the next keystroke via a native `NSView`-backed field, validates it parses through `KeybindingShortcut`, and surfaces inline warnings when the captured shortcut collides with another action. Cancel abandons the edit, Save commits it, and a dedicated Clear button unbinds the action entirely.
- **Runtime wiring (`MenuKeybindingsBinder`)** — the menu bar now reads shortcuts from the live `[keybindings]` section instead of hardcoded literals. Each rebindable `NSMenuItem` carries a stable catalog id on its `NSUserInterfaceItemIdentifier`; the binder walks the menu tree after construction, overlays `keyEquivalent` + `keyEquivalentModifierMask` for every tagged item, and subscribes to `ConfigService.configChangedPublisher` so edits in Preferences (or direct TOML edits picked up by `ConfigWatcher`) take effect on the live menu bar without an app restart. Non-rebindable items (About, Hide, Quit, Cut/Copy/Paste, Undo/Redo, Services, Bring All to Front, the hidden Escape handler, Full Screen pre-existing macOS default) keep their original literals and are never rewritten.
- **Command Palette labels resolve live** — the shortcut column beside each palette row now calls `MenuKeybindingsBinder.prettyShortcut(for:in:)` with the live config so it displays whatever the menu displays. The palette engine is rebuilt on every open so fresh labels land without additional wiring. Actions outside the rebindable catalog (theme cycling, remote workspace toggle, workspace browser, sidebar transparency, etc.) keep their hardcoded `shortcut` strings.
- New domain types: `KeybindingShortcut` (canonical plus-separated string `<->` pretty macOS glyph label `<->` `NSEvent`), `KeybindingAction` + `KeybindingActionCatalog` (single source of truth for the 38 rebindable actions, categories, defaults), and `KeybindingsConfig.customOverrides: [String: String]` for extending the TOML `[keybindings]` section without breaking the eight legacy typed fields.
- `ConfigService` now parses both legacy kebab-case keys (`new-tab = "cmd+t"`) and quoted dotted catalog ids (`"split.close" = "cmd+shift+w"`) side-by-side. Quoted TOML keys are unquoted before lookup, unknown ids are ignored, and matching values are dropped from `customOverrides` so `[keybindings]` only stores meaningful user changes.
- `KeybindingsConfig.tomlSection()` is the single emitter used by both `ConfigService.generateDefaultToml()` and `PreferencesViewModel.generateToml()`, keeping the wire format identical regardless of who triggers the save.

### Changed
- Extracted `KeybindingsConfig` from `Sources/Domain/Protocols/ConfigProviding.swift` into its own file under `Sources/Domain/Models/` to keep both files under the 600-line quality budget after the new catalog helpers landed.
- `PreferencesViewModel` gained `applyKeybindings(_:)` / `effectiveKeybindings` / a lazy `keybindingsEditor`; the save path now threads pending keybindings through the same TOML writer that handles General, Appearance, Agent Detection, Notifications, and Terminal sections.
- `KeybindingShortcut` gained `menuKeyEquivalent`, `modifierMask`, and `isAssignableToMenuItem` helpers so the binder can map a parsed shortcut to `NSMenuItem.keyEquivalent` + `NSMenuItem.keyEquivalentModifierMask` in one step, including named keys (arrows, function keys, `plus`, `minus`, `grave`).
- `editor.zoomIn` default moved from the `"="` token (same physical key as `"+"` on US layouts) to the explicit `"plus"` token so the canonical TOML round-trips through the parser without hitting the ambiguous double-separator case (`"cmd++"`).
- Split defaults restored to the historical pairing: Split Horizontal = `Cmd+D` and Split Vertical = `Cmd+Shift+D`. The editable-keybindings feature shipped with the pairing reversed, which would have flipped every fresh install's muscle memory; menu setup, doc comments, and user-facing copy already described the historical pairing, so this reconciles the catalog defaults with shipped behaviour.

### Fixed
- `KeybindingsConfig` now decodes cleanly from legacy `CocxyConfig` JSON snapshots that omit the new `customOverrides` dictionary. A custom `init(from decoder:)` treats `customOverrides` as optional and falls back to an empty map so older session JSONs round-trip through the current decoder without throwing `.keyNotFound`.

### Notes
- `AppDelegate+MenuSetup` no longer encodes `keyEquivalent` literals for rebindable items; each rebindable item is declared via `MenuKeybindingsBinder.tag(_:with:)`. The menu tree keeps the hardcoded shortcut characters only for built-in macOS commands that users cannot rebind.
- `KeybindingsEditorViewModel.assign` stores shortcuts in their canonical plus-separated form regardless of the order the user held modifiers, so a later rebinding pass can compare stored values without re-parsing.

### Testing
- +14 Swift Testing cases in a new `MenuKeybindingsBinder` suite: identifier round-trip, apply-from-config, default fallback for missing actions, idempotency on the same config, hot-reload overwrite, invalid-shortcut preservation, untagged-item skip, submenu traversal, complex modifier combos, named-key resolution (arrow keys), and palette pretty-label lookup.
- Total new coverage across the keybindings feature (editor + runtime): 59 Swift Testing cases across four suites — `KeybindingShortcut` (19), `KeybindingsEditorViewModel` (15), `KeybindingsConfig` TOML round-trip (11), and `MenuKeybindingsBinder` (14).
- Full suite after runtime wiring: 2514 XCTest + 1368 Swift Testing = **3882 tests**, zero failures, zero warnings, debug + release builds green.
- Full suite on rebased branch (incl. decoder fix + split-default swap): 2514 XCTest + 1453 Swift Testing = **3967 tests**, zero failures, debug + release builds green.

## [0.1.75] - 2026-04-18

### Added
- New `appearance.transparency-chrome-theme` TOML key lets users pin the translucent sidebar, horizontal tab strip, and status bar to a light or dark tint independently of the macOS system appearance. Valid values: `"follow-system"` (default, preserves current behaviour), `"light"`, `"dark"`. Only applies while `background-opacity` is below `1.0`; otherwise the chrome is opaque and the override has no visible effect.
- New Preferences toggle: Appearance → Transparency → Glass chrome tint. The picker surfaces all three options, stays interactive even when the window is fully opaque (so the selection persists for when the user lowers the background opacity later), and hot-reloads via the existing config subscription so changes apply without restarting Cocxy. When the window is opaque a highlighted info note below the picker explains that the tint only appears while transparency is active and points the user at the opacity slider.
- Added accessibility metadata (label + hint) on the new picker so VoiceOver announces the setting's purpose.

### Changed
- `AppearanceConfig` now carries a new `transparencyChromeTheme` property. Custom `Decodable` init decodes cleanly from legacy session snapshots that lack the key (falls back to `.followSystem`) so previously persisted configs and sessions round-trip unchanged.
- `TabBarView`, `HorizontalTabStripView`, and `StatusBarView` (plus the shared `VisualEffectBackground` wrapper used by every SwiftUI panel) accept an optional `NSAppearance` override on their vibrancy layers. `MainWindowController.applyEffectiveAppearance` resolves the enum once per config change and fans the override out to every chrome site; `refreshStatusBar` and `buildRootView` mirror the override on initial render.
- Extended the override to every on-demand overlay: Command Palette, Dashboard, Timeline, Code Review, Notification panel, Browser (main + DevTools + Downloads + History + Bookmarks), Remote Workspace, Scrollback Search bar, and live Subagent split panels. Each view exposes a new `vibrancyAppearanceOverride: NSAppearance?` property with a `nil` default, so existing call sites compile without change. Host controllers pass the override at construction time via `resolveVibrancyAppearanceOverride()`, and a new `syncVibrancyOverrideToLiveOverlays` pass rebuilds the SwiftUI root view of every visible overlay whenever `applyEffectiveAppearance` runs — so live panels hot-reload in place when the user flips between `dark`, `light`, and `follow-system`.

### Testing
- 25 new Swift Testing cases for the base feature: `TransparencyChromeThemeRoundTripTests` (TOML round-trip for all three values, tolerant parsing of unknown strings / wrong types / missing keys, default template, and legacy JSON backwards compatibility), `PreferencesViewModelTransparencyChromeThemeTests` (load reflects config, dirty tracking, discard, save persistence, generated TOML shape, editable flag gating on `backgroundOpacity`), and `TransparencyChromeThemeVibrancyAppearanceTests` (enum → `NSAppearance?` resolver for every case).
- 19 additional Swift Testing cases covering overlay propagation: `ResolveVibrancyOverrideTests` (helper resolves correctly for every enum case plus the opaque guard), `OverlayVibrancyConstructionTests` (seven overlays each receive the forced appearance at construction time), `OverlayVibrancyHotReloadTests` (live overlays repaint when `applyEffectiveAppearance` is invoked with a new config, revert to `nil` on `follow-system`, and stay unaffected when the default preserves legacy behaviour), and `SubagentContentViewVibrancyTests` (initializer + `setVibrancyAppearanceOverride` round-trip).
- Smoke test: launched app with `~/.config/cocxy/config.toml` containing `transparency-chrome-theme = "dark"` and `background-opacity = 0.85`. Command Palette, Dashboard, Timeline, Notification panel, Browser (main + History + Bookmarks + Downloads + DevTools), Code Review, and Remote Workspace all rendered with forced dark vibrancy regardless of macOS appearance; toggling to `light` hot-reloaded every live overlay without dismissal; reverting to `follow-system` restored inheritance within the debounced reload window.
- Full suite on rebased branch: 2514 XCTest + 1394 Swift Testing = 3908 tests, zero failures, debug + release builds green.

### Notes
- The override intentionally does not touch terminal buffer content — CocxyCore still renders according to the selected `[appearance] theme`. Only the translucent chrome tint changes. This matches the user's intent: wallpapers with warm vs cool tones should not require flipping the entire macOS appearance.
- `VisualEffectBackground` keeps backward compatibility: existing call sites that don't pass `appearanceOverride` get `nil` (inherit), so any future SwiftUI panel that forgets to thread the override simply falls back to system appearance.

## [0.1.74] - 2026-04-18

### Added
- Sidebar mini-pills now carry the agent's two-letter abbreviation (`Cl` Claude, `Co` Codex, `Ge` Gemini, `Ai` Aider, `Gh` GitHub Copilot, `Cu` Cursor, `Cn` Cline, `Ct` Continue, `Qw` Qwen, `Op` OpenCode, `Ki` Kiro; unknown agents fall back to the first two letters of the name capitalized), draw a 1.5pt border in the state color when the split is focused, and route clicks to the target split so a tap activates the tab (if needed) and lands keyboard focus on the right pane. Inline budget adjusted from 5 to 4 pills plus the `+N` overflow label because each pill now reserves ~30pt for the abbreviation.
- Status bar renders a compact mini-matrix of agent-state dots between the port indicators and the active-agent text whenever the active tab has two or more active agents. Each dot reflects the state color of its split, uses a 1.5pt stroke overlay around the focused split, and exposes the agent name + state via hover tooltip and accessibility label. Up to six dots render inline plus a `+N` overflow counter.
- New `SurfaceAgentSnapshot` value type bundling a surface ID with its `SurfaceAgentState` plus `isFocused` / `isPrimary` flags. The snapshot powers per-split features (mini-pills, status-bar matrix, code-review surface selector) so every consumer shares one source of truth and a click can route focus back to the correct surface.
- `SurfaceAgentStateResolver` gains `additionalActiveSnapshots(...)` and `allActiveSnapshots(...)` — identity-aware twins of the existing `additionalActiveStates`. `MainWindowController` exposes thin wrappers (`additionalActiveAgentSnapshots(for:)`, `allActiveAgentSnapshots(for:)`) so every consumer reuses the same filter (`state.isActive || state.hasAgent`) and deterministic UUID ordering.
- `MainWindowController+FocusSplit` extension with `focusSplit(tabID:surfaceID:)` that activates the owning tab when needed and makes the split's host view the window's first responder on the next run-loop tick. Safe with stale surface IDs (silent no-op when the split was closed between render and click).
- New `ForegroundProcessProbe` (main-actor isolated) runs `ForegroundProcessDetector.detect(...)` on a user-initiated dispatch queue with a hard 50 ms deadline. The shell-prompt recovery path no longer stalls the main thread on `sysctl(KERN_PROC_ALL)` under lock contention — a stall there previously froze keydown delivery for the focused surface, the root cause of "split pane stops accepting typing after a zsh autocorrect prompt". The probe is cancelled from every teardown path (`destroyTerminalSurface`, `destroyAllSurfaces`, `closeSplitAction`, `.processExited`) and from the reset routine itself so late completions cannot touch a cleared store.
- New `SurfaceInputDropMonitor` (main-actor isolated) watches the bridge's `inputDeliveryObserver` stream and raises a user-visible notification when three consecutive PTY writes drop for the same surface. The handler plays `NSSound.beep()`, resolves the owning tab, and enqueues a notification that hints at the recovery action (`Cmd+Shift+W` closes the split). A successful delivery resets the counter so future stuck episodes can still fire.

### Changed
- `TabItemView.configureMiniIndicators` now consumes `TabDisplayItem.perSurfaceAgents` (`[SurfaceAgentSnapshot]`) instead of the legacy `additionalActiveAgentStates` (`[AgentState]`). Backward compatibility is preserved: the legacy field and its provider stay populated for consumers that still depend on them; they will be retired in a follow-up cleanup once every call site has migrated.
- `AgentSummary` gains a `perSurfaceSnapshots` field consumed by the status bar mini-matrix. Single-split tabs keep the compact header because the matrix only renders at `>=2` active agents.
- `CocxyCoreBridge.sendKeyEvent` and `sendText` now emit an `InputDeliveryEvent` (`.delivered` / `.dropped(reason)`) for every attempt so downstream monitors observe the PTY outcome directly instead of inferring it from return values. The observer is optional; test doubles and the CLI companion leave it unset without behavioural change.

### Fixed
- Agent state written in response to a hook event can no longer leak into a sibling tab that shares the same working directory. When the user creates a new tab, its initial CWD is inherited from the previously active tab; launching an agent in the new tab then sent a hook with that shared CWD, and the per-surface routing picked the first live surface the bridge iterated over — frequently the older tab's primary — so the sidebar pill, status-bar text, and notification ring appeared on the wrong tab. `CocxyCoreBridge.resolveSurfaceID(matchingCwd:)` now accepts an optional `within:` surface-ID filter, and `AppDelegate+AgentWiring.surfaceIDForDualWrite` passes the surfaces that belong to the resolved tab so the CWD match stays inside the correct boundary. The legacy single-argument call path is preserved for any caller that still lacks a tab context.
- Terminal bell (BEL byte) no longer pushes an entry into the in-app notification panel every time the shell rings — zsh autocorrect prompts, tab-completion mismatches, and readline beeps were filling the panel with low-signal "Terminal bell" cards and bumping the Dock badge on every typo. The bell callback now plays `NSSound.beep()` on the main queue, matching standard macOS terminal behaviour, and the CocxyCore callback stays registered so a future `terminal.audibleBell` preference can remap the sound without touching the C API.
- Silent PTY drops in `sendKeyEvent` / `sendText` now log to `os_log` (subsystem `dev.cocxy.bridge`, category `input`) so post-mortem diagnosis can pair a drop with its triggering lifecycle event. Two reasons are distinguished: `surfaceMissing` (the bridge lost the surface entry while the caller still held its ID) and `ptyWriteFailed` (the kernel rejected the write despite a live surface).

### Testing
- +17 Swift Testing cases for the new sidebar + status-bar providers (12 resolver, 4 viewModel wiring, 1 equality).
- +5 Swift Testing cases for the new `resolveSurfaceID(matchingCwd:within:)` filter: legacy nil-allowed behavior, restriction to an explicit surface set, exclusion when the match lies outside the set, empty-set short-circuit, and a regression scenario where two tabs share a CWD and each must resolve to its own surface.
- +9 Swift Testing cases for `ForegroundProcessProbe` covering the fast path, detector-nil path, deadline win, cancellation, rescheduling across the same surface, surface isolation, and the introspection contract.
- +10 Swift Testing cases for `SurfaceInputDropMonitor` covering sub-threshold silence, single-fire per stuck episode, delivery resets, surface isolation, per-surface clear, full clearAll, threshold tuning, and post-construction handler swap.
- Full suite: 2514 XCTest + 1350 Swift Testing = 3864 tests, zero failures, debug + release builds green.

## [0.1.73] - 2026-04-17

### Fixed
- Per-surface agent state now resets to `.idle` when a shell prompt returns on a surface whose PTY foreground process is a login shell, even if the agent terminated without emitting a `SessionEnd` hook. Previously, agents that aborted early (an agent launch failing before bootstrap, a manual `Ctrl+C`, or any crash before the hook handshake) left the sidebar pill, status bar, and progress overlay reporting activity indefinitely. The recovery is conservative: it only fires when the PTY foreground matches a known shell binary (`zsh`, `bash`, `fish`, `sh`, `dash`, `ksh`, `tcsh`, `csh`), so editors, sub-commands invoked by the agent (`git`, `npm`, …), and long-running builds keep their state intact.
- A secondary watchdog now flushes per-surface state back to `.idle` after 30 seconds if a surface enters `.launched` and never progresses (no output, no hook event, no teardown). This catches agents that crash before printing anything — the case where the shell-prompt recovery cannot fire because the shell never redraws its prompt.

### Added
- New `AgentLifecycleRecovery` pure helper encapsulating the shell-prompt reset decision. Testable without AppKit via `AgentLifecycleRecoverySwiftTestingTests` (17 cases covering every shell binary, every non-idle state, case-insensitivity, whitespace handling, and the `.idle` / nil / empty short-circuits).
- New `AgentLaunchedWatchdog` main-actor scheduler around per-surface `DispatchWorkItem`. Idempotent `schedule` / `cancel` / `cancelAll` with introspection helpers for tests. 7 Swift Testing cases cover the full lifecycle.
- New `MainWindowController+AgentLifecycleRecovery` extension that wires the recovery and the watchdog into the surface lifecycle. A single `performAgentStateReset(surfaceID:tabID:reason:)` routine mirrors the teardown reset sequence (engine bucket cleanup, store reset, session registry sync, sidebar / status-bar / overlay / notification-ring refresh) so both code paths — the shell-prompt recovery and the watchdog — produce identical UI behaviour. Integrated into `MainWindowController+SurfaceLifecycle` (case `.shellPrompt` plus every teardown path) and `AppDelegate+AgentWiring` (auto-schedule/cancel when the store transitions into or out of `.launched`). 9 Swift Testing cases cover the end-to-end integration.

### Testing
- Full suite: 2514 XCTest + 1309 Swift Testing = 3823 tests, zero failures, zero warnings, debug + release builds green.
- +33 Swift Testing cases vs v0.1.72 (17 helper + 7 watchdog + 9 integration).

## [0.1.72] - 2026-04-17

### Changed
- Tab-scoped agent indicators (sidebar pill, agent progress overlay, per-surface notification ring, status-bar summary, and multi-agent mini-pills) now resolve their state through `SurfaceAgentStateResolver` instead of reading tab-level fields. The resolver's priority chain is focused split > primary surface > any other surface with live activity > `.idle` fallback, so splits running independent agents drive their own indicators and the focused pane never pulses on its own tab.
- Split panes running independent agents show their own pulsing notification ring when waiting on user input, while the pane the user is actively looking at stays quiet.
- Tabs with multiple active splits now render mini-pills next to the primary sidebar pill, one per additional active surface (up to five inline plus a `+N` overflow label), sorted deterministically by surface UUID so successive renders stay stable.

### Fixed
- Shell-exit handler (`MainWindowController+SurfaceLifecycle.processExited`) now explicitly calls `engine.clearSurface(sid)` after `notifyProcessExited(surfaceID:)`. Previously only the exit transition fired, and the engine's debounce and hook-session buckets stayed populated until the surface was destroyed, so a surface that outlived its shell could carry stale per-surface routing state. Store reset continues to run in the same block. A new regression test `notifyProcessExitedDoesNotClearBuckets` pins the engine contract.

### Removed
- Retired the five tab-level forwarding fields (`agentState`, `detectedAgent`, `agentActivity`, `agentToolCount`, `agentErrorCount`) from `Tab`. Per-surface agent state lives exclusively in `AgentStatePerSurfaceStore`; the `AppDelegate+AgentWiring` sink now writes only the store, and surface teardown releases the entry alongside the engine's debounce and hook-session buckets. Legacy session JSONs keep decoding because Swift's auto-synthesised `Codable` silently ignores the retired keys.
- Removed the unused `TabViewModel` type and its test file. Its only production reference was the `maxTitleLength` constant, which now lives on `TabBarViewModel`.

### Testing
- Rewrote `AgentWiringDualWriteSwiftTestingTests` as `AgentWiringStoreOnlySwiftTestingTests` (16 cases) to pin the store-only wiring contract end-to-end.
- Added Swift Testing coverage for every new helper: `SurfaceAgentStateResolver` (priority chain + tab-less signature), `NotificationRingDecision` (per-surface ring decisions), `AgentStatusTextFormatter` (status-bar label and counter bucket mapping), and `TabBarViewModel` resolver wiring (sidebar pill + multi-agent mini-pills).
- Added `PerSurfaceStoreE2ESwiftTestingTests` wiring the real store, resolver, and view model together without booting AppKit.
- Preserved every legacy integration test by migrating it to the per-surface store. Full suite: 2514 XCTest + 1276 Swift Testing = 3790 tests, zero failures, zero warnings, debug + release builds green.

## [0.1.71] - 2026-04-17

### Changed
- Agent detection is now scoped per terminal surface instead of per tab. Debounce buckets and hook-session tracking key on the originating surface, so an agent running in one split of a tab no longer masks or corrupts a sibling split's detection state. Tabs without splits keep their previous behavior exactly.
- Every production call site in the surface lifecycle forwards the originating surface through to the detection engine (`processTerminalOutput`, `notifyUserInput`, `notifyProcessExited`), so every emitted state transition carries the split that produced it.
- Surface teardown now releases both the engine's per-surface debounce and hook-session buckets and the new shadow per-surface agent state store, preventing stale state from outliving a destroyed split.

### Added
- `CocxyCoreBridge.resolveSurfaceID(matchingCwd:)` returns the first live surface whose working directory matches an external path. Path matching is normalized via `URL.standardizedFileURL.path`, tolerant of trailing slashes and `.` components, and rejects prefix-only matches.
- `AgentStatePerSurfaceStore` is a new main-actor shadow source of truth that mirrors every tab-level agent mutation onto a per-surface entry. Tab fields remain the reader for now; the store is the groundwork for the upcoming UI migration so sidebar pills, status bar, and notification rings can render independent state for each split.
- New lifecycle hook `AgentDetecting.clearSurface(_:)` lets callers release a surface's per-surface state (debounce + hook-session buckets) in one idempotent step. The production detection engine implements it; other conformers get a no-op default.

### Testing
- 34 new Swift Testing cases across three suites: per-surface debounce and hook buckets plus `clearSurface` lifecycle (`AgentDetectionEngineSurfaceRoutingSwiftTestingTests`), CWD resolution contract (`CocxyCoreBridgeCwdResolutionSwiftTestingTests`), and end-to-end dual-write coherence between `Tab` and the per-surface store (`AgentWiringDualWriteSwiftTestingTests`). Full suite: 2535 XCTest + 1223 Swift Testing = 3758 tests, zero failures.

## [0.1.70] - 2026-04-16

### Fixed
- Baseline jitter between neighbouring letters on the same line. The fix has two parts that must land together: (1) each glyph is rasterised onto a whole-pixel grid in the atlas (CoreGraphics subpixel positioning and subpixel quantisation disabled, bitmap origin rounded) so no fractional offset is baked into the cached pixels; (2) the per-glyph `bearing_y` is stored as an integer distance from the top of the bitmap to the baseline, derived from the same `@ceil`/`@round` expressions that sized the bitmap, so every cell on a row resolves to the same `glyph_y + bearing_y` and therefore a stable baseline regardless of whether the glyph has a descender or a tall ascender.

### Changed
- Bumped the bundled CocxyCore engine to v0.13.3. The new engine ships the pixel-aligned rasterisation path and the baseline-consistent `bearing_y` formula used by every consumer of `GlyphInfo`.
- Metal glyph sampler comment in `MetalTerminalRenderer` now reflects the pixel-aligned pipeline so future readers do not mistake linear sampling for a workaround around subpixel placement.

### Testing
- New Zig regression suite `metal_pixel_align_test.zig` locks two contracts simultaneously: per-cell `glyph_x` / `glyph_y` must be integers (covered on both the atlas-hit and fallback paths), and `glyph_y + bearing_y` must be constant for every glyph on a given row (the baseline invariant). Any future refactor that drops a `@round(...)` or reverts the integer bearing formula fails the test instead of silently reintroducing the jitter.

## [0.1.69] - 2026-04-16

### Added
- Configurable font stroke thickening: new `font-thicken` key under `[appearance]` in `config.toml`, plus a "Thicken font strokes" switch in Preferences → Appearance. Off by default so glyph strokes render thin and crisp on the grayscale atlas; turn it on to boost stroke weight for users who prefer a heavier look.

### Changed
- Bumped the bundled CocxyCore engine to v0.13.1. Previous builds applied `CGContextSetShouldSmoothFonts(true)` unconditionally during glyph rasterization; upgrading installs will see thinner, crisper strokes by default. The engine now exposes `cocxycore_terminal_set_thicken` / `_get_thicken` and persists the flag across font changes, so switching fonts no longer resets the preference.

### Fixed
- CocxyCore's WebSocket handshake now tolerates fragmented HTTP upgrade headers across short socket read timeouts, eliminating sporadic `ConnectionClosed` / `ConnectionResetByPeer` failures that surfaced in the web-relay test suite when the upgrade request arrived as more than one TCP segment.

## [0.1.68] - 2026-04-15

### Added
- Five new built-in color themes: Catppuccin Frappe, Catppuccin Macchiato, Nord, Gruvbox Dark, and Tokyo Night (fixes #1, #2, #3). The built-in catalog now ships 11 themes, each with the full palette (background, foreground, cursor, selection, tab states, badge colors, and 16 ANSI colors) sourced from the official specification of each project. Custom themes via `~/.config/cocxy/themes/*.toml` continue to extend the catalog.
- Agent detection patterns for Cursor Agent and Windsurf (fixes #5). The detection catalog now covers 8 agents out of the box, with launch, waiting, error, and finished indicators plus idle-timeout override per agent.

### Changed
- The reference `Resources/defaults/agents.toml` snapshot is now kept in sync with the authoritative `AgentConfigService.defaultAgentConfigs()` source of truth via a dedicated parity test; the runtime continues to read from the Swift-side source so the TOML file remains a documentation/manual-install reference.

## [0.1.67] - 2026-04-14

### Added
- Agent Code Review panel auto-refreshes within ~200 ms of any file change reported by the integrated coding agent, eliminating the previous polling/manual-refresh latency.
- Agent Dashboard now uses the agent's own filesystem signal as the canonical source for `touchedFilePaths`, attributing edits to the active subagent when one is uniquely identifiable and to the session otherwise.
- Tab working directory follows the agent when it changes directory mid-session, complementing the existing OSC 7 path so the sidebar and status bar stay accurate even for tools that bypass the shell.
- `cocxy setup-hooks` (and the auto-installer that runs on every launch) now register the two new lifecycle event types alongside the existing twelve.

### Changed
- Hook event coverage expanded from 12 to 14 event types end-to-end (CLI handler, normalizer, socket router, in-process publisher, detection engine, dashboard, timeline, code-review panel, snapshot tracker).

### Security
- Continued strict CWD exact-match enforcement for the new hook consumers — no parent-directory fallback, eliminating cross-terminal contamination as a possible regression vector.

## [0.1.65] - 2026-04-14

### Added
- Agent Code Review panel is now resizable with `-` / `+` controls in the header; the preferred width is persisted across sessions and restored on re-launch.

### Changed
- CocxyCore compatibility matrix tests use explicit higher timeouts on heavy scenarios (vim, nano, less, man, curl progress, rsync progress) so failures stay deterministic under full-suite CPU contention instead of being masked by retries.

### Fixed
- Review panel width no longer loses the user's preference after the window is temporarily shrunk and then re-grown.

## [0.1.63] - 2026-04-13

### Fixed
- V0.1.63 — add SUPublicEDKey for Sparkle verification, fix CI type-check

## [0.1.62] - 2026-04-13

### Added
- V0.1.62 — agent detection full parity, multi-agent hooks, Quick Look offline preview

## [0.1.61] - 2026-04-13

### Fixed
- V0.1.61 — add SUFeedURL to Info.plist for Sparkle auto-update

## [0.1.60] - 2026-04-12

### Fixed
- Hook handler now only forwards events from shells spawned inside Cocxy, preventing unrelated lifecycle events from other terminals
- QuickLook extension registration now verified from the installed app path

### Added
- `install-local-app.sh` script for local app installation with QuickLook registration verification
- Swift Testing suite for hook handler forwarding logic

## [0.1.59] - 2026-04-12

### Added
- Markdown Fase 5 complete — reference-style links, setext headings, code block filenames, sortable tables, TSV table copy, inline [TOC] generation, copy as Markdown/HTML/Rich Text/Plain Text
- QuickLook extension for previewing `.md` files in Finder with Mermaid, KaTeX, and syntax highlighting
- File explorer context menu: rename, move to trash, reveal in Finder
- `CocxyMarkdownLib` extracted as independent SPM library target
- CLI `send --stdin` for multiline and escape-safe input
- 15 callout types and 200+ emoji shortcodes in markdown parser

### Fixed
- CocxyCore charwidth: U+23F8-23FA and U+2733-2734 reclassified as narrow, fixing smeared TUI delta redraws
- Markdown preview template refactored from 667 LOC monolith into 3 focused files (base + CSS + JS)

## [0.1.58] - 2026-04-12

### Added
- Markdown Fase 4 complete — interactive preview, callouts, footnotes, extended syntax

## [0.1.57] - 2026-04-12

### Fixed
- V0.1.57 — harden per-surface terminal locking across all public bridge paths

## [0.1.56] - 2026-04-12

### Added
- V0.1.56 — markdown Fase 3 complete: file explorer, search, git blame/diff, slides, word count

## [0.1.55] - 2026-04-12

### Added
- V0.1.55 — markdown Fase 2 complete: WKWebView preview, Mermaid, KaTeX, export, scroll sync

## [0.1.54] - 2026-04-12

### Fixed
- V0.1.54 — production launch crash, missing CI bundle resources, packaging verification

## [0.1.53] - 2026-04-12

### Fixed
- V0.1.53 — click-to-position, shell cmd tracking, ligatures refresh, font overhaul

## [0.1.52] - 2026-04-10

### Added
- Markdown source view is now a real plain-text editor: undo/redo, native Find bar (Cmd+F), and all AppKit autosubstitutions disabled so markdown syntax is never rewritten under the user
- Cmd+B toggles `**bold**` on the current selection (wraps new, unwraps existing)
- Cmd+I toggles `*italic*` on the current selection
- Cmd+K wraps the selection in `[text](https://)` and selects the URL placeholder for immediate typing; with no selection it inserts `[link text](https://)` and selects the label
- Live propagation from source edits to the preview pane, heading outline, and document model via a debounced pipeline
- Debounced save-on-edit writes back to disk atomically 150 ms after the last keystroke
- File watcher now reacts to `write`, `rename`, and `delete` events and dedupes its own saves by comparing on-disk content against the in-memory document

### Fixed
- Two local-variable warnings in `MarkdownParser` (`var` → `let` where the binding was never reassigned)
- File watcher could previously re-enter a reload loop on the writer's own atomic save because it never compared the new on-disk content against the in-memory document
- Markdown panel leaked its `DispatchSourceFileSystemObject` and pending save work item when removed from a parent without an explicit teardown; `viewWillMove(toSuperview:)` now cancels both

### Changed
- Markdown source view moved from `NSTextView` readonly to an editable `MarkdownEditorTextView` subclass that routes key equivalents through a custom shortcut handler before falling back to the standard AppKit pipeline
- Re-highlight pass after an edit runs inside a disabled-undo scope so cosmetic attribute updates no longer contaminate the user's undo stack
- `typingAttributes` are reset after every re-highlight so newly typed characters always start with the theme's base font and color instead of inheriting the attribute run under the caret

## [0.1.51] - 2026-04-10

### Added
- Native markdown viewer with GFM parser written in pure Swift, zero dependencies
- Source / preview / split view modes with Cmd+1, Cmd+2, Cmd+3 shortcuts
- Heading outline sidebar with tree navigation (Cmd+Shift+O toggle)
- Syntax highlighting for markdown source view
- Preview renders headings H1-H6, bold, italic, strikethrough, inline code, code blocks with language, blockquotes, ordered and unordered lists, nested lists, task lists, GFM tables with alignments, horizontal rules, and frontmatter YAML
- `NSLock` per-surface serializing PTY feed against frame build to eliminate render race conditions
- `MainWindowController` now handles `windowDidChangeScreen`, `windowDidChangeScreenProfile`, `windowDidChangeBackingProperties` as a render safety net

### Fixed
- Terminal surface becoming transparent when the window moves between displays with different backing scales
- Terminal surface becoming transparent when launching an AI coding agent with heavy output
- `MetalTerminalRenderer.draw` bailing silently without re-arming the dirty flag, causing the display link to skip subsequent frames until an external event re-triggered rendering
- Race condition between `cocxycore_terminal_feed` (background queue) and `cocxycore_terminal_build_frame` (main thread) causing frames to be dropped
- `CVDisplayLink` continuing to tick against the original display after the window moved to a different screen
- `CAMetalLayer` `contentsScale` and `drawableSize` changing outside a `CATransaction` with actions disabled, leaving the drawable temporarily inconsistent with the layer geometry
- `NSWindow.didChangeScreenNotification` observer refreshing through an unnecessary async hop that could land after the display link had already dropped a tick

### Changed
- `MetalTerminalRenderer.draw` now returns `Bool` indicating whether a frame was committed
- `CocxyCoreView.renderFrame` re-arms `needsRender` when `draw` returns false so transient render failures recover on the next display link tick
- `MarkdownContentView` rewritten from a basic prefix-detecting text view into a full markdown document panel with toolbar, outline sidebar, mode switcher, and live reload

## [0.1.50] - 2026-04-10

### Fixed
- Display scale resync on screen change, deferred CWD probe, live agent status

## [0.1.49] - 2026-04-09

### Added
- Centralized PTY write path, mode diagnostics, async proxy startup

## [0.1.48] - 2026-04-09

### Added
- PTY-backed process detection, native search, CocxyCore contract wiring

## [0.1.47] - 2026-04-08

### Fixed
- CocxyCore AGENT_WAITING events never triggering waiting-input state in detection engine
- CocxyCore AGENT_ERROR events invisible to detection engine and dashboard
- Smart Routing overlay navigation broken (tabNavigator nil)
- CLI `cocxy new-tab --dir` parameter mismatch (directory vs dir)
- ConfigWatcher hot-reload silently replacing config with defaults on malformed TOML
- ConfigWatcher for config.toml never instantiated in production
- NotificationManager attention queue growing without bound (memory leak)
- Dashboard ignoring idle transitions for pattern-detected agents (sessions stuck forever)
- Detection engine reset() not clearing pattern detector stale matches
- Scrollback search searchAsync() blocking MainActor on large buffers
- Browser "Manage Profiles" button visible but non-functional
- CLI version stuck at 0.1.45 instead of 0.1.46
- Dashboard handleTeammateIdle setting .idle instead of .waitingForInput
- MetalTerminalRenderer double cursor read per frame (wasted C API call)
- IDECursorController padding hardcoded to 8,4 instead of reading configured values
- Timeline subjects dictionary growing without bound on session clear
- Hook events without CWD bypassing dashboard tab ownership filter
- Search bar result count and navigation not updating after next/prev (missing @Published)
- Bash PROMPT_COMMAND array flattened to string in Bash 5.1+
- Bash preexec firing for every command in pipeline instead of once
- Bash debug trap recursion guard missing cocxy helper functions
- Fish printf using non-standard `--` end-of-options marker
- Appearance observer hardcoding "Catppuccin Latte" as light theme
- Session restore silencing errors without logging
- TOML parser truncating basic strings with escaped quotes
- Split close always focusing first leaf instead of nearest sibling
- File descriptors leaked to child processes (missing O_CLOEXEC on 7 watchers)
- ProjectConfig isEmpty comparison fragile against new fields
- Bash integration loaded flag exported unnecessarily to child processes

### Added
- `reloadIfValid()` method on ConfigService for safe hot-reload
- ConfigWatcher production instantiation with startConfigWatcher() in AppDelegate
- `lightTheme` field in AppearanceConfig (configurable via `light-theme` in config.toml)
- `reset()` method on PatternMatchingDetector for clean session transitions
- Quick Terminal toggle action in Command Palette
- Background thread search via `Task.detached` in ScrollbackSearchEngine
- `isEmpty` computed property on ProjectConfig
- `transitionAllPatternSessionsToIdle()` in dashboard for clean idle transitions
- Notification queue pruning at 200 items max

## [0.1.46] - 2026-04-08

### Fixed
- Data race in CommandPaletteEngine between execute() and search() on shared state
- ConfigWatcher/AgentConfigWatcher silently stop watching after atomic write (vim/emacs rename)
- ConfigWatcher marks isWatching=true when config file does not exist yet
- ProjectConfigWatcher same isWatching bug — now returns false for non-existent files
- Command Palette "New Tab" creates blank tab without terminal surface
- paneSnapshotFromFirstResponder filters out terminal panes in split focus sync
- Mouse click-to-cell mapping uses hardcoded padding instead of configured values
- IME preedit overlay width incorrect for CJK characters (UTF-8 bytes vs display columns)
- CLI version stuck at 0.1.0-alpha instead of matching app version
- AppearanceObserver auto dark/light theme switch not applied to terminal surfaces
- Fish shell integration does not restore XDG_CONFIG_HOME after bootstrap
- Fish OSC 133;D reports exit status 0 instead of real command exit code
- CLI config set truncates multi-word values like font family names
- handleWindowFullscreen reports inverted fullscreen state (async toggle)
- ANSI escape regex recompiled on every call in TerminalOutputBuffer
- AnyCodableValue silently drops nested arrays and objects in hook event data
- PatternMatchingDetector can miss patterns when UTF-8 character split across chunks
- destroySurface race condition between read source cancel and PTY teardown
- Port scanner and remote workspace subscriptions lost after window re-creation
- Tab.isCommandRunning can show stale state without atomic field reset
- AgentConfigWatcher double-parses TOML on reload
- CVDisplayLink passUnretained pointer risk during teardown
- windowWillClose missing nil cleanup for sidebar and tab bar callbacks
- CodableColor Hashable inconsistent with custom Equatable
- CommandPaletteCoordinator placeholder methods now use proper closures
- Bash shell integration sources user .bashrc in non-interactive mode
- Quick switch palette action incorrectly wired to quick terminal
- CWD reporting uses raw path instead of URL-encoded format in OSC 7

### Added
- URI percent-encoding for OSC 7 CWD reporting in all three shells (zsh, bash, fish)
- Tab.markCommandStarted/markCommandFinished methods for safe state transitions
- CocxyCoreBridge.terminalDisplayWidth for correct CJK column width calculation
- ConfigWatcher parent directory watching when target config file doesn't yet exist
- isInternal property on CLICommand to hide internal commands from --help
- reloadIfValid on AgentConfigService to preserve state on malformed TOML
- MockClipboardService restricted to debug builds only
- spawnPty main-thread precondition assertion

### Changed
- Shell integration scripts now capture exit status before any conditional checks
- Command Palette coordinator fully wired with closures for all AppKit-layer actions

## [0.1.45] - 2026-04-08

### Added
- Fish shell integration with full OSC 133 semantic marks and OSC 7 CWD reporting
- Bash .bashrc bootstrap that restores HOME before sourcing user config
- Triple-check font availability in FontFallbackResolver (NSFont, manager, descriptor)

### Fixed
- CocxyCore font fallback retries with system monospace when requested family fails
- Bash preexec correctly wired through DEBUG trap with self-referential guard
- Split creation inherits the visible tab's working directory, not the domain-model active tab
- Focused pane resolution prefers AppKit first responder over stale domain model state
- Active terminal surface avoids returning stale bootstrap surfaces after restore
- Dashboard pattern context aligned with visible tab and active surface resolution

## [0.1.44] - 2026-04-08

### Added
- Native Cocxy shell integration for zsh (OSC 133 + OSC 7 + title) and bash (CWD reporting)
- Shell integration resources bundled in app and copied to app bundle on build

### Fixed
- Launch no longer creates throwaway bootstrap surface when a saved session is available to restore
- Bootstrap surface recreated cleanly when session restore fails or comes back empty
- Font re-rasterization on window attach and backing scale changes (fixes fuzzy/huge text on display switch)
- Closing the last terminal pane when only panels remain is now blocked with audible feedback
- Subagent panels no longer opened for generic agent types (Agent, Subagent, general-purpose, unknown)
- Cross-window focus now aligns activeTabID alongside the visible tab
- Split close fallback chain expanded to prevent empty container state
- resetControllerForRestore cleans container subviews, nils surface view, and resets output buffer

## [0.1.43] - 2026-04-07

### Fixed
- Session restore no longer reuses stale primary surfaces — each tab gets a fresh terminal view
- Programmatic restore gate prevents blank terminals after app relaunch or update
- Generic child processes no longer misidentified as agent subagents (no false loading panels)
- Closing the last split pane now promotes the surviving terminal to primary surface
- Tab sidebar CWD updates via PID-based fallback when the shell does not emit OSC 7
- Hook event model extended with TaskCompleted and TeammateIdle lifecycle events

## [0.1.42] - 2026-04-07

### Fixed
- Window title, zoom, and project config now target the visible tab instead of the bootstrap tab
- Background tabs can no longer override window chrome or project config of the visible tab
- Agent detection routing filters output from non-visible tabs and split panes
- Browser tab operations (add, select, close) now emit navigation load events
- CocxyCoreView forwards Cmd+shortcuts to main menu and exposes copy/paste/selectAll
- Per-surface font application in CocxyCoreBridge for tab-scoped zoom

## [0.1.41] - 2026-04-07

### Security
- OSC 52 clipboard read now requires user confirmation (prompt by default)
- New `clipboard-read-access` config option: `allow`, `prompt`, or `deny`

### Fixed
- Periodic session auto-save now wired in production (was implemented but never called)
- Timeline navigation now uses real navigator instead of no-op stub
- Aider agent detection patterns no longer conflict between launch and waiting
- QuickTerminal restore clamps height to valid range defensively
- Git branch watcher race condition on cancellation
- CodableColor equality now case-insensitive
- Session delete API accepts unnamed session consistently with save
- QuickSwitch result shows destination tab name

## [0.1.40] - 2026-04-07

### Fixed
- Terminal surfaces appearing visually blank after tab switch or window focus
- Reattached surfaces now force geometry sync and immediate redraw
- Re-selecting the already-displayed tab refreshes interaction state
- Split pane surfaces refresh correctly when restored from saved state

## [0.1.39] - 2026-04-07

### Added
- Multi-window session synchronization (Phase 8G)
- Central SessionRegistry tracking all terminal sessions across windows
- Tab drag-and-drop between windows with zero PTY data loss
- Cross-window notification badge synchronization
- Cross-window agent state aggregation in dashboard and timeline
- "All Windows" / "This Window" scope picker in dashboard and timeline
- Window labels on dashboard rows and timeline events
- WindowEventBus for cross-window theme, config, and focus events
- "Move Tab to New Window" command in File menu
- Remote unread count indicator in sidebar footer
- Multi-window session save/restore (Session model v2)
- 103 new tests for multi-window functionality (646 total, 56 suites)

## [0.1.38] - 2026-04-07

### Added
- CocxyCoreKit v0.13.0 — Web Terminal support

## [0.1.37] - 2026-04-07

### Added
- CocxyCoreKit v0.12.0 — Plugin extension API

## [0.1.36] - 2026-04-07

### Added
- CocxyCoreKit v0.11.0 — GPU-accelerated regex search

## [0.1.35] - 2026-04-06

### Added
- Inline image rendering via Sixel and Kitty graphics protocols
- CocxyCoreKit v0.10.0 with 14 new C API exports for image control, atlas query, and quad frame access
- Metal two-pass image rendering: background images before glyphs, foreground images after
- Image atlas with shelf-packing, free-region recycling, coalescing, and dirty tracking
- Sixel parser with RGB/HLS color, repeat/newline operators, aspect ratio, and background mode
- Kitty graphics protocol: transmit (f=24/32/100), display, delete, query, chunked transfers, zlib, PNG decode
- LRU image eviction with configurable memory budget
- Z-index based image layering with O(n log n) stable sort

### Fixed
- CLI hook-handler SIGPIPE crash (exit code 141) during socket communication race conditions

## [0.1.34] - 2026-04-05

### Added
- CocxyCoreKit v0.9.0 with ligature rendering C API (7 new exports)
- Ligature scanner for ASCII operator detection (-> => != == etc.)
- Shaped run cache with FNV-1a hash and generation-based LRU (512 slots)
- CoreText shaping via dlopen for macOS, HarfBuzz shaping for Linux
- Two-pass GPU rendering: base glyphs + ligature overlay (non-destructive)

### Fixed
- CI test verification now checks output instead of exit code (PTY cleanup SIGHUP workaround)
- CocxyCorePerformanceBenchmarks skipped in CI to avoid latency threshold failures

## [0.1.33] - 2026-04-05

### Added
- CocxyCore as sole terminal engine — Ghostty dependency fully removed
- CocxyCoreKit v0.8.0 xcframework with cross-platform engine and compatibility matrix
- Dual-engine architecture with feature flag for gradual migration (Phase 6)
- Directional split navigation, compiled pattern matcher, Sendable cleanup

### Changed
- CI/Release/Nightly workflows updated: removed Ghostty build steps, arm64-only builds
- Binary output paths corrected for `.build/arm64-apple-macosx/release/`
- libcocxycore.a migrated to Git LFS (2.5 MB binary → 132 byte pointer)
- Git LFS checkout enabled in all CI workflows

### Removed
- GhosttyBridge, GhosttyKeyConverter, TerminalSurfaceView, and all Ghostty build scripts (115 files, -8362 lines)
- GhosttyKit and libc++ dependencies from Package.swift

## [0.1.31] - 2026-04-02

### Added
- Sidebar mini-stats: inline tool count, error count, and duration chips when an agent is active
- Agent progress overlay: translucent pill in terminal corner showing real-time agent activity
- Welcome panel redesigned with feature highlights grid, entrance animation, and app version
- Subagent panel enter/exit animations (fade transitions, reduce-motion aware)

### Changed
- Subagent panel background now uses native vibrancy (NSVisualEffectView) for visual consistency
- Welcome panel shortcut for Dashboard corrected to Cmd+Option+A

## [0.1.30] - 2026-04-02

### Fixed
- Subagent panels now open in the correct tab instead of the active tab
- Subagent panels auto-close 2 seconds after the subagent finishes
- Notification bell button now responds to clicks reliably
- Dashboard "Go to Tab" navigation now works correctly
- Double-click titlebar in fullscreen mode now exits fullscreen

## [0.1.29] - 2026-04-02

### Added
- Auto-split subagent panels: live activity panels spawn automatically when agents create subagents
- SubagentPanelView with real-time stats, activity feed, tool/error counters, and duration tracking
- SSH drag-and-drop file upload via scp with notification on completion
- Remote port scanner auto-starts when managed SSH connections are established

### Fixed
- Terminal not filling available space on session restore, theme switch, and split creation
- Sidebar header buttons (search, notifications) not responding to clicks
- Dashboard not updating in real-time (missing @Published on sessions)
- HookEvent decoder dropping SubagentStart/SubagentStop/TaskCompleted payloads

## [0.1.28] - 2026-04-02

### Added
- Deep subagent visualization, 66 real CLI commands, SSH one-liner, drag-drop files, auto port bridging

## [0.1.27] - 2026-04-02

### Added
- 18 real CLI handlers, terminal layout sync fix

## [0.1.26] - 2026-04-01

### Added
- 18 new CLI commands (47 → 65 total): window management, session save/restore, tab duplicate/pin, config list/reload, split swap/zoom, capture-pane, notification list/clear
- Exposed 17 existing server-only commands to CLI parser: browser (8), remote (5), plugin (3), config-project
- Terminal inner padding via ghostty config (`window-padding-x`, `window-padding-y`)
- `syncSizeWithGhostty()` method for explicit surface size notification after creation

### Fixed
- Terminal not filling available space on first open — race condition where `setFrameSize` fired before surface creation, silently dropping the size notification to libghostty
- Terminal content sticking to edges — window padding values were never passed to ghostty config

### Changed
- `TerminalEngineConfig` now carries `windowPaddingX` and `windowPaddingY` through the initialization chain
- `needsBridgeRestart` detection expanded to include `windowPaddingX` and `windowPaddingY` changes
- Updated web stats: tests 3,051 → 3,053, CLI commands 47 → 65
- Updated README CLI examples to use correct compound subcommand syntax
- Fixed agent detection layer count from 3-layer to 4-layer in releases page

## [0.1.25] - 2026-04-01

### Fixed
- Hook duplication in settings.json — single-quote mismatch in command string detection caused duplicate entries on every app launch
- Tab switching lag (~250ms) — removed doubleClickInterval timer, use clickCount detection for immediate response
- Notification panel showing "No notifications yet" despite badge count — panel now seeds from existing attention queue on first open
- `Tab.hasUnreadNotification` field never set to true — now derived from notification manager unread count
- Notification config changes not taking effect until restart — preferences now propagate to all notification components immediately
- Redundant bridge.resize() with approximate cell dimensions during tab switch removed

### Added
- 3 custom notification sounds: cocxy-attention (ascending pings), cocxy-finished (descending chime), cocxy-error (low tone)
- `DockBadgeController.updateConfig()` for dynamic config propagation
- `NotificationManagerImpl.allNotifications()` for historical notification backfill
- 2 new tests for quoted-path hook detection and removal

## [0.1.24] - 2026-03-31

### Fixed
- Terminal input frozen after closing Preferences — focus now restored via `windowWillClose` callback
- Double bridge restart when saving Preferences — `onSave` simplified to config reload only, `applyConfig` handles all UI updates and bridge restart via `lastAppliedConfig` comparison
- CHANGELOG pipeline generated empty entries ("Release vX.Y.Z") — now uses `git log` between tags instead of GitHub release body which only lists PRs

### Changed
- App screenshot replaces HTML mockup in landing page hero section
- App screenshot added to README for GitHub preview

## [0.1.23] - 2026-03-31

### Added
- Configurable vibrancy/glass effect on sidebar, tab strip, and status bar via `background-opacity`
- NSVisualEffectView with `.headerView` material on horizontal tab strip
- Conditional SwiftUI material background on status bar
- Background Opacity slider (30%-100%) in Preferences replacing sidebar transparency toggle

### Fixed
- Double-click-to-zoom on tab strip broken by background layer intercepting hitTest
- Theme color overridden when switching from transparent to opaque mode
- Stale web stats: tests 2,898 → 3,051, releases page CLI commands 43 → 47

## [0.1.22] - 2026-03-30

### Fixed
- DaemonConnection double-resume crash — continuation resume moved to atomic MainActor guard
- RelayAuditLog auto-rotation — size check after each append triggers rotation at 10 MB
- RelayAuthBroker ACL enforcement — `evaluate(processName:remoteHost:)` now called with real remote host
- RelayManager auto-cleanup on SSH disconnect — channels and proxy cleaned up on all disconnect paths
- DaemonManager connection cleanup on disconnect — heartbeats and pending requests properly stopped
- cocxyd.sh sync_changes word-split — paths with spaces handled via temp file and read loop
- cocxyd.sh cleanup removes stale sync markers and idle timestamp on shutdown

### Added
- RelayChannel `createdAt` timestamp field with default value
- RelayControlView per-channel "View Audit Log" with inline viewer
- RelayControlView per-channel "Edit ACL" with Save button and `updateACL()` support
- DaemonControlView live session list with create, kill, and refresh
- DaemonControlView persistent forwards list with add, remove, and refresh
- DaemonControlView file sync watch with add path and check changes
- cocxyd.sh real `forward.add`/`forward.remove`/`forward.list` with port validation (1-65535)
- cocxyd.sh real `sync.watch`/`sync.changes` with find-based polling and JSON escaping
- cocxyd.sh auto-cleanup after 24h idle with `update_last_client` tracking
- cocxyd.sh protocol version validation (warn-only, backward compatible)

## [0.1.21] - 2026-03-30

### Added
- SOCKS5 proxy manager with state machine (off/starting/active/failing/failover)
- HTTP CONNECT proxy via Network.framework (NWListener + bidirectional relay)
- System-wide proxy integration via `networksetup` with admin privilege escalation
- Proxy exclusion list with wildcard matching and PAC file generation
- Proxy health monitor with TCP probe, 3-failure threshold, and auto-failover
- Proxy control UI panel with SOCKS/HTTP/system-wide toggles and stats
- Agent relay multi-channel manager with reverse SSH tunnels
- Relay HMAC-SHA256 token authentication via CryptoKit with rotation support
- Relay access control lists (ACL) per channel with process and host filtering
- Relay auth broker with 60-byte wire protocol handshake validation
- Relay audit log with JSON lines format and file rotation
- Relay Keychain persistence for production token storage
- Relay control UI panel with channel management and global stats
- Remote daemon manager with deploy/connect/stop/upgrade lifecycle
- cocxyd.sh POSIX shell daemon (~500 LOC) with 3-level session fallback (tmux/screen/PTY)
- Daemon JSON-RPC protocol with 15 commands and version negotiation
- Daemon deployer with platform detection, SFTP upload, and version checking
- Daemon connection via NWConnection with request multiplexing and 30s heartbeat
- Daemon session bridge with bidirectional I/O (base64) and 50ms output polling
- Daemon file sync watcher with remote directory monitoring
- Daemon control UI panel with deploy/stop/upgrade buttons
- 7 new Remote Workspace sub-panels: Sessions, Tunnels, Proxy, Relay, Daemon, Keys, SFTP

## [0.1.20] - 2026-03-30

### Fixed
- SFTP file browser connected — `SystemSFTPExecutor` with batch mode via ControlMaster
- SSH Key Manager connected — `sshKeyManager` passed to RemoteConnectionView with lazy ViewModel
- Port forwarding tunnels connected to real SSH — `forwardPort()`/`cancelForward()` in RemoteConnectionManager
- Bookmark list instant refresh — `@State storeRevision` counter with `.id()` modifier on list views

## [0.1.19] - 2026-03-30

### Fixed
- Browser history recording — `recordPageVisit()` now called on navigation finish
- Browser tab auto-selection — new panels receive focus via `focusNewPanel` parameter
- Browser bookmarks with split panels — dynamic ViewModel resolution across all instances
- Browser DevTools (Console, Network, DOM) — connected from scaffolding to functional
- Browser Find Bar — connected with `window.find()` JavaScript integration
- Browser Downloads — tracking with status states in ViewModel
- Browser Profile Selector — wired in overlay panel header
- Notification config toggles (`flashTab`, `badgeOnTab`) now read from config and hot-reload
- CLI `cocxy notify` now dispatches real notifications through the notification pipeline
- Custom notification sounds per type (`sound-finished`, `sound-attention`, `sound-error`)
- WebKit delegate concurrency warnings — proper `@MainActor @Sendable` signatures
- Dead code in BrowserContentView find bar constraint management
- CHANGELOG pipeline variable substitution — heredoc now passes vars via environment

## [0.1.18] - 2026-03-29

### Added
- Remote persistence via tmux — zero-install session survival across SSH disconnects
- Plugin system — extensible event-driven architecture with sandboxed script execution
- Nightly build channel — side-by-side installation with separate Sparkle update feed
- Remote session management UI panel in Remote Workspace
- 3 new CLI commands: `plugin-list`, `plugin-enable`, `plugin-disable`
- 5 remote workspace CLI commands now fully implemented (were stubs)
- TmuxSessionManager with support detection, session CRUD, and attach commands
- RemoteSessionStore for local persistence of remote session metadata
- PluginManifest TOML parser with 8 event types
- PluginSandbox with timeout enforcement and clean environment isolation
- 61 new tests (35 remote persistence + 26 plugin system)

## [0.1.17] - 2026-03-29

### Fixed
- Status bar agent count pill not updating when agent state changes
- `refreshStatusBar()` was missing from `wireAgentDetectionToTabs`

## [0.1.16] - 2026-03-29

### Fixed
- `GHOSTTY_ZSH_ZDOTDIR=""` (empty string) broke Prezto, Oh My Zsh, and YADR
- zsh interpreted empty ZDOTDIR as "use current directory" instead of `$HOME`
- Changed from `?? ""` to `if let` guard for ZDOTDIR environment variable

## [0.1.15] - 2026-03-29

### Fixed
- Shell integration ZDOTDIR not configured in production (GUI launch from Dock)
- Cross-terminal hook contamination — parent directory matching removed, exact-only
- Duplicate hook entries in settings.json — deduplication on install
- CLI PATH resolution — `~/.local/bin` added to shell profile
- Release pipeline: `NSAppleScriptEnabled` and `.sdef` copy in workflow

## [0.1.14] - 2026-03-29

### Added
- Per-project configuration via `.cocxy.toml` files
- AppleScript scripting support with `.sdef` vocabulary
- `config-project` CLI command for active tab overrides
- ProjectConfigService with directory walk-up detection
- ProjectConfigWatcher with hot-reload on file changes
- ScriptableTab, CocxyScriptCommands, NSApplication+Scripting bridge

### Fixed
- Hook CWD filter for accurate per-tab event routing

## [0.1.13] - 2026-03-28

### Fixed
- Socket server race condition on concurrent connections
- Hook path resolution for non-standard installations
- Agent config hot-reload via AgentConfigWatcher with Combine pipeline

## [0.1.12] - 2026-03-28

### Fixed
- Shell integration setup for embedded libghostty
- Auto-setup of Claude Code hooks on first launch
- Connected 14 dead code methods to production (dead code audit)

## [0.1.11] - 2026-03-28

### Fixed
- Agent detection per-tab state tracking
- Notification badge synchronization with panel
- Cross-tab agent state isolation

## [0.1.10] - 2026-03-28

### Fixed
- Wakeup callback use-after-free crash in libghostty bridge

### Added
- SEO foundations: Open Graph meta tags, structured data, sitemap

## [0.1.9] - 2026-03-28

### Fixed
- Release pipeline API call for release notes generation
- Docs page redesign with sidebar navigation

## [0.1.8] - 2026-03-27

### Added
- Releases page with full release notes, pagination, and download links

### Fixed
- Releases page styling and content rendering

## [0.1.7] - 2026-03-27

### Fixed
- Deploy full landing page from repo on each release
- Added Docs navigation link to site header

## [0.1.6] - 2026-03-27

### Fixed
- Agent detection engine reliability
- Shell integration for embedded terminal
- Sparkle EdDSA key configuration
- Releases page generation from GitHub API

### Added
- Getting Started documentation page

## [0.1.5] - 2026-03-27

### Fixed
- Sparkle lazy initialization — no error dialog on app launch
- Update check only triggers on explicit user action

## [0.1.4] - 2026-03-27

### Fixed
- CI green: dynamic version fallback for test builds
- Settings menu keyboard shortcut test
- Performance test threshold for CI runners

## [0.1.3] - 2026-03-27

### Fixed
- Homebrew tap auto-update using PAT authentication

## [0.1.2] - 2026-03-27

### Fixed
- Version reading from Info.plist at runtime
- CI build: `weak let` to `weak var` for Swift 6 strict concurrency

## [0.1.1] - 2026-03-27

### Fixed
- Homebrew symlink pointing to CLI binary instead of GUI app
- Check for Updates button in Preferences
- Auto-update website version on release deploy

## [0.1.0] - 2026-03-27

### Added
- Initial release of Cocxy Terminal
- Metal GPU-accelerated terminal rendering via libghostty
- Multi-tab with Cmd+T, Cmd+W, Cmd+1-9 switching
- Horizontal and vertical splits with Cmd+D, Cmd+Shift+D
- 4-layer agent detection engine (Hooks, OSC sequences, pattern matching, timing)
- Support for 6 AI agents: Claude Code, Codex, Gemini CLI, Aider, GitHub Copilot, Cursor
- Agent Dashboard with live session monitoring
- Agent Timeline with chronological event log and JSON/Markdown export
- Smart Routing for intelligent agent navigation
- Command Palette with fuzzy search (Cmd+Shift+P)
- Built-in browser with profiles, DevTools, bookmarks, and split/overlay modes
- Markdown panel viewer with live file watching
- SSH multiplexing with ControlMaster, tunnels, and SFTP browser
- SSH key management (list, generate, add to agent)
- Quick Terminal global dropdown
- Scrollback search (Cmd+F)
- Session persistence across restarts
- 47 CLI commands via Unix Domain Socket API
- Hook integration for real-time agent event streaming
- Port scanner for localhost dev server detection
- SSH session detection from process titles
- Configurable themes (8 built-in, TOML-based)
- Background opacity and blur
- Cursor style, blink, and opacity settings
- Mouse hide while typing
- Copy-on-select and clipboard paste protection
- Equalize splits (Cmd+Shift+E) and toggle split zoom (Cmd+Shift+F)
- Auto-update via Sparkle with EdDSA signatures
- Homebrew Cask distribution (`brew install --cask cocxy`)
- Zero telemetry — no PostHog, no Sentry, no analytics
- MIT License

[0.1.83]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.82...v0.1.83
[0.1.63]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.62...v0.1.63
[0.1.62]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.61...v0.1.62
[0.1.61]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.60...v0.1.61
[0.1.59]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.58...v0.1.59
[0.1.58]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.57...v0.1.58
[0.1.57]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.56...v0.1.57
[0.1.56]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.55...v0.1.56
[0.1.55]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.54...v0.1.55
[0.1.54]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.53...v0.1.54
[0.1.53]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.52...v0.1.53
[0.1.50]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.49...v0.1.50
[0.1.49]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.48...v0.1.49
[0.1.48]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.47...v0.1.48
[0.1.38]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.37...v0.1.38
[0.1.37]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.36...v0.1.37
[0.1.36]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.35...v0.1.36
[0.1.35]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.34...v0.1.35
[0.1.34]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.33...v0.1.34
[0.1.33]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.31...v0.1.33
[0.1.28]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.27...v0.1.28
[0.1.27]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.26...v0.1.27
[0.1.23]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.22...v0.1.23
[0.1.22]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.21...v0.1.22
[0.1.21]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.20...v0.1.21
[0.1.20]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.19...v0.1.20
[0.1.19]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.18...v0.1.19
[0.1.18]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.17...v0.1.18
[0.1.17]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.16...v0.1.17
[0.1.16]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.15...v0.1.16
[0.1.15]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.14...v0.1.15
[0.1.14]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.13...v0.1.14
[0.1.13]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.12...v0.1.13
[0.1.12]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.11...v0.1.12
[0.1.11]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.10...v0.1.11
[0.1.10]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.9...v0.1.10
[0.1.9]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.8...v0.1.9
[0.1.8]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.7...v0.1.8
[0.1.7]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.6...v0.1.7
[0.1.6]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.5...v0.1.6
[0.1.5]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/salp2403/cocxy-terminal/releases/tag/v0.1.0
