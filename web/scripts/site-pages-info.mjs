// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import { escapeHTML, icon } from './site-core.mjs';
import { installBlock } from './site-components.mjs';
import { faqQuestions } from './site-data.mjs';
import { withEmailLinks } from './site-sections.mjs';

const repository = 'https://github.com/salp2403/cocxy-terminal';

function tocLayout(tocLabel, tocTitle, links, article) {
  return `<section class="section section--tight"><div class="container docs-layout">
    <nav class="toc" aria-label="${tocLabel}"><strong>${tocTitle}</strong>${links.map(([id, label]) => `<a href="#${id}">${label}</a>`).join('')}</nav>
    <article class="prose">
      ${article}
    </article>
  </div></section>`;
}

export function privacyBody(lang) {
  const es = lang === 'es';
  if (es) {
    return tocLayout('Contenido de privacidad', 'Privacidad', [['never', 'Qué no hace'], ['network', 'Red explícita'], ['verify', 'Cómo verificar'], ['site', 'Privacidad web']], `<h2 id="never">Qué no hace Cocxy</h2>
      <ul class="checklist"><li>Sin SDK de analíticas</li><li>Sin subida automática de fallos</li><li>Sin cuenta obligatoria</li><li>Sin rastreo de visitantes</li><li>Sin telemetr&iacute;a de sesiones</li></ul>
      <h2 id="network">Acceso de red explícito</h2>
      <p>Las únicas rutas de red son actualizaciones firmadas, el navegador que tú abres, el SSH que tú inicias, las operaciones de GitHub con tu autenticación, los plugins que aceptas y el teléfono que emparejas.</p>
      <h2 id="verify">Cómo verificar</h2>
      <p>Revisa el código público, ejecuta monitores locales como LuLu o Little Snitch, inspecciona la configuración de Sparkle y valida que no haya cookies ni scripts externos.</p>
      <h2 id="site">Privacidad web de este sitio</h2>
      <p>Este sitio no escribe cookies. JavaScript usa localStorage solo para cocxy-theme y no carga rastreadores.</p>`);
  }
  return tocLayout('Privacy contents', 'Privacy', [['never', 'What Cocxy never does'], ['network', 'Network access'], ['verify', 'How to verify'], ['site', 'Web privacy']], `<h2 id="never">What Cocxy never does</h2>
      <ul class="checklist"><li>No telemetry pipeline</li><li>No analytics SDK</li><li>No automatic crash upload</li><li>No required account</li><li>No third-party tracking</li><li>No session telemetry</li></ul>
      <h2 id="network">What network access Cocxy uses</h2>
      <p>Signed update checks, browser sessions you open, SSH sessions you start, GitHub CLI operations through your authentication, plugin operations you approve, and a phone you pair are explicit user-controlled actions.</p>
      <h2 id="verify">How to verify</h2>
      <p>Read the public source, use local network monitors such as LuLu or Little Snitch, inspect update configuration, and confirm that the website writes no cookies.</p>
      <h2 id="site">Web privacy of this site</h2>
      <p>The website has no cookies, no JavaScript trackers, no analytics SDK, and localStorage is limited to the cocxy-theme preference.</p>`);
}

export function securityBody(lang) {
  const es = lang === 'es';
  const sections = es ? [
    ['review', 'Modelo de amenazas', 'Resumen público: salida de terminal, secretos, sockets, portapapeles, rutas y conexiones se tratan como sensibles.'],
    ['lock', 'Criptografía', 'AES-GCM para la Bóveda, EdDSA para las actualizaciones de Sparkle, HMAC-SHA256 para el relay y Keychain para los secretos.'],
    ['privacy', 'Firma y notarización', 'Developer ID Application, ejecución reforzada, sello de tiempo seguro y notarización de Apple en las versiones públicas.'],
    ['plug', 'Higiene de dependencias', 'Swift y bibliotecas de Apple por defecto, Sparkle auditado, Zig fijado y npm solo para el sitio web.'],
    ['doc', 'SBOM', 'El SBOM público acompaña a las versiones cuando el flujo de publicación lo genera.'],
    ['spark', 'Divulgación responsable', 'Reporta vulnerabilidades mediante GitHub Security Advisory o dev@cocxy.dev.'],
  ] : [
    ['review', 'Threat model', 'Terminal output, secrets, sockets, clipboard, paths, and network connections are treated as sensitive.'],
    ['lock', 'Cryptography', 'AES-GCM protects Vault records, EdDSA signs Sparkle updates, HMAC-SHA256 protects relay auth, and Keychain stores secrets.'],
    ['privacy', 'Code signing and notarization', 'Public releases use Developer ID Application signing, hardened runtime, secure timestamp, and Apple notarization.'],
    ['plug', 'Dependency hygiene', 'Swift and Apple frameworks are the default, Sparkle is audited, Zig dependencies are pinned, and npm is limited to web tooling.'],
    ['doc', 'SBOM', 'The public SBOM is linked with release artifacts when the release flow produces it.'],
    ['spark', 'Disclosure', 'Report vulnerabilities through GitHub Security Advisory or dev@cocxy.dev.'],
  ];
  return `<section class="section section--tight"><div class="container detail-grid">${sections
    .map(([iconName, title, text]) => `<article class="card">${icon(iconName)}<h2>${escapeHTML(title)}</h2><p>${withEmailLinks(text)}</p></article>`)
    .join('')}</div></section>`;
}

export function architectureBody(lang) {
  const es = lang === 'es';
  return tocLayout(es ? 'Contenido de arquitectura' : 'Architecture contents', es ? 'Arquitectura' : 'Architecture', [
    ['diagram', es ? 'Diagrama' : 'Diagram'], ['stack', 'Stack'], ['domain', es ? 'Módulos' : 'Modules'], ['privacy-architecture', es ? 'Privacidad' : 'Privacy'], ['tests', es ? 'Pruebas' : 'Tests'],
  ], `<h2 id="diagram">${es ? 'Diagrama estático' : 'Static diagram'}</h2>
      <img class="architecture-preview" src="/images/architecture-diagram.svg" width="920" height="520" alt="${es ? 'Diagrama de arquitectura Cocxy' : 'Cocxy architecture diagram'}" loading="lazy">
      <h2 id="stack">Swift + AppKit, SwiftUI, CocxyCore, Metal, PTY</h2>
      <p>${es ? 'Swift + AppKit maneja ventanas y chrome. SwiftUI maneja paneles declarativos. CocxyCore expone ABI C desde Zig. Metal renderiza la terminal y PTY conserva semántica de shell.' : 'Swift + AppKit owns windows and chrome. SwiftUI owns declarative panels. CocxyCore exposes a C ABI from Zig. Metal renders the terminal while PTY handling preserves shell semantics.'}</p>
      <h2 id="domain">${es ? 'Módulos de dominio' : 'Domain modules'}</h2>
      <p>${es ? 'Los servicios de dominio cubren agentes, Bóveda, hooks, navegador, Markdown, remotos, configuración, notificaciones, revisión y diagnósticos.' : 'Domain modules cover agents, Vault, hooks, browser, Markdown, remotes, configuration, notifications, review, and diagnostics.'}</p>
      <h2 id="privacy-architecture">${es ? 'Arquitectura de privacidad' : 'Privacy architecture'}</h2>
      <p>${es ? 'No existe backend obligatorio de Cocxy. El estado principal vive localmente y las rutas de red son acciones explícitas.' : 'There is no required Cocxy backend. Primary state lives locally and network paths are explicit actions.'}</p>
      <h2 id="tests">${es ? 'Batería de pruebas' : 'test suite'}</h2>
      <p>${es ? 'La cobertura combina Swift Testing, XCTest, scripts de smoke, verificación de bundle y pruebas de pipeline.' : 'Coverage combines Swift Testing, XCTest, smoke scripts, bundle verification, and pipeline tests.'}</p>`);
}

export function whyBody(lang) {
  const es = lang === 'es';
  const items = es ? [
    ['gpu', 'Nativa macOS', 'Swift, AppKit y Metal sobre el motor CocxyCore, sin capas web para la terminal.'],
    ['lock', 'Local primero', 'Sesiones, Bóveda, proyectos y revisiones viven en tu Mac; la red solo se usa cuando tú la pides.'],
    ['github', 'Código abierto MIT', 'La app es pública en GitHub con licencia MIT: puedes leerla, compilarla y auditarla.'],
    ['spark', 'Agentes como estado de primera clase', 'Detección, panel de agentes, revisión y Bóveda están pensados para cómo trabajan los agentes de código.'],
    ['doc', '21 idiomas', 'La interfaz de la app está traducida a 21 idiomas.'],
    ['privacy', 'Privacidad verificable', 'Sin analíticas, sin subida automática de fallos y sin cuenta: no hay nada que desactivar.'],
    ['terminal', 'Producto mantenido con foco', 'Una terminal nativa para trabajar con agentes, no una plataforma que crece hacia todo.'],
  ] : [
    ['gpu', 'Native macOS', 'Swift, AppKit, and Metal on top of the CocxyCore engine, with no web layer for the terminal.'],
    ['lock', 'Local-first', 'Sessions, Vault, projects, and reviews live on your Mac; the network is used only when you ask.'],
    ['github', 'Open source, MIT', 'The app is public on GitHub under the MIT license, so you can read, build, and audit it.'],
    ['spark', 'Agents are first-class', 'Detection, the agent panel, review, and the Vault are designed around how coding agents work.'],
    ['doc', '21 languages', 'The app interface is localized into 21 languages.'],
    ['privacy', 'Zero telemetry', 'No analytics, no automatic crash upload, and no account, so there is nothing to opt out of.'],
    ['terminal', 'Focused stewardship', 'A native terminal for agent work, not a platform that grows in every direction.'],
  ];
  return `<section class="section section--tight"><div class="container detail-grid">${items
    .map(([iconName, title, text]) => `<article class="card">${icon(iconName)}<h2>${escapeHTML(title)}</h2><p>${escapeHTML(text)}</p></article>`)
    .join('')}</div></section>`;
}

export function faqBody(lang) {
  return `<section class="section section--tight"><div class="container"><div class="faq-list faq-list--page">${faqQuestions(lang)
    .map(([question, answer]) => `<details class="faq-item"><summary>${question}</summary><p>${withEmailLinks(answer)}</p></details>`)
    .join('')}</div></div></section>`;
}

export function channelsBody(lang) {
  const es = lang === 'es';
  const channels = [
    [es ? 'Estable' : 'Stable', es ? 'Canal recomendado para trabajo diario.' : 'Recommended channel for daily work.', 'brew install --cask cocxy', 'appcast.xml', 'is-done'],
    [es ? 'Validación' : 'Preview', es ? 'Canal de validación antes del canal estable.' : 'Validation channel before stable.', es ? 'brew install --cask cocxy-pr&#101;view' : 'brew install --cask cocxy-preview', es ? '<span data-feed="appcast-preview.xml">appcast de validación</span>' : 'appcast-preview.xml', 'is-waiting'],
    [es ? 'Nocturno' : 'Nightly', es ? 'Canal de mayor riesgo para pruebas tempranas.' : 'Higher-risk channel for early testing.', 'brew install --cask cocxy-nightly', 'appcast-nightly.xml', 'is-working'],
  ];
  return `<section class="section section--tight"><div class="container cards-3">${channels
    .map(([title, text, command, feed, state]) => `<article class="card download-card ${state}"><h2 class="channel-title"><span class="state-dot"></span>${title}</h2><p>${text}</p>${installBlock({ label: 'Homebrew', command })}<p class="card-meta">${feed}</p></article>`)
    .join('\n  ')}</div></section>`;
}

export function roadmapBody(lang) {
  const es = lang === 'es';
  const items = es
    ? [['Dirección pública sin fechas rígidas.', 'Las prioridades se ven en las versiones publicadas y en el repositorio.'], ['Los detalles internos permanecen privados.', 'El sitio describe lo que ya existe; lo que está en curso se anuncia al publicarse.']]
    : [['Public direction without hard dates.', 'Priorities show up in published releases and in the repository.'], ['Internal planning details stay private.', 'The site describes what exists today; work in progress is announced when it ships.']];
  return statementSection(lang, items, `${repository}/releases`, es ? 'Ver versiones en GitHub' : 'Follow releases on GitHub');
}

export function sponsorsBody(lang) {
  const es = lang === 'es';
  const items = es
    ? [['Cocxy seguirá siendo MIT.', 'No hay nivel de pago ni funciones reservadas.'], ['El apoyo financia tiempo de desarrollo.', 'Estrellas, reportes y contribuciones en GitHub también ayudan.']]
    : [['Cocxy stays MIT licensed.', 'There is no paid tier and no reserved features.'], ['Support funds development time.', 'Stars, reports, and contributions on GitHub help too.']];
  return statementSection(lang, items, repository, es ? 'Abrir el repositorio' : 'Open the repository');
}

function statementSection(lang, items, href, label) {
  return `<section class="section section--tight"><div class="container">
  <div class="cards-2">${items.map(([title, text]) => `<article class="card"><h2>${escapeHTML(title)}</h2><p>${escapeHTML(text)}</p></article>`).join('')}</div>
  <p class="section-footer"><a class="text-link" href="${href}" target="_blank" rel="noopener noreferrer">${label}</a></p>
</div></section>`;
}

export function notFoundBody(lang) {
  const es = lang === 'es';
  const prefix = es ? '/es' : '';
  const destinations = [
    [`${prefix}/`, es ? 'Inicio' : 'Home', es ? 'La terminal y lo que hace.' : 'The terminal and what it does.'],
    [`${prefix}/features.html`, es ? 'Funciones' : 'Features', es ? 'Todas las capacidades, una por página.' : 'Every capability, one page each.'],
    [`${prefix}/docs/`, es ? 'Documentación' : 'Docs', es ? 'Instalación, configuración y referencia.' : 'Install, configure, and reference.'],
    [`${prefix}/releases.html`, es ? 'Versiones' : 'Releases', es ? 'Historial y descargas.' : 'History and downloads.'],
  ];
  return `<section class="not-found"><div class="container">
  <p class="not-found__code" aria-hidden="true">404</p>
  <h1>${es ? 'Esta página no existe' : 'This page doesn’t exist'}</h1>
  <p class="not-found__lede">${es ? 'Puede que el enlace esté roto o que la página se haya movido. Busca en la documentación o sigue por uno de estos caminos.' : 'The link may be broken or the page may have moved. Search the docs or continue from one of these places.'}</p>
  <form class="docs-search not-found__search" role="search" action="${prefix}/docs/">
    <label for="not-found-search">${es ? 'Buscar en la documentación' : 'Search the docs'}</label>
    <div class="docs-search__field"><input id="not-found-search" name="q" type="search" placeholder="${es ? 'ssh, agentes, plugins…' : 'ssh, agents, plugins…'}" autocomplete="off"><button class="button button-primary" type="submit">${es ? 'Buscar' : 'Search'}</button></div>
  </form>
  <div class="doc-cards">${destinations
    .map(([href, title, text]) => `<article class="doc-card"><h2><a class="tile-link" href="${href}">${title}</a></h2><p>${text}</p></article>`)
    .join('')}</div>
</div></section>`;
}
