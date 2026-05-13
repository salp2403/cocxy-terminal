# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: ko -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> 이 로컬라이즈된 README는 기준 영어 README.md에서 생성됩니다. 원본을 바꾼 뒤에는 `scripts/translate-readme.sh`를 실행해 hash를 갱신하세요.

## 개요

Cocxy Terminal은 coding agent 세션을 이해하는 native macOS terminal입니다. Metal 기반 GPU rendering, 다층 agent detection, 내장 code review, native Markdown workspace, 로컬 notebooks, 내장 browser, 지속 SSH 세션을 zero telemetry로 제공합니다.

## 설치

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

업데이트:

```bash
brew update && brew upgrade --cask cocxy
```

## 핵심 기능

- hooks, OSC, pattern matching, timing 기반 agent detection과 세션별 Dashboard, Timeline.
- local-first Agent Mode: MCP servers, codebase indexing, skills, inline completions, sandboxed Computer Use, 암호화된 대화.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools, 풍부한 CLI companion.
- CocxyCore는 Zig와 Metal로 만든 terminal engine이며 ligatures, inline images, search, Protocol v2를 지원합니다.
- Remote Workspaces는 SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay, local daemon을 제공합니다.

## 개인정보와 보안

Cocxy에는 analytics SDK, 자동 진단 전송, terminal activity backend가 없습니다. 네트워크는 서명된 업데이트나 사용자가 명시적으로 실행한 작업에만 사용됩니다.

## source에서 빌드

macOS 14+, Xcode 16+, Swift 5.10+, Zig 0.15+가 필요합니다. `swift build`, `swift test`를 실행하거나 `./scripts/build-app.sh release`로 로컬 app을 빌드하세요.


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
