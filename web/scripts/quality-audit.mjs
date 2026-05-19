#!/usr/bin/env node
// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import lighthouse from 'lighthouse';
import { launch } from 'chrome-launcher';
import { chromium } from 'playwright';
import { AxeBuilder } from '@axe-core/playwright';
import { HtmlValidate } from 'html-validate';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(__dirname, '..');
const repoRoot = path.resolve(webRoot, '..');
const publicRoot = path.join(webRoot, 'public');
const reportRoot = path.join(repoRoot, 'build', 'web-quality-audit');
const port = Number(process.env.COCXY_WEB_QUALITY_PORT || 3117);
const baseURL = `http://127.0.0.1:${port}`;
const chromePath = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const fullLighthouse = process.env.COCXY_WEB_QUALITY_FULL === '1';

const failures = [];
const consoleErrors = [];

const coreLighthouseUrls = [
  '/',
  '/features.html',
  '/why-cocxy.html',
  '/privacy.html',
  '/security.html',
  '/architecture.html',
  '/docs/',
  '/features/agents.html',
  '/es/',
  '/es/features.html',
  '/es/privacy.html',
  '/es/docs/',
];

function fail(message) {
  failures.push(message);
}

function walkFiles(dir, predicate, files = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const absolute = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkFiles(absolute, predicate, files);
    } else if (predicate(absolute)) {
      files.push(absolute);
    }
  }
  return files;
}

function urlForHtmlFile(file) {
  const relative = path.relative(publicRoot, file).split(path.sep).join('/');
  if (relative === 'index.html') return '/';
  if (relative.endsWith('/index.html')) return `/${relative.slice(0, -'index.html'.length)}`;
  return `/${relative}`;
}

function slugFor(url) {
  return (url === '/' ? 'index' : url.replace(/^\//, '').replace(/\/$/, '').replaceAll('/', '-').replace(/\.html$/, '')) || 'index';
}

function startServer() {
  return spawn(process.execPath, ['server.js'], {
    cwd: webRoot,
    env: { ...process.env, PORT: String(port) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
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

async function validateHtml(files) {
  const htmlvalidate = new HtmlValidate({
    extends: ['html-validate:recommended'],
    rules: {
      'no-inline-style': 'error',
      'require-sri': 'off',
    },
  });

  const results = [];
  for (const file of files) {
    const report = await htmlvalidate.validateFile(file);
    const messages = report.results.flatMap((result) => result.messages);
    if (!report.valid) {
      fail(`HTML validation failed for ${path.relative(repoRoot, file)}: ${messages.map((message) => `${message.ruleId} line ${message.line}`).join(', ')}`);
    }
    results.push({
      file: path.relative(repoRoot, file),
      valid: report.valid,
      messages: messages.map((message) => ({
        ruleId: message.ruleId,
        severity: message.severity,
        message: message.message,
        line: message.line,
        column: message.column,
      })),
    });
  }
  return results;
}

async function runAxe(urls) {
  const browser = await chromium.launch({ executablePath: chromePath, headless: true });
  const context = await browser.newContext();
  const page = await context.newPage();
  const results = [];
  page.on('console', (message) => {
    if (message.type() === 'error' && !message.text().includes('Failed to load resource')) {
      consoleErrors.push(`${page.url()}: ${message.text()}`);
    }
  });
  page.on('pageerror', (error) => consoleErrors.push(`${page.url()}: ${error.message}`));
  page.on('response', (response) => {
    const status = response.status();
    if (status >= 400) consoleErrors.push(`${response.url()} returned ${status}`);
  });

  try {
    for (const url of urls) {
      const response = await page.goto(`${baseURL}${url}`, { waitUntil: 'networkidle' });
      if (!response || !response.ok()) {
        fail(`Axe navigation failed for ${url}: ${response?.status() ?? 'no response'}`);
        continue;
      }
      const analysis = await new AxeBuilder({ page }).analyze();
      const violations = analysis.violations.map((violation) => ({
        id: violation.id,
        impact: violation.impact,
        description: violation.description,
        nodes: violation.nodes.map((node) => ({
          target: node.target,
          failureSummary: node.failureSummary,
        })),
      }));
      if (violations.length) {
        fail(`axe violations on ${url}: ${violations.map((violation) => `${violation.id}(${violation.nodes.length})`).join(', ')}`);
      }
      results.push({ url, violations });
    }
  } finally {
    await context.close();
    await browser.close();
  }
  return results;
}

function lighthouseThresholds(url) {
  const isDoc = url.includes('/docs/');
  return {
    performance: isDoc ? 0.9 : 0.95,
    accessibility: 1,
    'best-practices': 0.95,
    seo: 1,
  };
}

async function runLighthouse(urls) {
  const chrome = await launch({
    chromePath,
    chromeFlags: [
      '--headless=new',
      '--disable-gpu',
      '--no-sandbox',
      '--disable-dev-shm-usage',
    ],
  });
  const results = [];
  try {
    for (const url of urls) {
      const runnerResult = await lighthouse(`${baseURL}${url}`, {
        port: chrome.port,
        output: 'json',
        logLevel: 'error',
        onlyCategories: ['performance', 'accessibility', 'best-practices', 'seo'],
      }, {
        extends: 'lighthouse:default',
        settings: {
          formFactor: 'mobile',
          screenEmulation: {
            mobile: true,
            width: 390,
            height: 844,
            deviceScaleFactor: 2,
            disabled: false,
          },
          throttlingMethod: 'simulate',
        },
      });
      const lhr = runnerResult.lhr;
      const categories = Object.fromEntries(
        Object.entries(lhr.categories).map(([key, category]) => [key, category.score])
      );
      const thresholds = lighthouseThresholds(url);
      for (const [category, threshold] of Object.entries(thresholds)) {
        const score = categories[category] ?? 0;
        if (score < threshold) {
          fail(`Lighthouse ${category} on ${url} scored ${score}, below ${threshold}`);
        }
      }
      const reportPath = path.join(reportRoot, `lighthouse-${slugFor(url)}.json`);
      fs.writeFileSync(reportPath, runnerResult.report);
      results.push({
        url,
        scores: categories,
        report: path.relative(repoRoot, reportPath),
      });
    }
  } finally {
    await chrome.kill();
  }
  return results;
}

function verifyBudgets() {
  const cssFiles = walkFiles(path.join(publicRoot, 'css'), (file) => file.endsWith('.css'));
  const jsFiles = walkFiles(path.join(publicRoot, 'js'), (file) => file.endsWith('.js'));
  const cssGzip = cssFiles.reduce((total, file) => total + zlib.gzipSync(fs.readFileSync(file)).length, 0);
  const jsGzip = jsFiles.reduce((total, file) => total + zlib.gzipSync(fs.readFileSync(file)).length, 0);
  const heroAvif = path.join(publicRoot, 'images', 'cocxy-preview.avif');
  const heroWebp = path.join(publicRoot, 'images', 'cocxy-preview.webp');
  const webm = path.join(publicRoot, 'videos', 'cocxy-demo.webm');

  const budgets = {
    cssGzipBytes: cssGzip,
    cssGzipLimitBytes: 25 * 1024,
    jsGzipBytes: jsGzip,
    jsGzipLimitBytes: 15 * 1024,
    heroAvifBytes: fs.existsSync(heroAvif) ? fs.statSync(heroAvif).size : null,
    heroImageLimitBytes: 80 * 1024,
    heroWebpBytes: fs.existsSync(heroWebp) ? fs.statSync(heroWebp).size : null,
    webmBytes: fs.existsSync(webm) ? fs.statSync(webm).size : null,
  };

  if (budgets.cssGzipBytes > budgets.cssGzipLimitBytes) fail(`CSS gzip budget exceeded: ${budgets.cssGzipBytes} > ${budgets.cssGzipLimitBytes}`);
  if (budgets.jsGzipBytes > budgets.jsGzipLimitBytes) fail(`JS gzip budget exceeded: ${budgets.jsGzipBytes} > ${budgets.jsGzipLimitBytes}`);
  if (budgets.heroAvifBytes === null) fail('Missing AVIF hero image');
  if (budgets.heroWebpBytes === null) fail('Missing WebP hero image');
  if (budgets.heroAvifBytes !== null && budgets.heroAvifBytes > budgets.heroImageLimitBytes) {
    fail(`Hero AVIF budget exceeded: ${budgets.heroAvifBytes} > ${budgets.heroImageLimitBytes}`);
  }
  if (budgets.webmBytes === null) fail('Missing WebM demo video');

  return budgets;
}

async function main() {
  if (!fs.existsSync(chromePath)) throw new Error(`Google Chrome not found at ${chromePath}`);
  fs.mkdirSync(reportRoot, { recursive: true });

  const htmlFiles = walkFiles(publicRoot, (file) => file.endsWith('.html')).sort();
  const urls = htmlFiles.map(urlForHtmlFile).sort();
  const lighthouseUrls = fullLighthouse
    ? urls
    : coreLighthouseUrls.filter((url) => urls.includes(url));
  const report = {
    status: 'pending',
    baseURL,
    fullLighthouse,
    pageCount: urls.length,
    html: [],
    axe: [],
    lighthouse: [],
    budgets: {},
    failures,
  };

  const server = startServer();
  server.stderr.on('data', (data) => {
    const text = String(data).trim();
    if (text) consoleErrors.push(`server: ${text}`);
  });

  try {
    await waitForServer();
    report.html = await validateHtml(htmlFiles);
    report.budgets = verifyBudgets();
    report.axe = await runAxe(urls);
    report.lighthouse = await runLighthouse(lighthouseUrls);
  } finally {
    server.kill('SIGTERM');
  }

  if (consoleErrors.length) fail(`Console/server errors: ${consoleErrors.join(' | ')}`);
  report.status = failures.length ? 'failed' : 'passed';
  fs.writeFileSync(path.join(reportRoot, 'report.json'), `${JSON.stringify(report, null, 2)}\n`);

  if (failures.length) {
    console.error('Quality audit failed:');
    for (const failure of failures) console.error(`- ${failure}`);
    console.error(`Report: ${path.relative(repoRoot, path.join(reportRoot, 'report.json'))}`);
    process.exit(1);
  }

  console.log(`Quality audit passed (${urls.length} pages, ${lighthouseUrls.length} Lighthouse runs). Report: ${path.relative(repoRoot, path.join(reportRoot, 'report.json'))}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
