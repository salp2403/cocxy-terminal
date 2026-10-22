#!/usr/bin/env node
// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { siteFooter, siteHeader, themeBootScript, themeHeadTags } from './site-chrome.mjs';

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
const repository = 'https://github.com/salp2403/cocxy-terminal';

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
      languageHref: '/releases.html',
      ogImage: `${site}/og/og-es-releases.jpg`,
      eyebrow: 'Versiones',
      heading: 'Versiones',
      intro: 'Historial de versiones, notas y descargas de Cocxy Terminal.',
      allReleases: 'Todas las versiones en GitHub',
      latest: 'Actual',
      download: 'Descargar DMG',
      notes: 'Notas en GitHub',
      compare: 'Comparar cambios',
      details: 'Qué cambió',
      englishNotes: 'Las notas de cada versión se publican en inglés.',
      older: 'Mostrar versiones anteriores',
      canonical: `${site}/es/releases.html`,
      inLanguage: 'es-HN',
      dateLocale: 'es-ES',
      sections: {
        "What's Changed": 'Cambios',
        'New Contributors': 'Nuevas contribuciones',
        Added: 'Añadido',
        Changed: 'Cambiado',
        Fixed: 'Corregido',
        Removed: 'Retirado',
        Security: 'Seguridad',
      },
    }
  : {
      htmlLang: 'en',
      title: 'Releases - Cocxy Terminal',
      description: 'Release history and changelog for Cocxy Terminal.',
      locale: 'en_US',
      home: 'Home',
      languageHref: '/es/releases.html',
      ogImage: `${site}/og/og-releases.jpg`,
      eyebrow: 'Releases',
      heading: 'Releases',
      intro: 'Release history, notes, and downloads for Cocxy Terminal.',
      allReleases: 'All releases on GitHub',
      latest: 'Latest',
      download: 'Download DMG',
      notes: 'Notes on GitHub',
      compare: 'Compare changes',
      details: 'What changed',
      englishNotes: '',
      older: 'Show older releases',
      canonical: `${site}/releases.html`,
      inLanguage: 'en',
      dateLocale: 'en-US',
      sections: {},
    };

// Published release bodies are history on GitHub; these fix typos on the
// site copy without rewriting what each release said.
const noteCorrections = [
  ['reparenteea', 'reparents'],
];

// Sections every release body repeats; the page shows them once instead.
const boilerplateSections = new Set(['Install', 'System Requirements']);

function escapeHTML(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function inlineMarkdown(value) {
  return escapeHTML(value)
    .replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/https:\/\/github\.com\/salp2403\/cocxy-terminal\/pull\/(\d+)/g, `<a href="${repository}/pull/$1">#$1</a>`);
}

function correct(value) {
  return noteCorrections.reduce((line, [wrong, right]) => line.replaceAll(wrong, right), value);
}

function translateRequirement(line) {
  if (locale !== 'es') return line;
  return line
    .replace(/ or later$/, ' o posterior')
    .replace(/^Apple Silicon or Intel Mac$/, 'Mac con Apple Silicon o Intel')
    .replace(/^Apple Silicon Mac$/, 'Mac con Apple Silicon');
}

function parseBody(body) {
  const sections = [];
  const requirements = [];
  let compareURL = '';
  let current = null;
  for (const rawLine of String(body ?? '').split(/\r?\n/)) {
    const line = correct(rawLine.trim());
    if (!line) continue;
    const changelog = line.match(/^\*\*Full Changelog\*\*:\s*(\S+)/);
    if (changelog) {
      compareURL = changelog[1];
      continue;
    }
    const heading = line.match(/^#{2,3}\s+(.+)$/);
    if (heading) {
      const title = heading[1].trim();
      current = /^Cocxy Terminal v?\d/.test(title) ? null : { title, lines: [] };
      if (current) sections.push(current);
      continue;
    }
    if (!current) continue;
    if (current.title === 'System Requirements') {
      if (/^[-*] /.test(line)) requirements.push(translateRequirement(line.slice(2)));
      continue;
    }
    current.lines.push(line);
  }
  const notes = sections.filter((section) => !boilerplateSections.has(section.title) && section.lines.length);
  return { notes, requirements, compareURL };
}

// Release bodies are written in English; the Spanish page translates the
// headings and marks the note text so assistive technology reads it as English.
function notesHTML(notes) {
  const noteLang = locale === 'es' ? ' lang="en"' : '';
  return notes.map((section) => {
    const items = [];
    const paragraphs = [];
    for (const line of section.lines) {
      if (/^[-*] /.test(line)) items.push(`<li>${inlineMarkdown(line.slice(2))}</li>`);
      else paragraphs.push(`<p${noteLang}>${inlineMarkdown(line)}</p>`);
    }
    const heading = text.sections[section.title] ?? section.title;
    return `<h3>${escapeHTML(heading)}</h3>${paragraphs.join('')}${items.length ? `<ul${noteLang}>${items.join('')}</ul>` : ''}`;
  }).join('');
}

function formatDate(date) {
  if (!date) return '';
  return new Intl.DateTimeFormat(text.dateLocale, { dateStyle: 'long', timeZone: 'UTC' }).format(new Date(`${date}T00:00:00Z`));
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
  const downloadURL = `${repository}/releases/download/${encodeURIComponent(tag)}/CocxyTerminal-${escapeHTML(releaseVersion)}.dmg`;
  const releaseURL = `${repository}/releases/tag/${encodeURIComponent(tag)}`;
  const hidden = index >= 5 ? ' hidden data-release-hidden="true"' : '';
  const latest = index === 0;
  const badge = latest ? `<span class="rel-badge">${text.latest}</span>` : '';
  const { notes, requirements, compareURL } = parseBody(release.body);
  const englishNote = text.englishNotes ? `<p class="rel-note">${text.englishNotes}</p>` : '';
  const renderedNotes = notes.length ? `<div class="rel-notes">${notesHTML(notes)}</div>` : '';
  const body = !renderedNotes
    ? ''
    : latest
      ? `${englishNote}${renderedNotes}`
      : `<details class="rel-details"><summary>${text.details}</summary>${englishNote}${renderedNotes}</details>`;
  const compare = compareURL.startsWith(`${repository}/compare/`)
    ? `<a class="text-link" href="${escapeHTML(compareURL)}" target="_blank" rel="noopener noreferrer">${text.compare}</a>`
    : '';

  releaseItems.push({
    '@type': 'SoftwareApplication',
    name: `Cocxy Terminal ${tag}`,
    applicationCategory: 'DeveloperApplication',
    operatingSystem: 'macOS 15.0+',
    softwareVersion: releaseVersion,
    url: releaseURL,
    downloadUrl: downloadURL,
    datePublished: date,
  });

  return [
    `<article class="rel-card${latest ? ' rel-card--latest' : ''}" id="v${escapeHTML(releaseVersion.replaceAll('.', '-'))}"${hidden}>`,
    `  <div class="rel-header"><h2>${escapeHTML(tag)}</h2>${badge}<time datetime="${escapeHTML(date)}">${escapeHTML(formatDate(date))}</time></div>`,
    requirements.length ? `  <p class="rel-meta">${requirements.map(escapeHTML).join(' · ')}</p>` : '',
    body ? `  ${body}` : '',
    `  <div class="rel-actions"><a href="${downloadURL}" class="button ${latest ? 'button-primary' : 'button-secondary'}">${text.download}</a><a href="${releaseURL}" target="_blank" rel="noopener noreferrer" class="text-link">${text.notes}</a>${compare}</div>`,
    '</article>',
  ].filter(Boolean).join('\n');
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
      operatingSystem: 'macOS 15.0+',
      softwareVersion: version,
      url: site,
      downloadUrl: `${repository}/releases/latest`,
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
  ${themeHeadTags()}
  <link rel="stylesheet" href="/css/style.css?v=${version}">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Cocxy Terminal">
  <meta property="og:title" content="${text.title}">
  <meta property="og:description" content="${text.description}">
  <meta property="og:url" content="${text.canonical}">
  <meta property="og:image" content="${text.ogImage}">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:image:alt" content="${text.title}">
  <meta property="og:locale" content="${text.locale}">
  <meta name="twitter:card" content="summary_large_image">
  <link rel="canonical" href="${text.canonical}">
  <link rel="alternate" hreflang="en" href="${site}/releases.html">
  <link rel="alternate" hreflang="es" href="${site}/es/releases.html">
  <link rel="alternate" hreflang="x-default" href="${site}/releases.html">
  <link rel="icon" type="image/svg+xml" href="/images/icon.svg">
  <link rel="apple-touch-icon" href="/images/icon-192.png">
  <link rel="manifest" href="/manifest.webmanifest">
  <link rel="alternate" type="application/rss+xml" title="Cocxy Terminal Appcast" href="/appcast.xml">
  <link rel="alternate" type="application/rss+xml" title="Cocxy Terminal Updates" href="/feed.xml">
  <link rel="alternate" type="application/rss+xml" title="Cocxy Terminal Releases" href="/releases.xml">
  ${themeBootScript()}
  <script type="application/ld+json">
${structuredData}
  </script>
</head>
<body>
${siteHeader({ lang: locale, langHref: text.languageHref, downloadHref: '#download' })}
<main id="main">
  <section class="page-hero"><div class="container">
    <p class="eyebrow">${text.eyebrow}</p>
    <h1>${text.heading}</h1>
    <p>${text.intro}</p>
    <div class="page-hero__actions"><a class="button button-secondary" href="${repository}/releases" target="_blank" rel="noopener noreferrer">${text.allReleases}</a></div>
  </div></section>
  <section class="section section--tight" id="download">
    <div class="container releases">
      ${cards}
      ${showMore}
    </div>
  </section>
</main>
${siteFooter(locale)}
<script src="/js/theme-switcher.js?v=${version}" defer></script>
<script src="/js/main.js?v=${version}" defer></script>
</body>
</html>
`;

fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, html);
console.log(`Generated ${path.relative(repoRoot, output)} with ${releases.length} releases.`);
