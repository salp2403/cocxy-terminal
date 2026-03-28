# Cocxy Terminal

[![Build](https://github.com/salp2403/cocxy-terminal/actions/workflows/ci.yml/badge.svg)](https://github.com/salp2403/cocxy-terminal/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14%2B-black.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.10-orange.svg)](https://swift.org)
[![No Telemetry](https://img.shields.io/badge/telemetry-zero-brightgreen.svg)](#zero-telemetry)

**Native macOS terminal built for developers who work with coding agents.** GPU-accelerated rendering, real-time agent detection, remote workspaces, built-in browser, and zero telemetry.

Cocxy detects when your coding agent is working, waiting for input, or finished -- and notifies you so you can focus on what matters instead of watching terminals.

<!-- TODO: Add hero screenshot -->
<!-- ![Cocxy Terminal](docs/assets/hero.png) -->

## Features

### Agent Detection

Passive, three-layer detection engine that identifies coding agent state in real time without intercepting or modifying agent traffic.

- **6 Agents Supported** -- Claude Code (with full hook integration), Codex, Gemini CLI, Aider, Kiro, and OpenCode
- **3-Layer Engine** -- OSC sequences, output pattern matching, and timing heuristics working together for high-confidence detection
- **Agent Dashboard** -- Live view of all agent sessions with state, working directory, and duration
- **Agent Timeline** -- Chronological log of agent actions with JSON and Markdown export
- **Smart Routing** -- Intelligent navigation between agent sessions by priority

### Remote Workspaces

SSH multiplexing, port tunneling, and SFTP integration for seamless remote development.

- **SSH Detection** -- Automatic detection of SSH sessions with connection metadata
- **Port Scanning** -- Auto-detects active dev servers (3000, 5173, 8080, etc.) shown in status bar

### Built-in Browser

In-app browser panel for previewing dev servers, reading documentation, and inspecting web output without leaving the terminal.

- **Profile Support** -- Separate browsing profiles with isolated cookies and storage
- **DevTools** -- Web inspector access for debugging
- **Bookmarks** -- Quick access to frequently used URLs
- **Split or Overlay** -- Open as a split pane alongside your terminal or as a floating overlay

### GPU Terminal

High-performance terminal rendering powered by libghostty and Metal.

- **Metal-Accelerated** -- GPU rendering for smooth scrolling and fast output
- **Multi-Tab + Splits** -- Vertical sidebar with git branch display, agent state indicator, and split panes
- **Command Palette** -- Fuzzy search across all commands
- **Scrollback Search** -- Search terminal output with debounced live results
- **Quick Terminal** -- Global dropdown terminal from any app
- **Session Persistence** -- Tabs, splits, working directories, and window state restored on relaunch
- **Inline Images** -- Render images directly in the terminal via OSC sequences

### Zero Telemetry

Cocxy sends **zero data** to any external server. No analytics, no crash reporting, no tracking, no exceptions. Your terminal activity stays on your machine. You can verify this with any network monitoring tool.

### Smart CLI

50+ commands for scripting and automation via Unix Domain Socket.

- **Hook Integration** -- Full integration with Claude Code hook events for real-time agent state
- **Tab Management** -- Create, list, focus, close, rename, and pin tabs from the command line
- **Notifications** -- Trigger notifications from scripts and pipelines
- **Dashboard Control** -- Toggle panels, query agent state, and export timeline data

## Install

### Homebrew

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

To update:

```bash
brew update && brew upgrade --cask cocxy
```

> **Note:** `brew update` syncs the tap before upgrading. Running `brew upgrade` alone may not detect new versions from third-party taps.

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
| Agent Dashboard | `Cmd+Option+D` |
| Agent Timeline | `Cmd+Shift+T` |
| Notifications | `Cmd+Shift+I` |
| Browser Panel | `Cmd+Shift+B` |
| Find in Terminal | `Cmd+F` |
| Split Horizontal | `Cmd+D` |
| Split Vertical | `Cmd+Shift+D` |
| Close Split | `Cmd+Shift+W` |
| Navigate Splits | `Cmd+Option+Arrows` |
| Quick Terminal | `` Cmd+` `` |
| Zoom In / Out | `Cmd++` / `Cmd+-` |
| Next Tab | `Cmd+Shift+]` |
| Previous Tab | `Cmd+Shift+[` |
| Jump to Tab 1-9 | `Cmd+1` through `Cmd+9` |
| Dismiss Overlay | `Esc` |

## CLI

The `cocxy` CLI companion communicates with the running app via a local Unix Domain Socket.

```bash
# Install hooks for Claude Code (auto-configures settings)
cocxy hooks install

# Notify from scripts
cocxy notify "Build finished"

# Tab management
cocxy list-tabs
cocxy new-tab --directory ~/projects/my-app
cocxy focus-tab <id>
cocxy rename-tab <id> "API Server"
cocxy pin-tab <id>

# Dashboard and panels
cocxy dashboard-toggle
cocxy timeline-export --format json

# Check app status
cocxy status
```

Run `cocxy help` for the full list of available commands.

## Supported Agents

| Agent | Hook Integration | OSC Detection | Pattern Detection |
|-------|-----------------|---------------|-------------------|
| Claude Code | Yes (12 events) | Yes | Yes |
| Codex | -- | -- | Yes |
| Aider | -- | -- | Yes |
| Gemini CLI | -- | -- | Yes |
| Kiro | -- | -- | Yes |
| OpenCode | -- | -- | Yes |

## Configuration

Configuration files live in `~/.config/cocxy/`:

```
~/.config/cocxy/
  config.toml       # Main config (fonts, theme, keybindings)
  agents.toml       # Agent detection patterns and thresholds
  themes/*.toml     # Custom themes (Ghostty-compatible format)
  sessions/         # Auto-saved session state
```

### Example config.toml

```toml
[font]
family = "JetBrains Mono"
size = 14.0

[theme]
name = "catppuccin-mocha"

[window]
restore-session = true

[terminal]
scrollback-lines = 10000
cursor-style = "block"
```

### Themes

Cocxy ships with Catppuccin (Mocha and Latte), One Dark, and Solarized. It also imports Ghostty `.toml` theme files directly. Drop a `.toml` file into `~/.config/cocxy/themes/` and it becomes available immediately.

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

# Build the terminal engine (takes 5-10 minutes on first run)
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
swift test
```

Or via Xcode:

```bash
xcodebuild test -scheme CocxyTerminal -destination 'platform=macOS'
```

## Architecture

MVVM + Coordinators with Swift protocols as contracts between modules. Zero third-party Swift dependencies.

```
Sources/
  App/               # Entry point, AppDelegate, lifecycle
  Core/              # Terminal engine bridge, PTY, socket server
  Domain/            # Business logic, detection engine, session management
  UI/                # Windows, tabs, panels, overlays, animations
CLI/                 # cocxy companion tool (50+ commands)
Tests/               # 2,000+ test cases
```

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide.

## Security

Found a vulnerability? Do not open a public issue. See [SECURITY.md](SECURITY.md) for the responsible disclosure process.

## License

MIT License. Copyright (c) 2026 Said Arturo Lopez. See [LICENSE](LICENSE).

## Author

**Said Arturo Lopez** ([@salp2403](https://github.com/salp2403))
