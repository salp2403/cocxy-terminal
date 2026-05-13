# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: de -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> Diese lokalisierte README wird aus der kanonischen englischen README.md erzeugt. Nach Änderungen an der Quelle `scripts/translate-readme.sh` ausführen, damit der hash aktuell bleibt.

## Überblick

Cocxy Terminal ist ein natives macOS terminal für coding agent-Sitzungen. Es kombiniert GPU rendering mit Metal, mehrschichtige agent detection, integriertes code review, ein natives Markdown workspace, lokale notebooks, einen eingebauten browser und persistente SSH-Sitzungen mit zero telemetry.

## Installation

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Aktualisieren:

```bash
brew update && brew upgrade --cask cocxy
```

## Kernfunktionen

- Agent detection über hooks, OSC, pattern matching und timing, inklusive Dashboard und Timeline pro Sitzung.
- Local-first Agent Mode mit MCP servers, codebase indexing, skills, inline completions, sandboxed Computer Use und verschlüsselten Gesprächen.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools und umfangreicher CLI companion.
- CocxyCore liefert eine terminal engine in Zig und Metal mit ligatures, inline images, search und Protocol v2.
- Remote Workspaces bieten SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay und local daemon.

## Datenschutz und Sicherheit

Cocxy enthält kein analytics SDK, keinen automatischen Diagnosedienst und kein backend für terminal activity. Netzwerkzugriff passiert nur für signierte Updates oder explizite Benutzeraktionen.

## Aus dem Quellcode bauen

Erfordert macOS 14+, Xcode 16+, Swift 5.10+ und Zig 0.15+. `swift build`, danach `swift test`, oder eine lokale app mit `./scripts/build-app.sh release` bauen.


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
