# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: ja -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> このローカライズ版 README は、正本である英語の README.md から生成されます。元ファイルを変更した後は `scripts/translate-readme.sh` を実行して hash を更新してください。

## 概要

Cocxy Terminal は coding agent のセッションを理解するネイティブ macOS terminal です。Metal による GPU rendering、多層の agent detection、組み込み code review、ネイティブ Markdown workspace、ローカル notebooks、組み込み browser、永続 SSH セッションを zero telemetry で提供します。

## インストール

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

更新:

```bash
brew update && brew upgrade --cask cocxy
```

## 主な機能

- hooks、OSC、pattern matching、timing による agent detection。セッションごとの Dashboard と Timeline を提供。
- local-first の Agent Mode。MCP servers、codebase indexing、skills、inline completions、sandboxed Computer Use、暗号化された会話に対応。
- Markdown workspace、Jupyter import/export、workflows、browser profiles、DevTools、豊富な CLI companion。
- CocxyCore は Zig と Metal で作られた terminal engine で、ligatures、inline images、search、Protocol v2 を備えます。
- Remote Workspaces は SSH multiplexing、tmux/screen fallback、SFTP、proxy、relay、local daemon を扱います。

## プライバシーとセキュリティ

Cocxy には analytics SDK、自動診断送信、terminal activity 用 backend はありません。ネットワークは署名済み更新またはユーザーが明示した操作だけに使われます。

## ソースからビルド

macOS 14+、Xcode 16+、Swift 5.10+、Zig 0.15+ が必要です。`swift build`、`swift test` を実行するか、`./scripts/build-app.sh release` でローカル app を作成します。


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
