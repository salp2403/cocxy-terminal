# Changelog

All notable changes to Cocxy Terminal are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.19] - 2026-03-30

### Changed
- *Full Changelog**: https://github.com/salp2403/cocxy-terminal/compare/v0.1.18...v0.1.19

### Fixed
- *Direct download:** Download the DMG below.
- *Homebrew:** `brew tap salp2403/tap && brew install --cask cocxy`
- macOS 14.0 (Sonoma) or later
- Apple Silicon or Intel Mac

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

[Unreleased]: https://github.com/salp2403/cocxy-terminal/compare/v0.1.19...HEAD
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
