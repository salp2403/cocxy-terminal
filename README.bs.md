# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: bs -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> Ovaj lokalizovani README se generiše iz kanonskog engleskog README.md. Nakon promjene izvora pokreni `scripts/translate-readme.sh` da osvježiš hash.

## Pregled

Cocxy Terminal je native macOS terminal koji razumije sesije coding agent-a. Kombinuje GPU rendering kroz Metal, višeslojnu detekciju agent-a, ugrađeni code review, native Markdown workspace, lokalne notebooks, ugrađeni browser i trajne SSH sesije uz zero telemetry.

## Instalacija

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Ažuriranje:

```bash
brew update && brew upgrade --cask cocxy
```

## Ključne mogućnosti

- Agent detection kroz hooks, OSC, pattern matching i timing, sa Dashboard i Timeline prikazima po sesiji.
- Local-first Agent Mode sa MCP servers, codebase indexing, skills, inline completions, sandboxed Computer Use i šifrovanim razgovorima.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools i bogat CLI companion.
- CocxyCore donosi terminal engine pisan u Zig i Metal sa ligatures, inline images, search i Protocol v2.
- Remote Workspaces pokrivaju SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay i local daemon.

## Privatnost i sigurnost

Cocxy nema analytics SDK, automatski pošiljalac dijagnostike ni backend za terminal aktivnost. Mreža se koristi samo za potpisana ažuriranja ili za eksplicitne korisničke akcije.

## Build iz izvora

Potrebni su macOS 14+, Xcode 16+, Swift 5.10+ i Zig 0.15+. Pokreni `swift build`, zatim `swift test`, ili napravi lokalni app sa `./scripts/build-app.sh release`.


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
