# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: vi -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> README bản địa hóa này được tạo từ README.md tiếng Anh chuẩn. Sau khi đổi nguồn, hãy chạy `scripts/translate-readme.sh` để cập nhật hash.

## Tổng quan

Cocxy Terminal là native macOS terminal hiểu các phiên coding agent. Nó kết hợp GPU rendering bằng Metal, agent detection nhiều lớp, code review tích hợp, native Markdown workspace, notebooks cục bộ, browser tích hợp và SSH sessions bền vững với zero telemetry.

## Cài đặt

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Cập nhật:

```bash
brew update && brew upgrade --cask cocxy
```

## Khả năng chính

- Agent detection qua hooks, OSC, pattern matching và timing, với Dashboard và Timeline cho từng session.
- Agent Mode local-first với MCP servers, codebase indexing, skills, inline completions, Computer Use sandboxed và cuộc trò chuyện được mã hóa.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools và CLI companion đầy đủ.
- CocxyCore cung cấp terminal engine bằng Zig và Metal với ligatures, inline images, search và Protocol v2.
- Remote Workspaces hỗ trợ SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay và local daemon.

## Quyền riêng tư và bảo mật

Cocxy không có analytics SDK, không tự động gửi chẩn đoán và không có backend cho terminal activity. Mạng chỉ dùng cho signed updates hoặc hành động rõ ràng của người dùng.

## Build từ source

Cần macOS 14+, Xcode 16+, Swift 5.10+ và Zig 0.15+. Chạy `swift build`, sau đó `swift test`, hoặc tạo app cục bộ bằng `./scripts/build-app.sh release`.


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
