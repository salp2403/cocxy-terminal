# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: no -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> Denne lokaliserte README-en genereres fra den kanoniske engelske README.md. Kjør `scripts/translate-readme.sh` etter kildeendringer for å oppdatere hash.

## Oversikt

Cocxy Terminal er en native macOS terminal som forstår coding agent-økter. Den kombinerer GPU rendering med Metal, flerlags agent detection, innebygd code review, native Markdown workspace, lokale notebooks, innebygd browser og varige SSH-økter med zero telemetry.

## Installasjon

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Oppdatering:

```bash
brew update && brew upgrade --cask cocxy
```

## Kjernefunksjoner

- Agent detection via hooks, OSC, pattern matching og timing, med Dashboard og Timeline per økt.
- Local-first Agent Mode med MCP servers, codebase indexing, skills, inline completions, sandboxed Computer Use og krypterte samtaler.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools og en rik CLI companion.
- CocxyCore leverer en terminal engine bygget i Zig og Metal med ligatures, inline images, search og Protocol v2.
- Remote Workspaces dekker SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay og local daemon.

## Personvern og sikkerhet

Cocxy har ingen analytics SDK, ingen automatisk diagnostikksender og ingen backend for terminal activity. Nettverk brukes bare til signerte oppdateringer eller eksplisitte brukerhandlinger.

## Bygg fra kilde

Krever macOS 14+, Xcode 16+, Swift 5.10+ og Zig 0.15+. Kjør `swift build`, deretter `swift test`, eller bygg en lokal app med `./scripts/build-app.sh release`.


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
