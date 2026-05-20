#!/usr/bin/env node
// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(__dirname, '..');
const imageRoot = path.join(webRoot, 'public', 'images');
const pngPath = path.join(imageRoot, 'cocxy-preview.png');
const webpPath = path.join(imageRoot, 'cocxy-preview.webp');
const avifPath = path.join(imageRoot, 'cocxy-preview.avif');
const chromePath = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

function run(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error(`${command} failed: ${result.stderr || result.stdout}`);
  }
}

const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<style>
* { box-sizing: border-box; }
html, body { margin: 0; width: 1917px; height: 1049px; overflow: hidden; background: #090b12; }
body {
  font-family: Inter, ui-sans-serif, -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", sans-serif;
  color: #eff2ff;
  letter-spacing: 0;
}
.stage {
  width: 1917px;
  height: 1049px;
  padding: 44px 52px;
  background:
    radial-gradient(circle at 20% 20%, rgba(137, 180, 250, 0.18), transparent 30%),
    radial-gradient(circle at 83% 22%, rgba(166, 227, 161, 0.12), transparent 30%),
    linear-gradient(135deg, #090b12 0%, #101422 52%, #0b0e16 100%);
}
.window {
  width: 100%;
  height: 100%;
  border: 1px solid rgba(205, 214, 244, 0.18);
  border-radius: 22px;
  overflow: hidden;
  background: rgba(24, 26, 39, 0.92);
  box-shadow: 0 40px 110px rgba(0, 0, 0, 0.58);
}
.titlebar {
  height: 52px;
  display: grid;
  grid-template-columns: 210px 1fr 250px;
  align-items: center;
  padding: 0 20px;
  background: linear-gradient(180deg, #4b4c54, #393b46);
  border-bottom: 1px solid rgba(255,255,255,0.08);
}
.traffic { display: flex; gap: 10px; }
.traffic span { width: 13px; height: 13px; border-radius: 50%; display: block; }
.red { background: #ff6b6b; } .yellow { background: #f9e2af; } .green { background: #a6e3a1; }
.tabs { display: flex; align-items: end; gap: 4px; height: 52px; }
.tab {
  height: 42px;
  min-width: 146px;
  padding: 0 18px;
  display: flex;
  align-items: center;
  gap: 10px;
  border-radius: 12px 12px 0 0;
  color: #b7c0dc;
  background: rgba(38, 41, 58, 0.72);
  font-size: 15px;
  font-weight: 650;
}
.tab.active { color: #eef2ff; background: #2b2f43; }
.tab-dot { width: 8px; height: 8px; border-radius: 50%; background: #89b4fa; box-shadow: 0 0 14px #89b4fa; }
.toolbar-icons { display: flex; justify-content: flex-end; gap: 11px; color: #8e98b6; font-size: 19px; }
.app {
  height: calc(100% - 52px);
  display: grid;
  grid-template-columns: 270px 1fr 560px;
}
.sidebar {
  position: relative;
  padding: 26px 18px;
  background: linear-gradient(180deg, #1b2434 0%, #171c26 62%, #222315 100%);
  border-right: 1px solid rgba(205, 214, 244, 0.13);
}
.side-head {
  display: flex;
  justify-content: space-between;
  color: #aab3d1;
  font-size: 12px;
  letter-spacing: 3px;
  text-transform: uppercase;
  font-weight: 850;
  margin-bottom: 20px;
}
.workspace {
  position: relative;
  display: grid;
  grid-template-columns: 10px 1fr auto;
  gap: 13px;
  align-items: center;
  min-height: 76px;
  padding: 14px 13px;
  margin-bottom: 12px;
  border-radius: 14px;
  background: rgba(116, 129, 170, 0.12);
  border: 1px solid rgba(205, 214, 244, 0.09);
}
.workspace.active { background: rgba(137, 180, 250, 0.16); border-color: rgba(137, 180, 250, 0.36); }
.rail { width: 4px; height: 48px; border-radius: 4px; background: #89b4fa; }
.rail.orange { background: #fab387; } .rail.green { background: #a6e3a1; } .rail.pink { background: #f5c2e7; }
.ws-title { font-size: 17px; font-weight: 800; color: #edf1ff; margin-bottom: 5px; }
.ws-sub { font-size: 13px; color: #aab3d1; display: flex; gap: 7px; align-items: center; }
.pulse { width: 8px; height: 8px; border-radius: 50%; background: #a6e3a1; box-shadow: 0 0 15px #a6e3a1; }
.status { font-size: 12px; color: #939bb9; }
.new-tab {
  position: absolute;
  left: 18px;
  bottom: 24px;
  width: 96px;
  padding: 10px 12px;
  border-radius: 11px;
  background: rgba(137, 180, 250, 0.12);
  color: #dbe5ff;
  font-size: 13px;
  font-weight: 800;
}
.terminal-area {
  display: grid;
  grid-template-rows: 56% 44%;
  background: #262b3a;
}
.pane {
  position: relative;
  padding: 25px 28px;
  border-bottom: 1px solid rgba(0,0,0,0.48);
  background:
    radial-gradient(circle at 72% 6%, rgba(137, 180, 250, 0.08), transparent 30%),
    #292d3d;
}
.pane.review { border-bottom: 0; background: #252a38; }
.prompt { font: 18px "JetBrains Mono", "SF Mono", ui-monospace, monospace; color: #cdd6f4; margin-bottom: 17px; }
.user { color: #cba6f7; } .host { color: #fab387; } .cmd { color: #a6e3a1; }
.terminal-card {
  border: 1px solid rgba(205,214,244,0.13);
  border-radius: 16px;
  overflow: hidden;
  background: rgba(13, 15, 24, 0.64);
}
.card-head {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 12px 16px;
  background: rgba(49, 53, 74, 0.76);
  border-bottom: 1px solid rgba(205,214,244,0.1);
  color: #cdd6f4;
  font-size: 14px;
  font-weight: 850;
}
.badge {
  display: inline-flex;
  align-items: center;
  gap: 7px;
  padding: 6px 10px;
  border-radius: 999px;
  background: rgba(137,180,250,0.16);
  color: #dbe7ff;
  font-size: 12px;
  font-weight: 850;
}
table { width: 100%; border-collapse: collapse; font: 15px "JetBrains Mono", ui-monospace, monospace; }
th, td { text-align: left; padding: 12px 16px; border-bottom: 1px solid rgba(205,214,244,0.08); }
th { color: #8f9abd; font-size: 12px; text-transform: uppercase; letter-spacing: 1.4px; }
td { color: #dbe2ff; }
.state { color: #a6e3a1; } .wait { color: #f9e2af; } .think { color: #89b4fa; } .done { color: #94e2d5; }
.review-grid { display: grid; grid-template-columns: 210px 1fr; height: 245px; }
.files { background: rgba(15,18,30,0.54); border-right: 1px solid rgba(205,214,244,0.08); padding: 14px; }
.file { padding: 10px 12px; border-radius: 9px; color: #aab3d1; font: 13px "JetBrains Mono", ui-monospace, monospace; margin-bottom: 5px; }
.file.active { background: rgba(137,180,250,0.15); color: #eff4ff; }
.diff { padding: 16px 19px; font: 14px "JetBrains Mono", ui-monospace, monospace; line-height: 1.65; color: #cdd6f4; }
.add { color: #a6e3a1; } .del { color: #f38ba8; } .muted { color: #7f88a6; }
.right {
  display: grid;
  grid-template-rows: 44% 56%;
  background: #111421;
  border-left: 1px solid rgba(205,214,244,0.12);
}
.browser, .inspector { padding: 20px; }
.url {
  height: 36px;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 0 13px;
  border: 1px solid rgba(205,214,244,0.16);
  border-radius: 11px;
  background: rgba(11,13,22,0.82);
  color: #cdd6f4;
  font: 13px "JetBrains Mono", ui-monospace, monospace;
}
.browser-page {
  margin-top: 17px;
  height: 302px;
  border: 1px solid rgba(205,214,244,0.12);
  border-radius: 18px;
  overflow: hidden;
  background:
    radial-gradient(circle at 50% 10%, rgba(137,180,250,0.17), transparent 36%),
    #0a0b14;
  padding: 26px;
}
.site-brand { display: flex; gap: 10px; align-items: center; color: #eef2ff; font-weight: 900; margin-bottom: 24px; }
.logo-box { width: 34px; height: 34px; border-radius: 10px; background: #24273a; display: grid; place-items: center; color: #89b4fa; font: 22px "JetBrains Mono"; }
.browser-page h1 { margin: 0 0 12px; font-size: 40px; line-height: 1.05; color: #bfd0ff; }
.browser-page p { margin: 0 0 20px; color: #b7c0dc; font-size: 17px; line-height: 1.45; }
.mini-cards { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }
.mini-card { padding: 14px; border-radius: 14px; background: rgba(137,180,250,0.11); border: 1px solid rgba(137,180,250,0.22); color: #dbe5ff; font-size: 13px; font-weight: 800; }
.inspector {
  display: grid;
  grid-template-rows: auto 1fr;
  gap: 16px;
}
.segmented { display: flex; gap: 8px; }
.segment { padding: 9px 12px; border-radius: 11px; background: rgba(205,214,244,0.08); color: #aab3d1; font-size: 13px; font-weight: 850; }
.segment.active { background: rgba(166,227,161,0.16); color: #d7ffdc; }
.vault {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 14px;
}
.panel {
  border-radius: 18px;
  padding: 18px;
  background: rgba(35, 39, 57, 0.72);
  border: 1px solid rgba(205,214,244,0.11);
}
.panel h2 { margin: 0 0 12px; font-size: 18px; color: #eef2ff; }
.session { padding: 11px 0; border-bottom: 1px solid rgba(205,214,244,0.08); color: #b7c0dc; font-size: 14px; }
.session strong { color: #eef2ff; display: block; margin-bottom: 4px; }
.markdown {
  font-size: 14px;
  line-height: 1.55;
  color: #cdd6f4;
}
.markdown code {
  display: block;
  margin-top: 12px;
  padding: 12px;
  border-radius: 12px;
  background: #10131f;
  color: #a6e3a1;
  font-family: "JetBrains Mono", ui-monospace, monospace;
}
.statusbar {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 0;
  height: 27px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0 18px;
  background: rgba(19, 21, 17, 0.92);
  border-top: 1px solid rgba(205,214,244,0.09);
  color: #9ca6c7;
  font: 12px "JetBrains Mono", ui-monospace, monospace;
}
</style>
</head>
<body>
<div class="stage">
  <div class="window">
    <div class="titlebar">
      <div class="traffic"><span class="red"></span><span class="yellow"></span><span class="green"></span></div>
      <div class="tabs">
        <div class="tab active"><span class="tab-dot"></span>api-server</div>
        <div class="tab">web-client</div>
        <div class="tab">Review</div>
        <div class="tab">Vault</div>
        <div class="tab">Browser</div>
      </div>
      <div class="toolbar-icons"><span>+</span><span>⌘K</span><span>◫</span><span>⌁</span></div>
    </div>
    <div class="app">
      <aside class="sidebar">
        <div class="side-head"><span>Workspaces</span><span>⌕  ●</span></div>
        <div class="workspace active"><span class="rail"></span><div><div class="ws-title">api-server</div><div class="ws-sub"><span class="pulse"></span>Codex working</div></div><span class="status">2m</span></div>
        <div class="workspace"><span class="rail orange"></span><div><div class="ws-title">web-client</div><div class="ws-sub"><span class="pulse"></span>Claude waiting</div></div><span class="status">9m</span></div>
        <div class="workspace"><span class="rail green"></span><div><div class="ws-title">remote-lab</div><div class="ws-sub"><span class="pulse"></span>SSH connected</div></div><span class="status">live</span></div>
        <div class="workspace"><span class="rail pink"></span><div><div class="ws-title">docs-site</div><div class="ws-sub"><span class="pulse"></span>Review ready</div></div><span class="status">ok</span></div>
        <div class="new-tab">+ New Tab</div>
      </aside>
      <main class="terminal-area">
        <section class="pane">
          <div class="prompt"><span class="user">dev</span>@<span class="host">local</span> ~/projects/api-server <span class="cmd">$ cocxy agents --watch</span></div>
          <div class="terminal-card">
            <div class="card-head"><span>Agent dashboard</span><span class="badge"><span class="pulse"></span>11 profiles · zero telemetry</span></div>
            <table>
              <thead><tr><th>Agent</th><th>State</th><th>Surface</th><th>Last action</th></tr></thead>
              <tbody>
                <tr><td>Codex</td><td class="state">working</td><td>PTY + review</td><td>writing tests</td></tr>
                <tr><td>Claude</td><td class="wait">waiting</td><td>team pane</td><td>needs input</td></tr>
                <tr><td>OpenCode</td><td class="done">done</td><td>Vault</td><td>session saved</td></tr>
                <tr><td>Gemini</td><td class="think">thinking</td><td>browser</td><td>checking localhost</td></tr>
              </tbody>
            </table>
          </div>
        </section>
        <section class="pane review">
          <div class="prompt"><span class="user">dev</span>@<span class="host">local</span> ~/projects/api-server <span class="cmd">$ cocxy review open --session current</span></div>
          <div class="terminal-card">
            <div class="card-head"><span>Inline code review</span><span class="badge">3 files changed · 147 insertions</span></div>
            <div class="review-grid">
              <div class="files">
                <div class="file active">M Sources/API/RateLimit.swift</div>
                <div class="file">M Tests/API/RateLimitTests.swift</div>
                <div class="file">A Docs/Runbook.md</div>
              </div>
              <div class="diff">
                <div class="muted">@@ middleware request scope @@</div>
                <div class="del">- let limit = defaultLimit</div>
                <div class="add">+ let limit = policy.limit(for: route)</div>
                <div class="add">+ audit.record("rate-limit", visibility: .private)</div>
                <div class="muted">Comment: keep request IDs public, paths private.</div>
              </div>
            </div>
          </div>
        </section>
      </main>
      <aside class="right">
        <section class="browser">
          <div class="url">⌁ http://localhost:3000/docs/first-run.html</div>
          <div class="browser-page">
            <div class="site-brand"><div class="logo-box">&gt;_</div><span>Cocxy Terminal</span></div>
            <h1>Local-first agent workspace</h1>
            <p>Terminal, browser, Markdown, Vault, remotes, and review stay visible in one native macOS surface.</p>
            <div class="mini-cards"><div class="mini-card">11 agents detected</div><div class="mini-card">Encrypted Vault</div><div class="mini-card">Remote SSH panes</div><div class="mini-card">No telemetry</div></div>
          </div>
        </section>
        <section class="inspector">
          <div class="segmented"><div class="segment active">Vault</div><div class="segment">Markdown</div><div class="segment">Remote</div></div>
          <div class="vault">
            <div class="panel">
              <h2>Encrypted Vault</h2>
              <div class="session"><strong>api-server rate limit</strong>Codex · resumable · local</div>
              <div class="session"><strong>docs first run</strong>Claude · waiting for input</div>
              <div class="session"><strong>remote build pane</strong>SSH · attached</div>
            </div>
            <div class="panel markdown">
              <h2>Markdown workspace</h2>
              <p>Release notes, runbooks, and review feedback live next to terminal output.</p>
              <code># Smoke result
status: passed
privacy: verified</code>
            </div>
          </div>
        </section>
      </aside>
    </div>
    <div class="statusbar"><span>demo@local · public workspace</span><span>agent: working · ports: 3000 4000 5000 · zero telemetry</span></div>
  </div>
</div>
</body>
</html>`;

async function main() {
  fs.mkdirSync(imageRoot, { recursive: true });
  if (!fs.existsSync(chromePath)) throw new Error(`Google Chrome not found at ${chromePath}`);
  const browser = await chromium.launch({ executablePath: chromePath, headless: true });
  const page = await browser.newPage({ viewport: { width: 1917, height: 1049 }, deviceScaleFactor: 1 });
  await page.setContent(html, { waitUntil: 'load' });
  await page.screenshot({ path: pngPath, fullPage: false });
  await browser.close();

  run('/usr/local/bin/cwebp', ['-quiet', '-q', '82', pngPath, '-o', webpPath]);
  run('/usr/local/bin/avifenc', ['--min', '24', '--max', '38', '--speed', '6', pngPath, avifPath]);
  console.log(`Rendered ${path.relative(webRoot, pngPath)}`);
  console.log(`Rendered ${path.relative(webRoot, webpPath)}`);
  console.log(`Rendered ${path.relative(webRoot, avifPath)}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
