# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: it -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> Questo README localizzato viene generato dal README.md inglese canonico. Esegui `scripts/translate-readme.sh` dopo ogni modifica della sorgente per aggiornare l'hash.

## Panoramica

Cocxy Terminal è un terminal nativo per macOS che comprende le sessioni di coding agent. Combina GPU rendering con Metal, agent detection multilivello, code review integrato, Markdown workspace nativo, notebooks locali, browser integrato e sessioni SSH persistenti con zero telemetry.

## Installazione

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Aggiornamento:

```bash
brew update && brew upgrade --cask cocxy
```

## Funzionalità principali

- Agent detection tramite hooks, OSC, pattern matching e timing, con Dashboard e Timeline per sessione.
- Agent Mode local-first con MCP servers, codebase indexing, skills, inline completions, Computer Use sandboxed e conversazioni cifrate.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools e CLI companion completo.
- CocxyCore fornisce una terminal engine in Zig e Metal con ligatures, inline images, search e Protocol v2.
- Remote Workspaces copre SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay e local daemon.

## Privacy e sicurezza

Cocxy non include analytics SDK, invio automatico di diagnostica o backend per l'attività del terminal. La rete viene usata solo per aggiornamenti firmati o azioni esplicite dell'utente.

## Build da sorgente

Richiede macOS 14+, Xcode 16+, Swift 5.10+ e Zig 0.15+. Esegui `swift build`, poi `swift test`, oppure crea l'app locale con `./scripts/build-app.sh release`.


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
