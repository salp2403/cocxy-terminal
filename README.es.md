# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: es -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> Este README localizado se genera desde el README.md canónico en inglés. Ejecuta `scripts/translate-readme.sh` después de cambiar el origen para refrescar el hash.

## Resumen

Cocxy Terminal es un terminal nativo de macOS que entiende sesiones de coding agent. Combina GPU rendering con Metal, agent detection en múltiples capas, code review integrado, Markdown workspace nativo, notebooks locales, browser integrado y sesiones SSH persistentes con zero telemetry.

## Instalación

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Actualizar:

```bash
brew update && brew upgrade --cask cocxy
```

## Capacidades principales

- Agent detection por hooks, OSC, pattern matching y timing, con Dashboard y Timeline por sesión.
- Agent Mode local-first con MCP servers, codebase indexing, skills, inline completions, Computer Use sandboxed y conversaciones cifradas.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools y CLI companion completo.
- CocxyCore ofrece un terminal engine en Zig y Metal con ligatures, inline images, search y Protocol v2.
- Remote Workspaces cubre SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay y local daemon.

## Privacidad y seguridad

Cocxy no tiene analytics SDK, envío automático de diagnósticos ni backend para actividad de terminal. La red solo se usa para actualizaciones firmadas o acciones explícitas del usuario.

## Build desde código fuente

Requiere macOS 14+, Xcode 16+, Swift 5.10+ y Zig 0.15+. Ejecuta `swift build`, luego `swift test`, o genera la app local con `./scripts/build-app.sh release`.


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
