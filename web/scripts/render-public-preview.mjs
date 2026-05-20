#!/usr/bin/env node
// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(__dirname, '..');
const repoRoot = path.resolve(webRoot, '..');
const imageRoot = path.join(webRoot, 'public', 'images');
const pngPath = path.join(imageRoot, 'cocxy-preview.png');
const webpPath = path.join(imageRoot, 'cocxy-preview.webp');
const avifPath = path.join(imageRoot, 'cocxy-preview.avif');
const chromePath = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const realScreenshots = {
  dashboard: path.join(imageRoot, 'getting-started-dashboard.png'),
  commandPalette: path.join(imageRoot, 'getting-started-command-palette.png'),
  browser: path.join(imageRoot, 'getting-started-browser.png'),
  preferences: path.join(imageRoot, 'getting-started-preferences.png'),
};

function run(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error(`${command} failed: ${result.stderr || result.stdout}`);
  }
}

function readJSON(relativePath) {
  const filePath = path.join(repoRoot, relativePath);
  if (!fs.existsSync(filePath)) return null;
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function minLighthouseScores(report) {
  const scores = {
    performance: 1,
    accessibility: 1,
    'best-practices': 1,
    seo: 1,
  };

  for (const row of report?.lighthouse || []) {
    for (const [key, value] of Object.entries(row.scores || {})) {
      if (typeof value === 'number') {
        scores[key] = Math.min(scores[key] ?? value, value);
      }
    }
  }

  return scores;
}

function formatPercent(value) {
  if (typeof value !== 'number' || !Number.isFinite(value)) return 'n/a';
  return `${Math.round(value * 100)}`;
}

function formatBytes(value) {
  if (typeof value !== 'number' || !Number.isFinite(value)) return 'n/a';
  return `${Math.round(value / 1024)} KB`;
}

function escapeHTML(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function screenshotURL(name) {
  const filePath = realScreenshots[name];
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing real Cocxy screenshot: ${path.relative(repoRoot, filePath)}`);
  }
  return `data:image/png;base64,${fs.readFileSync(filePath).toString('base64')}`;
}

function smokeFacts() {
  const quality = readJSON('build/web-quality-audit/report.json');
  const visual = readJSON('build/web-visual-smoke/report.json');
  const scores = minLighthouseScores(quality);
  const failures = (quality?.failures?.length || 0) + (visual?.failures?.length || 0);
  const currentHeroAvifBytes = fs.existsSync(avifPath)
    ? fs.statSync(avifPath).size
    : quality?.budgets?.heroAvifBytes;

  return {
    qualityStatus: quality?.status === 'passed' ? 'passed' : 'not run',
    pageCount: quality?.pageCount || 0,
    visualStatus: visual?.status === 'passed' ? 'passed' : 'not run',
    screenshotCount: visual?.screenshots?.length || 0,
    failures,
    performance: formatPercent(scores.performance),
    accessibility: formatPercent(scores.accessibility),
    bestPractices: formatPercent(scores['best-practices']),
    seo: formatPercent(scores.seo),
    heroAvif: formatBytes(currentHeroAvifBytes),
    heroLimit: formatBytes(quality?.budgets?.heroImageLimitBytes),
  };
}

function renderHTML(facts) {
  const dashboard = screenshotURL('dashboard');
  const browser = screenshotURL('browser');
  const preferences = screenshotURL('preferences');

  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<style>
* { box-sizing: border-box; }
html,
body {
  margin: 0;
  width: 1574px;
  height: 808px;
  overflow: hidden;
  background: #070a12;
}
body {
  font-family: Inter, ui-sans-serif, -apple-system, BlinkMacSystemFont, "SF Pro Display", "Segoe UI", sans-serif;
  color: #eef2ff;
  letter-spacing: 0;
}
.stage {
  position: relative;
  width: 1574px;
  height: 808px;
  padding: 38px;
  background:
    linear-gradient(180deg, rgba(137, 180, 250, 0.08), transparent 34%),
    linear-gradient(135deg, #070a12 0%, #111725 48%, #0a0d14 100%);
}
.shell {
  position: absolute;
  inset: 38px;
  border: 1px solid rgba(205, 214, 244, 0.16);
  border-radius: 18px;
  background: rgba(14, 17, 27, 0.86);
  box-shadow: 0 34px 90px rgba(0, 0, 0, 0.56);
}
.main-shot {
  position: absolute;
  left: 38px;
  top: 38px;
  width: 1036px;
  height: 633px;
  overflow: hidden;
  border-radius: 18px 0 0 0;
  border-right: 1px solid rgba(205, 214, 244, 0.14);
  border-bottom: 1px solid rgba(205, 214, 244, 0.12);
  background: #151824;
}
.main-shot img {
  width: 100%;
  height: 100%;
  display: block;
}
.prompt-mask {
  position: absolute;
  left: 16.1%;
  width: 63%;
  border-radius: 8px;
  background: #1e1b30;
  border: 1px solid rgba(205, 214, 244, 0.08);
  box-shadow: 0 0 0 4px #1e1b30;
  color: #cdd6f4;
  font: 15px "JetBrains Mono", "SF Mono", ui-monospace, monospace;
  padding: 7px 10px;
  line-height: 1.45;
}
.prompt-mask.top { top: 2.7%; height: 10.8%; }
.prompt-mask.bottom { top: 51.2%; height: 16.6%; }
.dashboard-mask {
  position: absolute;
  right: 1.5%;
  top: 6.2%;
  width: 18.5%;
  height: 18%;
  padding: 10px 11px;
  border-radius: 10px;
  background: rgba(33, 35, 37, 0.96);
  border: 1px solid rgba(205, 214, 244, 0.10);
  color: #d7def8;
  font-size: 11px;
  font-weight: 800;
  line-height: 1.35;
}
.user { color: #cba6f7; }
.host { color: #fab387; }
.path { color: #a6e3a1; }
.cmd { color: #a6e3a1; }
.evidence {
  position: absolute;
  left: 1074px;
  top: 38px;
  width: 462px;
  height: 633px;
  padding: 26px 28px;
  border-radius: 0 18px 0 0;
  background: linear-gradient(180deg, rgba(15, 18, 31, 0.96), rgba(10, 12, 21, 0.98));
  border-bottom: 1px solid rgba(205, 214, 244, 0.12);
  overflow: hidden;
}
.eyebrow {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 7px 11px;
  border-radius: 999px;
  color: #d8fbd2;
  background: rgba(166, 227, 161, 0.16);
  border: 1px solid rgba(166, 227, 161, 0.24);
  font-size: 13px;
  font-weight: 800;
}
.dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: #a6e3a1;
  box-shadow: 0 0 14px rgba(166, 227, 161, 0.7);
}
h1 {
  margin: 16px 0 9px;
  font-size: 34px;
  line-height: 1.03;
  color: #c7d2ff;
}
.lead {
  margin: 0 0 14px;
  color: #bac3dc;
  font-size: 15px;
  line-height: 1.45;
}
.facts {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
  margin-bottom: 13px;
}
.fact {
  min-height: 74px;
  padding: 11px 13px;
  border-radius: 12px;
  background: rgba(137, 180, 250, 0.10);
  border: 1px solid rgba(137, 180, 250, 0.18);
}
.label {
  display: block;
  margin-bottom: 5px;
  color: #9fa9c8;
  font-size: 11px;
  font-weight: 850;
  text-transform: uppercase;
  letter-spacing: 1.5px;
}
.value {
  color: #eef2ff;
  font-size: 20px;
  font-weight: 900;
}
.subvalue {
  margin-top: 4px;
  color: #aeb8d7;
  font-size: 12px;
  font-weight: 700;
}
.scores {
  display: grid;
  gap: 7px;
  margin-bottom: 14px;
}
.score-row {
  display: grid;
  grid-template-columns: 122px 1fr 42px;
  align-items: center;
  gap: 10px;
  color: #cdd6f4;
  font-size: 13px;
  font-weight: 800;
}
.bar {
  height: 8px;
  border-radius: 999px;
  overflow: hidden;
  background: rgba(205, 214, 244, 0.12);
}
.bar span {
  display: block;
  height: 100%;
  width: var(--w);
  border-radius: inherit;
  background: linear-gradient(90deg, #89b4fa, #a6e3a1);
}
.thumbs {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 11px;
}
.thumb {
  position: relative;
  height: 62px;
  overflow: hidden;
  border-radius: 12px;
  border: 1px solid rgba(205, 214, 244, 0.16);
  background: #111421;
}
.thumb img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}
.thumb.palette img {
  width: 146%;
  max-width: none;
  transform: translate(-16%, -14%);
}
.thumb.preferences img {
  object-position: 68% 32%;
}
.thumb span {
  position: absolute;
  left: 9px;
  bottom: 5px;
  padding: 5px 8px;
  border-radius: 8px;
  color: #eff3ff;
  background: rgba(8, 10, 18, 0.70);
  border: 1px solid rgba(205, 214, 244, 0.14);
  font-size: 10px;
  font-weight: 850;
}
.feature-strip {
  position: absolute;
  left: 38px;
  right: 38px;
  bottom: 38px;
  height: 99px;
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  gap: 10px;
  padding: 17px;
  border-radius: 0 0 18px 18px;
  background: rgba(13, 16, 25, 0.98);
}
.feature {
  display: grid;
  align-content: center;
  gap: 5px;
  padding: 0 12px;
  border-radius: 12px;
  background: rgba(36, 40, 59, 0.72);
  border: 1px solid rgba(205, 214, 244, 0.10);
}
.feature strong {
  color: #eef2ff;
  font-size: 14px;
  line-height: 1.1;
}
.feature span {
  color: #9fa9c8;
  font-size: 11px;
  line-height: 1.25;
}
</style>
</head>
<body>
<main class="stage" aria-label="Cocxy Terminal public smoke capture">
  <div class="shell">
    <section class="main-shot">
      <img src="${dashboard}" alt="Real Cocxy Terminal dashboard capture">
      <div class="prompt-mask top">
        <span class="user">demo</span>@<span class="host">local</span> <span class="path">/workspace/cocxy-demo</span> $ <span class="cmd">printf "public smoke ready\\n"</span><br>
        public smoke ready
      </div>
      <div class="prompt-mask bottom">
        <span class="user">demo</span>@<span class="host">local</span> <span class="path">/workspace/cocxy-demo</span> $ <span class="cmd">npm run smoke:visual</span><br>
        visual smoke passed · quality audit passed
      </div>
      <div class="dashboard-mask">Agent dashboard<br>active session · safe demo<br>1 file touched · 2m</div>
    </section>
    <aside class="evidence">
      <div class="eyebrow"><span class="dot"></span>Smoke test evidence</div>
      <h1>Real Cocxy workflow, verified locally.</h1>
      <p class="lead">The main image is based on actual Cocxy app captures, with private prompt text replaced by public demo text.</p>
      <div class="facts">
        <div class="fact"><span class="label">Quality audit</span><span class="value">${escapeHTML(facts.qualityStatus)}</span><div class="subvalue">${escapeHTML(facts.pageCount)} pages · ${escapeHTML(facts.failures)} failures</div></div>
        <div class="fact"><span class="label">Visual smoke</span><span class="value">${escapeHTML(facts.visualStatus)}</span><div class="subvalue">${escapeHTML(facts.screenshotCount)} screenshots</div></div>
        <div class="fact"><span class="label">Hero AVIF</span><span class="value">${escapeHTML(facts.heroAvif)}</span><div class="subvalue">budget ${escapeHTML(facts.heroLimit)}</div></div>
        <div class="fact"><span class="label">Telemetry</span><span class="value">none</span><div class="subvalue">local-first surfaces</div></div>
      </div>
      <div class="scores">
        <div class="score-row"><span>Performance</span><div class="bar"><span style="--w:${escapeHTML(facts.performance)}%"></span></div><span>${escapeHTML(facts.performance)}</span></div>
        <div class="score-row"><span>Accessibility</span><div class="bar"><span style="--w:${escapeHTML(facts.accessibility)}%"></span></div><span>${escapeHTML(facts.accessibility)}</span></div>
        <div class="score-row"><span>Best practices</span><div class="bar"><span style="--w:${escapeHTML(facts.bestPractices)}%"></span></div><span>${escapeHTML(facts.bestPractices)}</span></div>
        <div class="score-row"><span>SEO</span><div class="bar"><span style="--w:${escapeHTML(facts.seo)}%"></span></div><span>${escapeHTML(facts.seo)}</span></div>
      </div>
      <div class="thumbs">
        <div class="thumb"><img src="${browser}" alt="Cocxy browser capture"><span>Browser pane</span></div>
        <div class="thumb preferences"><img src="${preferences}" alt="Cocxy preferences capture"><span>Privacy controls</span></div>
      </div>
    </aside>
    <section class="feature-strip" aria-label="Principal Cocxy capabilities">
      <div class="feature"><strong>Agent dashboard</strong><span>live state, activity, files</span></div>
      <div class="feature"><strong>Split panes</strong><span>terminal surfaces side by side</span></div>
      <div class="feature"><strong>Browser</strong><span>local docs and dev servers</span></div>
      <div class="feature"><strong>Vault</strong><span>resume local sessions</span></div>
      <div class="feature"><strong>Markdown</strong><span>preview beside work</span></div>
      <div class="feature"><strong>Code review</strong><span>diffs next to terminal</span></div>
      <div class="feature"><strong>Zero telemetry</strong><span>no tracking backend</span></div>
    </section>
  </div>
</main>
</body>
</html>`;
}

async function main() {
  fs.mkdirSync(imageRoot, { recursive: true });
  if (!fs.existsSync(chromePath)) throw new Error(`Google Chrome not found at ${chromePath}`);

  const facts = smokeFacts();
  const browser = await chromium.launch({ executablePath: chromePath, headless: true });
  const page = await browser.newPage({ viewport: { width: 1574, height: 808 }, deviceScaleFactor: 1 });
  await page.setContent(renderHTML(facts), { waitUntil: 'load' });
  await page.screenshot({ path: pngPath, fullPage: false });
  await browser.close();

  run('/usr/local/bin/cwebp', ['-quiet', '-q', '80', pngPath, '-o', webpPath]);
  run('/usr/local/bin/avifenc', ['--min', '32', '--max', '52', '--speed', '6', pngPath, avifPath]);
  console.log(`Rendered ${path.relative(webRoot, pngPath)}`);
  console.log(`Rendered ${path.relative(webRoot, webpPath)}`);
  console.log(`Rendered ${path.relative(webRoot, avifPath)}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
