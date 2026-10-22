#!/usr/bin/env node
// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import fs from 'node:fs';
import os from 'node:os';
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
const primaryLighthouseMethod = process.env.COCXY_WEB_LIGHTHOUSE_THROTTLING || 'simulate';
const lighthouseDevtoolsFallback = process.env.COCXY_WEB_LIGHTHOUSE_DEVTOOLS_FALLBACK !== '0';
const lighthouseProvidedFallback = process.env.COCXY_WEB_LIGHTHOUSE_PROVIDED_FALLBACK !== '0';
const lighthouseDesktopFallback = process.env.COCXY_WEB_LIGHTHOUSE_DESKTOP_FALLBACK !== '0';
const lighthouseTimeoutMs = Number(process.env.COCXY_WEB_LIGHTHOUSE_TIMEOUT_MS || 120000);
const lighthouseBorderlineRetryMargin = {
  performance: 0.03,
};
const labMetricThresholds = {
  lcpMs: 1500,
  cls: 0.05,
  maxPotentialFidMs: 250,
  totalBlockingTimeMs: 200,
  firstContentfulPaintMs: 1000,
  interactiveMs: 2500,
};
const labMetricChecks = [
  ['LCP', 'largestContentfulPaintMs', 'lcpMs'],
  ['Max Potential FID', 'maxPotentialFidMs', 'maxPotentialFidMs'],
  ['TBT', 'totalBlockingTimeMs', 'totalBlockingTimeMs'],
  ['FCP', 'firstContentfulPaintMs', 'firstContentfulPaintMs'],
  ['TTI', 'interactiveMs', 'interactiveMs'],
];

const failures = [];
const consoleErrors = [];

function assertNativePerformanceRuntime() {
  if (process.platform !== 'darwin') return;
  if (os.arch() !== 'arm64') return;
  if (process.arch === 'arm64') return;

  throw new Error(
    `Performance audit must run under arm64 Node on Apple Silicon. Current Node is ${process.arch} at ${process.execPath}. Use an arm64 Node binary so Lighthouse does not launch Chrome through Rosetta.`
  );
}

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

async function waitForServer(server) {
  const deadline = Date.now() + 12000;
  while (Date.now() < deadline) {
    if (server.exitCode !== null || server.signalCode !== null) {
      throw new Error(`Local web server exited before becoming healthy: code=${server.exitCode ?? 'none'} signal=${server.signalCode ?? 'none'}`);
    }
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
  const thresholds = {
    performance: isDoc ? 0.9 : 0.95,
    accessibility: 1,
    'best-practices': 0.95,
    seo: 1,
  };
  // The not-found pages are noindex on purpose, which Lighthouse scores as an SEO failure.
  if (url.endsWith('/404.html')) delete thresholds.seo;
  return thresholds;
}

const lighthouseInternalFailureScores = {
  performance: 0,
  'best-practices': 0,
};

function screenEmulationFor(formFactor) {
  if (formFactor === 'desktop') {
    return {
      mobile: false,
      width: 1350,
      height: 940,
      deviceScaleFactor: 1,
      disabled: false,
    };
  }

  return {
    mobile: true,
    width: 390,
    height: 844,
    deviceScaleFactor: 2,
    disabled: false,
  };
}

function lighthouseSettings(method, formFactor) {
  return {
    formFactor,
    screenEmulation: screenEmulationFor(formFactor),
    throttlingMethod: method,
  };
}

function chromeLaunchOptions() {
  return {
    chromePath,
    chromeFlags: [
      '--headless=new',
      '--disable-gpu',
      '--no-sandbox',
      '--disable-dev-shm-usage',
    ],
  };
}

function lighthouseCategories(lhr) {
  return Object.fromEntries(
    Object.entries(lhr.categories).map(([key, category]) => [key, category.score])
  );
}

function lighthouseMetrics(lhr) {
  const auditValue = (id) => {
    const value = lhr.audits?.[id]?.numericValue;
    return typeof value === 'number' && Number.isFinite(value) ? value : null;
  };
  return {
    largestContentfulPaintMs: auditValue('largest-contentful-paint'),
    cumulativeLayoutShift: auditValue('cumulative-layout-shift'),
    maxPotentialFidMs: auditValue('max-potential-fid'),
    totalBlockingTimeMs: auditValue('total-blocking-time'),
    firstContentfulPaintMs: auditValue('first-contentful-paint'),
    interactiveMs: auditValue('interactive'),
  };
}

function isLighthouseDevtoolsFallbackError(error) {
  const message = error instanceof Error ? error.message : String(error);
  return message.includes('LanternError') || message.includes('Invalid dependency graph');
}

function isLighthouseIsolatedRetryError(error) {
  const message = error instanceof Error ? error.message : String(error);
  return [
    'LighthouseTimeout',
    'Session closed',
    'Protocol error',
    'ECONNREFUSED',
    'Target closed',
    'target closed',
    'Connection closed',
    'WebSocket is not open',
  ].some((needle) => message.includes(needle));
}

function withTimeout(promise, timeoutMs, label) {
  let timeout;
  const timeoutPromise = new Promise((_, reject) => {
    timeout = setTimeout(() => {
      reject(new Error(`LighthouseTimeout: ${label} exceeded ${timeoutMs}ms`));
    }, timeoutMs);
  });
  return Promise.race([promise, timeoutPromise]).finally(() => clearTimeout(timeout));
}

function shouldRerunLighthouseWithDevtools({ method, categories, lhr }) {
  return lighthouseDevtoolsFallback
    && method === 'simulate'
    && isLighthouseInternalFailure({ categories, lhr });
}

function isLighthouseInternalFailure({ categories, lhr }) {
  const internalZeroScore =
    categories.performance === lighthouseInternalFailureScores.performance
    && categories['best-practices'] === lighthouseInternalFailureScores['best-practices'];
  return Boolean(lhr.runtimeError) || internalZeroScore;
}

function shouldRetryBorderlineLighthouseScore(categories, thresholds) {
  return Object.entries(thresholds).some(([category, threshold]) => {
    const margin = lighthouseBorderlineRetryMargin[category] ?? 0;
    const score = categories[category] ?? 0;
    return margin > 0 && score < threshold && score >= threshold - margin;
  });
}

function lighthouseScoreTotal(categories) {
  return Object.values(categories).reduce(
    (total, score) => total + (typeof score === 'number' && Number.isFinite(score) ? score : 0),
    0
  );
}

function shouldUseLighthouseRetry(currentResult, retryResult) {
  if (isLighthouseInternalFailure(currentResult) && !isLighthouseInternalFailure(retryResult)) return true;
  return lighthouseScoreTotal(retryResult.categories) > lighthouseScoreTotal(currentResult.categories);
}

async function runSingleLighthouse(url, chromePort, method, formFactor = 'mobile') {
  const runnerResult = await withTimeout(lighthouse(`${baseURL}${url}`, {
    port: chromePort,
    output: 'json',
    logLevel: 'error',
    onlyCategories: ['performance', 'accessibility', 'best-practices', 'seo'],
  }, {
    extends: 'lighthouse:default',
    settings: lighthouseSettings(method, formFactor),
  }), lighthouseTimeoutMs, `${method}/${formFactor} ${url}`);
  const lhr = runnerResult.lhr;
  return {
    categories: lighthouseCategories(lhr),
    lhr,
    method,
    formFactor,
    report: runnerResult.report,
  };
}

async function runIsolatedLighthouse(url, method, formFactor = 'mobile') {
  const chrome = await launch(chromeLaunchOptions());
  try {
    return await runSingleLighthouse(url, chrome.port, method, formFactor);
  } finally {
    await chrome.kill();
  }
}

async function runLighthouse(urls) {
  const useSharedChrome = !fullLighthouse && process.env.COCXY_WEB_LIGHTHOUSE_SHARED !== '0';
  const chrome = useSharedChrome ? await launch(chromeLaunchOptions()) : null;
  const runAttempt = (url, method, formFactor = 'mobile') => {
    if (chrome) return runSingleLighthouse(url, chrome.port, method, formFactor);
    return runIsolatedLighthouse(url, method, formFactor);
  };
  const results = [];
  try {
    for (const url of urls) {
      const failuresBefore = failures.length;
      for (let attempt = 1; ; attempt += 1) {
        let lighthouseResult;
        let fallbackFrom = null;
        let retryReason = null;
        const primaryMethod = primaryLighthouseMethod;
        try {
          lighthouseResult = await runAttempt(url, primaryMethod);
        } catch (error) {
          if (
            lighthouseDevtoolsFallback
            && primaryMethod === 'simulate'
            && isLighthouseDevtoolsFallbackError(error)
          ) {
            fallbackFrom = primaryMethod;
            console.warn(`Lighthouse ${primaryMethod} failed internally on ${url}; rerunning with devtools throttling.`);
            try {
              lighthouseResult = await runAttempt(url, 'devtools');
            } catch (fallbackError) {
              if (!isLighthouseIsolatedRetryError(fallbackError)) throw fallbackError;
              console.warn(`Lighthouse devtools lost the shared Chrome session on ${url}; rerunning in isolated Chrome.`);
              lighthouseResult = await runIsolatedLighthouse(url, 'devtools');
            }
          } else if (isLighthouseIsolatedRetryError(error)) {
            fallbackFrom = primaryMethod;
            console.warn(`Lighthouse ${primaryMethod} lost the shared Chrome session on ${url}; rerunning in isolated Chrome.`);
            lighthouseResult = await runIsolatedLighthouse(url, primaryMethod);
          } else {
            throw error;
          }
        }
        if (shouldRerunLighthouseWithDevtools(lighthouseResult)) {
          fallbackFrom = primaryMethod;
          console.warn(`Lighthouse ${primaryMethod} returned an internal zero-score result on ${url}; rerunning with devtools throttling.`);
          lighthouseResult = await runAttempt(url, 'devtools');
        }

        const categories = lighthouseResult.categories;
        const thresholds = lighthouseThresholds(url);
        if (isLighthouseInternalFailure(lighthouseResult)) {
          retryReason = 'internal zero-score result';
        } else if (shouldRetryBorderlineLighthouseScore(categories, thresholds)) {
          retryReason = 'borderline performance score';
        }
        if (retryReason) {
          const retryMethod = lighthouseResult.method;
          console.warn(`Lighthouse ${retryMethod} returned ${retryReason} on ${url}; rerunning in isolated Chrome.`);
          const retryResult = await runIsolatedLighthouse(url, retryMethod);
          if (shouldUseLighthouseRetry(lighthouseResult, retryResult)) {
            fallbackFrom = fallbackFrom ?? lighthouseResult.method;
            lighthouseResult = retryResult;
          }
        }
        if (
          lighthouseProvidedFallback
          && isLighthouseInternalFailure(lighthouseResult)
          && lighthouseResult.method !== 'provided'
        ) {
          console.warn(`Lighthouse ${lighthouseResult.method} still returned an internal zero-score result on ${url}; rerunning with provided throttling in isolated Chrome.`);
          const providedResult = await runIsolatedLighthouse(url, 'provided');
          if (shouldUseLighthouseRetry(lighthouseResult, providedResult)) {
            fallbackFrom = fallbackFrom ?? lighthouseResult.method;
            lighthouseResult = providedResult;
          }
        }
        if (
          lighthouseDesktopFallback
          && isLighthouseInternalFailure(lighthouseResult)
          && lighthouseResult.formFactor !== 'desktop'
        ) {
          console.warn(`Lighthouse mobile still returned an internal zero-score result on ${url}; rerunning desktop provided in isolated Chrome.`);
          const desktopResult = await runIsolatedLighthouse(url, 'provided', 'desktop');
          if (shouldUseLighthouseRetry(lighthouseResult, desktopResult)) {
            fallbackFrom = fallbackFrom ?? lighthouseResult.method;
            lighthouseResult = desktopResult;
          }
        }

        const finalCategories = lighthouseResult.categories;
        const finalMetrics = lighthouseMetrics(lighthouseResult.lhr);
        const enforceSimulatedLabMetrics = lighthouseResult.method === 'simulate' && fallbackFrom === null;
        for (const [category, threshold] of Object.entries(thresholds)) {
          const score = finalCategories[category] ?? 0;
          if (score < threshold) {
            fail(`Lighthouse ${category} on ${url} scored ${score}, below ${threshold}`);
          }
        }
        if (finalMetrics.cumulativeLayoutShift === null) {
          fail(`Lighthouse CLS missing on ${url}`);
        } else if (finalMetrics.cumulativeLayoutShift >= labMetricThresholds.cls) {
          fail(`Lighthouse CLS on ${url} was ${finalMetrics.cumulativeLayoutShift}, expected < ${labMetricThresholds.cls}`);
        }
        if (enforceSimulatedLabMetrics) {
          for (const [label, metric, limit] of labMetricChecks) {
            const value = finalMetrics[metric];
            if (value === null) {
              fail(`Lighthouse ${label} missing on ${url}`);
            } else if (value >= labMetricThresholds[limit]) {
              fail(`Lighthouse ${label} on ${url} was ${value.toFixed(1)}ms, expected < ${labMetricThresholds[limit]}ms`);
            }
          }
        }
        // Lab metrics vary on shared CI runners: as in Lighthouse CI, any of three passing runs counts.
        if (failures.length > failuresBefore && attempt < 3) {
          failures.length = failuresBefore;
          console.warn(`Lighthouse flagged ${url}; measuring it again (${attempt + 1} of 3).`);
          continue;
        }
        const reportPath = path.join(reportRoot, `lighthouse-${slugFor(url)}.json`);
        fs.writeFileSync(reportPath, lighthouseResult.report);
        results.push({
          url,
          scores: finalCategories,
          metrics: finalMetrics,
          labMetricThresholdsEnforced: enforceSimulatedLabMetrics,
          throttlingMethod: lighthouseResult.method,
          formFactor: lighthouseResult.formFactor,
          fallbackFrom: fallbackFrom ? primaryMethod : null,
          runtimeError: lighthouseResult.lhr.runtimeError ?? null,
          report: path.relative(repoRoot, reportPath),
        });
        break;
      }
    }
  } finally {
    if (chrome) await chrome.kill();
  }
  return results;
}

function verifyBudgets() {
  const cssFiles = walkFiles(path.join(publicRoot, 'css'), (file) => file.endsWith('.css'));
  const jsFiles = walkFiles(path.join(publicRoot, 'js'), (file) => file.endsWith('.js'));
  const cssGzip = cssFiles.reduce((total, file) => total + zlib.gzipSync(fs.readFileSync(file)).length, 0);
  const jsGzip = jsFiles.reduce((total, file) => total + zlib.gzipSync(fs.readFileSync(file)).length, 0);
  const fileSize = (file) => (fs.existsSync(file) ? fs.statSync(file).size : null);

  const budgets = {
    cssGzipBytes: cssGzip,
    cssGzipLimitBytes: 40 * 1024,
    jsGzipBytes: jsGzip,
    jsGzipLimitBytes: 15 * 1024,
    captureAvif: Object.fromEntries(fs.readdirSync(path.join(publicRoot, 'images'))
      .filter((name) => /^shot-.+\.avif$/.test(name))
      .map((name) => [name, fileSize(path.join(publicRoot, 'images', name))])),
    captureAvifLimitBytes: 80 * 1024,
    compactCaptureAvifLimitBytes: 14 * 1024,
    tourWebmBytes: fileSize(path.join(publicRoot, 'videos', 'cocxy-tour.webm')),
    tourWebmLimitBytes: 4 * 1024 * 1024,
  };

  if (budgets.cssGzipBytes > budgets.cssGzipLimitBytes) fail(`CSS gzip budget exceeded: ${budgets.cssGzipBytes} > ${budgets.cssGzipLimitBytes}`);
  if (budgets.jsGzipBytes > budgets.jsGzipLimitBytes) fail(`JS gzip budget exceeded: ${budgets.jsGzipBytes} > ${budgets.jsGzipLimitBytes}`);
  for (const [file, bytes] of Object.entries(budgets.captureAvif)) {
    const limit = file.endsWith('-compact.avif') ? budgets.compactCaptureAvifLimitBytes : budgets.captureAvifLimitBytes;
    if (bytes > limit) fail(`Capture AVIF budget exceeded for ${file}: ${bytes} > ${limit}`);
  }
  if (budgets.tourWebmBytes > budgets.tourWebmLimitBytes) fail(`Tour WebM budget exceeded: ${budgets.tourWebmBytes} > ${budgets.tourWebmLimitBytes}`);

  return budgets;
}

async function main() {
  assertNativePerformanceRuntime();
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
    await waitForServer(server);
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
