# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: th -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> README ฉบับแปลนี้ถูกสร้างจาก README.md ภาษาอังกฤษหลัก หลังจากแก้ไขต้นฉบับให้รัน `scripts/translate-readme.sh` เพื่ออัปเดต hash

## ภาพรวม

Cocxy Terminal คือ native macOS terminal ที่เข้าใจ session ของ coding agent รวม GPU rendering ด้วย Metal, agent detection หลายชั้น, code review ในตัว, Markdown workspace แบบ native, notebooks ภายในเครื่อง, browser ในตัว และ SSH sessions แบบถาวร พร้อม zero telemetry

## ติดตั้ง

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

อัปเดต:

```bash
brew update && brew upgrade --cask cocxy
```

## ความสามารถหลัก

- Agent detection ผ่าน hooks, OSC, pattern matching และ timing พร้อม Dashboard และ Timeline ต่อ session
- Agent Mode แบบ local-first พร้อม MCP servers, codebase indexing, skills, inline completions, Computer Use sandboxed และ conversations ที่เข้ารหัส
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools และ CLI companion ครบถ้วน
- CocxyCore ให้ terminal engine ที่สร้างด้วย Zig และ Metal พร้อม ligatures, inline images, search และ Protocol v2
- Remote Workspaces รองรับ SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay และ local daemon

## ความเป็นส่วนตัวและความปลอดภัย

Cocxy ไม่มี analytics SDK, ไม่มีการส่ง diagnostics อัตโนมัติ และไม่มี backend สำหรับ terminal activity เครือข่ายใช้เฉพาะ signed updates หรือการกระทำที่ผู้ใช้สั่งชัดเจน

## Build จาก source

ต้องใช้ macOS 14+, Xcode 16+, Swift 5.10+ และ Zig 0.15+ รัน `swift build`, ตามด้วย `swift test`, หรือสร้าง app ภายในเครื่องด้วย `./scripts/build-app.sh release`


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
