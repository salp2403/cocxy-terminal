# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: uk -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> Цей локалізований README генерується з канонічного англомовного README.md. Після зміни джерела запустіть `scripts/translate-readme.sh`, щоб оновити hash.

## Огляд

Cocxy Terminal — це native macOS terminal, який розуміє сесії coding agent. Він поєднує GPU rendering через Metal, багаторівневий agent detection, вбудований code review, native Markdown workspace, локальні notebooks, вбудований browser і постійні SSH-сесії з zero telemetry.

## Встановлення

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Оновлення:

```bash
brew update && brew upgrade --cask cocxy
```

## Основні можливості

- Agent detection через hooks, OSC, pattern matching і timing, з Dashboard та Timeline для кожної сесії.
- Local-first Agent Mode з MCP servers, codebase indexing, skills, inline completions, sandboxed Computer Use і зашифрованими розмовами.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools і повний CLI companion.
- CocxyCore надає terminal engine на Zig і Metal з ligatures, inline images, search і Protocol v2.
- Remote Workspaces охоплює SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay і local daemon.

## Приватність і безпека

Cocxy не має analytics SDK, автоматичного надсилання діагностики або backend для terminal activity. Мережа використовується лише для підписаних оновлень або явних дій користувача.

## Build із source

Потрібні macOS 14+, Xcode 16+, Swift 5.10+ і Zig 0.15+. Запустіть `swift build`, потім `swift test`, або створіть локальний app через `./scripts/build-app.sh release`.


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
