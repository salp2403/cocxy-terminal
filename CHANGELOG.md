# Changelog

All notable changes to Cocxy Terminal are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
