# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: pl -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> Ten zlokalizowany README jest generowany z kanonicznego angielskiego README.md. Po zmianie źródła uruchom `scripts/translate-readme.sh`, aby odświeżyć hash.

## Przegląd

Cocxy Terminal to natywny terminal macOS rozumiejący sesje coding agent. Łączy GPU rendering przez Metal, wielowarstwowe agent detection, wbudowany code review, natywny Markdown workspace, lokalne notebooks, wbudowany browser i trwałe sesje SSH z zero telemetry.

## Instalacja

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Aktualizacja:

```bash
brew update && brew upgrade --cask cocxy
```

## Kluczowe możliwości

- Agent detection przez hooks, OSC, pattern matching i timing, z Dashboard oraz Timeline dla każdej sesji.
- Local-first Agent Mode z MCP servers, codebase indexing, skills, inline completions, sandboxed Computer Use i szyfrowanymi rozmowami.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools oraz rozbudowany CLI companion.
- CocxyCore dostarcza terminal engine w Zig i Metal z ligatures, inline images, search i Protocol v2.
- Remote Workspaces obejmuje SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay i local daemon.

## Prywatność i bezpieczeństwo

Cocxy nie ma analytics SDK, automatycznego wysyłania diagnostyki ani backendu dla terminal activity. Sieć jest używana tylko do podpisanych aktualizacji lub jawnych działań użytkownika.

## Budowanie ze źródeł

Wymaga macOS 14+, Xcode 16+, Swift 5.10+ i Zig 0.15+. Uruchom `swift build`, potem `swift test`, albo zbuduj lokalną app przez `./scripts/build-app.sh release`.


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
