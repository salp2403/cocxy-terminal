#!/usr/bin/env bash
# Generate localized README files from the canonical English README.
# This script is local-only and never calls network services.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README_EN="$ROOT_DIR/README.md"
LOCALES=(
  ar bs da de es fr it ja km ko no pl pt-BR ru th tr uk vi zh-CN zh-TW
)

source_hash() {
  shasum -a 256 "$README_EN" | awk '{print $1}'
}

language_name() {
  case "$1" in
    ar) printf 'العربية' ;;
    bs) printf 'Bosanski' ;;
    da) printf 'Dansk' ;;
    de) printf 'Deutsch' ;;
    es) printf 'Español' ;;
    fr) printf 'Français' ;;
    it) printf 'Italiano' ;;
    ja) printf '日本語' ;;
    km) printf 'ភាសាខ្មែរ' ;;
    ko) printf '한국어' ;;
    no) printf 'Norsk' ;;
    pl) printf 'Polski' ;;
    pt-BR) printf 'Português do Brasil' ;;
    ru) printf 'Русский' ;;
    th) printf 'ไทย' ;;
    tr) printf 'Türkçe' ;;
    uk) printf 'Українська' ;;
    vi) printf 'Tiếng Việt' ;;
    zh-CN) printf '简体中文' ;;
    zh-TW) printf '繁體中文' ;;
    *) printf '%s' "$1" ;;
  esac
}

language_links() {
  printf '[English](README.md)'
  for locale in "${LOCALES[@]}"; do
    printf ' | [%s](README.%s.md)' "$(language_name "$locale")" "$locale"
  done
  printf '\n'
}

technical_terms() {
  cat <<'TEXT'
Technical terms intentionally preserved: terminal, agent, MCP, CocxyCore, Homebrew, Swift, Metal, AppKit, SwiftUI, Zig, macOS, GitHub, SSH, SFTP, tmux, screen, PTY, GPU, CLI, Markdown, Jupyter, WebKit, Foundation Models.
TEXT
}

localized_body() {
  case "$1" in
    ar)
      cat <<'TEXT'
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

Cocxy لا يحتوي على analytics SDK، ولا crash upload تلقائي، ولا backend للبيانات الطرفية. الشبكة تستخدم فقط للتحديثات الموقعة أو للأوامر التي يختارها المستخدم صراحة.

## البناء من المصدر

يتطلب macOS 14+ و Xcode 16+ و Swift 5.10+ و Zig 0.15+. شغل `swift build`، ثم `swift test`، أو أنشئ app محلي باستخدام `./scripts/build-app.sh release`.
TEXT
      ;;
    bs)
      cat <<'TEXT'
> Ovaj lokalizovani README se generiše iz kanonskog engleskog README.md. Nakon promjene izvora pokreni `scripts/translate-readme.sh` da osvježiš hash.

## Pregled

Cocxy Terminal je native macOS terminal koji razumije sesije coding agent-a. Kombinuje GPU rendering kroz Metal, višeslojnu detekciju agent-a, ugrađeni code review, native Markdown workspace, lokalne notebooks, ugrađeni browser i trajne SSH sesije uz zero telemetry.

## Instalacija

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Ažuriranje:

```bash
brew update && brew upgrade --cask cocxy
```

## Ključne mogućnosti

- Agent detection kroz hooks, OSC, pattern matching i timing, sa Dashboard i Timeline prikazima po sesiji.
- Local-first Agent Mode sa MCP servers, codebase indexing, skills, inline completions, sandboxed Computer Use i šifrovanim razgovorima.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools i bogat CLI companion.
- CocxyCore donosi terminal engine pisan u Zig i Metal sa ligatures, inline images, search i Protocol v2.
- Remote Workspaces pokrivaju SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay i local daemon.

## Privatnost i sigurnost

Cocxy nema analytics SDK, automatski crash upload ni backend za terminal aktivnost. Mreža se koristi samo za potpisana ažuriranja ili za eksplicitne korisničke akcije.

## Build iz izvora

Potrebni su macOS 14+, Xcode 16+, Swift 5.10+ i Zig 0.15+. Pokreni `swift build`, zatim `swift test`, ili napravi lokalni app sa `./scripts/build-app.sh release`.
TEXT
      ;;
    da)
      cat <<'TEXT'
> Denne lokaliserede README genereres fra den kanoniske engelske README.md. Kør `scripts/translate-readme.sh` efter ændringer i kilden for at opdatere hash.

## Overblik

Cocxy Terminal er en native macOS terminal, der forstår coding agent-sessioner. Den kombinerer GPU rendering med Metal, flerlags agent detection, indbygget code review, native Markdown workspace, lokale notebooks, indbygget browser og vedvarende SSH-sessioner med zero telemetry.

## Installation

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Opdatering:

```bash
brew update && brew upgrade --cask cocxy
```

## Kernefunktioner

- Agent detection via hooks, OSC, pattern matching og timing, med Dashboard og Timeline for hver session.
- Local-first Agent Mode med MCP servers, codebase indexing, skills, inline completions, sandboxed Computer Use og krypterede samtaler.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools og en stærk CLI companion.
- CocxyCore leverer en terminal engine bygget i Zig og Metal med ligatures, inline images, search og Protocol v2.
- Remote Workspaces omfatter SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay og local daemon.

## Privatliv og sikkerhed

Cocxy har ingen analytics SDK, ingen automatisk crash upload og ingen backend til terminalaktivitet. Netværk bruges kun til signerede opdateringer eller eksplicitte brugerhandlinger.

## Byg fra source

Kræver macOS 14+, Xcode 16+, Swift 5.10+ og Zig 0.15+. Kør `swift build`, derefter `swift test`, eller byg en lokal app med `./scripts/build-app.sh release`.
TEXT
      ;;
    de)
      cat <<'TEXT'
> Diese lokalisierte README wird aus der kanonischen englischen README.md erzeugt. Nach Änderungen an der Quelle `scripts/translate-readme.sh` ausführen, damit der hash aktuell bleibt.

## Überblick

Cocxy Terminal ist ein natives macOS terminal für coding agent-Sitzungen. Es kombiniert GPU rendering mit Metal, mehrschichtige agent detection, integriertes code review, ein natives Markdown workspace, lokale notebooks, einen eingebauten browser und persistente SSH-Sitzungen mit zero telemetry.

## Installation

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Aktualisieren:

```bash
brew update && brew upgrade --cask cocxy
```

## Kernfunktionen

- Agent detection über hooks, OSC, pattern matching und timing, inklusive Dashboard und Timeline pro Sitzung.
- Local-first Agent Mode mit MCP servers, codebase indexing, skills, inline completions, sandboxed Computer Use und verschlüsselten Gesprächen.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools und umfangreicher CLI companion.
- CocxyCore liefert eine terminal engine in Zig und Metal mit ligatures, inline images, search und Protocol v2.
- Remote Workspaces bieten SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay und local daemon.

## Datenschutz und Sicherheit

Cocxy enthält kein analytics SDK, keinen automatischen crash upload und kein backend für terminal activity. Netzwerkzugriff passiert nur für signierte Updates oder explizite Benutzeraktionen.

## Aus dem Quellcode bauen

Erfordert macOS 14+, Xcode 16+, Swift 5.10+ und Zig 0.15+. `swift build`, danach `swift test`, oder eine lokale app mit `./scripts/build-app.sh release` bauen.
TEXT
      ;;
    es)
      cat <<'TEXT'
> Este README localizado se genera desde el README.md canónico en inglés. Ejecuta `scripts/translate-readme.sh` después de cambiar el origen para refrescar el hash.

## Resumen

Cocxy Terminal es un terminal nativo de macOS que entiende sesiones de coding agent. Combina GPU rendering con Metal, agent detection en múltiples capas, code review integrado, Markdown workspace nativo, notebooks locales, browser integrado y sesiones SSH persistentes con zero telemetry.

## Instalación

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Actualizar:

```bash
brew update && brew upgrade --cask cocxy
```

## Capacidades principales

- Agent detection por hooks, OSC, pattern matching y timing, con Dashboard y Timeline por sesión.
- Agent Mode local-first con MCP servers, codebase indexing, skills, inline completions, Computer Use sandboxed y conversaciones cifradas.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools y CLI companion completo.
- CocxyCore ofrece un terminal engine en Zig y Metal con ligatures, inline images, search y Protocol v2.
- Remote Workspaces cubre SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay y local daemon.

## Privacidad y seguridad

Cocxy no tiene analytics SDK, crash upload automático ni backend para actividad de terminal. La red solo se usa para actualizaciones firmadas o acciones explícitas del usuario.

## Build desde código fuente

Requiere macOS 14+, Xcode 16+, Swift 5.10+ y Zig 0.15+. Ejecuta `swift build`, luego `swift test`, o genera la app local con `./scripts/build-app.sh release`.
TEXT
      ;;
    fr)
      cat <<'TEXT'
> Ce README localisé est généré depuis le README.md anglais canonique. Lancez `scripts/translate-readme.sh` après toute modification de la source pour mettre à jour le hash.

## Aperçu

Cocxy Terminal est un terminal macOS natif qui comprend les sessions de coding agent. Il combine GPU rendering avec Metal, agent detection multicouche, code review intégré, Markdown workspace natif, notebooks locaux, browser intégré et sessions SSH persistantes avec zero telemetry.

## Installation

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Mise à jour:

```bash
brew update && brew upgrade --cask cocxy
```

## Capacités principales

- Agent detection par hooks, OSC, pattern matching et timing, avec Dashboard et Timeline par session.
- Agent Mode local-first avec MCP servers, codebase indexing, skills, inline completions, Computer Use sandboxed et conversations chiffrées.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools et CLI companion complet.
- CocxyCore fournit une terminal engine en Zig et Metal avec ligatures, inline images, search et Protocol v2.
- Remote Workspaces couvre SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay et local daemon.

## Confidentialité et sécurité

Cocxy n'a pas d'analytics SDK, pas de crash upload automatique et pas de backend pour l'activité du terminal. Le réseau sert uniquement aux mises à jour signées ou aux actions explicites de l'utilisateur.

## Construire depuis la source

Nécessite macOS 14+, Xcode 16+, Swift 5.10+ et Zig 0.15+. Exécutez `swift build`, puis `swift test`, ou créez l'app locale avec `./scripts/build-app.sh release`.
TEXT
      ;;
    it)
      cat <<'TEXT'
> Questo README localizzato viene generato dal README.md inglese canonico. Esegui `scripts/translate-readme.sh` dopo ogni modifica della sorgente per aggiornare l'hash.

## Panoramica

Cocxy Terminal è un terminal nativo per macOS che comprende le sessioni di coding agent. Combina GPU rendering con Metal, agent detection multilivello, code review integrato, Markdown workspace nativo, notebooks locali, browser integrato e sessioni SSH persistenti con zero telemetry.

## Installazione

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Aggiornamento:

```bash
brew update && brew upgrade --cask cocxy
```

## Funzionalità principali

- Agent detection tramite hooks, OSC, pattern matching e timing, con Dashboard e Timeline per sessione.
- Agent Mode local-first con MCP servers, codebase indexing, skills, inline completions, Computer Use sandboxed e conversazioni cifrate.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools e CLI companion completo.
- CocxyCore fornisce una terminal engine in Zig e Metal con ligatures, inline images, search e Protocol v2.
- Remote Workspaces copre SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay e local daemon.

## Privacy e sicurezza

Cocxy non include analytics SDK, crash upload automatico o backend per l'attività del terminal. La rete viene usata solo per aggiornamenti firmati o azioni esplicite dell'utente.

## Build da sorgente

Richiede macOS 14+, Xcode 16+, Swift 5.10+ e Zig 0.15+. Esegui `swift build`, poi `swift test`, oppure crea l'app locale con `./scripts/build-app.sh release`.
TEXT
      ;;
    ja)
      cat <<'TEXT'
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

Cocxy には analytics SDK、自動 crash upload、terminal activity 用 backend はありません。ネットワークは署名済み更新またはユーザーが明示した操作だけに使われます。

## ソースからビルド

macOS 14+、Xcode 16+、Swift 5.10+、Zig 0.15+ が必要です。`swift build`、`swift test` を実行するか、`./scripts/build-app.sh release` でローカル app を作成します。
TEXT
      ;;
    km)
      cat <<'TEXT'
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

Cocxy មិនមាន analytics SDK, crash upload ស្វ័យប្រវត្តិ ឬ backend សម្រាប់ terminal activity ទេ។ បណ្តាញត្រូវបានប្រើតែសម្រាប់ signed updates ឬសកម្មភាពដែលអ្នកប្រើជ្រើសរើសច្បាស់លាស់។

## Build ពី source

ត្រូវការ macOS 14+, Xcode 16+, Swift 5.10+ និង Zig 0.15+។ រត់ `swift build`, បន្ទាប់មក `swift test`, ឬបង្កើត app មូលដ្ឋានជាមួយ `./scripts/build-app.sh release`។
TEXT
      ;;
    ko)
      cat <<'TEXT'
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

Cocxy에는 analytics SDK, 자동 crash upload, terminal activity backend가 없습니다. 네트워크는 서명된 업데이트나 사용자가 명시적으로 실행한 작업에만 사용됩니다.

## source에서 빌드

macOS 14+, Xcode 16+, Swift 5.10+, Zig 0.15+가 필요합니다. `swift build`, `swift test`를 실행하거나 `./scripts/build-app.sh release`로 로컬 app을 빌드하세요.
TEXT
      ;;
    no)
      cat <<'TEXT'
> Denne lokaliserte README-en genereres fra den kanoniske engelske README.md. Kjør `scripts/translate-readme.sh` etter kildeendringer for å oppdatere hash.

## Oversikt

Cocxy Terminal er en native macOS terminal som forstår coding agent-økter. Den kombinerer GPU rendering med Metal, flerlags agent detection, innebygd code review, native Markdown workspace, lokale notebooks, innebygd browser og varige SSH-økter med zero telemetry.

## Installasjon

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Oppdatering:

```bash
brew update && brew upgrade --cask cocxy
```

## Kjernefunksjoner

- Agent detection via hooks, OSC, pattern matching og timing, med Dashboard og Timeline per økt.
- Local-first Agent Mode med MCP servers, codebase indexing, skills, inline completions, sandboxed Computer Use og krypterte samtaler.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools og en rik CLI companion.
- CocxyCore leverer en terminal engine bygget i Zig og Metal med ligatures, inline images, search og Protocol v2.
- Remote Workspaces dekker SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay og local daemon.

## Personvern og sikkerhet

Cocxy har ingen analytics SDK, ingen automatisk crash upload og ingen backend for terminal activity. Nettverk brukes bare til signerte oppdateringer eller eksplisitte brukerhandlinger.

## Bygg fra kilde

Krever macOS 14+, Xcode 16+, Swift 5.10+ og Zig 0.15+. Kjør `swift build`, deretter `swift test`, eller bygg en lokal app med `./scripts/build-app.sh release`.
TEXT
      ;;
    pl)
      cat <<'TEXT'
> Ten zlokalizowany README jest generowany z kanonicznego angielskiego README.md. Po zmianie źródła uruchom `scripts/translate-readme.sh`, aby odświeżyć hash.

## Przegląd

Cocxy Terminal to natywny terminal macOS rozumiejący sesje coding agent. Łączy GPU rendering przez Metal, wielowarstwowe agent detection, wbudowany code review, natywny Markdown workspace, lokalne notebooks, wbudowany browser i trwałe sesje SSH z zero telemetry.

## Instalacja

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Aktualizacja:

```bash
brew update && brew upgrade --cask cocxy
```

## Kluczowe możliwości

- Agent detection przez hooks, OSC, pattern matching i timing, z Dashboard oraz Timeline dla każdej sesji.
- Local-first Agent Mode z MCP servers, codebase indexing, skills, inline completions, sandboxed Computer Use i szyfrowanymi rozmowami.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools oraz rozbudowany CLI companion.
- CocxyCore dostarcza terminal engine w Zig i Metal z ligatures, inline images, search i Protocol v2.
- Remote Workspaces obejmuje SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay i local daemon.

## Prywatność i bezpieczeństwo

Cocxy nie ma analytics SDK, automatycznego crash upload ani backendu dla terminal activity. Sieć jest używana tylko do podpisanych aktualizacji lub jawnych działań użytkownika.

## Budowanie ze źródeł

Wymaga macOS 14+, Xcode 16+, Swift 5.10+ i Zig 0.15+. Uruchom `swift build`, potem `swift test`, albo zbuduj lokalną app przez `./scripts/build-app.sh release`.
TEXT
      ;;
    pt-BR)
      cat <<'TEXT'
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

Cocxy não possui analytics SDK, crash upload automático nem backend para terminal activity. A rede é usada apenas para atualizações assinadas ou ações explícitas do usuário.

## Build a partir do código-fonte

Requer macOS 14+, Xcode 16+, Swift 5.10+ e Zig 0.15+. Execute `swift build`, depois `swift test`, ou crie a app local com `./scripts/build-app.sh release`.
TEXT
      ;;
    ru)
      cat <<'TEXT'
> Этот локализованный README создается из канонического английского README.md. После изменения источника запустите `scripts/translate-readme.sh`, чтобы обновить hash.

## Обзор

Cocxy Terminal — это native macOS terminal, который понимает сессии coding agent. Он объединяет GPU rendering через Metal, многоуровневый agent detection, встроенный code review, native Markdown workspace, локальные notebooks, встроенный browser и постоянные SSH-сессии с zero telemetry.

## Установка

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Обновление:

```bash
brew update && brew upgrade --cask cocxy
```

## Основные возможности

- Agent detection через hooks, OSC, pattern matching и timing, с Dashboard и Timeline для каждой сессии.
- Local-first Agent Mode с MCP servers, codebase indexing, skills, inline completions, sandboxed Computer Use и зашифрованными разговорами.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools и развитый CLI companion.
- CocxyCore предоставляет terminal engine на Zig и Metal с ligatures, inline images, search и Protocol v2.
- Remote Workspaces включает SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay и local daemon.

## Приватность и безопасность

Cocxy не содержит analytics SDK, автоматического crash upload или backend для terminal activity. Сеть используется только для подписанных обновлений или явных действий пользователя.

## Сборка из исходного кода

Требуются macOS 14+, Xcode 16+, Swift 5.10+ и Zig 0.15+. Запустите `swift build`, затем `swift test`, или соберите локальное app через `./scripts/build-app.sh release`.
TEXT
      ;;
    th)
      cat <<'TEXT'
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

Cocxy ไม่มี analytics SDK, ไม่มี crash upload อัตโนมัติ และไม่มี backend สำหรับ terminal activity เครือข่ายใช้เฉพาะ signed updates หรือการกระทำที่ผู้ใช้สั่งชัดเจน

## Build จาก source

ต้องใช้ macOS 14+, Xcode 16+, Swift 5.10+ และ Zig 0.15+ รัน `swift build`, ตามด้วย `swift test`, หรือสร้าง app ภายในเครื่องด้วย `./scripts/build-app.sh release`
TEXT
      ;;
    tr)
      cat <<'TEXT'
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

Cocxy'de analytics SDK, otomatik crash upload veya terminal activity backend yoktur. Ağ yalnızca imzalı güncellemeler veya kullanıcının açıkça başlattığı işlemler için kullanılır.

## Kaynaktan build

macOS 14+, Xcode 16+, Swift 5.10+ ve Zig 0.15+ gerekir. `swift build`, ardından `swift test` çalıştırın veya `./scripts/build-app.sh release` ile yerel app oluşturun.
TEXT
      ;;
    uk)
      cat <<'TEXT'
> Цей локалізований README генерується з канонічного англомовного README.md. Після зміни джерела запустіть `scripts/translate-readme.sh`, щоб оновити hash.

## Огляд

Cocxy Terminal — це native macOS terminal, який розуміє сесії coding agent. Він поєднує GPU rendering через Metal, багаторівневий agent detection, вбудований code review, native Markdown workspace, локальні notebooks, вбудований browser і постійні SSH-сесії з zero telemetry.

## Встановлення

```bash
brew tap salp2403/tap && brew install --cask cocxy
```

Оновлення:

```bash
brew update && brew upgrade --cask cocxy
```

## Основні можливості

- Agent detection через hooks, OSC, pattern matching і timing, з Dashboard та Timeline для кожної сесії.
- Local-first Agent Mode з MCP servers, codebase indexing, skills, inline completions, sandboxed Computer Use і зашифрованими розмовами.
- Markdown workspace, Jupyter import/export, workflows, browser profiles, DevTools і повний CLI companion.
- CocxyCore надає terminal engine на Zig і Metal з ligatures, inline images, search і Protocol v2.
- Remote Workspaces охоплює SSH multiplexing, tmux/screen fallback, SFTP, proxy, relay і local daemon.

## Приватність і безпека

Cocxy не має analytics SDK, автоматичного crash upload або backend для terminal activity. Мережа використовується лише для підписаних оновлень або явних дій користувача.

## Build із source

Потрібні macOS 14+, Xcode 16+, Swift 5.10+ і Zig 0.15+. Запустіть `swift build`, потім `swift test`, або створіть локальний app через `./scripts/build-app.sh release`.
TEXT
      ;;
    vi)
      cat <<'TEXT'
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

Cocxy không có analytics SDK, không tự động crash upload và không có backend cho terminal activity. Mạng chỉ dùng cho signed updates hoặc hành động rõ ràng của người dùng.

## Build từ source

Cần macOS 14+, Xcode 16+, Swift 5.10+ và Zig 0.15+. Chạy `swift build`, sau đó `swift test`, hoặc tạo app cục bộ bằng `./scripts/build-app.sh release`.
TEXT
      ;;
    zh-CN)
      cat <<'TEXT'
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

Cocxy 没有 analytics SDK、没有自动 crash upload，也没有用于 terminal activity 的 backend。网络只用于签名更新或用户明确发起的操作。

## 从 source 构建

需要 macOS 14+、Xcode 16+、Swift 5.10+ 和 Zig 0.15+。运行 `swift build`、`swift test`，或使用 `./scripts/build-app.sh release` 构建本地 app。
TEXT
      ;;
    zh-TW)
      cat <<'TEXT'
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
TEXT
      ;;
  esac
}

generate_one() {
  local locale="$1"
  local output="$ROOT_DIR/README.$locale.md"
  local hash
  hash="$(source_hash)"

  {
    printf '# Cocxy Terminal\n\n'
    printf '<!-- cocxy-readme-source-sha256: %s -->\n' "$hash"
    printf '<!-- cocxy-readme-locale: %s -->\n\n' "$locale"
    language_links
    printf '\n'
    localized_body "$locale"
    printf '\n\n'
    technical_terms
    printf '\n\n## Links\n\n'
    printf -- '- [Website](https://cocxy.dev)\n'
    printf -- '- [GitHub Releases](https://github.com/salp2403/cocxy-terminal/releases)\n'
    printf -- '- [Security](SECURITY.md)\n'
    printf -- '- [License](LICENSE)\n'
  } > "$output"
}

main() {
  for locale in "${LOCALES[@]}"; do
    generate_one "$locale"
  done
  printf 'Generated %d localized README files from %s\n' "${#LOCALES[@]}" "$README_EN"
}

main "$@"
