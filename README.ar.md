# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: ar -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> يتم إنشاء هذا README المحلي من README.md الإنجليزي الأساسي. حافظ على سطر hash محدثا بتشغيل `scripts/translate-readme.sh` بعد أي تغيير في المصدر.

## نظرة عامة

Cocxy Terminal هو terminal أصلي لنظام macOS يفهم جلسات agent البرمجية. يجمع بين GPU rendering عبر Metal، كشف agent متعدد الطبقات، مراجعة تغييرات مدمجة، مساحة Markdown أصلية، notebooks محلية، browser مدمج، وجلسات SSH مستمرة مع zero telemetry.

## التثبيت

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

للتحديث:

```bash
brew update && brew upgrade --cask cocxy
```

## القدرات الأساسية

- كشف agent عبر hooks و OSC و pattern matching و timing، مع Dashboard و Timeline لكل جلسة.
- Agent Mode محلي أولا مع MCP servers، codebase indexing، skills، inline completions، Computer Use sandboxed، ومحادثات مشفرة.
- Markdown workspace، Jupyter import/export، workflows، browser profiles، DevTools، و CLI companion غني.
- CocxyCore يقدم terminal engine مبنيا بـ Zig و Metal مع ligatures، inline images، search، و Protocol v2.
- Remote Workspaces تشمل SSH multiplexing، tmux/screen fallback، SFTP، proxy، relay، و daemon محلي.

## الخصوصية والأمان

Cocxy لا يحتوي على analytics SDK، ولا مُرسِل تشخيصات تلقائي، ولا backend للبيانات الطرفية. الشبكة تستخدم فقط للتحديثات الموقعة أو للأوامر التي يختارها المستخدم صراحة.

## البناء من المصدر

يتطلب macOS 14+ و Xcode 16+ و Swift 5.10+ و Zig 0.15+. شغل `swift build`، ثم `swift test`، أو أنشئ app محلي باستخدام `./scripts/build-app.sh release`.


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
