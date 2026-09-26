#!/usr/bin/env node
// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { appArtwork, compatibilityBlock, stateChips } from './site-components.mjs';
import {
  homeArchitecture,
  homeClosing,
  homeDemo,
  homeFaq,
  homeFaqSection,
  homeMoments,
  homePrivacy,
} from './site-home.mjs';
import {
  alternateLinks,
  breadcrumbSchema,
  canonicalFor,
  escapeHTML,
  escapeXML,
  icon,
  json,
  logoImage,
  pageToSlug,
  site,
} from './site-core.mjs';
import { siteFooter, siteHeader, themeBootScript, themeHeadTags } from './site-chrome.mjs';
import { agents, docPages, faqQuestions, featurePages, topPages } from './site-data.mjs';
import { downloadSection, emailLink, pageHero } from './site-sections.mjs';
import { agentsPageBody, featureDetailBody, featureHubBody, featureTile } from './site-pages-features.mjs';
import { docDetailBody, docsHubBody, movedBody } from './site-pages-docs.mjs';
import {
  architectureBody,
  channelsBody,
  faqBody,
  notFoundBody,
  privacyBody,
  roadmapBody,
  securityBody,
  sponsorsBody,
  whyBody,
} from './site-pages-info.mjs';
import { productShot, tourVideoURLs } from './site-shots.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(__dirname, '..');
const publicRoot = path.join(webRoot, 'public');
const repoRoot = path.resolve(webRoot, '..');
const assetVersion = '0.0.0';
const cssHref = `/css/style.css?v=${assetVersion}`;
const releaseVersion = assetVersion;
const contentUpdated = '2026-09-26';
const scriptSrc = (file) => `/js/${file}?v=${assetVersion}`;

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function write(relative, content) {
  const target = path.join(publicRoot, relative);
  ensureDir(path.dirname(target));
  fs.writeFileSync(target, `${content.trim()}\n`);
}

function writeWeb(relative, content) {
  const target = path.join(webRoot, relative);
  ensureDir(path.dirname(target));
  fs.writeFileSync(target, `${content.trim()}\n`);
}

function buildCSSBundle() {
  const cssDir = path.join(publicRoot, 'css');
  const parts = ['tokens.css', 'base.css', 'components.css', 'content.css', 'glass.css', 'pages.css', 'interior.css', 'home.css', 'home-sections.css', 'artwork.css', 'print.css'];
  const bundled = parts.map((file) => {
    const source = fs.readFileSync(path.join(cssDir, file), 'utf8').trim();
    return source;
  }).join('\n\n');
  fs.writeFileSync(path.join(cssDir, 'style.css'), `${minifyCSS(bundled)}\n`);
}

function stripCSSComments(source) {
  let output = '';
  let quote = null;

  for (let index = 0; index < source.length; index += 1) {
    const current = source[index];
    const next = source[index + 1];

    if (quote) {
      output += current;
      if (current === '\\') {
        index += 1;
        if (index < source.length) output += source[index];
      } else if (current === quote) {
        quote = null;
      }
      continue;
    }

    if (current === '"' || current === "'") {
      quote = current;
      output += current;
      continue;
    }

    if (current === '/' && next === '*') {
      index += 2;
      while (index < source.length && !(source[index] === '*' && source[index + 1] === '/')) {
        index += 1;
      }
      index += 1;
      continue;
    }

    output += current;
  }

  return output;
}

function minifyCSS(source) {
  return stripCSSComments(source)
    .replace(/\s+/g, ' ')
    .replace(/\s*([{}:;,>])\s*/g, '$1')
    .replace(/;}/g, '}')
    .trim();
}

function head({ title, description, page, lang = 'en', type = 'website', robots = 'index, follow, max-snippet:-1, max-image-preview:large' }) {
  const htmlLang = lang === 'es' ? 'es-HN' : 'en';
  const ogLocale = lang === 'es' ? 'es_HN' : 'en_US';
  const url = canonicalFor(page, lang);
  const titleFull = `${title} - Cocxy Terminal`;
  const ogImage = `${site}/og/og-${lang === 'es' ? 'es-' : ''}${pageToSlug(page)}.jpg`;
  return `<!DOCTYPE html>
<html lang="${htmlLang}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHTML(titleFull)}</title>
  <meta name="description" content="${escapeHTML(description)}">
  <meta name="author" content="Said Arturo Lopez">
  <meta name="robots" content="${robots}">
  ${themeHeadTags()}
  <link rel="stylesheet" href="${cssHref}">
  <meta property="og:type" content="${type}">
  <meta property="og:site_name" content="Cocxy Terminal">
  <meta property="og:title" content="${escapeHTML(titleFull)}">
  <meta property="og:description" content="${escapeHTML(description)}">
  <meta property="og:url" content="${url}">
  <meta property="og:image" content="${ogImage}">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:image:alt" content="${escapeHTML(titleFull)}">
  <meta property="og:locale" content="${ogLocale}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escapeHTML(titleFull)}">
  <meta name="twitter:description" content="${escapeHTML(description)}">
  <meta name="twitter:image" content="${ogImage}">
  ${alternateLinks(page, lang)}
  <link rel="icon" type="image/svg+xml" href="/images/icon.svg">
  <link rel="apple-touch-icon" href="/images/icon-192.png">
  <link rel="manifest" href="/manifest.webmanifest">
  <link rel="alternate" type="application/rss+xml" title="Cocxy Terminal Appcast" href="/appcast.xml">
  <link rel="alternate" type="application/rss+xml" title="Cocxy Terminal Updates" href="/feed.xml">
  <link rel="alternate" type="application/rss+xml" title="Cocxy Terminal Releases" href="/releases.xml">
  ${themeBootScript()}
</head>`;
}

function schemaScripts(schema = []) {
  return schema.map((entry) => `<script type="application/ld+json">\n${json(entry)}\n</script>`).join('\n');
}

function nav(lang = 'en', active = '') {
  const es = lang === 'es';
  return siteHeader({
    lang,
    active,
    langHref: es ? alternateCurrent('en') : alternateCurrent('es'),
    downloadHref: pageHasLocalDownload(currentPage) ? '#download' : `${es ? '/es/' : '/'}#download`,
  });
}

let currentPage = '/';
function alternateCurrent(lang) {
  return lang === 'es' ? `/es${currentPage === '/' ? '/' : currentPage}` : currentPage;
}

function pageHasLocalDownload(page) {
  if (page === '/') return true;
  if (page === '/releases.html') return true;
  if (page === '/features.html' || page.startsWith('/features/')) return true;
  return topPages.some((item) => `/${item[0]}.html` === page && item[0] !== 'agents');
}

function footer(lang = 'en') {
  return `${siteFooter(lang)}
<script src="${scriptSrc('theme-switcher.js')}" defer></script>
<script src="${scriptSrc('main.js')}" defer></script>
</body>
</html>`;
}

function softwareSchema(lang = 'en') {
  return {
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    name: 'Cocxy Terminal',
    applicationCategory: 'DeveloperApplication',
    applicationSubCategory: 'Terminal Emulator',
    operatingSystem: 'macOS 15.0+',
    url: site,
    downloadUrl: 'https://github.com/salp2403/cocxy-terminal/releases/latest',
    softwareVersion: releaseVersion,
    license: 'https://opensource.org/licenses/MIT',
    isAccessibleForFree: true,
    inLanguage: lang === 'es' ? 'es-HN' : 'en',
    featureList: lang === 'es' ? [
      'Detección local de agentes en tiempo real',
      'Bóveda cifrada de sesiones',
      'Panel de revisión de código',
      'Espacio Markdown nativo',
      'Renderizado de terminal por GPU',
      'Espacios remotos',
      'Navegador incorporado',
      'Hooks de plugins',
      'Integración con la shell',
      'Cero telemetría',
    ] : [
      'Real-time local agent detection',
      'Encrypted session Vault',
      'Inline code review panel',
      'Native Markdown workspace',
      'GPU terminal rendering',
      'Remote workspaces',
      'Built-in browser',
      'Plugin hooks',
      'Shell integration',
      'Zero telemetry',
    ],
    offers: {
      '@type': 'Offer',
      price: '0',
      priceCurrency: 'USD',
      availability: 'https://schema.org/InStock',
    },
    author: { '@type': 'Person', name: 'Said Arturo Lopez', url: 'https://github.com/salp2403' },
  };
}

function layout({ page, lang = 'en', title, description, active = '', schema = [], body, robots }) {
  currentPage = page;
  return `${head({ title, description, page, lang, robots })}\n<body>\n${nav(lang, active)}\n<main id="main">\n${body}\n</main>\n${schemaScripts(schema)}\n${footer(lang)}`;
}

function home(lang = 'en') {
  const es = lang === 'es';
  const page = '/';
  const title = es ? 'La terminal nativa de macOS para agentes de IA' : 'The native macOS terminal for AI coding agents';
  const description = es
    ? 'Cocxy es una terminal nativa para macOS que sigue a tus agentes de IA en tiempo real, con revisión de código, proyectos, espejo móvil cifrado y cero telemetría.'
    : 'Cocxy is a native macOS terminal that follows your AI coding agents in real time, with code review, projects, an encrypted phone mirror, and zero telemetry.';
  const faq = homeFaq(lang);
  const schema = [
    { '@context': 'https://schema.org', '@type': 'Organization', name: 'Cocxy Terminal', url: site, logo: `${site}/images/icon.png`, founder: { '@type': 'Person', name: 'Said Arturo Lopez' } },
    { '@context': 'https://schema.org', '@type': 'WebSite', url: site, name: 'Cocxy Terminal', potentialAction: { '@type': 'SearchAction', target: `${site}${es ? '/es' : ''}/docs/?q={search_term_string}`, 'query-input': 'required name=search_term_string' } },
    softwareSchema(lang),
    {
      '@context': 'https://schema.org',
      '@type': 'FAQPage',
      mainEntity: faq.map(([question, answer]) => ({ '@type': 'Question', name: question, acceptedAnswer: { '@type': 'Answer', text: answer } })),
    },
    breadcrumbSchema([[es ? 'Inicio' : 'Home', es ? '/es/' : '/']]),
  ];
  const tour = tourVideoURLs();
  if (tour) {
    schema.push({
      '@context': 'https://schema.org',
      '@type': 'VideoObject',
      name: es ? 'Recorrido por Cocxy Terminal' : 'Cocxy Terminal tour',
      description,
      thumbnailUrl: `${site}${tour.poster}`,
      uploadDate: contentUpdated,
      contentUrl: `${site}${tour.mp4}`,
      embedUrl: `${site}${es ? '/es' : ''}/#demo`,
    });
  }
  const body = `<section id="hero" class="hero" aria-labelledby="hero-title">
  <div class="container hero__intro">
    <p class="hero__brand">${logoImage({ width: 32, height: 32 })}<span>Cocxy Terminal</span></p>
    <h1 id="hero-title" class="hero__title">${es ? 'Cada agente, <span>siempre a la vista.</span>' : 'Every agent, <span>in plain sight.</span>'}</h1>
    <p class="hero__lede">${es ? 'Una terminal nativa para macOS que sigue a cada agente de código en tiempo real, te deja revisar sus cambios antes de aplicarlos y viene sin telemetría.' : 'A native macOS terminal that follows every coding agent in real time, lets you review its changes before they land, and ships with zero telemetry.'}</p>
    <div class="hero__actions">
      <a class="button button-primary button-lg" href="https://github.com/salp2403/cocxy-terminal/releases/download/v0.0.0/CocxyTerminal-0.0.0.dmg">${es ? 'Descargar para macOS' : 'Download for macOS'}</a>
      <a class="button button-secondary button-lg" href="#download">${es ? 'Instalar con Homebrew' : 'Install with Homebrew'}</a>
    </div>
    <div class="hero-version"><span class="version-badge">v0.0.0</span><span>macOS 15.0+</span><span>${es ? 'Cero telemetría' : 'Zero telemetry'}</span></div>
  </div>
  <figure class="hero-shot container">
    <div class="hero-shot__stage">
      ${productShot({
        slot: 'hero',
        alt: es ? 'Ventana de Cocxy Terminal con sesiones de agentes en la barra lateral, una terminal y el panel de agentes' : 'Cocxy Terminal window with agent sessions in the sidebar, a terminal, and the agent panel',
        artworkLabel: es ? 'Ilustración de la ventana de Cocxy: sesiones, terminal y panel de agentes' : 'Illustration of the Cocxy window: sessions, terminal, and agent panel',
        artwork: appArtwork('hero'),
        priority: true,
      })}
      ${stateChips(lang)}
    </div>
  </figure>
  <div class="container">
    ${compatibilityBlock(lang)}
  </div>
</section>
<section class="facts" aria-label="${es ? 'Datos clave' : 'Key facts'}">
  <div class="container stats-grid">
    ${stat('11', es ? 'perfiles de agente' : 'agent profiles')}
    ${stat('21', es ? 'idiomas' : 'languages')}
    ${stat('0', es ? 'telemetría' : 'telemetry')}
    ${stat('MIT', es ? 'licencia' : 'license')}
    ${stat('15+', 'macOS')}
  </div>
</section>
<section class="section" id="comparison" aria-labelledby="different-title">
  <div class="container">
    <div class="section-header" data-reveal="fade-up">
      <p class="eyebrow">${es ? 'Por qué Cocxy' : 'Why Cocxy'}</p>
      <h2 id="different-title">${es ? 'Pensada para agentes desde el primer día.' : 'Built around agents, not bolted on.'}</h2>
      <p>${es ? 'Cocxy trata cada sesión de agente como algo que entender, no solo como texto que pasa.' : 'Cocxy treats every agent session as something to understand, not just text scrolling by.'}</p>
    </div>
    <div class="pillars" data-reveal="stagger">
      <article class="pillar is-working">
        ${icon('spark')}
        <h3>${es ? 'Atenta a los agentes' : 'Agent-aware'}</h3>
        <p>${es ? 'Cuatro capas de detección (hooks, señales de terminal, patrones de proceso y tiempos) te dicen cuándo un agente piensa, trabaja, te espera o termina.' : 'Four detection layers (hooks, terminal signals, process patterns, and timing) tell you when an agent is thinking, working, waiting for you, or done.'}</p>
      </article>
      <article class="pillar is-done">
        ${icon('lock')}
        <h3>${es ? 'Local primero' : 'Local-first'}</h3>
        <p>${es ? 'Las sesiones, la Bóveda cifrada, los proyectos y las revisiones se quedan en tu Mac. Cocxy no tiene analíticas, ni subida automática de fallos, ni cuentas.' : 'Sessions, the encrypted Vault, projects, and reviews stay on your Mac. Cocxy has no analytics, no automatic crash upload, and no account.'}</p>
      </article>
      <article class="pillar is-waiting">
        ${icon('gpu')}
        <h3>${es ? 'Nativa de verdad' : 'Native to the core'}</h3>
        <p>${es ? 'Swift y AppKit sobre CocxyCore, un motor de terminal escrito en Zig que dibuja con Metal en la GPU.' : 'Swift and AppKit on top of CocxyCore, a terminal engine written in Zig and rendered with Metal on the GPU.'}</p>
      </article>
    </div>
  </div>
</section>
${homeMoments(lang)}
<section class="section" id="features" aria-labelledby="features-title">
  <div class="container">
    <div class="section-header" data-reveal="fade-up">
      <p class="eyebrow">${es ? 'Funciones' : 'Features'}</p>
      <h2 id="features-title">${es ? 'Todo lo que rodea al agente, integrado.' : 'Everything around the agent, built in.'}</h2>
      <p>${es ? 'Terminal, revisión, Bóveda, navegador, Markdown y remotos comparten una sola ventana nativa.' : 'Terminal, review, Vault, browser, Markdown, and remotes share one native window.'}</p>
    </div>
    <div class="feature-tiles" data-reveal="stagger">
      ${featurePages.map((feature) => featureTile(feature, lang)).join('\n')}
    </div>
    <p class="section-footer"><a class="text-link" href="${es ? '/es/features.html' : '/features.html'}">${es ? 'Ver todas las funciones' : 'See all features'}</a></p>
  </div>
</section>
${homePrivacy(lang)}
${homeArchitecture(lang)}
${homeDemo(lang)}
${homeFaqSection(lang)}
${downloadSection(lang)}
${homeClosing(lang, logoImage({ width: 112, height: 112 }))}`;
  return layout({ page, lang, title, description, active: '', schema, body });
}

function stat(value, label) {
  return `<div class="stat"><strong>${value}</strong><span>${label}</span></div>`;
}

function topPage(slug, lang = 'en') {
  const entry = topPages.find((item) => item[0] === slug);
  const es = lang === 'es';
  const page = `/${slug}.html`;
  const title = es ? entry[2] : entry[1];
  const description = es ? entry[4] : entry[3];
  const bodies = {
    privacy: privacyBody,
    security: securityBody,
    architecture: architectureBody,
    'why-cocxy': whyBody,
    faq: faqBody,
    channels: channelsBody,
    press: pressBody,
    roadmap: roadmapBody,
    sponsors: sponsorsBody,
  };
  const body = slug === 'agents'
    ? agentsPageBody(lang, { title, description })
    : `${pageHero({ lang, eyebrow: 'Cocxy Terminal', title, description })}\n${bodies[slug](lang)}\n${downloadSection(lang)}`;
  const schema = [breadcrumbSchema([[es ? 'Inicio' : 'Home', es ? '/es/' : '/'], [title, page]])];
  if (slug === 'press') {
    schema.push({
      '@context': 'https://schema.org',
      '@type': 'Article',
      headline: title,
      description,
      image: `${site}/images/og-image.png`,
      author: { '@type': 'Person', name: 'Said Arturo Lopez' },
      publisher: { '@type': 'Organization', name: 'Cocxy Terminal', logo: { '@type': 'ImageObject', url: `${site}/images/icon.png` } },
      inLanguage: es ? 'es-HN' : 'en',
    });
  }
  if (slug === 'faq') {
    schema.push({
      '@context': 'https://schema.org',
      '@type': 'FAQPage',
      mainEntity: faqQuestions(lang).map(([question, answer]) => ({
        '@type': 'Question',
        name: question,
        acceptedAnswer: { '@type': 'Answer', text: answer },
      })),
    });
  }
  return layout({
    page,
    lang,
    title,
    description,
    active: ['privacy', 'security', 'agents'].includes(slug) ? slug : '',
    schema,
    body,
  });
}

function featureHubPage(lang = 'en') {
  const es = lang === 'es';
  const page = '/features.html';
  const description = es ? topPages[0][4] : topPages[0][3];
  return layout({
    page,
    lang,
    title: es ? 'Todas las funciones' : 'All Features',
    description,
    active: 'features',
    schema: [
      breadcrumbSchema([[es ? 'Inicio' : 'Home', es ? '/es/' : '/'], [es ? 'Funciones' : 'Features', page]]),
      {
        '@context': 'https://schema.org',
        '@type': 'ItemList',
        name: es ? 'Funciones de Cocxy Terminal' : 'Cocxy Terminal features',
        numberOfItems: featurePages.length,
        itemListElement: featurePages.map((feature, index) => ({
          '@type': 'ListItem',
          position: index + 1,
          name: es ? feature.esTitle : feature.title,
          url: `${site}${es ? '/es' : ''}/features/${feature.slug}.html`,
        })),
      },
    ],
    body: `${featureHubBody(lang, description)}\n${downloadSection(lang)}`,
  });
}

function featureDetailPage(feature, lang = 'en') {
  const es = lang === 'es';
  const page = `/features/${feature.slug}.html`;
  const title = es ? feature.esTitle : feature.title;
  const description = es ? feature.esSummary : feature.summary;
  const isAgents = feature.slug === 'agents';
  return layout({
    page,
    lang,
    title,
    description,
    active: isAgents ? 'agents' : 'features',
    schema: [
      breadcrumbSchema([[es ? 'Inicio' : 'Home', es ? '/es/' : '/'], [es ? 'Funciones' : 'Features', es ? '/es/features.html' : '/features.html'], [title, page]]),
      {
        '@context': 'https://schema.org',
        '@type': isAgents ? 'ItemList' : 'TechArticle',
        name: title,
        description,
        inLanguage: es ? 'es-HN' : 'en',
        ...(isAgents ? { numberOfItems: agents.length, itemListElement: agents.map((agent, index) => ({ '@type': 'ListItem', position: index + 1, name: agent[0] })) } : {}),
      },
    ],
    body: `${featureDetailBody(feature, lang)}\n${downloadSection(lang)}`,
  });
}

function docsHubPage(lang = 'en') {
  const es = lang === 'es';
  const page = '/docs/';
  const description = es ? 'Documentación para instalar, configurar y extender Cocxy Terminal.' : 'Documentation for installing, configuring, and extending Cocxy Terminal.';
  return layout({ page, lang, title: es ? 'Documentación' : 'Documentation', description, active: 'docs', schema: [breadcrumbSchema([[es ? 'Inicio' : 'Home', es ? '/es/' : '/'], [es ? 'Documentación' : 'Docs', page]])], body: docsHubBody(lang, description) });
}

function docDetailPage(doc, lang = 'en') {
  const [slug, enTitle, esTitle, enDesc, esDesc] = doc;
  const es = lang === 'es';
  const page = `/docs/${slug}.html`;
  const title = es ? esTitle : enTitle;
  const description = es ? esDesc : enDesc;
  return layout({ page, lang, title, description, active: 'docs', schema: [breadcrumbSchema([[es ? 'Inicio' : 'Home', es ? '/es/' : '/'], [es ? 'Documentación' : 'Docs', es ? '/es/docs/' : '/docs/'], [title, page]])], body: docDetailBody(doc, lang) });
}

function movedPage(lang = 'en') {
  const es = lang === 'es';
  const page = '/getting-started.html';
  return layout({
    page,
    lang,
    title: es ? 'Primer arranque' : 'First Run',
    description: es ? 'Esta guía se movió al hub de documentación.' : 'This guide moved into the documentation hub.',
    active: 'docs',
    schema: [breadcrumbSchema([[es ? 'Inicio' : 'Home', es ? '/es/' : '/'], [es ? 'Primer arranque' : 'First Run', page]])],
    body: `${movedBody(lang)}\n${downloadSection(lang)}`,
  });
}

function releasesPage(lang = 'en') {
  const es = lang === 'es';
  const page = '/releases.html';
  return layout({
    page,
    lang,
    title: es ? 'Versiones' : 'Releases',
    description: es ? 'Historial de versiones y cambios de Cocxy Terminal.' : 'Release history and changelog for Cocxy Terminal.',
    schema: [
      breadcrumbSchema([[es ? 'Inicio' : 'Home', es ? '/es/' : '/'], [es ? 'Versiones' : 'Releases', page]]),
      {
        '@context': 'https://schema.org',
        '@type': 'CollectionPage',
        '@id': `${site}${es ? '/es' : ''}/releases.html#releases`,
        name: es ? 'Versiones de Cocxy Terminal' : 'Cocxy Terminal Releases',
        url: `${site}${es ? '/es' : ''}/releases.html`,
        mainEntity: { '@type': 'ItemList', itemListElement: [] },
        about: softwareSchema(lang),
      },
      softwareSchema(lang),
    ],
    body: `${pageHero({
      lang,
      eyebrow: es ? 'Versiones' : 'Releases',
      title: es ? 'Versiones' : 'Releases',
      description: es ? 'Historial de versiones, notas y descargas de Cocxy Terminal.' : 'Release history, notes, and downloads for Cocxy Terminal.',
      actions: `<a class="button button-secondary" href="https://github.com/salp2403/cocxy-terminal/releases" target="_blank" rel="noopener noreferrer">${es ? 'Todas las versiones en GitHub' : 'All releases on GitHub'}</a>`,
    })}\n${downloadSection(lang)}`,
  });
}

function notFoundPage(lang = 'en') {
  const es = lang === 'es';
  return layout({
    page: '/404.html',
    lang,
    title: es ? 'Página no encontrada' : 'Page not found',
    description: es ? 'La página que buscas no existe en cocxy.dev.' : 'The page you are looking for does not exist on cocxy.dev.',
    robots: 'noindex, follow',
    schema: [breadcrumbSchema([[es ? 'Inicio' : 'Home', es ? '/es/' : '/'], [es ? 'Página no encontrada' : 'Page not found', '/404.html']])],
    body: notFoundBody(lang),
  });
}

function pressBody(lang) {
  const es = lang === 'es';
  return `<section class="section section--tight"><div class="container detail-grid">
  <article class="card"><h2>${es ? 'Borrador de nota de lanzamiento' : 'Launch note draft'}</h2><p>${es ? 'Cocxy Terminal es una terminal nativa para macOS, local primero, con Bóveda cifrada, revisión de código y cero telemetría.' : 'Cocxy Terminal is a native macOS terminal, local-first, with encrypted Vault, code review, and zero telemetry.'}</p></article>
  <article class="card"><h2>${es ? 'Guion de demo' : 'Demo outline'}</h2><p>${es ? 'Mostrar terminal, agentes, Bóveda, navegador, Markdown, remotos y descarga en menos de tres minutos.' : 'Show terminal, agents, Vault, browser, Markdown, remotes, and download in under three minutes.'}</p></article>
  <article class="card"><h2>${es ? 'Recursos visuales' : 'Visual assets'}</h2><ul class="asset-list"><li><a href="/images/icon.png">${es ? 'Icono de la app (PNG)' : 'App icon (PNG)'}</a></li><li><a href="/images/og-image.png">${es ? 'Tarjeta de marca (PNG)' : 'Brand card (PNG)'}</a></li></ul></article>
  <article class="card"><h2>${es ? 'Datos' : 'Facts'}</h2><ul><li>Cocxy Terminal</li><li>macOS 15+</li><li>MIT</li><li>${emailLink()}</li></ul></article>
</div>
<p class="section-footer">${es ? 'Sin sistema de telemetr&iacute;a.' : 'No telemetry pipeline.'}</p></section>`;
}

function docsSearchIndex() {
  return docPages.map(([slug, enTitle, esTitle, enDesc, esDesc]) => ({
    title: enTitle,
    titleEs: esTitle,
    url: `/docs/${slug}.html`,
    urlEs: `/es/docs/${slug}.html`,
    summary: enDesc,
    summaryEs: esDesc,
    terms: [slug, enTitle, esTitle, enDesc, esDesc].join(' ').toLowerCase(),
  }));
}

function architectureDiagram() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="920" height="520" viewBox="0 0 920 520" role="img" aria-labelledby="title desc">
  <title id="title">Cocxy Terminal architecture</title>
  <desc id="desc">Static architecture diagram showing app UI, domain services, CocxyCore, Metal renderer, PTY layer, and local stores.</desc>
  <defs>
    <linearGradient id="bg" x1="0" x2="1" y1="0" y2="1"><stop offset="0" stop-color="#111827"/><stop offset="1" stop-color="#202030"/></linearGradient>
    <linearGradient id="card" x1="0" x2="1"><stop offset="0" stop-color="#2c2d3d"/><stop offset="1" stop-color="#171722"/></linearGradient>
    <filter id="shadow" x="-10%" y="-10%" width="120%" height="130%"><feDropShadow dx="0" dy="18" stdDeviation="18" flood-color="#000" flood-opacity=".32"/></filter>
  </defs>
  <rect width="920" height="520" rx="24" fill="url(#bg)"/>
  <g fill="none" stroke="#8ab4ff" stroke-width="2" opacity=".75">
    <path d="M460 118v48M300 256h-80M620 256h80M460 342v58M348 260h224"/>
    <path d="M460 166C360 166 300 190 300 232M460 166c100 0 160 24 160 66"/>
  </g>
  ${svgNode(330, 44, 260, 74, 'macOS App', 'Swift + AppKit shell')}
  ${svgNode(72, 212, 230, 88, 'SwiftUI Panels', 'Vault · review · docs')}
  ${svgNode(345, 202, 230, 108, 'Domain Services', 'agents · browser · remote')}
  ${svgNode(618, 212, 230, 88, 'CocxyCore ABI', 'Zig core through C')}
  ${svgNode(110, 392, 200, 74, 'Local Stores', 'Keychain · files · SQLite')}
  ${svgNode(360, 392, 200, 74, 'Metal Renderer', 'glyph atlas · frames')}
  ${svgNode(610, 392, 200, 74, 'PTY Layer', 'shell semantics')}
</svg>`;
}

function svgNode(x, y, width, height, title, subtitle) {
  return `<g filter="url(#shadow)"><rect x="${x}" y="${y}" width="${width}" height="${height}" rx="14" fill="url(#card)" stroke="#5b5e72"/><text x="${x + 22}" y="${y + 34}" fill="#eef1ff" font-family="Inter, -apple-system, sans-serif" font-size="20" font-weight="700">${escapeHTML(title)}</text><text x="${x + 22}" y="${y + 58}" fill="#aab0c6" font-family="Inter, -apple-system, sans-serif" font-size="14">${escapeHTML(subtitle)}</text></g>`;
}

function previewComponents() {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Cocxy Web Components Preview</title>
  <link rel="stylesheet" href="../public/css/style.css?v=0.0.0">
</head>
<body>
  <main id="main">
    <section class="page-hero"><div class="container"><p class="eyebrow">Preview</p><h1>Component Preview</h1><p>Offline review surface for Cocxy web cards, buttons, stats, tables, docs search, and media frames.</p></div></section>
    <section class="section"><div class="container">
      <div class="hero-actions"><a class="button button-primary" href="#">Primary</a><a class="button button-secondary" href="#">Secondary</a><button class="theme-toggle" type="button" aria-label="Toggle theme"><span class="theme-toggle__sun">☀</span><span class="theme-toggle__moon">◐</span></button></div>
      <div class="feature-tiles">${featurePages.slice(0, 3).map((feature) => featureTile(feature, 'en', { anchor: false })).join('')}</div>
      <div class="stats-grid">${stat('11', 'agents')}${stat('21', 'languages')}${stat('0', 'telemetry')}${stat('MIT', 'license')}${stat('15+', 'macOS')}</div>
      <div class="docs-search"><label for="preview-search">Search</label><input id="preview-search" type="search" data-doc-search placeholder="ssh, agents, plugins"><div data-doc-search-results class="docs-search-results"></div></div>
      <pre class="code-block"><code>cocxy status</code><button class="copy-button" type="button">Copy</button></pre>
    </div></section>
  </main>
  <script src="../public/js/theme-switcher.js?v=${assetVersion}" defer></script>
  <script src="../public/js/main.js?v=${assetVersion}" defer></script>
</body>
</html>`;
}

function writeAll() {
  buildCSSBundle();
  write('index.html', home('en'));
  write('es/index.html', home('es'));
  write('features.html', featureHubPage('en'));
  write('es/features.html', featureHubPage('es'));
  for (const feature of featurePages) {
    write(`features/${feature.slug}.html`, featureDetailPage(feature, 'en'));
    write(`es/features/${feature.slug}.html`, featureDetailPage(feature, 'es'));
  }
  for (const [slug] of topPages) {
    if (slug === 'features') continue;
    write(`${slug}.html`, topPage(slug, 'en'));
    write(`es/${slug}.html`, topPage(slug, 'es'));
  }
  write('docs/index.html', docsHubPage('en'));
  write('es/docs/index.html', docsHubPage('es'));
  for (const doc of docPages) {
    write(`docs/${doc[0]}.html`, docDetailPage(doc, 'en'));
    write(`es/docs/${doc[0]}.html`, docDetailPage(doc, 'es'));
  }
  write('getting-started.html', movedPage('en'));
  write('es/getting-started.html', movedPage('es'));
  write('releases.html', releasesPage('en'));
  write('es/releases.html', releasesPage('es'));
  write('404.html', notFoundPage('en'));
  write('es/404.html', notFoundPage('es'));
  write('docs/search-index.json', json(docsSearchIndex()));
  write('images/architecture-diagram.svg', architectureDiagram());
  write('sitemap.xml', sitemap());
  write('robots.txt', robots());
  write('llms.txt', llms());
  write('feed.xml', feed());
  write('releases.xml', releasesFeed());
  write('service-worker.js', serviceWorker());
  writeWeb('preview/components.html', previewComponents());
}

function sitemap() {
  const pages = [
    '/',
    '/features.html',
    ...featurePages.map((item) => `/features/${item.slug}.html`),
    ...topPages.map((item) => `/${item[0]}.html`),
    '/docs/',
    ...docPages.map((item) => `/docs/${item[0]}.html`),
    '/releases.html',
  ];
  const unique = [...new Set(pages)];
  const urls = [];
  for (const page of unique) {
    urls.push(siteMapURL(page, 'en'));
    urls.push(siteMapURL(page, 'es'));
  }
  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
${urls.join('\n')}
</urlset>`;
}

function siteMapURL(page, lang) {
  const loc = canonicalFor(page, lang);
  const altEn = canonicalFor(page, 'en');
  const altEs = canonicalFor(page, 'es');
  return `  <url>
    <loc>${loc}</loc>
    <xhtml:link rel="alternate" hreflang="en" href="${altEn}"/>
    <xhtml:link rel="alternate" hreflang="es" href="${altEs}"/>
    <xhtml:link rel="alternate" hreflang="x-default" href="${altEn}"/>
    <lastmod>${contentUpdated}</lastmod>
    <changefreq>${page === '/' || page === '/releases.html' ? 'weekly' : 'monthly'}</changefreq>
    <priority>${page === '/' ? '1.0' : page.includes('/docs/') ? '0.7' : '0.8'}</priority>
  </url>`;
}

function robots() {
  return `User-agent: *
Allow: /
Disallow: /health

User-agent: AhrefsBot
Crawl-delay: 10
User-agent: SemrushBot
Crawl-delay: 10
User-agent: MJ12bot
Crawl-delay: 10

Sitemap: ${site}/sitemap.xml
Host: ${site}`;
}

function llms() {
  return `# Cocxy Terminal

> Native macOS terminal for developers working with local AI coding agents. Real-time agent detection, encrypted Vault, inline code review, Markdown workspace, GPU rendering, remote workspaces, zero telemetry, and MIT license.

## Quick facts
- Version: ${releaseVersion}
- License: MIT
- Platform: macOS 15.0+
- Source: https://github.com/salp2403/cocxy-terminal
- Telemetry: zero

## Important pages
- Home: ${site}/
- Features: ${site}/features.html
- Agents: ${site}/features/agents.html
- Privacy: ${site}/privacy.html
- Security: ${site}/security.html
- Architecture: ${site}/architecture.html
- Documentation: ${site}/docs/

## Supported agents
${agents.map((agent) => `- ${agent[0]}`).join('\n')}
`;
}

function rssItem({ title, link, description, pubDate, guid = link }) {
  return `    <item>
      <title>${escapeXML(title)}</title>
      <link>${escapeXML(link)}</link>
      <guid isPermaLink="true">${escapeXML(guid)}</guid>
      <pubDate>${escapeXML(pubDate)}</pubDate>
      <description>${escapeXML(description)}</description>
    </item>`;
}

function rssChannel({ title, description, link, atomSelf, items }) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>${escapeXML(title)}</title>
    <link>${escapeXML(link)}</link>
    <description>${escapeXML(description)}</description>
    <language>en-us</language>
    <lastBuildDate>Wed, 20 May 2026 00:00:00 GMT</lastBuildDate>
    <atom:link href="${escapeXML(atomSelf)}" rel="self" type="application/rss+xml"/>
${items.map(rssItem).join('\n')}
  </channel>
</rss>`;
}

function feed() {
  return rssChannel({
    title: 'Cocxy Terminal Updates',
    description: 'Product, documentation, security, privacy, and roadmap updates for Cocxy Terminal.',
    link: site,
    atomSelf: `${site}/feed.xml`,
    items: [
      {
        title: 'Cocxy Terminal 1.18.0 web and release readiness',
        link: `${site}/releases.html`,
        pubDate: 'Wed, 20 May 2026 00:00:00 GMT',
        description: 'Release readiness page with local-first privacy, agent workflows, Vault, documentation, and download links.',
      },
      {
        title: 'Security and privacy verification guide',
        link: `${site}/security.html`,
        pubDate: 'Tue, 19 May 2026 00:00:00 GMT',
        description: 'Threat model, signing, update, local storage, and zero telemetry verification notes.',
      },
      {
        title: 'Public roadmap',
        link: `${site}/roadmap.html`,
        pubDate: 'Mon, 18 May 2026 00:00:00 GMT',
        description: 'Public direction for the native macOS terminal, agent workflows, documentation, and release channels.',
      },
    ],
  });
}

function releasesFeed() {
  return rssChannel({
    title: 'Cocxy Terminal Releases',
    description: 'Release notes and download updates for Cocxy Terminal.',
    link: `${site}/releases.html`,
    atomSelf: `${site}/releases.xml`,
    items: [
      {
        title: 'Cocxy Terminal 1.18.0',
        link: 'https://github.com/salp2403/cocxy-terminal/releases/latest',
        guid: `${site}/releases.html#v1-18-0`,
        pubDate: 'Wed, 20 May 2026 00:00:00 GMT',
        description: 'Current release channel entry for the native macOS app and bundled command-line companion.',
      },
      {
        title: 'Release channels',
        link: `${site}/channels.html`,
        pubDate: 'Tue, 19 May 2026 00:00:00 GMT',
        description: 'Stable, preview, and nightly channel guidance with explicit risk tradeoffs.',
      },
    ],
  });
}

function serviceWorker() {
  const precacheURLs = [
    '/',
    '/features.html',
    '/features/agents.html',
    '/privacy.html',
    '/security.html',
    '/architecture.html',
    '/why-cocxy.html',
    '/docs/',
    '/docs/first-run.html',
    '/releases.html',
    `/css/style.css?v=${assetVersion}`,
    `/js/main.js?v=${assetVersion}`,
    `/js/theme-switcher.js?v=${assetVersion}`,
    '/images/icon.png',
    '/images/icon.svg',
    '/images/icon-192.png',
    '/images/icon.avif',
    '/images/icon.webp',
    '/manifest.webmanifest',
    '/llms.txt',
    '/feed.xml',
    '/releases.xml',
  ];
  return `const CACHE_NAME = 'cocxy-web-static-v${assetVersion}';
const PRECACHE_URLS = ${JSON.stringify(precacheURLs, null, 2)};

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => cache.addAll(PRECACHE_URLS))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((names) => Promise.all(names
        .filter((name) => name.startsWith('cocxy-web-') && name !== CACHE_NAME)
        .map((name) => caches.delete(name))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin || url.pathname === '/health') return;

  if (request.mode === 'navigate') {
    event.respondWith(networkFirst(request, '/'));
    return;
  }

  event.respondWith(cacheFirst(request));
});

async function networkFirst(request, fallbackURL) {
  const cache = await caches.open(CACHE_NAME);
  try {
    const response = await fetch(request);
    if (response.ok) await cache.put(request, response.clone());
    return response;
  } catch (_) {
    return (await cache.match(request)) || cache.match(fallbackURL);
  }
}

async function cacheFirst(request) {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(request);
  if (cached) return cached;
  const response = await fetch(request);
  if (response.ok) await cache.put(request, response.clone());
  return response;
}`;
}

function verifySourceFacts() {
  const agentsFile = path.join(repoRoot, 'Sources/Domain/Vault/VaultBuiltInAgents.swift');
  if (!fs.existsSync(agentsFile)) return;
  const source = fs.readFileSync(agentsFile, 'utf8');
  const missing = agents.map((agent) => agent[0]).filter((name) => !source.includes(name));
  if (missing.length) {
    throw new Error(`Built-in agent source mismatch: ${missing.join(', ')}`);
  }
}

verifySourceFacts();
if (process.argv.includes('--css-only')) {
  buildCSSBundle();
  console.log('Generated Cocxy CSS bundle');
} else {
  writeAll();
  console.log('Generated Cocxy web pages, sitemap, robots, and llms.txt');
}
