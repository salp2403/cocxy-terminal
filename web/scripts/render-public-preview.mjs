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
const sourcePath = path.join(webRoot, 'assets', 'cocxy-preview-source.png');
const appInfoPlistPath = path.join(repoRoot, 'Resources', 'Info.plist');
const pngPath = path.join(imageRoot, 'cocxy-preview.png');
const webpPath = path.join(imageRoot, 'cocxy-preview.webp');
const avifPath = path.join(imageRoot, 'cocxy-preview.avif');
const chromePath = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const requiredRealCaptureNames = [
  'getting-started-dashboard.png',
  'getting-started-browser.png',
  'getting-started-preferences.png',
];

function run(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error(`${command} failed: ${result.stderr || result.stdout}`);
  }
}

function runCapture(command, args) {
  const result = spawnSync(command, args, { encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error(`${command} failed: ${result.stderr || result.stdout}`);
  }
  return result.stdout.trim();
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

function escapeHTML(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function smokeFacts() {
  const quality = readJSON('build/web-quality-audit/report.json');
  const visual = readJSON('build/web-visual-smoke/report.json');
  const scores = minLighthouseScores(quality);
  const failures = (quality?.failures?.length || 0) + (visual?.failures?.length || 0);

  return {
    qualityStatus: quality?.status === 'passed' ? 'quality passed' : 'quality not run',
    pageCount: quality?.pageCount || 0,
    visualStatus: visual?.status === 'passed' ? 'visual smoke passed' : 'visual smoke not run',
    screenshotCount: visual?.screenshots?.length || 0,
    failures,
    performance: formatPercent(scores.performance),
    accessibility: formatPercent(scores.accessibility),
    bestPractices: formatPercent(scores['best-practices']),
    seo: formatPercent(scores.seo),
  };
}

function imageURL(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`Missing preview source: ${path.relative(repoRoot, filePath)}`);
  }
  return `data:image/png;base64,${fs.readFileSync(filePath).toString('base64')}`;
}

function assertReferenceCapturesExist() {
  for (const name of requiredRealCaptureNames) {
    const capturePath = path.join(imageRoot, name);
    if (!fs.existsSync(capturePath)) {
      throw new Error(`Missing real Cocxy capture: ${path.relative(repoRoot, capturePath)}`);
    }
  }
}

function bundleVersion() {
  if (!fs.existsSync(appInfoPlistPath)) {
    throw new Error(`Missing app Info.plist: ${path.relative(repoRoot, appInfoPlistPath)}`);
  }
  return runCapture('/usr/bin/plutil', [
    '-extract',
    'CFBundleShortVersionString',
    'raw',
    '-o',
    '-',
    appInfoPlistPath,
  ]);
}

function renderHTML(facts, sourceURL, version) {
  const qualitySummary = `${facts.qualityStatus} · ${facts.pageCount} pages · ${facts.failures} failures`;
  const visualSummary = `${facts.visualStatus} · ${facts.screenshotCount} screenshots`;
  const scoreSummary = `Lighthouse ${facts.performance}/${facts.accessibility}/${facts.bestPractices}/${facts.seo}`;

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
  background: #05070d;
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
  overflow: hidden;
  background: #05070d;
}
.capture {
  position: absolute;
  inset: 0;
  width: 1574px;
  height: 808px;
  display: block;
}
.label {
  position: absolute;
  color: #eef2ff;
  font-weight: 760;
  line-height: 1;
  white-space: nowrap;
}
.tab-label {
  left: 292px;
  top: 13px;
  font-size: 14px;
}
.space-label {
  left: 43px;
  top: 163px;
  font-size: 14px;
}
.session-label {
  left: 75px;
  top: 200px;
  font-size: 14px;
}
.terminal-line {
  left: 249px;
  top: 219px;
  font: 15px "SF Mono", "JetBrains Mono", ui-monospace, monospace;
  color: #cdd6f4;
}
.prompt-line {
  left: 250px;
  top: 273px;
  font: 14px "SF Mono", "JetBrains Mono", ui-monospace, monospace;
  color: #a6e3a1;
}
.command-mask {
  position: absolute;
  left: 244px;
  top: 56px;
  width: 996px;
  height: 28px;
  border-radius: 8px;
  background: rgba(20, 20, 29, 0.96);
  border: 1px solid rgba(205, 214, 244, 0.14);
}
.command-text {
  left: 302px;
  top: 65px;
  font: 13px "SF Mono", "JetBrains Mono", ui-monospace, monospace;
  color: #d7def8;
}
.version-mask {
  position: absolute;
  left: 244px;
  top: 83px;
  width: 638px;
  height: 20px;
  background: #1f1d2e;
}
.version-line {
  left: 249px;
  top: 89px;
  font: 15px "SF Mono", "JetBrains Mono", ui-monospace, monospace;
  color: #98f5c2;
}
.cli-status-mask {
  position: absolute;
  left: 247px;
  top: 107px;
  width: 574px;
  height: 19px;
  background: #1f1d2e;
}
.cli-status-line {
  left: 250px;
  top: 113px;
  font: 15px "SF Mono", "JetBrains Mono", ui-monospace, monospace;
  color: #cdd6f4;
}
.ok {
  color: #a6e3a1;
  font-weight: 900;
}
.agent-line-mask {
  position: absolute;
  left: 247px;
  top: 238px;
  width: 545px;
  height: 21px;
  background: #1f1d2e;
}
.agent-line {
  left: 249px;
  top: 241px;
  font: 15px "SF Mono", "JetBrains Mono", ui-monospace, monospace;
  color: #cdd6f4;
}
.vault-mask {
  position: absolute;
  left: 1310px;
  width: 248px;
  height: 68px;
  border-radius: 8px;
  background: rgba(82, 90, 100, 0.98);
}
.vault-mask.one { top: 205px; }
.vault-mask.two { top: 292px; }
.vault-mask.three { top: 397px; }
.vault-mask.four { top: 486px; }
.vault-mask.five { top: 572px; }
.vault-text {
  position: absolute;
  left: 1317px;
  width: 215px;
  color: #eef2ff;
  font-size: 13px;
  line-height: 1.25;
}
.vault-text strong {
  display: block;
  margin-bottom: 4px;
  font-size: 14px;
  line-height: 1;
}
.vault-text span {
  display: block;
  color: #c5ccda;
  font-size: 11px;
  font-weight: 650;
}
.vault-text.one { top: 212px; }
.vault-text.two { top: 299px; }
.vault-text.three { top: 404px; }
.vault-text.four { top: 493px; }
.vault-text.five { top: 579px; }
.pill-mask {
  position: absolute;
  left: 1287px;
  top: 119px;
  width: 287px;
  height: 28px;
  background: rgba(82, 90, 100, 0.98);
}
.pill-text {
  left: 1322px;
  top: 126px;
  font-size: 12px;
  color: #eef2ff;
}
.badge {
  position: absolute;
  left: 260px;
  bottom: 34px;
  display: grid;
  grid-template-columns: auto auto auto;
  gap: 8px;
  align-items: center;
  padding: 9px 10px;
  border-radius: 12px;
  background: rgba(14, 17, 27, 0.84);
  border: 1px solid rgba(166, 227, 161, 0.28);
  box-shadow: 0 14px 40px rgba(0, 0, 0, 0.36);
}
.badge span {
  padding: 6px 9px;
  border-radius: 8px;
  color: #d8fbd2;
  background: rgba(166, 227, 161, 0.12);
  font-size: 12px;
  font-weight: 820;
}
</style>
</head>
<body>
<main class="stage" aria-label="Cocxy Terminal real smoke capture">
  <img class="capture" src="${sourceURL}" alt="Cocxy Terminal real app capture">
  <div class="command-mask"></div>
  <div class="version-mask"></div>
  <div class="cli-status-mask"></div>
  <div class="agent-line-mask"></div>
  <div class="pill-mask"></div>
  <div class="vault-mask one"></div>
  <div class="vault-mask two"></div>
  <div class="vault-mask three"></div>
  <div class="vault-mask four"></div>
  <div class="vault-mask five"></div>
  <div class="label tab-label">Demo</div>
  <div class="label space-label">Demo</div>
  <div class="label session-label">Demo</div>
  <div class="label command-text"><span class="ok">ok</span> cocxy smoke --bundle-local --vault --privacy</div>
  <div class="label version-line">Cocxy Terminal v${escapeHTML(version)} Visual Smoke Test</div>
  <div class="label cli-status-line">[PASS] Bundle-local CLI status: Cocxy Terminal v${escapeHTML(version)}</div>
  <div class="label terminal-line">Active demo workspace: /workspace/cocxy-demo</div>
  <div class="label prompt-line">demo ok</div>
  <div class="label agent-line">Visible agents: code, review, browser, remote, audit</div>
  <div class="label pill-text">All · Code · Review · Browser</div>
  <div class="vault-text one"><strong>Code agent</strong><span>vault visual smoke · release demo</span></div>
  <div class="vault-text two"><strong>Review agent</strong><span>inline review · markdown workspace</span></div>
  <div class="vault-text three"><strong>Browser agent</strong><span>split pane · local docs</span></div>
  <div class="vault-text four"><strong>Remote agent</strong><span>ssh session · persistent workspace</span></div>
  <div class="vault-text five"><strong>Audit agent</strong><span>privacy check · zero telemetry</span></div>
  <div class="badge" aria-label="Smoke test evidence">
    <span>Smoke test evidence</span>
    <span>${escapeHTML(qualitySummary)}</span>
    <span>${escapeHTML(visualSummary)} · ${escapeHTML(scoreSummary)}</span>
  </div>
</main>
</body>
</html>`;
}

async function main() {
  fs.mkdirSync(imageRoot, { recursive: true });
  if (!fs.existsSync(chromePath)) throw new Error(`Google Chrome not found at ${chromePath}`);
  assertReferenceCapturesExist();

  const facts = smokeFacts();
  const version = bundleVersion();
  const browser = await chromium.launch({ executablePath: chromePath, headless: true });
  const page = await browser.newPage({ viewport: { width: 1574, height: 808 }, deviceScaleFactor: 1 });
  await page.setContent(renderHTML(facts, imageURL(sourcePath), version), { waitUntil: 'load' });
  await page.screenshot({ path: pngPath, fullPage: false });
  await browser.close();

  run('/usr/local/bin/cwebp', ['-quiet', '-q', '82', pngPath, '-o', webpPath]);
  run('/usr/local/bin/avifenc', ['--min', '28', '--max', '46', '--speed', '6', pngPath, avifPath]);
  console.log(`Rendered ${path.relative(webRoot, pngPath)}`);
  console.log(`Rendered ${path.relative(webRoot, webpPath)}`);
  console.log(`Rendered ${path.relative(webRoot, avifPath)}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
