#!/usr/bin/env node
// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(__dirname, '..');
const publicRoot = path.join(webRoot, 'public');
const repoRoot = path.resolve(webRoot, '..');

const requiredPages = [
  'index.html',
  'features.html',
  'features/agents.html',
  'features/vault.html',
  'features/code-review.html',
  'features/markdown.html',
  'features/github.html',
  'features/browser.html',
  'features/remote.html',
  'features/gpu.html',
  'features/cli.html',
  'features/shell.html',
  'features/plugins.html',
  'features/zero-telemetry.html',
  'architecture.html',
  'why-cocxy.html',
  'privacy.html',
  'security.html',
  'docs/index.html',
  'docs/install.html',
  'docs/first-run.html',
  'docs/configuration.html',
  'docs/agents-setup.html',
  'docs/shortcuts.html',
  'docs/cli-reference.html',
  'docs/plugins-dev.html',
  'docs/ssh-remote.html',
  'docs/markdown-guide.html',
  'docs/release-channels.html',
  'docs/troubleshooting.html',
  'docs/search-index.json',
  'faq.html',
  'releases.html',
  'channels.html',
  'press.html',
  'roadmap.html',
  'sponsors.html',
  'llms.txt',
  'sitemap.xml',
  'robots.txt',
];

const requiredPreviewFiles = [
  'preview/components.html',
];

const agentNames = [
  'Claude',
  'Codex',
  'OpenCode',
  'Pi',
  'Cursor',
  'Gemini',
  'Rovo',
  'Copilot',
  'CodeBuddy',
  'Factory',
  'Qoder',
];

const blockedProductTerms = [
  ['w', 'arp'],
  ['gh', 'ostty'],
  ['it', 'erm'],
  ['terminal', '.', 'app'],
  ['ki', 'tty'],
  ['alac', 'ritty'],
  ['wez', 'term'],
  ['hy', 'per'],
  ['c', 'mux'],
].map((parts) => parts.join(''));
const blockedTraceTerms = [
  ['Co', '-Authored-By'],
  ['claude', '.', 'com'],
  ['noreply@', 'anth', 'ropic'],
  ['Generated ', 'with'],
].map((parts) => parts.join(''));
const competitorPattern = new RegExp(`\\b(${blockedProductTerms.map(escapeRegExp).join('|')})\\b`, 'i');
const aiTracePattern = new RegExp(blockedTraceTerms.map(escapeRegExp).join('|'), 'i');
const forbiddenEmailPattern = /salp2403@gmail\.com/i;
const externalScriptPattern = /<script[^>]+src=["']https?:\/\//i;
const externalImagePattern = /<(?:img|source)[^>]+(?:src|srcset)=["']https?:\/\//i;
const externalStylesheetPattern = /<link[^>]+rel=["'][^"']*stylesheet[^"']*["'][^>]+href=["']https?:\/\//i;
const externalFontPattern = /fonts\.(?:googleapis|gstatic)\.com/i;
const styleAttrPattern = /\sstyle=/i;
const localStoragePattern = /localStorage\.(?:getItem|setItem|removeItem)\(["']([^"']+)["']/g;

const failures = [];

function fail(message) {
  failures.push(message);
}

function read(relative) {
  return fs.readFileSync(path.join(publicRoot, relative), 'utf8');
}

function exists(relative) {
  return fs.existsSync(path.join(publicRoot, relative));
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function walk(dir, files = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, files);
    else files.push(full);
  }
  return files;
}

for (const page of requiredPages) {
  if (!exists(page)) fail(`Missing required page or asset: ${page}`);
  if (page.endsWith('.html') && !exists(`es/${page}`) && page !== 'index.html') {
    fail(`Missing Spanish mirror: es/${page}`);
  }
}

for (const file of requiredPreviewFiles) {
  if (!fs.existsSync(path.join(webRoot, file))) fail(`Missing required preview artifact: ${file}`);
}

const publicFiles = walk(publicRoot).filter((file) => /\.(html|js|css|txt|xml|webmanifest|json|svg)$/.test(file));
for (const file of publicFiles) {
  const relative = path.relative(publicRoot, file);
  const content = fs.readFileSync(file, 'utf8');
  if (competitorPattern.test(content)) fail(`Competitor reference in ${relative}`);
  if (aiTracePattern.test(content)) fail(`AI trace in ${relative}`);
  if (forbiddenEmailPattern.test(content)) fail(`Forbidden email in ${relative}`);
}

const htmlFiles = publicFiles.filter((file) => file.endsWith('.html'));
for (const file of htmlFiles) {
  const relative = path.relative(publicRoot, file);
  const content = fs.readFileSync(file, 'utf8');
  if (styleAttrPattern.test(content)) fail(`Inline style attribute in ${relative}`);
  if (externalScriptPattern.test(content)) fail(`External script in ${relative}`);
  if (externalImagePattern.test(content)) fail(`External image in ${relative}`);
  if (externalStylesheetPattern.test(content)) fail(`External stylesheet in ${relative}`);
  if (externalFontPattern.test(content)) fail(`External font reference in ${relative}`);
  for (const needle of [
    '<main id="main">',
    'href="#main"',
    'rel="canonical"',
    'hreflang="en"',
    'hreflang="es"',
    'style.css?v=0.0.0',
    'application/ld+json',
  ]) {
    if (!content.includes(needle)) fail(`Missing ${needle} in ${relative}`);
  }
  if (relative.startsWith('es/') && !content.includes('lang="es-HN"')) {
    fail(`Spanish page lacks es-HN lang: ${relative}`);
  }
  verifyJSONLD(relative, content);
  verifyLocalReferences(relative, content);
  verifyOpenGraphImage(relative, content);
}

const jsFiles = publicFiles.filter((file) => file.endsWith('.js'));
for (const file of jsFiles) {
  const relative = path.relative(publicRoot, file);
  const content = fs.readFileSync(file, 'utf8');
  for (const match of content.matchAll(localStoragePattern)) {
    if (match[1] !== 'cocxy-theme') fail(`Unexpected localStorage key ${match[1]} in ${relative}`);
  }
  if (/\.style\./.test(content) || /\.setAttribute\(["']style["']/.test(content)) {
    fail(`Runtime inline style mutation in ${relative}`);
  }
}

const cssFiles = publicFiles.filter((file) => file.endsWith('.css'));
const entryCSS = cssFiles.find((file) => path.basename(file) === 'style.css');
if (entryCSS && new RegExp(`@${'import'}\\b`).test(fs.readFileSync(entryCSS, 'utf8'))) {
  fail('style.css still contains CSS imports; CSS must be bundled before deploy');
}
verifyCSSCustomProperties(cssFiles);

const home = read('index.html');
for (const section of ['hero', 'features', 'demo', 'comparison', 'faq', 'download', 'opensource']) {
  if (!home.includes(`id="${section}"`)) fail(`Homepage missing #${section}`);
}
for (const featureClass of [
  'feature-icon--agents',
  'feature-icon--review',
  'feature-icon--markdown',
  'feature-icon--ssh',
  'feature-icon--browser',
  'feature-icon--privacy',
  'feature-icon--gpu',
  'feature-icon--cli',
  'feature-icon--plugin',
  'feature-icon--config',
  'feature-icon--web',
  'feature-icon--shell',
]) {
  if (!home.includes(featureClass)) fail(`Homepage missing ${featureClass}`);
}
for (const schemaType of ['FAQPage', 'VideoObject', 'SoftwareApplication', 'WebSite']) {
  if (!home.includes(`"@type": "${schemaType}"`)) fail(`Homepage missing ${schemaType} JSON-LD`);
}
if (!home.includes('<source src="/videos/cocxy-demo.webm" type="video/webm">')) {
  fail('Homepage demo missing WebM fallback');
}
if (!home.includes('/images/architecture-diagram.svg')) {
  fail('Homepage missing static architecture SVG teaser');
}

const spanishHome = read('es/index.html');
for (const section of ['hero', 'features', 'demo', 'comparison', 'faq', 'download', 'opensource']) {
  if (!spanishHome.includes(`id="${section}"`)) fail(`Spanish homepage missing #${section}`);
}

const featuresHub = read('features.html');
for (const anchor of [
  'agent-detection',
  'code-review',
  'github-pane',
  'markdown',
  'quicklook',
  'gpu',
  'remote',
  'browser',
  'web-terminal',
  'plugins',
  'per-project',
  'applescript',
  'shell',
  'privacy',
  'cli',
]) {
  if (!featuresHub.includes(`id="${anchor}"`)) fail(`Features hub missing #${anchor}`);
  if (!featuresHub.includes(`href="#${anchor}"`)) fail(`Features hub TOC missing #${anchor}`);
}
if (!featuresHub.includes('"@type": "ItemList"')) fail('Features hub missing ItemList JSON-LD');

const docsHub = read('docs/index.html');
if (!docsHub.includes('data-doc-search')) fail('Docs hub missing local search input');
if (exists('docs/search-index.json')) {
  try {
    const index = JSON.parse(read('docs/search-index.json'));
    if (!Array.isArray(index) || index.length < 10) fail('Docs search index is too small');
    if (!JSON.stringify(index).includes('/docs/ssh-remote.html')) fail('Docs search index missing ssh-remote');
  } catch (error) {
    fail(`Docs search index parse failed: ${error.message}`);
  }
}

const architecture = read('architecture.html');
for (const needle of ['Swift + AppKit', 'SwiftUI', 'CocxyCore', 'Metal', 'PTY', 'Domain modules', 'test suite']) {
  if (!architecture.includes(needle)) fail(`Architecture page missing ${needle}`);
}
if (!exists('images/architecture-diagram.svg')) fail('Missing architecture diagram SVG');

const privacy = read('privacy.html');
for (const needle of ['No telemetry pipeline', 'No analytics SDK', 'No third-party tracking', 'How to verify', 'Web privacy of this site']) {
  if (!privacy.includes(needle)) fail(`Privacy page missing ${needle}`);
}

const security = read('security.html');
for (const needle of ['Threat model', 'AES-GCM', 'EdDSA', 'HMAC-SHA256', 'Keychain', 'SBOM', 'Disclosure']) {
  if (!security.includes(needle)) fail(`Security page missing ${needle}`);
}

const why = read('why-cocxy.html');
for (const needle of ['Native macOS', 'Local-first', 'Open source, MIT', 'Agents are first-class', '21 languages', 'Zero telemetry', 'Focused stewardship']) {
  if (!why.includes(needle)) fail(`Why page missing ${needle}`);
}

if (!exists('js/theme-switcher.js')) fail('Missing theme-switcher.js');
if (exists('js/theme-switcher.js')) {
  const theme = read('js/theme-switcher.js');
  if (!theme.includes("localStorage.getItem('cocxy-theme')")) fail('theme-switcher.js does not read cocxy-theme');
  if (!theme.includes("localStorage.setItem('cocxy-theme'")) fail('theme-switcher.js does not persist cocxy-theme');
}

const agentsPage = read('features/agents.html');
for (const name of agentNames) {
  if (!agentsPage.includes(name)) fail(`Agent page missing ${name}`);
}

const swiftAgents = fs.readFileSync(
  path.join(repoRoot, 'Sources/Domain/Vault/VaultBuiltInAgents.swift'),
  'utf8'
);
for (const name of agentNames) {
  if (!swiftAgents.includes(name)) fail(`Swift source missing expected agent ${name}`);
}

const sitemap = read('sitemap.xml');
for (const page of requiredPages.filter((page) => page.endsWith('.html'))) {
  if (page === 'getting-started.html') continue;
  const url = page === 'index.html'
    ? 'https://cocxy.dev/'
    : page === 'docs/index.html'
      ? 'https://cocxy.dev/docs/'
      : `https://cocxy.dev/${page}`;
  if (!sitemap.includes(url)) fail(`Sitemap missing ${url}`);
}

const server = fs.readFileSync(path.join(webRoot, 'server.js'), 'utf8');
for (const needle of [
  '"/getting-started.html"',
  '"/docs/first-run.html"',
  'Permissions-Policy',
  'frameAncestors',
  'frameguard',
  'action: "deny"',
  '"/health"',
  'PUBLIC_ROOT',
  'isPublicRequestPath',
  'dotfiles: "ignore"',
]) {
  if (!server.includes(needle)) fail(`server.js missing ${needle}`);
}

for (const asset of ['images/cocxy-preview.webp', 'images/cocxy-preview.avif', 'og/og-index.png']) {
  if (!exists(asset)) fail(`Missing generated asset: ${asset}`);
}

for (const asset of ['videos/cocxy-demo.mp4', 'videos/cocxy-demo.webm']) {
  if (!exists(asset)) fail(`Missing video asset: ${asset}`);
}

function verifyJSONLD(relative, content) {
  const regex = /<script type="application\/ld\+json">([\s\S]*?)<\/script>/g;
  let count = 0;
  for (const match of content.matchAll(regex)) {
    count += 1;
    try {
      JSON.parse(match[1]);
    } catch (error) {
      fail(`JSON-LD parse error in ${relative}: ${error.message}`);
    }
  }
  if (count === 0) fail(`No JSON-LD blocks in ${relative}`);
}

function verifyLocalReferences(relative, content) {
  const references = [];
  for (const attr of ['href', 'src', 'poster']) {
    const regex = new RegExp(`${attr}=["']([^"']+)["']`, 'g');
    for (const match of content.matchAll(regex)) references.push(match[1]);
  }
  for (const match of content.matchAll(/srcset=["']([^"']+)["']/g)) {
    for (const candidate of match[1].split(',')) {
      references.push(candidate.trim().split(/\s+/)[0]);
    }
  }

  for (const reference of references) {
    if (!reference || reference.startsWith('#') || reference.startsWith('mailto:')) continue;
    if (reference.startsWith('https://github.com/')) continue;
    if (reference.startsWith('https://opensource.org/')) continue;
    if (/^https?:\/\//.test(reference)) continue;
    const [withoutFragment, fragment] = reference.split('#');
    const pathPart = withoutFragment.split('?')[0];
    if (!pathPart || pathPart.startsWith('?')) continue;
    if (path.basename(pathPart) === 'appcast.xml') continue;
    const target = pathPart.startsWith('/')
      ? path.join(publicRoot, pathPart)
      : path.join(path.dirname(path.join(publicRoot, relative)), pathPart);
    if (!fs.existsSync(target)) {
      fail(`${relative} references missing local target ${reference}`);
      continue;
    }
    if (fragment && target.endsWith('.html')) {
      const targetHTML = fs.readFileSync(target, 'utf8');
      if (!targetHTML.includes(`id="${fragment}"`)) fail(`${relative} references missing anchor ${reference}`);
    }
  }
}

function verifyOpenGraphImage(relative, content) {
  const match = content.match(/<meta property="og:image" content="https:\/\/cocxy\.dev\/([^"']+)"/);
  if (!match) {
    fail(`Missing og:image in ${relative}`);
    return;
  }
  if (!exists(match[1])) fail(`Missing og:image asset for ${relative}: ${match[1]}`);
}

function verifyCSSCustomProperties(files) {
  const definitions = new Set();
  const uses = new Set();
  for (const file of files) {
    const content = fs.readFileSync(file, 'utf8');
    for (const match of content.matchAll(/--([a-z0-9-]+)\s*:/gi)) definitions.add(match[1]);
    for (const match of content.matchAll(/var\(--([a-z0-9-]+)/gi)) uses.add(match[1]);
  }
  for (const name of uses) {
    if (!definitions.has(name)) fail(`CSS variable --${name} is used but not defined`);
  }
}

if (failures.length) {
  console.error('Site verification failed:');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}

console.log(`Site verification passed (${htmlFiles.length} HTML files checked).`);
