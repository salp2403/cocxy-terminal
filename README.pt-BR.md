# Cocxy Terminal

<!-- cocxy-readme-source-sha256: 6421358cb8f505dbc80aa46424f78cf429367902b1d4a843df4acd82caca0b50 -->
<!-- cocxy-readme-locale: pt-BR -->

[English](README.md) | [العربية](README.ar.md) | [Bosanski](README.bs.md) | [Dansk](README.da.md) | [Deutsch](README.de.md) | [Español](README.es.md) | [Français](README.fr.md) | [Italiano](README.it.md) | [日本語](README.ja.md) | [ភាសាខ្មែរ](README.km.md) | [한국어](README.ko.md) | [Norsk](README.no.md) | [Polski](README.pl.md) | [Português do Brasil](README.pt-BR.md) | [Русский](README.ru.md) | [ไทย](README.th.md) | [Türkçe](README.tr.md) | [Українська](README.uk.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh-CN.md) | [繁體中文](README.zh-TW.md)

> Este README localizado é gerado a partir do README.md canônico em inglês. Execute `scripts/translate-readme.sh` após mudar a origem para atualizar o hash.

## Visão geral

Cocxy Terminal é um terminal nativo para macOS que entende sessões de coding agent. Ele combina GPU rendering com Metal, agent detection em múltiplas camadas, code review integrado, Markdown workspace nativo, notebooks locais, browser integrado e sessões SSH persistentes com zero telemetry.

## Instalação

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Atualização:

```bash
brew update && brew upgrade --cask cocxy
```

## Recursos principais

- Agent detection por hooks, OSC, pattern matching e timing, com Dashboard e Timeline por sessão.
- Agent Mode local-first com MCP servers, codebase indexing, skills, inline completions, Computer Use sandboxed e conversas criptografadas.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools e CLI companion completo.
- CocxyCore entrega um terminal engine em Zig e Metal com ligatures, inline images, search e Protocol v2.
- Remote Workspaces cobre SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay e local daemon.

## Privacidade e segurança

Cocxy não possui analytics SDK, envio automático de diagnósticos nem backend para terminal activity. A rede é usada apenas para atualizações assinadas ou ações explícitas do usuário.

## Build a partir do código-fonte

Requer macOS 14+, Xcode 16+, Swift 5.10+ e Zig 0.15+. Execute `swift build`, depois `swift test`, ou crie a app local com `./scripts/build-app.sh release`.


Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.


## Links

- [Website](https://cocxy.dev)
- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)
- [Security](SECURITY.md)
- [License](LICENSE)
