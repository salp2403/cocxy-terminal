#!/usr/bin/env node
// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(__dirname, '..');
const repoRoot = path.resolve(webRoot, '..');

const args = new Map();
for (let index = 2; index < process.argv.length; index += 2) {
  const key = process.argv[index];
  const value = process.argv[index + 1];
  if (!key?.startsWith('--') || value === undefined) {
    throw new Error(`Invalid argument near ${key ?? '<end>'}`);
  }
  args.set(key.slice(2), value);
}

const version = args.get('version') ?? '0.0.0';
const locale = args.get('locale') ?? 'en';
const output = args.get('output') ?? path.join(repoRoot, 'build', locale === 'es' ? 'es' : '', 'releases.html');
const site = 'https://cocxy.dev';

if (!/^\d+\.\d+\.\d+$/.test(version)) {
  throw new Error(`Invalid version: ${version}`);
}
if (!['en', 'es'].includes(locale)) {
  throw new Error(`Invalid locale: ${locale}`);
}

const text = locale === 'es'
  ? {
      htmlLang: 'es-HN',
      title: 'Versiones - Cocxy Terminal',
      description: 'Historial de versiones y cambios de Cocxy Terminal.',
      locale: 'es_HN',
      home: 'Inicio',
      navFeatures: 'Funciones',
      navAgents: 'Agentes',
      navPrivacy: 'Privacidad',
      navSecurity: 'Seguridad',
      navDocs: 'Documentación',
      navDownload: 'Descargar',
      theme: 'Cambiar tema',
      language: 'English',
      languageHref: '/releases.html',
      eyebrow: 'Versiones',
      heading: 'Versiones',
      intro: 'Historial de versiones, notas y descargas de Cocxy Terminal.',
      latest: 'Actual',
      download: 'Descargar DMG',
      notes: 'Notas',
      older: 'Mostrar versiones anteriores',
      skip: 'Saltar al contenido',
      madeBy: 'Hecho por Said Arturo Lopez',
      footer: 'Terminal nativa para macOS, local-first, MIT y sin telemetría.',
      canonical: `${site}/es/releases.html`,
      alternate: `${site}/releases.html`,
      inLanguage: 'es-HN',
    }
  : {
      htmlLang: 'en',
      title: 'Releases - Cocxy Terminal',
      description: 'Release history and changelog for Cocxy Terminal.',
      locale: 'en_US',
      home: 'Home',
      navFeatures: 'Features',
      navAgents: 'Agents',
      navPrivacy: 'Privacy',
      navSecurity: 'Security',
      navDocs: 'Docs',
      navDownload: 'Download',
      theme: 'Toggle theme',
      language: 'Español',
      languageHref: '/es/releases.html',
      eyebrow: 'Releases',
      heading: 'Releases',
      intro: 'Release history, notes, and downloads for Cocxy Terminal.',
      latest: 'Latest',
      download: 'Download DMG',
      notes: 'Release Notes',
      older: 'Show older releases',
      skip: 'Skip to main content',
      madeBy: 'Made by Said Arturo Lopez',
      footer: 'Native macOS terminal, local-first, MIT licensed, and zero telemetry.',
      canonical: `${site}/releases.html`,
      alternate: `${site}/es/releases.html`,
      inLanguage: 'en',
    };

function escapeHTML(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function mdToHTML(value) {
  if (!value) return '';
  const lines = String(value).split(/\r?\n/);
  const html = [];
  let inList = false;

  function closeList() {
    if (inList) {
      html.push('</ul>');
      inList = false;
    }
  }

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (!line) {
      closeList();
      continue;
    }
    if (line.startsWith('### ')) {
      closeList();
      html.push(`<h4>${inlineMarkdown(line.slice(4))}</h4>`);
      continue;
    }
    if (line.startsWith('## ')) {
      closeList();
      html.push(`<h3>${inlineMarkdown(line.slice(3))}</h3>`);
      continue;
    }
    if (line.startsWith('- ') || line.startsWith('* ')) {
      if (!inList) {
        html.push('<ul>');
        inList = true;
      }
      html.push(`<li>${inlineMarkdown(line.slice(2))}</li>`);
      continue;
    }
    closeList();
    html.push(`<p>${inlineMarkdown(line)}</p>`);
  }
  closeList();
  return html.join('\n');
}

function inlineMarkdown(value) {
  return escapeHTML(value)
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/`([^`]+)`/g, '<code>$1</code>');
}

async function fetchReleases() {
  const headers = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'cocxy-web-release-page',
  };
  if (process.env.GH_TOKEN) headers.Authorization = `Bearer ${process.env.GH_TOKEN}`;
  const response = await fetch('https://api.github.com/repos/salp2403/cocxy-terminal/releases?per_page=50', { headers });
  if (!response.ok) {
    throw new Error(`GitHub releases API returned ${response.status}`);
  }
  return response.json();
}

const releases = await fetchReleases();
const releaseItems = [];
const cards = releases.map((release, index) => {
  const tag = release.tag_name ?? '';
  const releaseVersion = tag.replace(/^v/, '');
  const date = String(release.published_at ?? '').slice(0, 10);
  const downloadURL = `https://github.com/salp2403/cocxy-terminal/releases/download/${encodeURIComponent(tag)}/CocxyTerminal-${escapeHTML(releaseVersion)}.dmg`;
  const releaseURL = `https://github.com/salp2403/cocxy-terminal/releases/tag/${encodeURIComponent(tag)}`;
  const hidden = index >= 5 ? ' hidden data-release-hidden="true"' : '';
  const badge = index === 0 ? `<span class="rel-badge">${text.latest}</span>` : '';
  const notes = mdToHTML(release.body ?? '');

  releaseItems.push({
    '@type': 'SoftwareApplication',
    name: `Cocxy Terminal ${tag}`,
    applicationCategory: 'DeveloperApplication',
    operatingSystem: 'macOS 14.0+',
    softwareVersion: releaseVersion,
    url: releaseURL,
    downloadUrl: downloadURL,
    datePublished: date,
  });

  return `<article class="rel-card"${hidden}>
  <div class="rel-header">
    <h2>${escapeHTML(tag)}</h2>
    ${badge}
    <time datetime="${escapeHTML(date)}">${escapeHTML(date)}</time>
  </div>
  ${notes ? `<div class="rel-notes">${notes}</div>` : ''}
  <div class="rel-actions">
    <a href="${downloadURL}" class="button button-primary">${text.download}</a>
    <a href="${releaseURL}" target="_blank" rel="noopener noreferrer" class="button button-secondary">${text.notes}</a>
  </div>
</article>`;
}).join('\n');

const hiddenCount = Math.max(0, releases.length - 5);
const showMore = hiddenCount
  ? `<div class="release-more"><button id="showMoreReleases" class="button button-secondary" type="button">${text.older} (${hiddenCount})</button></div>`
  : '';

const structuredData = JSON.stringify([
  {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: [
      {
        '@type': 'ListItem',
        position: 1,
        name: text.home,
        item: locale === 'es' ? `${site}/es/` : `${site}/`,
      },
      {
        '@type': 'ListItem',
        position: 2,
        name: text.heading,
        item: text.canonical,
      },
    ],
  },
  {
    '@context': 'https://schema.org',
    '@type': 'CollectionPage',
    '@id': `${text.canonical}#releases`,
    name: text.title,
    url: text.canonical,
    description: text.description,
    inLanguage: text.inLanguage,
    about: {
      '@type': 'SoftwareApplication',
      name: 'Cocxy Terminal',
      applicationCategory: 'DeveloperApplication',
      operatingSystem: 'macOS 14.0+',
      softwareVersion: version,
      url: site,
      downloadUrl: 'https://github.com/salp2403/cocxy-terminal/releases/latest',
    },
    mainEntity: {
      '@type': 'ItemList',
      itemListOrder: 'https://schema.org/ItemListOrderDescending',
      numberOfItems: releaseItems.length,
      itemListElement: releaseItems.map((item, index) => ({
        '@type': 'ListItem',
        position: index + 1,
        item,
      })),
    },
  },
], null, 2);

const html = `<!DOCTYPE html>
<html lang="${text.htmlLang}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${text.title}</title>
  <meta name="description" content="${text.description}">
  <meta name="author" content="Said Arturo Lopez">
  <meta name="robots" content="index, follow, max-snippet:-1, max-image-preview:large">
  <meta name="theme-color" content="#101018">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Cocxy Terminal">
  <meta property="og:title" content="${text.title}">
  <meta property="og:description" content="${text.description}">
  <meta property="og:url" content="${text.canonical}">
  <meta property="og:image" content="${site}/og/og-releases.png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:image:alt" content="${text.title}">
  <meta property="og:locale" content="${text.locale}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${text.title}">
  <meta name="twitter:description" content="${text.description}">
  <meta name="twitter:image" content="${site}/og/og-releases.png">
  <link rel="canonical" href="${text.canonical}">
  <link rel="alternate" hreflang="en" href="${site}/releases.html">
  <link rel="alternate" hreflang="es" href="${site}/es/releases.html">
  <link rel="alternate" hreflang="x-default" href="${site}/releases.html">
  <link rel="icon" type="image/png" href="/images/icon.png">
  <link rel="apple-touch-icon" href="/images/icon.png">
  <link rel="manifest" href="/manifest.webmanifest">
  <link rel="alternate" type="application/rss+xml" title="Cocxy Terminal Appcast" href="/appcast.xml">
  <link rel="alternate" type="application/rss+xml" title="Cocxy Terminal Updates" href="/feed.xml">
  <link rel="alternate" type="application/rss+xml" title="Cocxy Terminal Releases" href="/releases.xml">
  <link rel="stylesheet" href="/css/style.css?v=${version}">
  <script type="application/ld+json">
${structuredData}
  </script>
</head>
<body>
<a class="skip-link" href="#main">${text.skip}</a>
<header class="site-header">
  <nav class="nav container" aria-label="Main navigation">
    <a class="nav-logo" href="${locale === 'es' ? '/es/' : '/'}" aria-label="Cocxy Terminal">
      <img src="/images/icon.png" width="32" height="32" alt="">
      <span>Cocxy</span>
    </a>
    <button class="nav-toggle" type="button" aria-expanded="false" aria-controls="site-menu">
      <span></span><span></span><span></span>
      <span class="sr-only">Open navigation</span>
    </button>
    <div class="nav-links" id="site-menu">
      <a href="${locale === 'es' ? '/es/features.html' : '/features.html'}">${text.navFeatures}</a>
      <a href="${locale === 'es' ? '/es/features/agents.html' : '/features/agents.html'}">${text.navAgents}</a>
      <a href="${locale === 'es' ? '/es/privacy.html' : '/privacy.html'}">${text.navPrivacy}</a>
      <a href="${locale === 'es' ? '/es/security.html' : '/security.html'}">${text.navSecurity}</a>
      <a href="${locale === 'es' ? '/es/docs/' : '/docs/'}">${text.navDocs}</a>
      <a class="nav-cta" href="#download">${text.navDownload}</a>
      <button class="theme-toggle" type="button" aria-label="${text.theme}" title="${text.theme}">
        <span class="theme-toggle__sun" aria-hidden="true">☀</span>
        <span class="theme-toggle__moon" aria-hidden="true">◐</span>
      </button>
      <a href="${text.languageHref}" hreflang="${locale === 'es' ? 'en' : 'es'}">${text.language}</a>
      <a href="https://github.com/salp2403/cocxy-terminal" target="_blank" rel="noopener noreferrer">GitHub</a>
    </div>
  </nav>
</header>
<main id="main">
  <section class="page-hero">
    <div class="container">
      <p class="eyebrow">${text.eyebrow}</p>
      <h1>${text.heading}</h1>
      <p>${text.intro}</p>
    </div>
  </section>
  <section class="section" id="download">
    <div class="container">
      ${cards}
      ${showMore}
    </div>
  </section>
</main>
<footer class="site-footer">
  <div class="container footer-grid">
    <div>
      <a class="footer-brand" href="${locale === 'es' ? '/es/' : '/'}"><img src="/images/icon.png" width="28" height="28" alt=""><span>Cocxy Terminal</span></a>
      <p>${text.footer}</p>
    </div>
    <nav aria-label="Footer links">
      <a href="${locale === 'es' ? '/es/privacy.html' : '/privacy.html'}">${text.navPrivacy}</a>
      <a href="${locale === 'es' ? '/es/security.html' : '/security.html'}">${text.navSecurity}</a>
      <a href="${locale === 'es' ? '/es/releases.html' : '/releases.html'}">${text.heading}</a>
      <a href="https://github.com/salp2403/cocxy-terminal" target="_blank" rel="noopener noreferrer">GitHub</a>
    </nav>
    <p class="footer-credit">${text.madeBy}</p>
  </div>
</footer>
<script src="/js/main.js" defer></script>
<script src="/js/theme-switcher.js" defer></script>
</body>
</html>
`;

fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, html);
console.log(`Generated ${path.relative(repoRoot, output)} with ${releases.length} releases.`);
