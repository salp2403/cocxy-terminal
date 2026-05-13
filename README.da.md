# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: da -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> Denne lokaliserede README genereres fra den kanoniske engelske README.md. Kør `scripts/translate-readme.sh` efter ændringer i kilden for at opdatere hash.

## Overblik

Cocxy Terminal er en native macOS terminal, der forstår coding agent-sessioner. Den kombinerer GPU rendering med Metal, flerlags agent detection, indbygget code review, native Markdown workspace, lokale notebooks, indbygget browser og vedvarende SSH-sessioner med zero telemetry.

## Installation

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Opdatering:

```bash
brew update && brew upgrade --cask cocxy
```

## Kernefunktioner

- Agent detection via hooks, OSC, pattern matching og timing, med Dashboard og Timeline for hver session.
- Local-first Agent Mode med MCP servers, codebase indexing, skills, inline completions, sandboxed Computer Use og krypterede samtaler.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools og en stærk CLI companion.
- CocxyCore leverer en terminal engine bygget i Zig og Metal med ligatures, inline images, search og Protocol v2.
- Remote Workspaces omfatter SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay og local daemon.

## Privatliv og sikkerhed

Cocxy har ingen analytics SDK, ingen automatisk diagnostikafsender og ingen backend til terminalaktivitet. Netværk bruges kun til signerede opdateringer eller eksplicitte brugerhandlinger.

## Byg fra source

Kræver macOS 14+, Xcode 16+, Swift 5.10+ og Zig 0.15+. Kør `swift build`, derefter `swift test`, eller byg en lokal app med `./scripts/build-app.sh release`.


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
