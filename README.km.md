# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: km -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> README ដែលបានបកប្រែនេះត្រូវបានបង្កើតពី README.md ភាសាអង់គ្លេស។ បន្ទាប់ពីកែប្រភព សូមរត់ `scripts/translate-readme.sh` ដើម្បីធ្វើបច្ចុប្បន្នភាព hash។

## ទិដ្ឋភាពទូទៅ

Cocxy Terminal គឺជា terminal ដើមសម្រាប់ macOS ដែលយល់អំពី session របស់ coding agent។ វារួមបញ្ចូល GPU rendering ជាមួយ Metal, agent detection ច្រើនស្រទាប់, code review ខាងក្នុង, Markdown workspace ដើម, notebooks មូលដ្ឋាន, browser ខាងក្នុង និង SSH sessions ដែលរក្សាទុកដោយ zero telemetry។

## ដំឡើង

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

ធ្វើបច្ចុប្បន្នភាព:

```bash
brew update && brew upgrade --cask cocxy
```

## សមត្ថភាពសំខាន់ៗ

- Agent detection តាម hooks, OSC, pattern matching និង timing ជាមួយ Dashboard និង Timeline សម្រាប់ session នីមួយៗ។
- Agent Mode local-first ជាមួយ MCP servers, codebase indexing, skills, inline completions, Computer Use sandboxed និង conversations ដែលបានអ៊ិនគ្រីប។
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools និង CLI companion ពេញលេញ។
- CocxyCore ផ្តល់ terminal engine សរសេរដោយ Zig និង Metal ជាមួយ ligatures, inline images, search និង Protocol v2។
- Remote Workspaces គាំទ្រ SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay និង local daemon។

## ឯកជនភាព និងសុវត្ថិភាព

Cocxy មិនមាន analytics SDK, automatic diagnostic sender ឬ backend សម្រាប់ terminal activity ទេ។ បណ្តាញត្រូវបានប្រើតែសម្រាប់ signed updates ឬសកម្មភាពដែលអ្នកប្រើជ្រើសរើសច្បាស់លាស់។

## Build ពី source

ត្រូវការ macOS 14+, Xcode 16+, Swift 5.10+ និង Zig 0.15+។ រត់ `swift build`, បន្ទាប់មក `swift test`, ឬបង្កើត app មូលដ្ឋានជាមួយ `./scripts/build-app.sh release`។


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
