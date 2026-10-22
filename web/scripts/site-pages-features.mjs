// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import { escapeHTML, icon, renderInline } from './site-core.mjs';
import { appArtwork, codeBlock, reviewArtwork } from './site-components.mjs';
import { agents, featureAnchors, featurePages, localizedBullets } from './site-data.mjs';
import { note, pageHero } from './site-sections.mjs';
import { productShot } from './site-shots.mjs';

export function featureTile(feature, lang = 'en', { anchor = true, bullets = false } = {}) {
  const es = lang === 'es';
  const href = `${es ? '/es' : ''}/features/${feature.slug}.html`;
  const id = anchor ? ` id="${feature.anchor}"` : '';
  const list = bullets
    ? `\n  <ul>${localizedBullets(feature, lang).map((item) => `<li>${renderInline(item)}</li>`).join('')}</ul>`
    : '';
  return `<article class="feature-tile ${feature.cssClass}"${id}>
  ${icon(feature.icon)}
  <h3><a class="tile-link" href="${href}">${escapeHTML(es ? feature.esTitle : feature.title)}</a></h3>
  <p>${escapeHTML(es ? feature.esSummary : feature.summary)}</p>${list}
</article>`;
}

function featureShot(feature, lang) {
  const es = lang === 'es';
  const title = es ? feature.esTitle : feature.title;
  const artwork = feature.slug === 'code-review'
    ? reviewArtwork()
    : appArtwork(feature.slug === 'agents' ? 'agents' : 'window');
  return productShot({
    slot: `feature-${feature.slug}`,
    alt: es ? `${title} en Cocxy Terminal` : `${title} in Cocxy Terminal`,
    artworkLabel: es ? `Ilustración de la ventana de Cocxy: ${title}` : `Illustration of the Cocxy window: ${title}`,
    artwork,
    className: 'feature-shot',
  });
}

function relatedFeatures(feature, lang) {
  const es = lang === 'es';
  const index = featurePages.indexOf(feature);
  const related = [1, 2, 3].map((step) => featurePages[(index + step) % featurePages.length]);
  return `<section class="section section-band" aria-labelledby="related-title"><div class="container">
  <h2 id="related-title" class="section-title">${es ? 'Sigue explorando' : 'Keep exploring'}</h2>
  <div class="feature-tiles">${related.map((item) => featureTile(item, lang, { anchor: false })).join('\n')}</div>
</div></section>`;
}

export function featureHubBody(lang, description) {
  const es = lang === 'es';
  const extras = [
    ['quicklook', 'Quick Look', es ? 'Vista previa local y sanitizada para archivos y documentos.' : 'Local sanitized previews for files and documents.'],
    ['web-terminal', es ? 'Terminal remota' : 'Remote terminal', es ? 'Sesiones remotas iniciadas por el usuario con adjuntar y reconectar.' : 'User-started remote sessions with attach and reconnect paths.'],
    ['per-project', es ? 'Configuración por proyecto' : 'Per-project configuration', es ? '`.cocxy.toml` separa ajustes del repo y perfil global.' : '`.cocxy.toml` separates repo-local settings from the global profile.'],
    ['applescript', 'AppleScript', es ? 'Automatización de ventanas y pestañas mediante permisos del sistema.' : 'Window and tab automation through system permissions.'],
  ];
  return `${pageHero({ lang, eyebrow: es ? 'Funciones' : 'Features', title: es ? 'Funciones de Cocxy' : 'Cocxy features', description })}
<section class="section"><div class="container docs-layout">
  <nav class="toc" aria-label="${es ? 'Mapa de funciones' : 'Feature map'}"><strong>${es ? 'Mapa' : 'Map'}</strong>${featureAnchors(lang).map((item) => `<a href="#${item.id}">${escapeHTML(item.label)}</a>`).join('')}</nav>
  <div>
    <div class="section-header" data-reveal="fade-up">
      <h2>${es ? 'Capacidades principales' : 'Primary capabilities'}</h2>
      <p>${es ? 'Cada bloque enlaza con su página dedicada.' : 'Each block links to its dedicated page.'}</p>
    </div>
    <div class="feature-tiles feature-tiles--two" data-reveal="stagger">${featurePages.map((feature) => featureTile(feature, lang, { bullets: true })).join('\n')}</div>
    <div class="section-header section-header--sub">
      <h2>${es ? 'Capas adicionales' : 'Additional layers'}</h2>
      <p>${es ? 'Completan el mapa y se explican en la documentación.' : 'They complete the map and are covered in the docs.'}</p>
    </div>
    <div class="cards-2">${extras.map(([id, title, text]) => `<article class="card" id="${id}"><h3>${escapeHTML(title)}</h3><p>${renderInline(text)}</p></article>`).join('')}</div>
    <div class="callout"><h2>${es ? 'Comandos locales' : 'Local commands'}</h2>${codeBlock({ label: 'Terminal', lines: ['cocxy setup-hooks', 'cocxy github status', 'cocxy remote status'] })}<p>${es ? 'Todo queda local y explícito, con cero telemetr&iacute;a.' : 'Everything stays local and explicit, with zero telemetry.'}</p></div>
  </div>
</div></section>`;
}

export function featureDetailBody(feature, lang) {
  const es = lang === 'es';
  const title = es ? feature.esTitle : feature.title;
  const description = es ? feature.esSummary : feature.summary;
  const sections = es ? feature.esSections : feature.sections;
  const hero = pageHero({
    lang,
    title,
    description,
    iconName: feature.icon,
    crumbs: [[es ? 'Inicio' : 'Home', es ? '/es/' : '/'], [es ? 'Funciones' : 'Features', es ? '/es/features.html' : '/features.html'], [title]],
  });
  const body = feature.slug === 'agents'
    ? agentsSections(lang)
    : `<section class="section"><div class="container">
  <h2 class="sr-only">${es ? 'Capacidades' : 'Capabilities'}</h2>
  <ul class="capabilities">${localizedBullets(feature, lang).map((item) => `<li>${renderInline(item)}</li>`).join('')}</ul>
  <div class="detail-columns">${sections.map(([heading, text], index) => `<article id="section-${index + 1}"><h2>${escapeHTML(heading)}</h2><p>${renderInline(text)}</p></article>`).join('')}</div>
  ${note({ title: es ? 'Local primero' : 'Local-first', body: es ? 'La función opera desde tu Mac o desde conexiones que inicias explícitamente.' : 'The feature operates on your Mac or through connections you explicitly start.' })}
</div></section>`;
  return `${hero}
<section class="section section--flush"><div class="container">${featureShot(feature, lang)}</div></section>
${body}
${relatedFeatures(feature, lang)}`;
}

function agentsSections(lang) {
  const es = lang === 'es';
  const labels = es
    ? ['Agente', 'Binario', 'Detección', 'Reanudar desde la Bóveda']
    : ['Agent', 'Binary', 'Detection', 'Vault resume'];
  return `<section class="section"><div class="container">
  <div class="table-wrap table-wrap--stack">
    <table>
      <thead><tr>${labels.map((label) => `<th scope="col">${label}</th>`).join('')}</tr></thead>
      <tbody>${agents.map((agent) => `<tr><th scope="row">${agent[0]}</th><td data-label="${labels[1]}"><code>${agent[1]}</code></td><td data-label="${labels[2]}">${agent[2]}</td><td data-label="${labels[3]}"><code>${escapeHTML(agent[3])}</code></td></tr>`).join('')}</tbody>
    </table>
  </div>
  <div class="detail-grid section-mini">
    <article class="card"><h2>${es ? 'Añade los tuyos' : 'Add your own'}</h2><p>${renderInline(es ? 'Define agentes propios en `agents.toml` con comandos, patrones y reglas de reanudación sin modificar el código de la app.' : 'Define custom agents in `agents.toml` with commands, patterns, and resume rules without changing app code.')}</p>${codeBlock({ kind: 'config', label: 'agents.toml', lines: ['[agents.local-reviewer]', 'command = &quot;reviewer&quot;', 'resume = &quot;resume &lt;session-id&gt;&quot;', 'patterns = [&quot;waiting&quot;, &quot;working&quot;]'] })}</article>
    <article class="card"><h2>${es ? 'Cómo funciona' : 'How detection works'}</h2><p>${es ? 'Cocxy combina hooks, señales OSC, patrones de proceso y heurísticas de tiempo para mostrar estado local.' : 'Cocxy combines hooks, OSC signals, process patterns, and timing heuristics to show local state.'}</p></article>
    <article class="card"><h2>${es ? 'Integración con Bóveda' : 'Vault integration'}</h2><p>${es ? 'Las sesiones detectadas pueden buscarse y reanudarse desde la Bóveda cifrada.' : 'Detected sessions can be searched and resumed from the encrypted Vault.'}</p></article>
  </div>
</div></section>`;
}

export function agentsPageBody(lang, { title, description }) {
  const es = lang === 'es';
  const agentsFeature = featurePages.find((feature) => feature.slug === 'agents');
  return `${pageHero({ lang, eyebrow: 'Cocxy Terminal', title, description, iconName: agentsFeature.icon })}
<section class="section section--flush"><div class="container">${featureShot(agentsFeature, lang)}</div></section>
${agentsSections(lang)}`;
}
