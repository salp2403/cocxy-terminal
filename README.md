# Cocxy Terminal

[![Build](https://github.com/salp2403/cocxy-terminal/actions/workflows/ci.yml/badge.svg)](https://github.com/salp2403/cocxy-terminal/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![No Telemetry](https://img.shields.io/badge/telemetry-zero-brightgreen.svg)](#zero-telemetry)

**The native macOS terminal that understands your AI coding agents.** GPU-accelerated rendering, real-time 4-layer agent detection, persistent remote sessions, extensible plugin system, and absolute zero telemetry.

Cocxy knows when your coding agent is thinking, working, waiting for input, or done. It shows you -- so you stop watching terminals and start shipping code.

## Why Cocxy

Every terminal shows you text. Cocxy shows you what your agent is actually doing. It detects 6 coding agents across 4 independent detection layers, gives you a live dashboard of every session, and lets you jump between agents with a single keystroke. When your agent finishes a task at 3 AM, Cocxy knows -- and you know.

Built from scratch in Swift and Metal. No Electron. No web views wrapping a terminal. No data leaving your machine. Just a fast, native terminal that was designed for the way developers work in 2026.

## Features

### 4-Layer Agent Detection

Passive detection engine that identifies coding agent state in real time without intercepting or modifying agent traffic. Four independent layers cross-validate for high-confidence results.

| Layer | Method | What It Detects |
|-------|--------|-----------------|
| **Hooks** | Claude Code event streaming | Tool calls, responses, session lifecycle |
| **OSC** | Terminal escape sequences | Working directory, title changes, prompts |
| **Pattern** | Output pattern matching | Launch signatures, completion markers |
| **Timing** | Activity heuristics | Active vs idle periods, session boundaries |

- **6 Agents** -- Claude Code (with full 12-event hook integration), Codex, Gemini CLI, Aider, GitHub Copilot, and Cursor
- **Agent Dashboard** -- Live view of all sessions with state, working directory, tools in use, and duration
- **Agent Timeline** -- Chronological event log with JSON and Markdown export
- **Smart Routing** -- Jump between agent sessions by priority, state, or recency

### Remote Workspaces

SSH multiplexing with persistent sessions that survive disconnects.

- **Persistent Sessions** -- tmux-backed sessions on remote hosts that survive SSH disconnects. Zero installation required on the server
- **Session Management UI** -- Visual panel to create, list, attach, and kill remote sessions
- **SSH Multiplexing** -- OpenSSH ControlMaster for connection reuse across tabs
- **Port Tunneling** -- Local, remote, and dynamic SOCKS forwarding with conflict detection
- **SFTP Browser** -- Navigate and transfer files on remote hosts
- **Auto-Reconnect** -- Exponential backoff reconnection with configurable retry limits

### Built-in Browser

In-app browser for previewing dev servers, reading docs, and inspecting web output without switching apps.

- **Profiles** -- Isolated cookies, storage, and history per profile
- **DevTools** -- Console, Network, and DOM inspection
- **Bookmarks** -- Organized with nested folders
- **Split or Overlay** -- Side-by-side with terminal or floating panel

### Per-Project Configuration

Drop a `.cocxy.toml` file in any project root to override global settings per directory.

```toml
# .cocxy.toml
font-size = 13
background-opacity = 0.95

[agent-detection]
extra-launch-patterns = ["^python manage.py"]
```

Cocxy detects and applies project config automatically when you `cd` into a directory. Hot-reload on file changes.

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

Plugins respond to 8 terminal events (session start/end, agent detected, state changed, command complete, tab created/closed, directory changed). Scripts run in a sandboxed environment with timeout enforcement.

### GPU Terminal

High-performance rendering powered by libghostty and Metal.

- **Metal-Accelerated** -- GPU rendering for smooth scrolling at 120 fps
- **Multi-Tab + Splits** -- Vertical sidebar with git branch, agent state, and horizontal/vertical splits
- **Markdown Panels** -- Render Markdown files in split panes with live file watching
- **Command Palette** -- Fuzzy search across all commands (`Cmd+Shift+P`)
- **Scrollback Search** -- Live search with debounced results (`Cmd+F`)
- **Quick Terminal** -- Global dropdown from any app (`` Cmd+` ``)
- **Session Persistence** -- Tabs, splits, directories, and window state restored on relaunch

### Zero Telemetry

Cocxy sends **zero data** to any external server. No analytics. No crash reporting. No tracking. No exceptions. No PostHog. No Sentry. Nothing. Your terminal activity stays on your machine. Verify with any network monitor.

### CLI Companion

47 commands for scripting and automation via Unix Domain Socket.

```bash
cocxy hooks install              # Auto-configure Claude Code hooks
cocxy notify "Deploy complete"   # Trigger notification
cocxy list-tabs                  # List all tabs as JSON
cocxy remote-list                # List SSH profiles and status
cocxy remote-connect prod-web    # Connect to a remote profile
cocxy plugin-list                # List installed plugins
cocxy dashboard-toggle           # Toggle agent dashboard
cocxy config-project             # Show per-project overrides
```

Run `cocxy help` for the full command reference.

### Nightly Builds

Opt into early builds with experimental features. Nightly builds install side-by-side with the stable version using a separate bundle ID and update feed.

## Install

### Homebrew

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

To update:

```bash
brew update && brew upgrade --cask cocxy
```

> `brew update` syncs the tap before upgrading. Without it, third-party taps may not detect new versions.

### Direct Download

Download the latest `.dmg` from the [Releases](https://github.com/salp2403/cocxy-terminal/releases) page.

### Build from Source

See [Building from Source](#building-from-source) below.

## Keyboard Shortcuts

| Action | Shortcut |
|--------|----------|
| New Tab | `Cmd+T` |
| Close Tab | `Cmd+W` |
| New Window | `Cmd+N` |
| Command Palette | `Cmd+Shift+P` |
| Agent Dashboard | `Cmd+Option+A` |
| Agent Timeline | `Cmd+Shift+T` |
| Smart Routing | `Cmd+Shift+U` |
| Notifications | `Cmd+Shift+I` |
| Browser Panel | `Cmd+Shift+B` |
| Remote Workspaces | `Cmd+Shift+R` |
| Find in Terminal | `Cmd+F` |
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
| Jump to Tab 1-9 | `Cmd+1` through `Cmd+9` |
| Dismiss Overlay | `Esc` |

## Supported Agents

| Agent | Hooks | OSC | Pattern | Timing |
|-------|-------|-----|---------|--------|
| Claude Code | 12 events | Yes | Yes | Yes |
| Codex | -- | -- | Yes | Yes |
| Gemini CLI | -- | -- | Yes | Yes |
| Aider | -- | -- | Yes | Yes |
| GitHub Copilot | -- | -- | Yes | Yes |
| Cursor | -- | -- | Yes | Yes |

Custom agents can be added via `agents.toml`.

## Configuration

```
~/.config/cocxy/
  config.toml          # Fonts, theme, keybindings, terminal behavior
  agents.toml          # Agent detection patterns and thresholds
  themes/*.toml        # Custom themes (Ghostty-compatible format)
  plugins/             # Plugin directories with manifest.toml
  sessions/            # Auto-saved session state
  remotes/             # SSH connection profiles
  sockets/             # SSH ControlMaster socket files
```

### Example config.toml

```toml
[font]
family = "JetBrains Mono"
size = 14.0

[theme]
name = "catppuccin-mocha"

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
```

### Themes

Ships with Catppuccin (Mocha and Latte), One Dark, Solarized, and more. Also imports Ghostty `.toml` theme files. Drop a theme into `~/.config/cocxy/themes/` and it appears immediately.

## Building from Source

### Prerequisites

- macOS 14.0 (Sonoma) or later
- Xcode 16 or later
- Swift 5.10+
- Zig 0.15.2+ (for compiling libghostty)

### Build

```bash
git clone https://github.com/salp2403/cocxy-terminal.git
cd cocxy-terminal

# Build the terminal engine (5-10 minutes on first run)
chmod +x scripts/build-libghostty.sh
./scripts/build-libghostty.sh

# Build the app
swift build
```

### Run

```bash
swift run CocxyTerminal
```

### Test

```bash
swift test    # 2,898 tests
```

## Architecture

MVVM + Coordinators with Swift protocols as contracts between modules. Zero third-party Swift dependencies (only libghostty for rendering and Sparkle for updates).

```
Sources/
  App/               # Entry point, AppDelegate, scripting bridge
  Core/              # Terminal engine bridge, socket server, key input
  Domain/            # Detection engine, plugins, remote workspace, config
  UI/                # Windows, tabs, panels, overlays, animations
CLI/                 # cocxy companion tool (47 commands)
Tests/               # 2,898 test cases
```

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide.

## Security

Found a vulnerability? Do not open a public issue. Email [security@cocxy.dev](mailto:security@cocxy.dev). See [SECURITY.md](SECURITY.md) for the responsible disclosure process.

## License

MIT License. Copyright (c) 2026 Said Arturo Lopez. See [LICENSE](LICENSE).

## Links

- **Website:** [cocxy.dev](https://cocxy.dev)
- **Releases:** [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- **Changelog:** [CHANGELOG.md](CHANGELOG.md)
