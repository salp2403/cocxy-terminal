// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import { escapeHTML, renderInline } from './site-core.mjs';
import { codeBlock } from './site-components.mjs';
import { docPages, sampleCommand } from './site-data.mjs';
import { pageHero } from './site-sections.mjs';

const docGroups = [
  ['start', 'Get started', 'Primeros pasos', ['install', 'first-run', 'configuration', 'agents-setup']],
  ['use', 'Everyday use', 'Uso diario', ['shortcuts', 'markdown-guide', 'ssh-remote', 'release-channels']],
  ['extend', 'Extend and fix', 'Extender y resolver', ['cli-reference', 'plugins-dev', 'troubleshooting']],
];

const docHref = (slug, es) => `${es ? '/es' : ''}/docs/${slug}.html`;

// Doc summaries double as page metadata, so file names are marked at render time.
const markConfigFiles = (text) => text.replace(/(?<![\w`.])(\.cocxy\.toml|agents\.toml)(?![\w`])/g, '`$1`');

export function docsHubBody(lang, description) {
  const es = lang === 'es';
  const bySlug = new Map(docPages.map((doc) => [doc[0], doc]));
  return `${pageHero({ lang, eyebrow: es ? 'Documentación' : 'Documentation', title: es ? 'Docs de Cocxy' : 'Cocxy Docs', description })}
<section class="section section--tight"><div class="container">
  <form class="docs-search" role="search" action="${es ? '/es/docs/' : '/docs/'}">
    <label for="docs-search">${es ? 'Buscar en la documentación' : 'Search the docs'}</label>
    <div class="docs-search__field"><input id="docs-search" name="q" type="search" data-doc-search placeholder="${es ? 'ssh, agentes, plugins…' : 'ssh, agents, plugins…'}" autocomplete="off"><button class="button button-secondary" type="submit">${es ? 'Buscar' : 'Search'}</button></div>
    <div class="docs-search-results" data-doc-search-results aria-live="polite"></div>
  </form>
  ${docGroups.map(([id, enTitle, esTitle, slugs]) => `<section class="doc-group" aria-labelledby="docs-${id}">
    <h2 id="docs-${id}" class="section-title">${es ? esTitle : enTitle}</h2>
    <div class="doc-cards">${slugs.map((slug) => {
      const [, enDocTitle, esDocTitle, enDesc, esDesc] = bySlug.get(slug);
      return `<article class="doc-card"><h3><a class="tile-link" href="${docHref(slug, es)}">${escapeHTML(es ? esDocTitle : enDocTitle)}</a></h3><p>${escapeHTML(es ? esDesc : enDesc)}</p></article>`;
    }).join('')}</div>
  </section>`).join('\n  ')}
</div></section>`;
}

function docPager(slug, lang) {
  const es = lang === 'es';
  const index = docPages.findIndex((doc) => doc[0] === slug);
  const previous = docPages[index - 1];
  const next = docPages[index + 1];
  const link = (doc, rel) => {
    if (!doc) return '<span></span>';
    const label = rel === 'prev' ? (es ? 'Anterior' : 'Previous') : (es ? 'Siguiente' : 'Next');
    return `<a class="pager__link pager__link--${rel}" href="${docHref(doc[0], es)}" rel="${rel}"><span>${label}</span>${escapeHTML(es ? doc[2] : doc[1])}</a>`;
  };
  return `<nav class="pager" aria-label="${es ? 'Más documentación' : 'More documentation'}">${link(previous, 'prev')}${link(next, 'next')}</nav>`;
}

export function docDetailBody(doc, lang) {
  const [slug, enTitle, esTitle, enDesc, esDesc] = doc;
  const es = lang === 'es';
  const title = es ? esTitle : enTitle;
  const description = es ? esDesc : enDesc;
  const hero = pageHero({
    lang,
    title,
    description,
    crumbs: [[es ? 'Inicio' : 'Home', es ? '/es/' : '/'], [es ? 'Documentación' : 'Docs', es ? '/es/docs/' : '/docs/'], [title]],
  });
  if (slug === 'first-run') return `${hero}\n${firstRunGuide(lang, docPager(slug, lang))}`;
  return `${hero}
<section class="section section--tight"><div class="container docs-layout"><nav class="toc" aria-label="${es ? 'Contenido de documentación' : 'Documentation contents'}"><strong>${es ? 'Contenido' : 'Contents'}</strong><a href="#overview">${es ? 'Resumen' : 'Overview'}</a><a href="#steps">${es ? 'Pasos' : 'Steps'}</a><a href="#verify">${es ? 'Verificación' : 'Verification'}</a></nav><article class="prose"><h2 id="overview">${es ? 'Resumen' : 'Overview'}</h2><p>${renderInline(markConfigFiles(description))}</p><h2 id="steps">${es ? 'Pasos' : 'Steps'}</h2>${codeBlock({ label: 'Terminal', lines: [sampleCommand(slug)] })}<h2 id="verify">${es ? 'Verificación' : 'Verification'}</h2><p>${es ? 'Comprueba la salida localmente antes de depender del flujo en trabajo real.' : 'Verify the output locally before relying on the workflow for real work.'}</p>${docPager(slug, lang)}</article></div></section>`;
}

export function movedBody(lang) {
  const es = lang === 'es';
  const guide = docHref('first-run', es);
  return `${pageHero({
    lang,
    eyebrow: es ? 'Movido' : 'Moved',
    title: es ? 'Primer arranque ahora vive en Docs' : 'First Run now lives in Docs',
    description: es ? 'El servidor redirige esta URL a la guía nueva para preservar enlaces existentes.' : 'The server redirects this URL to the new guide so existing links keep working.',
    actions: `<a class="button button-primary" href="${guide}">${es ? 'Abrir guía' : 'Open guide'}</a>`,
  })}
${firstRunGuide(lang)}`;
}

function docSection(id, title, content, lang) {
  const es = lang === 'es';
  const parts = typeof content === 'string' ? [{ text: content }] : content;
  const rendered = parts.map((part) => {
    if (part.text) return `<p>${renderInline(part.text)}</p>`;
    if (part.caption) return `<p class="doc-caption">${escapeHTML(part.caption)}</p>`;
    if (part.commands) return codeBlock({ label: 'Terminal', lines: part.commands.map(escapeHTML) });
    if (part.config) return codeBlock({ kind: 'config', label: 'TOML', lines: part.config.map(escapeHTML) });
    if (part.terms) return `<ul class="term-list">${part.terms.map((term) => `<li><code>${escapeHTML(term)}</code></li>`).join('')}</ul>`;
    if (part.labels) return `<ul class="label-list">${part.labels.map((label) => `<li>${escapeHTML(label)}</li>`).join('')}</ul>`;
    if (part.keys) return `<p class="key-list">${part.keys.map((key) => `<kbd>${escapeHTML(key)}</kbd>`).join(' ')}</p>`;
    throw new Error(`Unknown doc part in ${id}${es ? ' (es)' : ''}`);
  }).join('');
  return `<h2 id="${id}">${escapeHTML(title)}</h2>${rendered}`;
}

export function firstRunGuide(lang = 'en', pager = '') {
  const es = lang === 'es';
  const sections = es ? [
    ['install', 'Instalar', [{ commands: ['brew tap salp2403/tap && brew install --cask cocxy'] }]],
    ['visual-tour', 'Recorrido visual', 'Abre la barra lateral, el navegador y la Bóveda para confirmar el estado local.'],
    ['concepts', 'Conceptos', 'Pestañas, paneles, sesiones, agentes y Bóveda viven en tu Mac.'],
    ['configuration', 'Configuración', '`.cocxy.toml` controla temas, hooks, agentes y seguridad por proyecto.'],
    ['keyboard-shortcuts', 'Atajos de teclado', 'Usa la paleta de comandos para descubrir acciones sin memorizar atajos.'],
    ['agent-detection', 'Detección de agentes', '`cocxy setup-hooks` instala hooks locales y `cocxy status` verifica el estado.'],
    ['code-review', 'Revisión de código', 'Revisa diffs, comentarios en línea y cambios antes de enviar observaciones.'],
    ['markdown', 'Markdown', 'Abre documentos, previsualiza y exporta sin salir del espacio local.'],
    ['quicklook', 'Quick Look', 'La vista previa opera offline con sanitización de contenido.'],
    ['browser', 'Navegador', 'Usa el navegador integrado para localhost, docs y apps web.'],
    ['remote-workspaces', 'Espacios remotos', 'SSH, SFTP, proxy y daemon se activan solo por acción explícita.'],
    ['web-terminal', 'Terminal web', 'Usa sesiones remotas cuando tú inicies la conexión.'],
    ['shell-integration', 'Integración de shell', 'zsh, bash y fish conservan tus dotfiles.'],
    ['per-project-config', 'Configuración por proyecto', 'Los ajustes locales del repo se separan del perfil global.'],
    ['applescript', 'AppleScript', 'Automatiza ventanas y pestañas con permisos del sistema.'],
    ['plugin-system', 'Sistema de plugins', 'Los plugins usan manifiesto TOML y permisos explícitos.'],
    ['splits', 'Divisiones', 'Divide terminal, navegador y Markdown según el flujo.'],
    ['quick-terminal', 'Terminal rápida', 'Abre una consola ligera sin perder contexto.'],
    ['notifications', 'Notificaciones', 'Las alertas locales se basan en eventos visibles.'],
    ['command-palette', 'Paleta de comandos', 'Busca acciones, ventanas y comandos desde un punto único.'],
    ['sessions', 'Sesiones', 'Reanuda trabajo desde la Bóveda local.'],
    ['local-backups', 'Copias locales', '{{Preferencias &gt; Backups}} permite revisar copias locales. Restaura solo el artefacto seleccionado.'],
    ['input-classifier', 'Clasificador de entrada', [
      { caption: 'clasificador de entrada' },
      { config: ['[input-classifier]', 'dangerous-command-warning = true', 'auto-route-natural-language = false', 'foundation-models-fallback = true'] },
      { commands: ['cocxy classify'] },
      { terms: ['dangerous-command', 'natural-language'] },
    ]],
    ['command-signatures', 'Firmas de comandos', [
      { caption: 'firmas de comandos' },
      { config: ['[security]', 'require-signed-templates = false', 'require-signed-macros = false', 'require-signed-plugins = false', 'warn-on-unsigned = true', 'trust-on-first-use = false'] },
      { commands: ['cocxy keys generate --author', 'cocxy sign template', 'cocxy verify template'] },
      { labels: ['verificada', 'sin firma', 'firma inv&aacute;lida'] },
    ]],
    ['sandbox-controls', 'Controles de sandbox', [
      { config: ['[security.sandbox]', 'plugins-strict = true', 'agents-isolated = true', 'mcp-isolated = true', 'audit-log-enabled = true', 'warn-on-grant = true'] },
      { commands: ['cocxy sandbox list-grants', 'cocxy sandbox revoke'] },
      { labels: ['Inspector de sandbox'] },
    ]],
    ['command-corrections', 'Correcciones de comandos', [
      { caption: 'correcciones de comandos' },
      { config: ['[command-corrections]', 'edit-distance-threshold = 2', 'foundation-models-enabled = true', 'agent-fallback = false', 'auto-show-on-failure = true', 'show-confidence-badge = true'] },
      { commands: ['cocxy correct'] },
      { terms: ['gti status', 'pyhton -m venv .'] },
      { keys: ['Tab', 'Esc'] },
    ]],
    ['cli-companion', 'CLI complementaria', '`cocxy --help` lista comandos para automatización local.'],
    ['themes', 'Temas', 'Configura colores, fuente y contraste desde preferencias.'],
    ['agents-toml', 'agents.toml', 'Define agentes propios, patrones y reglas de reanudación.'],
    ['migration-guide', 'Migrar desde versiones v0.x', '`~/.config/cocxy/` conserva configuración; usa `brew update && brew upgrade --cask cocxy`.'],
    ['troubleshooting', 'Solución de problemas', 'Ejecuta `cocxy doctor` y revisa permisos locales. Sin telemetr&iacute;a.'],
  ] : [
    ['install', 'Install', [{ commands: ['brew tap salp2403/tap && brew install --cask cocxy'] }]],
    ['visual-tour', 'Visual Tour', 'Open the sidebar, browser, and Vault to confirm local state.'],
    ['concepts', 'Concepts', 'Tabs, panes, sessions, agents, and Vault live on your Mac.'],
    ['configuration', 'Configuration', '`.cocxy.toml` controls themes, hooks, agents, and security per project.'],
    ['keyboard-shortcuts', 'Keyboard Shortcuts', 'Use the command palette to discover actions without memorizing shortcuts.'],
    ['agent-detection', 'Agent Detection', '`cocxy setup-hooks` installs local hooks and `cocxy status` verifies state.'],
    ['code-review', 'Code Review', 'Review diffs, inline comments, and changes before returning feedback.'],
    ['markdown', 'Markdown', 'Open documents, preview, and export without leaving the local workspace.'],
    ['quicklook', 'Quick Look', 'Preview content offline with sanitization.'],
    ['browser', 'Browser', 'Use the built-in browser for localhost, docs, and web apps.'],
    ['remote-workspaces', 'Remote Workspaces', 'SSH, SFTP, proxy, and daemon paths start only from explicit action.'],
    ['web-terminal', 'Web Terminal', 'Use remote sessions only when you start the connection.'],
    ['shell-integration', 'Shell Integration', 'zsh, bash, and fish preserve your dotfiles.'],
    ['per-project-config', 'Per-project Config', 'Repo-local settings stay separate from the global profile.'],
    ['applescript', 'AppleScript', 'Automate windows and tabs through system permissions.'],
    ['plugin-system', 'Plugin System', 'Plugins use TOML manifests and explicit permissions.'],
    ['splits', 'Splits', 'Place terminal, browser, and Markdown surfaces side by side.'],
    ['quick-terminal', 'Quick Terminal', 'Open a lightweight console without losing context.'],
    ['notifications', 'Notifications', 'Local alerts are based on visible events.'],
    ['command-palette', 'Command Palette', 'Search actions, windows, and commands from one place.'],
    ['sessions', 'Sessions', 'Resume work from local Vault history.'],
    ['local-backups', 'Local Backups', '{{Preferences > Backups}} lets you review local backups. Restore only the selected artifact.'],
    ['input-classifier', 'Input Classifier', [
      { config: ['[input-classifier]', 'dangerous-command-warning = true', 'auto-route-natural-language = false', 'foundation-models-fallback = true'] },
      { commands: ['cocxy classify'] },
      { terms: ['dangerous-command', 'natural-language'] },
    ]],
    ['command-signatures', 'Command Signatures', [
      { config: ['[security]', 'require-signed-templates = false', 'require-signed-macros = false', 'require-signed-plugins = false', 'warn-on-unsigned = true', 'trust-on-first-use = false'] },
      { commands: ['cocxy keys generate --author', 'cocxy sign template', 'cocxy verify template'] },
      { labels: ['verified', 'unsigned', 'invalid signature'] },
    ]],
    ['sandbox-controls', 'Sandbox Controls', [
      { config: ['[security.sandbox]', 'plugins-strict = true', 'agents-isolated = true', 'mcp-isolated = true', 'audit-log-enabled = true', 'warn-on-grant = true'] },
      { commands: ['cocxy sandbox list-grants', 'cocxy sandbox revoke'] },
      { labels: ['Sandbox Inspector'] },
      { text: 'Agent command tools run with workspace-scoped read/write access' },
    ]],
    ['command-corrections', 'Command Corrections', [
      { config: ['[command-corrections]', 'edit-distance-threshold = 2', 'foundation-models-enabled = true', 'agent-fallback = false', 'auto-show-on-failure = true', 'show-confidence-badge = true'] },
      { commands: ['cocxy correct'] },
      { terms: ['gti status', 'pyhton -m venv .'] },
      { keys: ['Tab', 'Esc'] },
    ]],
    ['cli-companion', 'CLI Companion', '`cocxy --help` lists commands for local automation.'],
    ['themes', 'Themes', 'Configure colors, font, and contrast from preferences.'],
    ['agents-toml', 'agents.toml', 'Define custom agents, patterns, and resume rules.'],
    ['migration-guide', 'Migration from v0.x', '`~/.config/cocxy/` keeps configuration; use `brew update && brew upgrade --cask cocxy`.'],
    ['troubleshooting', 'Troubleshooting', 'Run `cocxy doctor` and inspect local permissions.'],
  ];

  return `<section class="section section--tight"><div class="container docs-layout">
  <nav class="toc" aria-label="${es ? 'Contenido de primer arranque' : 'First run contents'}"><strong>${es ? 'Contenido' : 'Contents'}</strong>${sections.map(([id, title]) => `<a href="#${id}">${escapeHTML(!es && id === 'migration-guide' ? 'Migration Guide' : title)}</a>`).join('')}</nav>
  <article class="prose">
    ${sections.map(([id, title, text]) => docSection(id, title, text, lang)).join('\n')}${pager}
  </article>
</div></section>`;
}
