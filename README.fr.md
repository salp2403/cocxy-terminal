# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: fr -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> Ce README localisé est généré depuis le README.md anglais canonique. Lancez `scripts/translate-readme.sh` après toute modification de la source pour mettre à jour le hash.

## Aperçu

Cocxy Terminal est un terminal macOS natif qui comprend les sessions de coding agent. Il combine GPU rendering avec Metal, agent detection multicouche, code review intégré, Markdown workspace natif, notebooks locaux, browser intégré et sessions SSH persistantes avec zero telemetry.

## Installation

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Mise à jour:

```bash
brew update && brew upgrade --cask cocxy
```

## Capacités principales

- Agent detection par hooks, OSC, pattern matching et timing, avec Dashboard et Timeline par session.
- Agent Mode local-first avec MCP servers, codebase indexing, skills, inline completions, Computer Use sandboxed et conversations chiffrées.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools et CLI companion complet.
- CocxyCore fournit une terminal engine en Zig et Metal avec ligatures, inline images, search et Protocol v2.
- Remote Workspaces couvre SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay et local daemon.

## Confidentialité et sécurité

Cocxy n'a pas d'analytics SDK, pas d'envoi automatique de diagnostics et pas de backend pour l'activité du terminal. Le réseau sert uniquement aux mises à jour signées ou aux actions explicites de l'utilisateur.

## Construire depuis la source

Nécessite macOS 14+, Xcode 16+, Swift 5.10+ et Zig 0.15+. Exécutez `swift build`, puis `swift test`, ou créez l'app locale avec `./scripts/build-app.sh release`.


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
