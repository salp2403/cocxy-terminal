// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import { escapeHTML, icon } from './site-core.mjs';
import { installBlock } from './site-components.mjs';

export const securityAddress = 'dev@cocxy.dev';

// The host's email obfuscation rewrites addresses with a script the CSP
// blocks, so every published address sits inside an email_off region.
export function emailLink(address = securityAddress) {
  return `<!--email_off--><a href="mailto:${address}">${address}</a><!--/email_off-->`;
}

export function withEmailLinks(text) {
  return escapeHTML(text).replaceAll(securityAddress, emailLink());
}

export function breadcrumbs(lang, items) {
  const es = lang === 'es';
  const last = items.length - 1;
  return `<nav class="breadcrumbs" aria-label="${es ? 'Ruta de navegación' : 'Breadcrumb'}"><ol>${items
    .map(([label, href], index) => (index === last
      ? `<li><span aria-current="page">${escapeHTML(label)}</span></li>`
      : `<li><a href="${href}">${escapeHTML(label)}</a></li>`))
    .join('')}</ol></nav>`;
}

export function pageHero({ lang = 'en', eyebrow, title, description, crumbs, iconName, actions = '' }) {
  const lead = crumbs ? breadcrumbs(lang, crumbs) : `<p class="eyebrow">${escapeHTML(eyebrow)}</p>`;
  const mark = iconName ? `<span class="page-hero__icon" aria-hidden="true">${icon(iconName)}</span>` : '';
  return `<section class="page-hero"><div class="container">
    ${lead}
    ${mark}<h1>${escapeHTML(title)}</h1>
    <p>${escapeHTML(description)}</p>${actions ? `\n    <div class="page-hero__actions">${actions}</div>` : ''}
  </div></section>`;
}

export function downloadSection(lang = 'en') {
  const es = lang === 'es';
  return `<section class="section section-band" id="download" aria-labelledby="download-title">
  <div class="container">
    <div class="section-header section-header--center" data-reveal="fade-up">
      <p class="eyebrow">${es ? 'Descarga' : 'Download'}</p>
      <h2 id="download-title">${es ? 'Instala Cocxy en tu Mac' : 'Install Cocxy on your Mac'}</h2>
      <p>${es ? 'Firmada con Developer ID y notarizada por Apple. Las actualizaciones llegan por el actualizador integrado.' : 'Signed with a Developer ID and notarized by Apple. Updates arrive through the built-in updater.'}</p>
    </div>
    <div class="download-grid" data-reveal="stagger">
      <article class="card download-card download-card--primary">
        <h3>${es ? 'Descarga directa' : 'Direct download'}</h3>
        <p>${es ? 'La imagen de disco firmada, desde GitHub Releases.' : 'The signed disk image from GitHub Releases.'}</p>
        <a class="button button-primary" href="https://github.com/salp2403/cocxy-terminal/releases/download/v0.0.0/CocxyTerminal-0.0.0.dmg">${es ? 'Descargar v0.0.0' : 'Download v0.0.0'}</a>
      </article>
      <article class="card download-card">
        <h3>Homebrew</h3>
        <p>${es ? 'Instala y actualiza desde el tap oficial.' : 'Install and upgrade from the official tap.'}</p>
        ${installBlock({ label: 'Terminal', command: 'brew tap salp2403/tap &amp;&amp; brew install --cask cocxy' })}
      </article>
      <article class="card download-card">
        <h3>${es ? 'Canales' : 'Release channels'}</h3>
        <p>${es ? 'Estable para el día a día; validación y nocturno para probar antes.' : 'Stable for daily work; preview and nightly for early testing.'}</p>
        <a class="button button-secondary" href="${es ? '/es/channels.html' : '/channels.html'}">${es ? 'Ver canales' : 'View channels'}</a>
      </article>
    </div>
  </div>
</section>`;
}

export function note({ title, body, tone = 'done' }) {
  return `<div class="note is-${tone}"><h2>${escapeHTML(title)}</h2><p>${body}</p></div>`;
}
