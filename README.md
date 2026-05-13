# Cocxy Terminal

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

[![Build](https://github.com/salp2403/cocxy-terminal/actions/workflows/ci.yml/badge.svg)](https://github.com/salp2403/cocxy-terminal/actions/workflows/ci.yml)
[![Latest Release](https://img.shields.io/github/v/release/salp2403/cocxy-terminal?label=latest&color=8839ef)](https://github.com/salp2403/cocxy-terminal/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![No Telemetry](https://img.shields.io/badge/telemetry-zero-brightgreen.svg)](#zero-telemetry)
[![Stars](https://img.shields.io/github/stars/salp2403/cocxy-terminal?style=flat&color=fab387)](https://github.com/salp2403/cocxy-terminal/stargazers)

**The native macOS terminal that understands your AI coding agents.** GPU-accelerated rendering, real-time multi-agent detection, inline agent code review, a full native Markdown workspace, persistent remote sessions, and absolute zero telemetry.

Cocxy knows when your coding agent is thinking, working, waiting for input, or done. It shows you — so you stop watching terminals and start shipping code.

<p align="center">
  <img src="web/public/images/cocxy-preview.png" alt="Cocxy Terminal showing a live agent dashboard, an open Markdown workspace, and the agent code review panel" width="860" />
</p>

## Table of Contents

- [Why Cocxy](#why-cocxy)
- [Install](#install)
- [Features](#features)
- [Keyboard Shortcuts](#keyboard-shortcuts)
- [Supported Agents](#supported-agents)
- [Configuration](#configuration)
- [CLI Companion](#cli-companion)
- [Building from Source](#building-from-source)
- [Architecture](#architecture)
- [Contributing](#contributing)
- [Security](#security)
- [License](#license)

## Why Cocxy

Every terminal shows you text. Cocxy is a native macOS workspace built around how developers work with AI coding agents. It detects multiple coding agents across four independent layers, gives you a live dashboard of every session, lets you review an agent's changes inline before shipping them, runs your own local AI workspace (multi-provider Agent Mode, MCP servers, codebase indexing, skills, inline completions, sandboxed Computer Use), executes notebooks and workflows on-device, and ships with a native Markdown workspace for notes, plans, and docs. When your agent finishes a task at 3 AM, Cocxy knows — and you know.

Built from scratch in Swift and Metal. No Electron. No web view wrapping a terminal. No data leaves your machine. Just a fast, native macOS app designed for the way developers work in 2026.

## Install

### Homebrew (recommended)

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Update:

```bash
brew update && brew upgrade --cask cocxy
```

> `brew update` syncs the tap before upgrading. Without it, third-party taps may not detect new versions.

### Direct Download

Download the latest `.dmg` from the [Releases](https://github.com/salp2403/cocxy-terminal/releases) page. Universal builds for Apple Silicon (native) and Intel.

### Nightly Channel

Opt into early builds with experimental features. Nightly builds install side-by-side with the stable version using a separate bundle ID and update feed.

### Build from Source

See [Building from Source](#building-from-source) below.

## Features

### Multi-Layer Agent Detection

Passive detection engine that identifies coding agent state in real time without intercepting or modifying agent traffic. Four independent layers cross-validate for high-confidence results.

| Layer | Method | What It Detects |
|-------|--------|-----------------|
| **Hooks** | Agent event streaming | Tool calls, responses, session lifecycle, subagent spawn |
| **OSC** | Terminal escape sequences | Working directory, title changes, semantic prompts (OSC 133) |
| **Pattern** | Output pattern matching | Launch signatures, waiting prompts, completion markers |
| **Timing** | Activity heuristics | Active vs idle periods, session boundaries |

- **Bundled Agent Profiles** — Local profiles cover hook-capable, OSC-aware, pattern-only, and timing-fallback CLIs without vendor lock-in
- **Multi-Agent Hook Support** — Shared hook protocol across supported local CLIs and custom sources, with per-agent attribution
- **`cocxy setup-hooks`** — Auto-configures hooks in every installed agent with one command
- **Agent Dashboard** — Live view of all sessions with state, working directory, active tool, duration, file touches, and error counts (`Cmd+Option+A`)
- **Agent Timeline** — Chronological event log with six filters (All / Tools / Errors / Agents / Tasks / Session), JSON and Markdown export (`Cmd+Shift+T`)
- **Smart Routing** — Jump between agent sessions by priority, state, or recency (`Cmd+Shift+U`)
- **Agent State Indicator** — Per-tab status dot (working, waiting, finished, error, idle) and an inline ring around the active surface

### Agent Code Review Panel

A native panel to review every change an agent made, comment inline, and feed corrections back to the agent — all without leaving Cocxy.

- **Diff viewer** — File tree with status icons (added, modified, deleted, renamed), unified diff with line numbers, and per-author chips for each file
- **Inline comments** — Click any line in the gutter, type a comment, press Enter; the comment bubble anchors under that line
- **Feedback loop** — Submit all pending comments to the agent through the PTY; the agent picks up the formatted feedback and re-runs the task
- **Accept / reject per hunk** — Granular control via `git apply` (`--cached` to accept, `--reverse` to reject)
- **Keyboard-first** — `j` / `k` hunks, `n` / `p` files, `c` comment, `a` / `r` accept / reject, `d` toggle mode, `Cmd+Enter` submit all
- **Auto-trigger** — Panel opens automatically when the agent session ends (configurable)
- **Cross-tab-safe** — Feedback always reaches the agent in the tab the review belongs to, even if you switched tabs

Open with `Cmd+Option+R` or `cocxy review`.

### Local AI Workspace

A complete local-first AI workspace baked into the terminal. You bring the keys, Cocxy keeps the conversation on your machine.

- **Agent Mode** — Multi-provider local Agent Mode with on-device and bring-your-own-key providers, per-action approval, encrypted conversation persistence, retry on transient provider errors, and threaded conversation export
- **MCP servers** — Native Model Context Protocol client with stdio and HTTP transports, hardened auth boundaries, and a local-only server registry editable from Preferences
- **Codebase indexing** — On-device semantic + lexical index with incremental sync, query suggestions, vector store, and a fallback that runs without cloud embeddings
- **Skills** — Local skills loader with a built-in skill marketplace and bundled skill resources
- **Inline AI completions** — Foundation Models-powered ghost text, 200 ms idle trigger, Tab to accept, Esc to dismiss; gated behind an explicit toggle and respects an offline-first policy
- **Computer Use** — Sandboxed Computer Use actor with explicit per-action approval, Accessibility permission gate, screenshot capture, and an audit log
- **PR review depth** — Suggestion applier, conflict resolver, auto-merge safety gate, response templates, diff timeline, and reviewer suggestions from local `git blame`

### Notebooks and Workflows

Run notebooks and pipelines directly in Cocxy without spinning up a separate kernel server.

- **Multi-language cells** — Bash, Python, and Swift cells executed locally with a default sandbox (`sandbox-exec`, `deny network*`, `deny file-write*` outside the workspace) and an explicit `--sandbox none` escape
- **Jupyter import / export** — Open `.ipynb` directly and export back to Jupyter format
- **Standalone HTML export** — Self-contained HTML with bundled assets for sharing
- **Built-in templates** — Ready-to-run notebook templates
- **Workflows** — Local workflow runner with cell composition for repeatable pipelines

### Voice Input

On-device voice input powered by Apple's Speech framework. Multi-locale auto-detection with a manual override.

- **Local-only** — Audio never leaves the Mac; no cloud transcription
- **Auto-detect locale** — Picks the active locale and falls back to manual selection when needed
- **Configurable trigger** — Push-to-talk or toggle, configurable in Preferences

### Native Markdown Workspace

A first-class Markdown panel that renders in a split pane next to your terminal. Written from scratch in pure Swift — no external parser dependency.

- **Editable source view** — Cmd+B / Cmd+I / Cmd+K formatting, AppKit Find bar, undo / redo, debounced auto-save, file watcher deduplication
- **Live preview** — WKWebView-backed preview with Mermaid diagrams, KaTeX math, GitHub Flavored Markdown, fifteen callout types, footnotes, highlight / superscript / subscript, 200+ emoji shortcodes, reference-style links, setext headings
- **Split mode** — Source and preview side by side with scroll sync
- **Outline sidebar** — Heading tree navigation (`Cmd+Shift+O`)
- **File explorer** — Browse a project's Markdown files with rename, move-to-trash, reveal-in-Finder
- **Full-text search** — Multi-file search across the workspace with debounced results
- **Git integration** — Blame and diff views built in
- **Slide exporter** — Split a Markdown file into a slide deck by horizontal rules, preserving original formatting
- **Copy as** — Markdown, HTML, rich text (RTF), or plain text
- **Image handling** — Drag-and-drop to insert, paste PNG / TIFF from clipboard, lightbox on click, base64 inlining for standalone HTML exports
- **Interactive checkboxes** — Toggle task list checkboxes directly in the preview; changes write back to the source
- **Click-to-source** — Double-click any block in the preview to jump to its line in the source editor
- **Syntax highlighting** — Highlight.js bundled offline with zero network dependency
- **Sortable tables** — Click any column header; numeric-aware, three-state sort
- **Copy tables as TSV** — One-click copy for pasting into spreadsheets
- **[TOC]** — Inline table-of-contents placeholder generates from document headings

### QuickLook Preview Extension

A system-integrated extension that renders `.md` files directly in macOS Finder's QuickLook, with the same Mermaid, KaTeX, callouts, and syntax highlighting as the in-app preview. Zero network, zero dependencies, sandboxed.

### GPU Terminal Engine (CocxyCore)

A custom terminal engine built in Zig, running on Metal. Cross-platform-ready (macOS and Linux) with a stable C ABI.

- **Metal-accelerated rendering** — 120 fps smooth scrolling with a GPU-backed glyph atlas
- **Font ligatures** — OpenType ligatures via CoreText shaping with a configurable toggle
- **Inline image protocols** — Sixel and graphics-protocol image display in the terminal with configurable memory limits
- **GPU-accelerated regex search** — Native scrollback search with a Swift fallback for compatibility
- **Protocol v2** — Structured extension protocol for bidirectional agent-to-terminal communication
- **Multi-stream support** — Split PTY output into named streams addressable from the CLI
- **Mode diagnostics** — Inspect cursor, alt-screen, application cursor mode, and semantic block state from the CLI

### Remote Workspaces

SSH multiplexing with persistent sessions, proxy management, agent relay, and a remote daemon — all from the client, zero installation required on the server.

- **Persistent sessions** — tmux-backed sessions on remote hosts that survive SSH disconnects
- **Session management UI** — Visual panel to create, list, attach, and kill remote sessions
- **SSH multiplexing** — OpenSSH ControlMaster for connection reuse across tabs
- **Port tunneling** — Local, remote, and dynamic SOCKS forwarding with conflict detection
- **SOCKS5 + HTTP CONNECT proxy** — Native proxy with system-wide macOS integration, PAC generation, exclusion lists, and health monitoring with auto-failover
- **Agent relay** — Multi-channel reverse tunnels with HMAC-SHA256 auth, per-channel ACL, audit logging, token rotation, and Keychain persistence
- **Remote daemon** — POSIX shell daemon with three-level session fallback (tmux / screen / native PTY), persistent port forwards, file sync watching, and 24-hour auto-cleanup
- **SFTP browser** — Navigate and transfer files on remote hosts
- **Auto-reconnect** — Exponential backoff reconnection with configurable retry limits

### Built-in Browser

In-app browser for previewing dev servers, reading docs, and inspecting web output without switching apps.

- **Profiles** — Isolated cookies, storage, and history per profile
- **DevTools** — Console, Network, and DOM inspection
- **Bookmarks** — Organized with nested folders
- **Split or overlay** — Side by side with the terminal or as a floating panel
- **Downloads** — Tracked with progress and open-on-complete

### Web Terminal

Expose any local terminal over HTTP with a zero-dependency web frontend. Useful for quick peer programming or remote assistance.

- Tunable frame rate, on-demand full frame refresh, connection counts
- Per-terminal attach / detach with a single CLI command
- Events exposed to plugins for custom integrations

### Per-Project Configuration

Drop a `.cocxy.toml` file in any project root to override global settings per directory.

```toml
# .cocxy.toml
font-size = 13
background-opacity = 0.95

[agent-detection]
extra-launch-patterns = ["^python manage.py"]
```

Cocxy detects and applies the project config automatically when you `cd` into a directory. Hot-reload on file changes.

### macOS-Native Integrations

First-class macOS system integrations — every entry point is local-only with explicit privacy copy.

- **Shortcuts.app** — Catalog of local-only Shortcuts actions: open Cocxy, run command in Cocxy, open notebook, list skills
- **Touch Bar** — Contextual local terminal actions (new tab, command palette, agent panel, scrollback search) on supported MacBook Pro models
- **Handoff** — Privacy-preserving Handoff metadata; activity advertised across your devices without leaking terminal contents, paths, env, or search history
- **Continuity Camera** — Import images directly from an iPhone or iPad into the local Agent Mode attachments with `0600` permissions
- **Universal Clipboard** — Local clipboard history observer that respects macOS Universal Clipboard
- **Stage Manager** — Window collection behaviour tuned to participate cleanly in Stage Manager, Spaces, and Mission Control
- **Spotlight (Notes)** — Optional local Spotlight indexing for notes with a per-workspace privacy opt-out (`.cocxy-spotlight-ignore`)
- **QuickLook** — Sandboxed QuickLook extension renders Markdown directly in Finder

### Productivity Tools

A full productivity layer that lives next to the terminal so you do not switch apps for the small things.

- **Macros and Snippets** — Recordable terminal input macros, alias manager, snippet manager with parameter expansion, and inline replay
- **Clipboard history** — Local clipboard history observer with searchable history and a paste-by-keyword overlay
- **Project templates** — Ten built-in scaffolds covering Swift package, Python package, Rust crate, Node TypeScript, Go module, PHP composer, Ruby gem, static site, Docker service, and Flutter app, with sandbox hooks for custom templates
- **Notes** — Per-workspace Markdown notes panel with file watcher, autosave, and Spotlight opt-in
- **Tab configs** — Save, list, export, and replay terminal tab configurations as TOML

### Reliability and Recovery

Cocxy keeps your work safe even when something goes wrong.

- **Automatic local backups** — Daily backups under `~/.config/cocxy/backups/` with configurable retention (default 30 daily + 12 monthly), exact directory snapshots, manifest path containment guard, and a Preferences pane to inspect and restore
- **Crash recovery** — Periodic 5-minute snapshots, a local crash log, a restore prompt on the next launch, and best-effort panel and scroll restore. Tested under `kill -9` smoke
- **Session replay** — Local session recording store and panel with auto-record opt-in, deterministic 60-second replay, search and bookmark, delete-all, and `.cast` export
- **AI edit history** — Local timeline of agent-driven edits with diff and revert, plus hook recording for cross-tool tracking

### Activity Insights

Optional local analytics for your own work — never leaves the Mac.

- SQLite-backed activity store and dashboard with command duration, agent state, working directory, and error counts
- JSON / CSV export
- Default off; opt in from Preferences

### iCloud Sync

Encrypted opt-in sync across your Macs. Cocxy never sees the data.

- **Encrypted export / import** — End-to-end encryption with a master password you control
- **Manual conflict resolution** — Visual conflict UI; no silent overwrites
- **Two-device smoke gate** — Continuous regression coverage for the sync round-trip

### Onboarding

A six-step guided setup the first time Cocxy launches: theme, agent autonomy, LSP setup, tab configs, first skill, and first workflow. Skippable, and reachable any time from the Help menu.

### AppleScript Automation

Full AppleScript vocabulary for workflow automation and integration with Shortcuts, Automator, and Raycast.

```applescript
tell application "Cocxy Terminal"
    make new tab with properties {command:"ssh deploy@prod"}
    set name of tab 1 to "Production"
end tell
```

### Plugin System

Event-driven plugin architecture for extending Cocxy with custom integrations.

```
~/.config/cocxy/plugins/
  my-plugin/
    manifest.toml
    on-session-start.sh
    on-agent-detected.sh
```

Plugins respond to eight terminal events: session start / end, agent detected, state changed, command complete, tab created / closed, directory changed. Scripts run in a sandboxed environment with timeout enforcement.

**Bundled plugins (thirteen).** Cocxy ships with a curated catalogue of local plugins ready to enable from the marketplace panel: AWS CLI helper, Azure CLI, GCP CLI, Cloudflare, Docker, Kubernetes, GitHub pane, Jira, Linear, MySQL, PostgreSQL, Redis, and SQLite. Each plugin runs locally with the same sandbox and event contract as user plugins.

### Tabs, Splits, and Windows

- **Vertical sidebar** with git branch, agent state, and activity timing
- **Horizontal and vertical splits** with keyboard navigation and equalization
- **Mixed panels** — A single workspace can contain terminals, Markdown panels, and browser panels side by side
- **Session persistence** — Tabs, splits, directories, and window state restored on relaunch
- **Multi-window** — Every window is independent; sessions sync across them
- **Quick Terminal** — Global dropdown available from any app (`` Cmd+` ``)

### Command Palette and Scrollback Search

- **Command Palette** — Fuzzy search across every command, action, and setting (`Cmd+Shift+P`)
- **Scrollback search** — Live search with debounced results and native engine acceleration (`Cmd+F`)

### Shell Integration

Native shell integration for zsh, bash, and fish — installed automatically, no setup required. Preserves user frameworks (Prezto, Oh My Zsh, YADR, starship) without modification.

- OSC 7 working-directory reporting with URI encoding
- OSC 133 semantic prompts for command boundaries and duration
- Safe environment-variable injection that restores originals in every subshell

### Liquid Glass UI

A polished glass-material design system covering 36+ surfaces — sidebar, command palette, status bar, panels, overlays, and contextual sheets — tuned for macOS 14 through macOS 26 and ready for the Liquid Glass aesthetic when the host supports it.

### Localization

Shipped in English and Spanish out of the box (2,651+ strings each, kept symmetric). The active language follows the system or can be picked manually from Preferences. Public website covers EN and ES landings, features, releases, getting started, FAQ, and migration guidance.

### Zero Telemetry

Cocxy has no telemetry pipeline, no analytics SDK, no automatic crash upload, and no tracking. Network use exists only for signed updates and explicit user actions such as browser sessions, remotes, GitHub CLI operations, plugins, or tools you run yourself. Terminal activity is not uploaded to a Cocxy backend. Verify with any network monitor.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| New Tab | `Cmd+T` |
| Close Tab | `Cmd+W` |
| New Window | `Cmd+N` |
| Command Palette | `Cmd+Shift+P` |
| **Agent Code Review Panel** | **`Cmd+Option+R`** |
| Agent Dashboard | `Cmd+Option+A` |
| Agent Timeline | `Cmd+Shift+T` |
| Smart Routing | `Cmd+Shift+U` |
| Notifications | `Cmd+Shift+I` |
| Browser Panel | `Cmd+Shift+B` |
| Remote Workspaces | `Cmd+Shift+R` |
| Markdown Outline (when active) | `Cmd+Shift+O` |
| Markdown Source / Preview / Split | `Cmd+1` / `Cmd+2` / `Cmd+3` |
| Find in Terminal / Markdown | `Cmd+F` |
| Split Horizontal | `Cmd+D` |
| Split Vertical | `Cmd+Shift+D` |
| Equalize Splits | `Cmd+Shift+E` |
| Toggle Split Zoom | `Cmd+Shift+F` |
| Close Split | `Cmd+Shift+W` |
| Navigate Splits | `Cmd+Option+Arrows` |
| Quick Terminal | `` Cmd+` `` |
| Zoom In / Out | `Cmd++` / `Cmd+-` |
| Next Tab | `Cmd+Shift+]` |
| Previous Tab | `Cmd+Shift+[` |
| Jump to Tab 1–9 | `Cmd+1` through `Cmd+9` |
| Dismiss Overlay | `Esc` |

## Agent Profile Coverage

| Profile class | Hooks | OSC 7 / 133 | Pattern | Timing |
|---------------|-------|-------------|---------|--------|
| Hook-capable local CLIs | Yes | Optional | Yes | Yes |
| OSC-aware shells and tools | Optional | Yes | Yes | Yes |
| Pattern-only local CLIs | — | — | Yes | Yes |
| Timing fallback profiles | — | — | Optional | Yes |
| Custom profiles | Optional | Optional | Yes | Yes |

Custom agents are defined in `~/.config/cocxy/agents.toml`:

```toml
[my-agent]
display-name = "My Agent"
osc-supported = false
launch-patterns = ["^my-agent\\b"]
waiting-patterns = ["^>\\s*$"]
error-patterns = ["Error:"]
finished-indicators = ["^\\$\\s*$"]
idle-timeout-override = 10
```

## Configuration

```
~/.config/cocxy/
  config.toml          Fonts, theme, keybindings, terminal behavior
  agents.toml          Agent detection patterns and thresholds
  themes/*.toml        Custom themes
  plugins/             Plugin directories with manifest.toml
  sessions/            Auto-saved session state
  remotes/             SSH connection profiles
  sockets/             SSH ControlMaster socket files
```

### Example `config.toml`

```toml
[font]
family = "JetBrains Mono"
size = 14.0

[theme]
name = "catppuccin-mocha"
light-theme = "catppuccin-latte"

[terminal]
scrollback-lines = 10000
cursor-style = "block"
cursor-blink = true
copy-on-select = true
clipboard-paste-protection = true

[appearance]
background-opacity = 1.0
background-blur-radius = 0
window-padding-x = 2
window-padding-y = 2
ligatures = true

[code-review]
auto-show-on-session-end = true
```

### Themes

Ships with Catppuccin (Mocha and Latte), One Dark, and Solarized (Dark and Light). Drop a `.toml` theme into `~/.config/cocxy/themes/` and it appears immediately in the theme picker. Auto-switching between a light and dark pair follows the system appearance.

## CLI Companion

More than 100 commands for scripting and automation via a Unix Domain Socket with per-UID authentication.

```bash
cocxy setup-hooks                # Auto-configure hooks across every installed agent
cocxy notify "Deploy complete"   # Trigger a native notification with optional sound
cocxy list-tabs                  # List all tabs as JSON
cocxy window list                # List all open windows
cocxy session save my-workspace  # Save current session
cocxy session restore my-workspace
cocxy remote list                # List SSH profiles and status
cocxy remote connect prod-web    # Connect to a remote profile
cocxy plugin list                # List installed plugins
cocxy dashboard toggle           # Toggle the agent dashboard
cocxy timeline export --format json > events.json
cocxy review                     # Toggle the agent code review panel
cocxy review --submit            # Submit pending review comments to the agent
cocxy capture-pane               # Capture terminal content as text
cocxy send --stdin               # Read input from stdin for multiline, escape-safe send
cocxy core-modes                 # Dump terminal diagnostic state (alt-screen, cursor, etc.)
cocxy web-start --port 8080      # Expose the active terminal over HTTP
```

Run `cocxy help` for the full reference.

## Building from Source

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 16 or later
- Swift 5.10+
- Zig 0.15+ (`brew install zig`) — required to build CocxyCore locally

### Build and Run

```bash
git clone https://github.com/salp2403/cocxy-terminal.git
cd cocxy-terminal

swift build
swift run CocxyTerminal
```

### Test

```bash
swift test
```

### Package a Local `.app`

```bash
./scripts/build-app.sh release
./scripts/install-local-app.sh   # Copies the built bundle into /Applications and registers QuickLook
```

## Architecture

MVVM + Coordinators with Swift protocols as contracts between modules. Zero third-party Swift dependencies in app code; Sparkle is the only packaged binary dependency, used solely for auto-updates.

```
Sources/
  App/               Entry point, AppDelegate, scripting bridge
  Core/              Terminal engine bridge, socket server, renderers
  Domain/
    AgentDetection/    Multi-layer detection engine
    CodeReview/        Diff, comments, hunk actions, feedback loop
    Markdown/          Parser, renderer, outline, search, git integration
    Plugins/           Manifest loader and event dispatch
    RemoteWorkspace/   SSH, proxy, relay, daemon, SFTP
    CommandPalette/    Engine and coordinator
    Timeline/          Event store
    SmartRouting/      Priority-based tab routing
  UI/                Windows, tabs, panels, overlays, animations
CLI/                 cocxy companion tool (100+ commands)
QuickLook/           Markdown QuickLook extension
Tests/               Swift Testing suite
Resources/
  Themes/            Built-in color schemes
  Fonts/             Bundled JetBrains Mono and Monaspace Neon Nerd Font
  shell-integration/ zsh, bash, fish scripts
  Markdown/          KaTeX, Mermaid, Highlight.js bundled for offline preview
```

CocxyCore (the terminal engine) lives in a separate repository and is vendored as an `.xcframework` in `libs/` during local development. CI rebuilds it from source.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide: branch naming, commit conventions, test requirements, and code style.

## Security

Found a vulnerability? Do not open a public issue. Email [security@cocxy.dev](mailto:security@cocxy.dev). See [SECURITY.md](SECURITY.md) for the responsible disclosure process.

## License

MIT License. Copyright (c) 2026 Said Arturo Lopez. See [LICENSE](LICENSE).

## Links

- **Website:** [cocxy.dev](https://cocxy.dev)
- **Releases:** [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- **Changelog:** [CHANGELOG.md](CHANGELOG.md)
- **Documentation:** [cocxy.dev/getting-started.html](https://cocxy.dev/getting-started.html)
- **Issues:** [GitHub Issues](https://github.com/salp2403/cocxy-terminal/issues)
