#!/usr/bin/env node
// Copyright (c) 2026 Said Arturo Lopez. MIT License.

// Renders one Open Graph card per page and locale from the metadata of the
// generated pages, and records the text each card was drawn from so
// verify-site.mjs can tell when a card is stale.
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(__dirname, '..');
const publicRoot = path.join(webRoot, 'public');
const manifestPath = path.join(webRoot, 'assets', 'og-manifest.json');
const chromePath = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

function walk(dir, files = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, files);
    else if (entry.name.endsWith('.html')) files.push(full);
  }
  return files;
}

function attribute(content, property) {
  return content.match(new RegExp(`<meta property="${property}" content="([^"]*)"`))?.[1] ?? '';
}

function decode(value) {
  return value
    .replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(Number(code)))
    .replace(/&([a-z]+);/g, (entity, name) => ({ amp: '&', quot: '"', lt: '<', gt: '>', apos: "'", nbsp: ' ', iacute: 'í', oacute: 'ó', aacute: 'á', eacute: 'é', uacute: 'ú', ntilde: 'ñ' }[name] ?? entity));
}

function escapeHTML(value) {
  return value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

function sectionLabel(relative, spanish) {
  const route = relative.replace(/^es\//, '');
  if (route.startsWith('features/') || route === 'features.html') return spanish ? 'Funciones' : 'Features';
  if (route.startsWith('docs/') || route === 'getting-started.html') return spanish ? 'Documentación' : 'Docs';
  if (route === 'releases.html') return spanish ? 'Versiones' : 'Releases';
  if (route === 'index.html') return spanish ? 'Terminal nativa para macOS' : 'Native macOS terminal';
  return 'Cocxy Terminal';
}

function cardHTML({ title, description, label, spanish, icon }) {
  const footer = spanish ? 'Nativa · Sin telemetría · MIT' : 'Native · Zero telemetry · MIT';
  return `<!doctype html><html><head><meta charset="utf-8"><style>
  * { box-sizing: border-box; margin: 0; }
  body { width: 1200px; height: 630px; overflow: hidden; background: #0b0c10; color: #f4f5f7;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif; -webkit-font-smoothing: antialiased; }
  .card { position: relative; width: 1200px; height: 630px; padding: 64px 72px; display: flex; flex-direction: column; }
  .glow { position: absolute; inset: 0; background:
    radial-gradient(520px 360px at 88% 18%, rgba(127, 178, 255, 0.22), transparent 70%),
    radial-gradient(420px 300px at 12% 110%, rgba(110, 231, 160, 0.12), transparent 70%); }
  .brand { position: relative; display: flex; align-items: center; gap: 18px; font-size: 30px; font-weight: 600; letter-spacing: -0.01em; }
  .brand img { width: 56px; height: 56px; }
  .label { position: relative; margin-top: auto; color: #8fbcff; font-size: 26px; font-weight: 600; }
  h1 { position: relative; margin-top: 14px; font-size: 72px; line-height: 1.04; letter-spacing: -0.035em; font-weight: 700;
    display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
  p { position: relative; margin-top: 22px; max-width: 980px; color: #aeb4c1; font-size: 28px; line-height: 1.4;
    display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
  .foot { position: relative; margin-top: 40px; display: flex; justify-content: space-between; color: #8b92a1; font-size: 22px; }
</style></head><body><div class="card"><div class="glow"></div>
  <div class="brand"><img src="${icon}" alt="">Cocxy Terminal</div>
  <div class="label">${escapeHTML(label)}</div>
  <h1>${escapeHTML(title)}</h1>
  <p>${escapeHTML(description)}</p>
  <div class="foot"><span>cocxy.dev</span><span>${footer}</span></div>
</div></body></html>`;
}

async function main() {
  if (!fs.existsSync(chromePath)) throw new Error(`Google Chrome not found at ${chromePath}`);
  const icon = `data:image/png;base64,${fs.readFileSync(path.join(publicRoot, 'images', 'icon.png')).toString('base64')}`;
  const cards = new Map();
  for (const file of walk(publicRoot).sort()) {
    const relative = path.relative(publicRoot, file).split(path.sep).join('/');
    const content = fs.readFileSync(file, 'utf8');
    const image = attribute(content, 'og:image').replace('https://cocxy.dev/', '');
    if (!image.startsWith('og/') || cards.has(image)) continue;
    const title = attribute(content, 'og:title');
    const description = attribute(content, 'og:description');
    cards.set(image, { relative, title, description, spanish: relative.startsWith('es/') });
  }

  const browser = await chromium.launch({ executablePath: chromePath, headless: true });
  const page = await browser.newPage({ viewport: { width: 1200, height: 630 }, deviceScaleFactor: 1 });
  const manifest = {};
  try {
    for (const [image, card] of cards) {
      const heading = decode(card.title).replace(/ - Cocxy Terminal$/, '');
      await page.setContent(cardHTML({
        title: heading,
        description: decode(card.description),
        label: sectionLabel(card.relative, card.spanish),
        spanish: card.spanish,
        icon,
      }), { waitUntil: 'load' });
      const target = path.join(publicRoot, image);
      await page.screenshot({ path: target, type: 'jpeg', quality: 88 });
      const sha256 = crypto.createHash('sha256').update(fs.readFileSync(target)).digest('hex');
      manifest[image] = { title: card.title, description: card.description, sha256 };
    }
  } finally {
    await browser.close();
  }

  for (const file of fs.readdirSync(path.join(publicRoot, 'og'))) {
    if (!manifest[`og/${file}`]) fs.rmSync(path.join(publicRoot, 'og', file));
  }
  const sorted = Object.fromEntries(Object.entries(manifest).sort(([a], [b]) => a.localeCompare(b)));
  fs.writeFileSync(manifestPath, `${JSON.stringify(sorted, null, 2)}\n`);
  console.log(`Rendered ${cards.size} Open Graph cards.`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
