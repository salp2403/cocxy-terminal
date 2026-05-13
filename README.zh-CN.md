# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: zh-CN -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> 此本地化 README 从规范英文 README.md 生成。修改源文件后请运行 `scripts/translate-readme.sh` 以更新 hash。

## 概览

Cocxy Terminal 是理解 coding agent 会话的 native macOS terminal。它结合了 Metal GPU rendering、多层 agent detection、内置 code review、native Markdown workspace、本地 notebooks、内置 browser，以及 zero telemetry 的持久 SSH sessions。

## 安装

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

更新:

```bash
brew update && brew upgrade --cask cocxy
```

## 核心能力

- 通过 hooks、OSC、pattern matching 和 timing 进行 agent detection，并为每个 session 提供 Dashboard 和 Timeline。
- Local-first Agent Mode，包含 MCP servers、codebase indexing、skills、inline completions、sandboxed Computer Use 和加密会话。
- Markdown workspace、Jupyter import/export、workflows、browser profiles、DevTools 和完整 CLI companion。
- CocxyCore 提供由 Zig 与 Metal 构建的 terminal engine，支持 ligatures、inline images、search 和 Protocol v2。
- Remote Workspaces 覆盖 SSH multiplexing、tmux/screen fallback、SFTP、proxy、relay 和 local daemon。

## 隐私与安全

Cocxy 没有 analytics SDK、没有自动诊断发送，也没有用于 terminal activity 的 backend。网络只用于签名更新或用户明确发起的操作。

## 从 source 构建

需要 macOS 14+、Xcode 16+、Swift 5.10+ 和 Zig 0.15+。运行 `swift build`、`swift test`，或使用 `./scripts/build-app.sh release` 构建本地 app。


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
