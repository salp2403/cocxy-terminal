# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: ru -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> Этот локализованный README создается из канонического английского README.md. После изменения источника запустите `scripts/translate-readme.sh`, чтобы обновить hash.

## Обзор

Cocxy Terminal — это native macOS terminal, который понимает сессии coding agent. Он объединяет GPU rendering через Metal, многоуровневый agent detection, встроенный code review, native Markdown workspace, локальные notebooks, встроенный browser и постоянные SSH-сессии с zero telemetry.

## Установка

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Обновление:

```bash
brew update && brew upgrade --cask cocxy
```

## Основные возможности

- Agent detection через hooks, OSC, pattern matching и timing, с Dashboard и Timeline для каждой сессии.
- Local-first Agent Mode с MCP servers, codebase indexing, skills, inline completions, sandboxed Computer Use и зашифрованными разговорами.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools и развитый CLI companion.
- CocxyCore предоставляет terminal engine на Zig и Metal с ligatures, inline images, search и Protocol v2.
- Remote Workspaces включает SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay и local daemon.

## Приватность и безопасность

Cocxy не содержит analytics SDK, автоматической отправки диагностики или backend для terminal activity. Сеть используется только для подписанных обновлений или явных действий пользователя.

## Сборка из исходного кода

Требуются macOS 14+, Xcode 16+, Swift 5.10+ и Zig 0.15+. Запустите `swift build`, затем `swift test`, или соберите локальное app через `./scripts/build-app.sh release`.


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
