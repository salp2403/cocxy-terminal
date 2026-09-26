// Copyright (c) 2026 Said Arturo Lopez. MIT License.

// Site chrome shared by build-site.mjs and generate-releases-page.mjs, so the
// generated releases page carries the same header, footer, and theme wiring.
import { logoImage } from './site-core.mjs';
import { themeIcons } from './site-components.mjs';

export function themeHeadTags() {
  return `<meta name="color-scheme" content="light dark">
  <meta name="theme-color" content="#ffffff" media="(prefers-color-scheme: light)">
  <meta name="theme-color" content="#0b0c10" media="(prefers-color-scheme: dark)">`;
}

export function themeBootScript() {
  return `<script>
  (() => {
    const root = document.documentElement;
    root.classList.add('js');
    try {
      const saved = localStorage.getItem('cocxy-theme');
      if (saved === 'light' || saved === 'dark') root.dataset.theme = saved;
    } catch (_) {}
  })();
  </script>`;
}

export function siteHeader({ lang = 'en', active = '', langHref, downloadHref }) {
  const es = lang === 'es';
  const labels = es
    ? ['Funciones', 'Agentes', 'Privacidad', 'Seguridad', 'Documentación', 'Descargar', 'English']
    : ['Features', 'Agents', 'Privacy', 'Security', 'Docs', 'Download', 'Español'];
  return `<a class="skip-link" href="#main">${es ? 'Saltar al contenido' : 'Skip to main content'}</a>
<header class="site-header">
  <nav class="nav container" aria-label="${es ? 'Navegación principal' : 'Main navigation'}">
    <a class="nav-logo" href="${es ? '/es/' : '/'}" aria-label="Cocxy Terminal">
      ${logoImage({ width: 28, height: 28 })}
      <span>Cocxy</span>
    </a>
    <div class="nav-links" id="site-menu">
      <a ${active === 'features' ? 'aria-current="page"' : ''} href="${es ? '/es/features.html' : '/features.html'}">${labels[0]}</a>
      <a ${active === 'agents' ? 'aria-current="page"' : ''} href="${es ? '/es/features/agents.html' : '/features/agents.html'}">${labels[1]}</a>
      <a ${active === 'privacy' ? 'aria-current="page"' : ''} href="${es ? '/es/privacy.html' : '/privacy.html'}">${labels[2]}</a>
      <a ${active === 'security' ? 'aria-current="page"' : ''} href="${es ? '/es/security.html' : '/security.html'}">${labels[3]}</a>
      <a ${active === 'docs' ? 'aria-current="page"' : ''} href="${es ? '/es/docs/' : '/docs/'}">${labels[4]}</a>
      <a href="${langHref}" hreflang="${es ? 'en' : 'es'}" lang="${es ? 'en' : 'es'}">${labels[6]}</a>
      <a href="https://github.com/salp2403/cocxy-terminal" target="_blank" rel="noopener noreferrer">GitHub</a>
      <a class="nav-cta" href="${downloadHref}">${labels[5]}</a>
    </div>
    <div class="nav-actions">
      <button class="theme-toggle" type="button" aria-label="${es ? 'Cambiar tema' : 'Toggle theme'}" title="${es ? 'Cambiar tema' : 'Toggle theme'}">
        <span class="theme-toggle__sun">${themeIcons.sun}</span>
        <span class="theme-toggle__moon">${themeIcons.moon}</span>
      </button>
      <button class="nav-toggle" type="button" aria-expanded="false" aria-controls="site-menu">
        <span></span><span></span><span></span>
        <span class="sr-only">${es ? 'Abrir navegación' : 'Open navigation'}</span>
      </button>
    </div>
  </nav>
</header>`;
}

export function siteFooter(lang = 'en') {
  const es = lang === 'es';
  return `<footer class="site-footer">
  <div class="container footer-grid">
    <div>
      <a class="footer-brand" href="${es ? '/es/' : '/'}">${logoImage({ width: 28, height: 28 })}<span>Cocxy Terminal</span></a>
      <p>${es ? 'Terminal nativa para macOS, local primero, MIT y sin telemetría.' : 'Native macOS terminal, local-first, MIT licensed, and zero telemetry.'}</p>
    </div>
    <nav aria-label="${es ? 'Enlaces de pie' : 'Footer links'}">
      <a href="${es ? '/es/features.html' : '/features.html'}">${es ? 'Funciones' : 'Features'}</a>
      <a href="${es ? '/es/features/agents.html' : '/features/agents.html'}">${es ? 'Agentes' : 'Agents'}</a>
      <a href="${es ? '/es/docs/' : '/docs/'}">${es ? 'Documentación' : 'Docs'}</a>
      <a href="${es ? '/es/privacy.html' : '/privacy.html'}">${es ? 'Privacidad' : 'Privacy'}</a>
      <a href="${es ? '/es/security.html' : '/security.html'}">${es ? 'Seguridad' : 'Security'}</a>
      <a href="${es ? '/es/releases.html' : '/releases.html'}">${es ? 'Versiones' : 'Releases'}</a>
      <a href="${es ? '/es/channels.html' : '/channels.html'}">${es ? 'Canales' : 'Channels'}</a>
      <a href="https://github.com/salp2403/cocxy-terminal" target="_blank" rel="noopener noreferrer">GitHub</a>
      <a href="https://github.com/salp2403/cocxy-terminal/blob/main/LICENSE" target="_blank" rel="noopener noreferrer">${es ? 'Licencia MIT' : 'MIT License'}</a>
    </nav>
    <p class="footer-note">${es ? 'Hecho por Said Arturo Lopez.' : 'Made by Said Arturo Lopez.'}</p>
  </div>
</footer>`;
}
