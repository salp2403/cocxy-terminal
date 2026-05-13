# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: tr -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> Bu yerelleştirilmiş README, kanonik İngilizce README.md dosyasından üretilir. Kaynak değiştiğinde hash güncellemek için `scripts/translate-readme.sh` çalıştırın.

## Genel bakış

Cocxy Terminal, coding agent oturumlarını anlayan native macOS terminal uygulamasıdır. Metal ile GPU rendering, çok katmanlı agent detection, yerleşik code review, native Markdown workspace, yerel notebooks, yerleşik browser ve kalıcı SSH oturumlarını zero telemetry ile birleştirir.

## Kurulum

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Güncelleme:

```bash
brew update && brew upgrade --cask cocxy
```

## Temel yetenekler

- Hooks, OSC, pattern matching ve timing ile agent detection; her oturum için Dashboard ve Timeline.
- MCP servers, codebase indexing, skills, inline completions, sandboxed Computer Use ve şifreli konuşmalarla local-first Agent Mode.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools ve kapsamlı CLI companion.
- CocxyCore; Zig ve Metal tabanlı terminal engine, ligatures, inline images, search ve Protocol v2 sunar.
- Remote Workspaces; SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay ve local daemon içerir.

## Gizlilik ve güvenlik

Cocxy'de analytics SDK, otomatik tanılama gönderimi veya terminal activity backend yoktur. Ağ yalnızca imzalı güncellemeler veya kullanıcının açıkça başlattığı işlemler için kullanılır.

## Kaynaktan build

macOS 14+, Xcode 16+, Swift 5.10+ ve Zig 0.15+ gerekir. `swift build`, ardından `swift test` çalıştırın veya `./scripts/build-app.sh release` ile yerel app oluşturun.


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
