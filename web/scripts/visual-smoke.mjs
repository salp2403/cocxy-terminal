#!/usr/bin/env node
// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(__dirname, '..');
const repoRoot = path.resolve(webRoot, '..');
const reportRoot = path.join(repoRoot, 'build', 'web-visual-smoke');
const port = Number(process.env.COCXY_WEB_SMOKE_PORT || 3107);
const baseURL = `http://127.0.0.1:${port}`;
const chromePath = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const failures = [];
const consoleErrors = [];
const screenshots = [];

function fail(message) {
  failures.push(message);
}

function slugFor(url, viewport) {
  const name = url === '/' ? 'index' : url.replace(/^\//, '').replace(/\/$/, '').replaceAll('/', '-').replace(/\.html$/, '');
  return `${name}-${viewport.name}.png`;
}

async function waitForServer() {
  const deadline = Date.now() + 12000;
  while (Date.now() < deadline) {
    try {
      const response = await fetch(`${baseURL}/health`);
      if (response.ok) return;
    } catch (_) {}
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
  throw new Error('Local web server did not become healthy');
}

function startServer() {
  return spawn(process.execPath, ['server.js'], {
    cwd: webRoot,
    env: { ...process.env, PORT: String(port) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
}

async function verifyHeaders() {
  const response = await fetch(`${baseURL}/`);
  const csp = response.headers.get('content-security-policy') || '';
  const permissions = response.headers.get('permissions-policy') || '';
  const frameOptions = response.headers.get('x-frame-options') || '';
  if (!csp.includes("default-src 'self'")) fail('Missing self-only default CSP');
  if (!csp.includes("frame-ancestors 'none'")) fail('Missing frame-ancestors hardening');
  if (frameOptions.toUpperCase() !== 'DENY') fail(`X-Frame-Options is ${frameOptions || 'missing'}`);
  if (!permissions.includes('geolocation=()')) fail('Missing Permissions-Policy hardening');

  const redirect = await fetch(`${baseURL}/getting-started.html`, { redirect: 'manual' });
  if (redirect.status !== 301) fail(`getting-started redirect returned ${redirect.status}`);
  if (redirect.headers.get('location') !== '/docs/first-run.html') {
    fail(`getting-started redirect location is ${redirect.headers.get('location')}`);
  }
}

async function verifyPage(page, url, viewport) {
  await page.setViewportSize({ width: viewport.width, height: viewport.height });
  const response = await page.goto(`${baseURL}${url}`, { waitUntil: 'networkidle' });
  if (!response || !response.ok()) fail(`${url} returned ${response?.status() ?? 'no response'}`);

  const metrics = await page.evaluate(() => {
    const h1 = document.querySelector('h1');
    const video = document.querySelector('video');
    const firstSource = video?.querySelector('source');
    return {
      title: document.title,
      h1: h1?.textContent?.trim() || '',
      overflowX: Math.max(document.body.scrollWidth, document.documentElement.scrollWidth) - window.innerWidth,
      main: Boolean(document.querySelector('main#main')),
      themeButton: Boolean(document.querySelector('.theme-toggle')),
      videoSource: firstSource?.getAttribute('type') || '',
      imageCount: [...document.images].filter((image) => image.complete && image.naturalWidth > 0).length,
    };
  });

  if (!metrics.title.includes('Cocxy Terminal')) fail(`${url} title is missing Cocxy Terminal`);
  if (!metrics.h1) fail(`${url} has no h1`);
  if (!metrics.main) fail(`${url} has no main#main`);
  if (!metrics.themeButton) fail(`${url} has no theme toggle`);
  if (metrics.overflowX > 1) fail(`${url} ${viewport.name} horizontal overflow ${metrics.overflowX}px`);
  if ((url === '/' || url === '/es/') && metrics.videoSource !== 'video/webm') {
    fail(`${url} homepage video does not prefer WebM`);
  }
  if (metrics.imageCount === 0) fail(`${url} loaded no images`);

  const screenshot = path.join(reportRoot, slugFor(url, viewport));
  await page.screenshot({ path: screenshot, fullPage: false });
  screenshots.push(path.relative(repoRoot, screenshot));
}

async function verifyInteractions(page) {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto(`${baseURL}/docs/`, { waitUntil: 'networkidle' });
  await page.locator('[data-doc-search]').fill('ssh');
  await page.locator('[data-doc-search-results] a[href="/docs/ssh-remote.html"]').waitFor({ state: 'visible', timeout: 2500 });

  await page.goto(`${baseURL}/`, { waitUntil: 'networkidle' });
  const before = await page.evaluate(() => document.documentElement.dataset.theme || 'dark');
  await page.locator('.theme-toggle').click();
  const after = await page.evaluate(() => ({
    theme: document.documentElement.dataset.theme,
    stored: localStorage.getItem('cocxy-theme'),
  }));
  if (before === after.theme) fail('Theme toggle did not change theme');
  if (after.stored !== after.theme) fail('Theme toggle did not persist cocxy-theme');
}

async function main() {
  fs.mkdirSync(reportRoot, { recursive: true });
  if (!fs.existsSync(chromePath)) throw new Error(`Google Chrome not found at ${chromePath}`);
  const server = startServer();
  server.stderr.on('data', (data) => {
    const text = String(data).trim();
    if (text) consoleErrors.push(`server: ${text}`);
  });

  try {
    await waitForServer();
    await verifyHeaders();
    const browser = await chromium.launch({ executablePath: chromePath, headless: true });
    const page = await browser.newPage();
    page.on('console', (message) => {
      if (message.type() === 'error') consoleErrors.push(message.text());
    });
    page.on('pageerror', (error) => consoleErrors.push(error.message));

    const viewports = [
      { name: 'desktop', width: 1440, height: 1000 },
      { name: 'tablet', width: 768, height: 1024 },
      { name: 'mobile', width: 390, height: 844 },
      { name: 'narrow', width: 320, height: 700 },
    ];
    for (const viewport of viewports) {
      for (const url of ['/', '/es/', '/features.html', '/why-cocxy.html', '/privacy.html', '/docs/', '/features/agents.html']) {
        await verifyPage(page, url, viewport);
      }
    }
    await verifyInteractions(page);
    await browser.close();
  } finally {
    server.kill('SIGTERM');
  }

  if (consoleErrors.length) fail(`Console/server errors: ${consoleErrors.join(' | ')}`);
  const report = {
    status: failures.length ? 'failed' : 'passed',
    baseURL,
    screenshots,
    failures,
  };
  fs.writeFileSync(path.join(reportRoot, 'report.json'), `${JSON.stringify(report, null, 2)}\n`);
  if (failures.length) {
    console.error('Visual smoke failed:');
    for (const failure of failures) console.error(`- ${failure}`);
    process.exit(1);
  }
  console.log(`Visual smoke passed (${screenshots.length} screenshots). Report: ${path.relative(repoRoot, path.join(reportRoot, 'report.json'))}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
