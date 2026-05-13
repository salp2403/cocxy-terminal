# Cocxy Terminal

<!-- cocxy-readme-source-sha256: c0ca6c8413e844e7656e6e3e63e587930d1af0ef397aa8611a7b7fb5f18180e0 -->
<!-- cocxy-readme-locale: ko -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> 此本地化 README 由標準英文 README.md 產生。修改來源後請執行 `scripts/translate-readme.sh` 以更新 hash。

## 概覽

Cocxy Terminal 是理解 coding agent 工作階段的 native macOS terminal。它結合 Metal GPU rendering、多層 agent detection、內建 code review、native Markdown workspace、本機 notebooks、內建 browser，以及 zero telemetry 的持久 SSH sessions。

## 安裝

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

更新:

```bash
brew update && brew upgrade --cask cocxy
```

## 核心能力

- 透過 hooks、OSC、pattern matching 與 timing 進行 agent detection，並為每個 session 提供 Dashboard 與 Timeline。
- Local-first Agent Mode，包含 MCP servers、codebase indexing、skills、inline completions、sandboxed Computer Use 與加密對話。
- Markdown workspace、Jupyter import/export、workflows、browser profiles、DevTools 與完整 CLI companion。
- CocxyCore 提供以 Zig 與 Metal 建構的 terminal engine，支援 ligatures、inline images、search 與 Protocol v2。
- Remote Workspaces 涵蓋 SSH multiplexing、tmux/screen fallback、SFTP、proxy、relay 與 local daemon。

## 隱私與安全

Cocxy 沒有 analytics SDK、沒有自動 crash upload，也沒有用於 terminal activity 的 backend。網路只用於簽章更新或使用者明確啟動的動作。

## 從 source 建置

需要 macOS 14+、Xcode 16+、Swift 5.10+ 與 Zig 0.15+。執行 `swift build`、`swift test`，或使用 `./scripts/build-app.sh release` 建置本機 app。


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
