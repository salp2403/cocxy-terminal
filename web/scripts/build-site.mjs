#!/usr/bin/env node
// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(__dirname, '..');
const publicRoot = path.join(webRoot, 'public');
const repoRoot = path.resolve(webRoot, '..');
const site = 'https://cocxy.dev';
const cssHref = '/css/style.css?v=0.0.0';
const releaseVersion = '0.0.0';
const previewAssetVersion = '0.0.0';
const previewImage = (extension) => `/images/cocxy-preview.${extension}?v=${previewAssetVersion}`;

const agents = [
  ['Claude', 'claude', 'OSC and hooks', '--resume <session-id>'],
  ['Codex', 'codex', 'OSC and state projection', 'resume <session-id>'],
  ['OpenCode', 'opencode', 'Local pattern layer', 'resume <session-id>'],
  ['Pi', 'pi', 'Local pattern layer', 'resume <session-id>'],
  ['Cursor', 'cursor-agent', 'OSC-aware profile', 'resume <session-id>'],
  ['Gemini', 'gemini', 'Pattern and timing fallback', 'resume <session-id>'],
  ['Rovo', 'rovo', 'Local pattern layer', 'resume <session-id>'],
  ['Copilot', 'copilot', 'OSC and hooks', 'resume <session-id>'],
  ['CodeBuddy', 'codebuddy', 'Local pattern layer', 'resume <session-id>'],
  ['Factory', 'factory', 'Local pattern layer', 'resume <session-id>'],
  ['Qoder', 'qoder', 'Local pattern layer', 'resume <session-id>'],
];

const featurePages = [
  {
    slug: 'agents',
    icon: 'spark',
    anchor: 'agent-detection',
    cssClass: 'feature-icon--agents',
    title: 'Multi-Layer Agent Detection',
    esTitle: 'Detección multicapa de agentes',
    summary: 'Cocxy detects local coding agents through hooks, OSC signals, terminal semantics, pattern matching, and timing heuristics.',
    esSummary: 'Cocxy detecta agentes locales mediante hooks, señales OSC, semántica de terminal, patrones y heurísticas de tiempo.',
    bullets: ['11 built-in profiles', 'Custom agents.toml support', 'Per-surface state'],
    sections: [
      ['Detection layers', 'Hooks, OSC 7, OSC 133, process patterns, and timing signals combine so the UI can show thinking, working, waiting, and done states without external reporting.'],
      ['Custom profiles', 'A local agents.toml file lets teams add commands, resume rules, and matching patterns without rebuilding the app.'],
      ['Vault handoff', 'Detected sessions can be resumed from encrypted local history across tabs and panels.'],
    ],
    esSections: [
      ['Capas de detección', 'Hooks, OSC 7, OSC 133, patrones de proceso y señales de tiempo permiten mostrar estados sin reportes externos.'],
      ['Perfiles propios', 'Un archivo local agents.toml permite añadir comandos, reglas de reanudación y patrones sin recompilar la app.'],
      ['Conexión con Bóveda', 'Las sesiones detectadas pueden reanudarse desde historial local cifrado entre pestañas y paneles.'],
    ],
  },
  {
    slug: 'vault',
    icon: 'lock',
    anchor: 'vault',
    cssClass: 'feature-icon--config',
    title: 'Encrypted Vault',
    esTitle: 'Bóveda cifrada',
    summary: 'Search, resume, pin, preview, and export local agent sessions without sending terminal history to a remote service.',
    esSummary: 'Busca, reanuda, fija, previsualiza y exporta sesiones locales sin enviar historial de terminal a un servicio remoto.',
    bullets: ['Encrypted at rest', 'Full-text search', 'Smart resume'],
    sections: [
      ['Encrypted session memory', 'Vault stores session metadata locally with encrypted-at-rest records and macOS Keychain-backed secrets.'],
      ['Search and organization', 'Full-text search, pins, grouping, sorting, hover preview, and activity summaries keep long-running work findable.'],
      ['Export paths', 'Markdown, JSON, and text exports make review and archival explicit user actions.'],
    ],
    esSections: [
      ['Memoria local cifrada', 'Bóveda guarda metadatos de sesiones localmente con registros cifrados y secretos respaldados por Keychain.'],
      ['Búsqueda y organización', 'Búsqueda de texto, favoritos, grupos, orden, vista rápida y actividad ayudan a ubicar trabajo largo.'],
      ['Exportación explícita', 'Exportar a Markdown, JSON o texto ocurre solo por acción del usuario.'],
    ],
  },
  {
    slug: 'code-review',
    icon: 'review',
    anchor: 'code-review',
    cssClass: 'feature-icon--review',
    title: 'Inline Code Review',
    esTitle: 'Revisión de código en línea',
    summary: 'Review agent changes beside the terminal, comment on lines, accept or reject hunks, and return structured feedback to the session.',
    esSummary: 'Revisa cambios del agente junto a la terminal, comenta líneas, acepta o rechaza bloques y devuelve observaciones estructuradas.',
    bullets: ['File tree and diff', 'Inline comments', 'Keyboard workflow'],
    sections: [
      ['Diff beside the PTY', 'The review panel keeps file tree, unified diff, comments, and terminal context visible together.'],
      ['Actionable comments', 'Line comments and hunk decisions become structured text that can be sent back into the running session.'],
      ['Keyboard first', 'Navigation, comment, accept, reject, and submit commands are reachable without leaving the flow.'],
    ],
    esSections: [
      ['Diff junto a la terminal', 'El panel mantiene árbol de archivos, diff unificado, comentarios y contexto visible a la vez.'],
      ['Comentarios accionables', 'Los comentarios por línea y decisiones por bloque se convierten en texto estructurado para la sesión activa.'],
      ['Teclado primero', 'Navegar, comentar, aceptar, rechazar y enviar se puede hacer sin romper el flujo.'],
    ],
  },
  {
    slug: 'markdown',
    icon: 'doc',
    anchor: 'markdown',
    cssClass: 'feature-icon--markdown',
    title: 'Markdown Workspace',
    esTitle: 'Espacio Markdown',
    summary: 'A native writing surface with preview, outline, code blocks, diagrams, math, exports, and local file workflows.',
    esSummary: 'Un espacio nativo con vista previa, índice, bloques de código, diagramas, matemáticas, exportación y archivos locales.',
    bullets: ['Live preview', 'Mermaid and KaTeX', 'Export paths'],
    sections: [
      ['Write beside the terminal', 'Markdown files can sit next to terminal panes, browser panes, and review panels.'],
      ['Rich document support', 'Outline, code blocks, diagrams, math, callouts, task lists, images, and export paths are part of the workspace.'],
      ['Local files', 'Documents stay in the project filesystem, so normal Git review and backups continue working.'],
    ],
    esSections: [
      ['Escritura junto a la terminal', 'Los archivos Markdown pueden vivir junto a terminal, navegador y revisión.'],
      ['Documentos completos', 'Índice, código, diagramas, matemáticas, notas, tareas, imágenes y exportación forman parte del espacio.'],
      ['Archivos locales', 'Los documentos permanecen en el sistema de archivos del proyecto para Git y copias locales.'],
    ],
  },
  {
    slug: 'github',
    icon: 'github',
    anchor: 'github-pane',
    cssClass: 'feature-icon--web',
    title: 'GitHub Pane',
    esTitle: 'Panel de GitHub',
    summary: 'Keep pull requests, issues, checks, release pages, and repository context next to the terminal without adding a Cocxy account.',
    esSummary: 'Mantén pull requests, issues, checks, releases y contexto del repositorio junto a la terminal sin crear una cuenta de Cocxy.',
    bullets: ['gh auth reuse', 'Checks and releases', 'Local context'],
    sections: [
      ['Uses your GitHub auth', 'Cocxy shells out to the authenticated GitHub CLI paths you control instead of brokering repository data through a Cocxy backend.'],
      ['PR and release context', 'Checks, release links, issue references, and repository pages remain visible while agents work.'],
      ['Scriptable', 'The CLI companion keeps GitHub workflows addressable from shell scripts and local automation.'],
    ],
    esSections: [
      ['Usa tu autenticación de GitHub', 'Cocxy reutiliza rutas autenticadas de GitHub CLI que tú controlas, sin pasar datos por un backend de Cocxy.'],
      ['Contexto de PR y release', 'Checks, enlaces de release, issues y páginas del repo quedan visibles mientras trabajan los agentes.'],
      ['Automatizable', 'La CLI permite ejecutar flujos de GitHub desde scripts locales.'],
    ],
  },
  {
    slug: 'browser',
    icon: 'browser',
    anchor: 'browser',
    cssClass: 'feature-icon--browser',
    title: 'Built-in Browser',
    esTitle: 'Navegador incorporado',
    summary: 'Preview localhost, inspect pages, keep profiles isolated, and place the browser beside terminal panes.',
    esSummary: 'Previsualiza localhost, inspecciona páginas, mantiene perfiles aislados y coloca el navegador junto a la terminal.',
    bullets: ['Profiles', 'Dev tools', 'Split workflow'],
    sections: [
      ['Localhost preview', 'Open local web apps from terminal context and keep them in split panes beside commands.'],
      ['Profiles and downloads', 'Browser data, downloads, bookmarks, and inspection paths stay explicit and visible.'],
      ['Agent-safe UI actions', 'The page surface is prepared for deterministic automation without hidden tracking.'],
    ],
    esSections: [
      ['Vista de localhost', 'Abre apps web locales desde la terminal y colócalas junto a los comandos.'],
      ['Perfiles y descargas', 'Datos del navegador, descargas, marcadores e inspección quedan como acciones visibles.'],
      ['Acciones deterministas', 'La superficie está preparada para automatización explícita sin rastreo oculto.'],
    ],
  },
  {
    slug: 'remote',
    icon: 'remote',
    anchor: 'remote',
    cssClass: 'feature-icon--ssh',
    title: 'Remote Workspaces',
    esTitle: 'Espacios remotos',
    summary: 'SSH, proxy, relay, daemon, and file-transfer paths are designed as explicit user actions with local control.',
    esSummary: 'SSH, proxy, relay, daemon y transferencia de archivos se tratan como acciones explícitas bajo control local.',
    bullets: ['SSH multiplexing', 'SOCKS and CONNECT', 'SFTP handoff'],
    sections: [
      ['SSH-first workflow', 'ControlMaster, persistent sessions, file transfer, and terminal handoff are built around explicit SSH actions.'],
      ['Proxy and relay', 'SOCKS5, HTTP CONNECT, relay authentication, and audit logs are designed for clear boundaries.'],
      ['Recoverable sessions', 'Reconnect and attach paths preserve context without hiding network operations.'],
    ],
    esSections: [
      ['Flujo con SSH', 'ControlMaster, sesiones persistentes, transferencia de archivos y terminal operan sobre acciones SSH explícitas.'],
      ['Proxy y relay', 'SOCKS5, HTTP CONNECT, autenticación de relay y registros locales marcan límites claros.'],
      ['Sesiones recuperables', 'Reconectar y adjuntar preserva contexto sin ocultar operaciones de red.'],
    ],
  },
  {
    slug: 'gpu',
    icon: 'gpu',
    anchor: 'gpu',
    cssClass: 'feature-icon--gpu',
    title: 'GPU Terminal Engine',
    esTitle: 'Motor de terminal con GPU',
    summary: 'CocxyCore combines a Zig terminal core, C ABI, glyph atlas hardening, PTY handling, and Metal rendering for native macOS performance.',
    esSummary: 'CocxyCore combina núcleo Zig, ABI C, atlas de glifos, manejo PTY y renderizado Metal para rendimiento nativo en macOS.',
    bullets: ['Zig core', 'Metal renderer', 'PTY semantics'],
    sections: [
      ['CocxyCore boundary', 'Swift talks to CocxyCore through a C ABI, keeping the terminal engine testable and isolated from UI code.'],
      ['Metal rendering', 'Glyph atlas and renderer paths are tuned for stable frame pacing and native macOS drawing.'],
      ['PTY correctness', 'Resize, shell, and terminal state are handled at the engine layer before UI presentation.'],
    ],
    esSections: [
      ['Límite CocxyCore', 'Swift habla con CocxyCore mediante ABI C, separando el motor de terminal del UI.'],
      ['Renderizado Metal', 'El atlas de glifos y el renderizador buscan cadencia estable y dibujo nativo.'],
      ['Corrección PTY', 'Resize, shell y estado de terminal se resuelven en el motor antes del UI.'],
    ],
  },
  {
    slug: 'cli',
    icon: 'terminal',
    anchor: 'cli',
    cssClass: 'feature-icon--cli',
    title: 'CLI Companion',
    esTitle: 'CLI complementaria',
    summary: 'Script windows, tabs, agents, hooks, Vault, browser, markdown, remotes, configuration, themes, and diagnostics.',
    esSummary: 'Automatiza ventanas, pestañas, agentes, hooks, Bóveda, navegador, Markdown, remotos, configuración, temas y diagnósticos.',
    bullets: ['JSON-friendly output', 'Socket API', 'Shell scripts'],
    sections: [
      ['Scriptable app control', 'Window, tab, split, Vault, markdown, browser, remote, and diagnostic commands are designed for shell use.'],
      ['JSON output', 'Machine-readable output keeps jq pipelines and CI checks stable.'],
      ['Socket-backed', 'The app-local socket is explicit and keeps automation on the owner machine.'],
    ],
    esSections: [
      ['Control automatizable', 'Ventanas, pestañas, divisiones, Bóveda, Markdown, navegador, remoto y diagnósticos se pueden manejar desde shell.'],
      ['Salida JSON', 'La salida legible por máquinas mantiene pipelines con jq y checks locales.'],
      ['Socket local', 'El socket de la app opera en la máquina del usuario.'],
    ],
  },
  {
    slug: 'shell',
    icon: 'shell',
    anchor: 'shell',
    cssClass: 'feature-icon--shell',
    title: 'Shell Integration',
    esTitle: 'Integración de shell',
    summary: 'zsh, bash, and fish wrappers preserve user dotfiles while adding cwd, command-boundary, and browser-open signals.',
    esSummary: 'Wrappers para zsh, bash y fish preservan dotfiles y añaden cwd, límites de comandos y apertura de navegador.',
    bullets: ['zsh, bash, fish', 'OSC 7 cwd', 'OSC 133 blocks'],
    sections: [
      ['Dotfile-safe', 'Shell wrappers restore HOME, ZDOTDIR, and XDG_CONFIG_HOME expectations instead of taking over the login environment.'],
      ['Command boundaries', 'OSC 133 and OSC 7 provide cwd and command lifecycle signals to the app.'],
      ['Cross-shell', 'zsh, bash, and fish paths are documented and testable.'],
    ],
    esSections: [
      ['Respeta dotfiles', 'Los wrappers restauran HOME, ZDOTDIR y XDG_CONFIG_HOME sin apropiarse del entorno de login.'],
      ['Límites de comando', 'OSC 133 y OSC 7 entregan cwd y ciclo de vida del comando a la app.'],
      ['Varias shells', 'zsh, bash y fish tienen rutas documentadas y probables.'],
    ],
  },
  {
    slug: 'plugins',
    icon: 'plug',
    anchor: 'plugins',
    cssClass: 'feature-icon--plugin',
    title: 'Plugin System',
    esTitle: 'Sistema de plugins',
    summary: 'Local plugin hooks extend Cocxy while staying transparent, permissioned, and dependency-light.',
    esSummary: 'Hooks locales extienden Cocxy de forma transparente, con permisos explícitos y pocas dependencias.',
    bullets: ['Event hooks', 'TOML manifest', 'Local execution'],
    sections: [
      ['Event hooks', 'Plugins subscribe to documented local events instead of modifying hidden app state.'],
      ['TOML manifest', 'Permissions, commands, and metadata are visible before a plugin runs.'],
      ['Local execution', 'Plugin code executes locally under explicit controls.'],
    ],
    esSections: [
      ['Eventos locales', 'Los plugins se conectan a eventos documentados sin modificar estado oculto.'],
      ['Manifest TOML', 'Permisos, comandos y metadatos son visibles antes de ejecutar.'],
      ['Ejecución local', 'El código de plugin corre localmente con controles explícitos.'],
    ],
  },
  {
    slug: 'zero-telemetry',
    icon: 'privacy',
    anchor: 'privacy',
    cssClass: 'feature-icon--privacy',
    title: 'Zero Telemetry',
    esTitle: 'Cero telemetría',
    summary: 'Cocxy ships without analytics SDKs, automatic crash upload, required accounts, visitor tracking, or session telemetry.',
    esSummary: 'Cocxy se distribuye sin SDK de analíticas, subida automática de fallos, cuentas obligatorias, rastreo o telemetría de sesiones.',
    bullets: ['No analytics SDK', 'No account', 'No session upload'],
    sections: [
      ['No telemetry pipeline', 'There is no analytics SDK, automatic crash upload, or hidden event collector in the app or website.'],
      ['Explicit network actions', 'Updates, SSH, GitHub, browser, and plugins only use network paths that the user starts or configures.'],
      ['Verifiable', 'Public source, local monitors, and the privacy page describe exactly what to inspect.'],
    ],
    esSections: [
      ['Sin tubería de telemetría', 'No hay SDK de analíticas, subida automática de fallos ni recolector oculto de eventos.'],
      ['Red explícita', 'Updates, SSH, GitHub, navegador y plugins usan red solo cuando el usuario lo inicia o configura.'],
      ['Verificable', 'El código público, monitores locales y la página de privacidad explican qué revisar.'],
    ],
  },
];

const docPages = [
  ['install', 'Install Cocxy', 'Instalar Cocxy', 'Download the signed DMG or install with Homebrew.', 'Descarga el DMG firmado o instala con Homebrew.'],
  ['first-run', 'First Run', 'Primer arranque', 'Open Cocxy, connect shell integration, and run the first local agent session.', 'Abre Cocxy, conecta la integración de shell y ejecuta la primera sesión local.'],
  ['configuration', 'Configuration', 'Configuración', 'Use .cocxy.toml for projects, themes, shell behavior, and privacy controls.', 'Usa .cocxy.toml para proyectos, temas, shell y controles de privacidad.'],
  ['agents-setup', 'Agents Setup', 'Configurar agentes', 'Install hooks, define custom profiles, and verify local detection.', 'Instala hooks, define perfiles propios y verifica la detección local.'],
  ['shortcuts', 'Shortcuts', 'Atajos', 'Keyboard paths for panes, review, Vault, command palette, browser, and markdown.', 'Atajos para paneles, revisión, Bóveda, paleta, navegador y Markdown.'],
  ['cli-reference', 'CLI Reference', 'Referencia CLI', 'Script Cocxy through the bundled command-line companion.', 'Automatiza Cocxy con la CLI incluida.'],
  ['plugins-dev', 'Plugin Development', 'Desarrollo de plugins', 'Build local plugins with a manifest, event hooks, and explicit permissions.', 'Crea plugins locales con manifest, hooks y permisos explícitos.'],
  ['ssh-remote', 'SSH and Remote', 'SSH y remoto', 'Use SSH workspaces, proxy paths, daemon sessions, and SFTP handoff deliberately.', 'Usa espacios SSH, proxies, daemon y SFTP de forma explícita.'],
  ['markdown-guide', 'Markdown Guide', 'Guía Markdown', 'Write, preview, export, and keep documentation beside terminal work.', 'Escribe, previsualiza, exporta y mantén documentación junto a la terminal.'],
  ['release-channels', 'Release Channels', 'Canales de release', 'Understand stable, validation, and nightly update channels before switching.', 'Entiende los canales estable, validación y nocturno antes de cambiar.'],
  ['troubleshooting', 'Troubleshooting', 'Solución de problemas', 'Diagnose shell setup, agent detection, updates, signing, remotes, and browser panels.', 'Diagnostica shell, detección, updates, firma, remotos y navegador.'],
];

const topPages = [
  ['features', 'All Features', 'Todas las funciones', 'A complete map of Cocxy Terminal capabilities for agent-driven development.', 'Mapa completo de capacidades de Cocxy Terminal para desarrollo con agentes.'],
  ['privacy', 'Privacy', 'Privacidad', 'Zero telemetry is a verifiable implementation detail, not a marketing promise.', 'Cero telemetría es un detalle verificable de implementación, no una promesa de marketing.'],
  ['security', 'Security', 'Seguridad', 'Local secrets, signed updates, encrypted stores, hardened runtime, and explicit network actions.', 'Secretos locales, updates firmados, almacenes cifrados, ejecución reforzada y red explícita.'],
  ['architecture', 'Architecture', 'Arquitectura', 'Swift, AppKit, SwiftUI, Metal, and CocxyCore form a native macOS stack.', 'Swift, AppKit, SwiftUI, Metal y CocxyCore forman una pila nativa para macOS.'],
  ['why-cocxy', 'Why Cocxy', 'Por qué Cocxy', 'A terminal designed around local-first agent workflows on macOS.', 'Una terminal diseñada alrededor de flujos locales con agentes en macOS.'],
  ['faq', 'FAQ', 'Preguntas frecuentes', 'Answers about installation, privacy, agents, updates, remotes, and source code.', 'Respuestas sobre instalación, privacidad, agentes, updates, remotos y código fuente.'],
  ['channels', 'Channels', 'Canales', 'Stable, preview, and nightly channels with explicit risk tradeoffs.', 'Canales estable, validación y nocturno con riesgos claros.'],
  ['press', 'Press', 'Prensa', 'Brand facts, concise descriptions, screenshots, colors, and contact details.', 'Datos de marca, descripciones, capturas, colores y contacto.'],
  ['roadmap', 'Roadmap', 'Ruta pública', 'Public direction without exposing private planning details.', 'Dirección pública sin exponer planificación privada.'],
  ['sponsors', 'Sponsors', 'Patrocinios', 'Support ongoing MIT development without creating a paid tier.', 'Apoya el desarrollo MIT sin crear un nivel de pago.'],
  ['agents', 'Agents', 'Agentes', 'The supported agent profiles and detection layers.', 'Perfiles de agentes soportados y capas de detección.'],
];

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
  const parts = ['tokens.css', 'base.css', 'components.css', 'glass.css', 'pages.css', 'print.css'];
  const bundled = parts.map((file) => {
    const source = fs.readFileSync(path.join(cssDir, file), 'utf8').trim();
    return `/* ${file} */\n${source}`;
  }).join('\n\n');
  fs.writeFileSync(path.join(cssDir, 'style.css'), `${bundled}\n`);
}

function escapeHTML(value) {
  const entities = [];
  return String(value)
    .replace(/&(?:[a-zA-Z][a-zA-Z0-9]+|#[0-9]+|#x[0-9a-fA-F]+);/g, (entity) => {
      entities.push(entity);
      return `\u0000${entities.length - 1}\u0000`;
    })
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replace(/\u0000(\d+)\u0000/g, (_, index) => entities[Number(index)]);
}

function escapeXML(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

function json(value) {
  return JSON.stringify(value, null, 2)
    .replaceAll('<', '\\u003c')
    .replaceAll('>', '\\u003e')
    .replaceAll('&', '\\u0026');
}

function canonicalFor(page, lang = 'en') {
  const prefix = lang === 'es' ? '/es' : '';
  return `${site}${prefix}${page === '/' ? '/' : page}`;
}

function alternateLinks(page, lang = 'en') {
  const en = canonicalFor(page, 'en');
  const es = canonicalFor(page, 'es');
  return [
    `<link rel="canonical" href="${lang === 'es' ? es : en}">`,
    `<link rel="alternate" hreflang="en" href="${en}">`,
    `<link rel="alternate" hreflang="es" href="${es}">`,
    `<link rel="alternate" hreflang="x-default" href="${en}">`,
  ].join('\n  ');
}

function icon(name) {
  const paths = {
    spark: '<path d="M12 2l1.8 5.2L19 9l-5.2 1.8L12 16l-1.8-5.2L5 9l5.2-1.8L12 2z"/><path d="M5 14l.9 2.6L8.5 17.5l-2.6.9L5 21l-.9-2.6-2.6-.9 2.6-.9L5 14z"/>',
    lock: '<rect x="5" y="10" width="14" height="10" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/><path d="M12 14v2"/>',
    review: '<path d="M4 4h16v11H8l-4 4V4z"/><path d="M8 8h8M8 11h6"/>',
    doc: '<path d="M7 3h7l5 5v13H7z"/><path d="M14 3v5h5"/><path d="M10 13h6M10 16h4"/>',
    browser: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3 9h18M7 7h.01M10 7h.01"/>',
    remote: '<path d="M4 6h16v9H4z"/><path d="M8 19h8M12 15v4"/><path d="M8 10h3M13 10h3"/>',
    terminal: '<path d="M4 6h16v12H4z"/><path d="M8 10l2 2-2 2M12 14h4"/>',
    shell: '<path d="M5 7h14M5 12h14M5 17h9"/><path d="M4 4h16v16H4z"/>',
    plug: '<path d="M8 3v6M16 3v6M7 9h10v4a5 5 0 0 1-10 0V9z"/><path d="M12 18v3"/>',
    github: '<path d="M9 19c-4 1.2-4-2-5-2.5"/><path d="M15 22v-3.4a3 3 0 0 0-.8-2.3c2.7-.3 5.6-1.3 5.6-6A4.7 4.7 0 0 0 18.5 7a4.4 4.4 0 0 0-.1-3.2s-1-.3-3.3 1.2a11.5 11.5 0 0 0-6 0C6.8 3.5 5.8 3.8 5.8 3.8A4.4 4.4 0 0 0 5.7 7a4.7 4.7 0 0 0-1.3 3.3c0 4.6 2.8 5.7 5.5 6A3 3 0 0 0 9 18.6V22"/>',
    gpu: '<rect x="4" y="6" width="16" height="12" rx="2"/><path d="M8 10h8v4H8zM2 10h2M2 14h2M20 10h2M20 14h2M8 2v4M12 2v4M16 2v4M8 18v4M12 18v4M16 18v4"/>',
    privacy: '<path d="M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6l7-3z"/><path d="M9 12l2 2 4-5"/>',
  };
  return `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">${paths[name] ?? paths.spark}</svg>`;
}

function head({ title, description, page, lang = 'en', schema = [], type = 'website' }) {
  const htmlLang = lang === 'es' ? 'es-HN' : 'en';
  const ogLocale = lang === 'es' ? 'es_HN' : 'en_US';
  const url = canonicalFor(page, lang);
  const titleFull = `${title} - Cocxy Terminal`;
  return `<!DOCTYPE html>
<html lang="${htmlLang}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escapeHTML(titleFull)}</title>
  <meta name="description" content="${escapeHTML(description)}">
  <meta name="author" content="Said Arturo Lopez">
  <meta name="robots" content="index, follow, max-snippet:-1, max-image-preview:large">
  <meta name="theme-color" content="#101018">
  <meta property="og:type" content="${type}">
  <meta property="og:site_name" content="Cocxy Terminal">
  <meta property="og:title" content="${escapeHTML(titleFull)}">
  <meta property="og:description" content="${escapeHTML(description)}">
  <meta property="og:url" content="${url}">
  <meta property="og:image" content="${site}/og/og-${pageToSlug(page)}.png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:image:alt" content="${escapeHTML(titleFull)}">
  <meta property="og:locale" content="${ogLocale}">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escapeHTML(titleFull)}">
  <meta name="twitter:description" content="${escapeHTML(description)}">
  <meta name="twitter:image" content="${site}/og/og-${pageToSlug(page)}.png">
  ${alternateLinks(page, lang)}
  <link rel="icon" type="image/png" href="/images/icon.png">
  <link rel="apple-touch-icon" href="/images/icon.png">
  <link rel="manifest" href="/manifest.webmanifest">
  <link rel="alternate" type="application/rss+xml" title="Cocxy Terminal Appcast" href="/appcast.xml">
  <link rel="alternate" type="application/rss+xml" title="Cocxy Terminal Updates" href="/feed.xml">
  <link rel="alternate" type="application/rss+xml" title="Cocxy Terminal Releases" href="/releases.xml">
  <link rel="preload" as="image" href="${previewImage('avif')}" type="image/avif" fetchpriority="high">
  <link rel="stylesheet" href="${cssHref}">
  <script>
  (() => {
    try {
      const saved = localStorage.getItem('cocxy-theme');
      if (saved === 'light' || saved === 'dark') document.documentElement.dataset.theme = saved;
    } catch (_) {}
  })();
  </script>
  ${schema.map((entry) => `<script type="application/ld+json">\n${json(entry)}\n  </script>`).join('\n  ')}
</head>`;
}

function nav(lang = 'en', active = '') {
  const es = lang === 'es';
  const labels = es
    ? ['Funciones', 'Agentes', 'Privacidad', 'Seguridad', 'Documentación', 'Descargar', 'English']
    : ['Features', 'Agents', 'Privacy', 'Security', 'Docs', 'Download', 'Español'];
  const langHref = es ? alternateCurrent('en') : alternateCurrent('es');
  const downloadHref = pageHasLocalDownload(currentPage) ? '#download' : `${es ? '/es/' : '/'}#download`;
  return `<a class="skip-link" href="#main">${es ? 'Saltar al contenido' : 'Skip to main content'}</a>
<header class="site-header">
  <nav class="nav container" aria-label="${es ? 'Navegación principal' : 'Main navigation'}">
    <a class="nav-logo" href="${es ? '/es/' : '/'}" aria-label="Cocxy Terminal">
      <img src="/images/icon.png" width="32" height="32" alt="">
      <span>Cocxy</span>
    </a>
    <button class="nav-toggle" type="button" aria-expanded="false" aria-controls="site-menu">
      <span></span><span></span><span></span>
      <span class="sr-only">${es ? 'Abrir navegación' : 'Open navigation'}</span>
    </button>
    <div class="nav-links" id="site-menu">
      <a ${active === 'features' ? 'aria-current="page"' : ''} href="${es ? '/es/features.html' : '/features.html'}">${labels[0]}</a>
      <a ${active === 'agents' ? 'aria-current="page"' : ''} href="${es ? '/es/features/agents.html' : '/features/agents.html'}">${labels[1]}</a>
      <a ${active === 'privacy' ? 'aria-current="page"' : ''} href="${es ? '/es/privacy.html' : '/privacy.html'}">${labels[2]}</a>
      <a ${active === 'security' ? 'aria-current="page"' : ''} href="${es ? '/es/security.html' : '/security.html'}">${labels[3]}</a>
      <a ${active === 'docs' ? 'aria-current="page"' : ''} href="${es ? '/es/docs/' : '/docs/'}">${labels[4]}</a>
      <a class="nav-cta" href="${downloadHref}">${labels[5]}</a>
      <button class="theme-toggle" type="button" aria-label="${es ? 'Cambiar tema' : 'Toggle theme'}" title="${es ? 'Cambiar tema' : 'Toggle theme'}">
        <span class="theme-toggle__sun" aria-hidden="true">☀</span>
        <span class="theme-toggle__moon" aria-hidden="true">◐</span>
      </button>
      <a href="${langHref}" hreflang="${es ? 'en' : 'es'}" lang="${es ? 'en' : 'es'}">${labels[6]}</a>
      <a href="https://github.com/salp2403/cocxy-terminal" target="_blank" rel="noopener noreferrer">GitHub</a>
    </div>
  </nav>
</header>`;
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
  const es = lang === 'es';
  return `<footer class="site-footer">
  <div class="container footer-grid">
    <div>
      <a class="footer-brand" href="${es ? '/es/' : '/'}"><img src="/images/icon.png" width="28" height="28" alt=""><span>Cocxy Terminal</span></a>
      <p>${es ? 'Terminal nativa para macOS, local primero, MIT y sin telemetría.' : 'Native macOS terminal, local-first, MIT licensed, and zero telemetry.'}</p>
    </div>
    <nav aria-label="${es ? 'Enlaces de pie' : 'Footer links'}">
      <a href="${es ? '/es/privacy.html' : '/privacy.html'}">${es ? 'Privacidad' : 'Privacy'}</a>
      <a href="${es ? '/es/security.html' : '/security.html'}">${es ? 'Seguridad' : 'Security'}</a>
      <a href="${es ? '/es/releases.html' : '/releases.html'}">${es ? 'Releases' : 'Releases'}</a>
      <a href="https://github.com/salp2403/cocxy-terminal/blob/main/LICENSE" target="_blank" rel="noopener noreferrer">MIT</a>
    </nav>
    <p class="footer-note">${es ? 'Hecho por Said Arturo Lopez.' : 'Made by Said Arturo Lopez.'}</p>
  </div>
</footer>
<script src="/js/theme-switcher.js" defer></script>
<script src="/js/main.js" defer></script>
</body>
</html>`;
}

function pageToSlug(page) {
  if (page === '/') return 'index';
  return page.replace(/^\//, '').replace(/\/$/, '').replace(/\/index\.html$/, '').replace(/\.html$/, '').replaceAll('/', '-');
}

function breadcrumbSchema(items) {
  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: items.map((item, index) => ({
      '@type': 'ListItem',
      position: index + 1,
      name: item[0],
      item: `${site}${item[1]}`,
    })),
  };
}

function softwareSchema(lang = 'en') {
  return {
    '@context': 'https://schema.org',
    '@type': 'SoftwareApplication',
    name: 'Cocxy Terminal',
    applicationCategory: 'DeveloperApplication',
    applicationSubCategory: 'Terminal Emulator',
    operatingSystem: 'macOS 14.0+',
    url: site,
    downloadUrl: 'https://github.com/salp2403/cocxy-terminal/releases/latest',
    softwareVersion: releaseVersion,
    license: 'https://opensource.org/licenses/MIT',
    isAccessibleForFree: true,
    inLanguage: lang === 'es' ? 'es-HN' : 'en',
    featureList: [
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

function layout({ page, lang = 'en', title, description, active = '', schema = [], body }) {
  currentPage = page;
  return `${head({ title, description, page, lang, schema })}\n<body>\n${nav(lang, active)}\n<main id="main">\n${body}\n</main>\n${footer(lang)}`;
}

function downloadSection(lang = 'en') {
  const es = lang === 'es';
  return `<section class="section section-band" id="download" aria-labelledby="download-title">
  <div class="container">
    <div class="section-header">
      <p class="eyebrow">${es ? 'Descarga' : 'Download'}</p>
      <h2 id="download-title">${es ? 'Instala Cocxy en macOS' : 'Install Cocxy on macOS'}</h2>
      <p>${es ? 'El sitio conserva placeholders de versión para que el release workflow los reescriba al publicar.' : 'The site keeps version placeholders so the release workflow can rewrite them when publishing.'}</p>
    </div>
    <div class="download-grid">
      <article class="card">
        <h3>DMG</h3>
        <p>${es ? 'Descarga directa desde GitHub Releases.' : 'Direct download from GitHub Releases.'}</p>
        <a class="button button-primary" href="https://github.com/salp2403/cocxy-terminal/releases/download/v0.0.0/CocxyTerminal-0.0.0.dmg">${es ? 'Descargar v0.0.0' : 'Download v0.0.0'}</a>
      </article>
      <article class="card">
        <h3>Homebrew</h3>
        <p>${es ? 'Instalación reproducible desde el tap oficial.' : 'Reproducible install from the official tap.'}</p>
        <pre class="code-block"><code>brew tap salp2403/tap &amp;&amp; brew install --cask cocxy</code><button class="copy-button" type="button">${es ? 'Copiar' : 'Copy'}</button></pre>
      </article>
      <article class="card">
        <h3>${es ? 'Canales' : 'Channels'}</h3>
        <p>${es ? 'Canal estable, validación y nocturno documentados con sus riesgos.' : 'Stable, preview, and nightly are documented with clear risk levels.'}</p>
        <a class="button button-secondary" href="${es ? '/es/channels.html' : '/channels.html'}">${es ? 'Ver canales' : 'View channels'}</a>
      </article>
    </div>
  </div>
</section>`;
}

function home(lang = 'en') {
  const es = lang === 'es';
  const page = '/';
  const title = es ? 'Cocxy Terminal' : 'Cocxy Terminal';
  const description = es
    ? 'Terminal nativa para macOS que entiende agentes de IA, con Bóveda cifrada, revisión de código, Markdown, remotos y cero telemetría.'
    : 'Native macOS terminal that understands AI coding agents, with encrypted Vault, code review, Markdown, remotes, and zero telemetry.';
  const schema = [
    { '@context': 'https://schema.org', '@type': 'Organization', name: 'Cocxy Terminal', url: site, logo: `${site}/images/icon.png`, founder: { '@type': 'Person', name: 'Said Arturo Lopez' } },
    { '@context': 'https://schema.org', '@type': 'WebSite', url: site, name: 'Cocxy Terminal', potentialAction: { '@type': 'SearchAction', target: `${site}${es ? '/es' : ''}/docs/?q={search_term_string}`, 'query-input': 'required name=search_term_string' } },
    softwareSchema(lang),
    {
      '@context': 'https://schema.org',
      '@type': 'FAQPage',
      mainEntity: [
        { '@type': 'Question', name: es ? '¿Cocxy requiere cuenta?' : 'Does Cocxy require an account?', acceptedAnswer: { '@type': 'Answer', text: es ? 'No. Cocxy se instala y usa localmente sin cuenta obligatoria.' : 'No. Cocxy installs and runs locally without a required account.' } },
        { '@type': 'Question', name: es ? '¿Cocxy envía telemetría?' : 'Does Cocxy send telemetry?', acceptedAnswer: { '@type': 'Answer', text: es ? 'No. No hay analíticas, rastreo ni subida automática de sesiones.' : 'No. There are no analytics, tracking scripts, or automatic session uploads.' } },
      ],
    },
    {
      '@context': 'https://schema.org',
      '@type': 'VideoObject',
      name: es ? 'Demo de Cocxy Terminal' : 'Cocxy Terminal demo',
      description,
      thumbnailUrl: `${site}/images/og-image.png`,
      uploadDate: '2026-05-16',
      contentUrl: `${site}/videos/cocxy-demo.mp4`,
      embedUrl: `${site}/#demo`,
    },
    breadcrumbSchema([[es ? 'Inicio' : 'Home', es ? '/es/' : '/']]),
  ];
  const body = `<section class="hero hero-product" id="hero" aria-labelledby="hero-title">
  <picture class="hero-media">
    <source srcset="${previewImage('avif')}" type="image/avif">
    <source srcset="${previewImage('webp')}" type="image/webp">
    <img src="${previewImage('png')}" width="1574" height="808" alt="${es ? 'Cocxy Terminal con paneles, navegador y agentes locales' : 'Cocxy Terminal with panes, browser, and local agent state'}" fetchpriority="high">
  </picture>
  <div class="container hero-inner">
    <img class="hero-logo" src="/images/icon.png" width="92" height="92" alt="">
    <p class="eyebrow">${es ? 'Nativa macOS · Local primero · MIT' : 'Native macOS · Local-first · MIT'}</p>
    <h1 id="hero-title">Cocxy Terminal</h1>
    <p class="hero-lede">${es ? 'La terminal que entiende a los agentes de IA.' : 'The terminal that understands AI coding agents.'}</p>
    <p>${es ? 'Detección en tiempo real, revisión de código en línea, Bóveda cifrada, Markdown nativo, espacios remotos y cero telemetría.' : 'Real-time detection, inline code review, encrypted Vault, native Markdown, remote workspaces, and zero telemetry.'}</p>
    <div class="hero-actions">
      <a class="button button-primary" href="#download">${es ? 'Descargar para macOS' : 'Download for macOS'}</a>
      <a class="button button-secondary" href="https://github.com/salp2403/cocxy-terminal" target="_blank" rel="noopener noreferrer">GitHub</a>
    </div>
    <div class="hero-version"><span class="version-badge">v0.0.0</span><span>macOS 14.0+</span><span>Zero telemetry</span></div>
    <div class="hero-console glass" role="group" aria-label="${es ? 'Estado local de agentes' : 'Local agent state'}">
      <span class="console-dot"></span><span class="console-dot"></span><span class="console-dot"></span>
      <strong>$ cocxy agents status</strong>
      <code>${es ? 'bóveda: cifrada · navegador: localhost:3000 · revisión: 3 archivos' : 'vault: encrypted · browser: localhost:3000 · review: 3 files'}</code>
      <code>${es ? 'agente: trabajando · estado: visible · telemetría: cero' : 'agent: working · state: visible · telemetry: zero'}</code>
    </div>
  </div>
</section>
<section class="stats-strip" aria-label="${es ? 'Datos clave' : 'Key facts'}">
  <div class="container stats-grid">
    ${stat('11', es ? 'agentes' : 'agents')}
    ${stat('21', es ? 'idiomas' : 'languages')}
    ${stat('0', es ? 'telemetría' : 'telemetry')}
    ${stat('MIT', es ? 'licencia' : 'license')}
    ${stat('14+', 'macOS')}
  </div>
</section>
<section class="section" id="comparison" aria-labelledby="different-title">
  <div class="container">
    <div class="section-header">
      <p class="eyebrow">${es ? 'Diferencia central' : 'What makes Cocxy different'}</p>
      <h2 id="different-title">${es ? 'Conciencia de agentes, privacidad local y motor nativo' : 'Agent awareness, local privacy, and a native engine'}</h2>
      <p>${es ? 'El sitio explica capacidades de Cocxy por sí mismas: estado de agentes visible, datos locales y una app nativa para macOS.' : 'The site explains Cocxy on its own terms: visible agent state, local data, and a native macOS app.'}</p>
    </div>
    <div class="cards-3">
      <article class="card"><h3>${es ? 'Agentes en tiempo real' : 'Real-time agent awareness'}</h3><p>${es ? 'Cocxy entiende cuando un agente piensa, trabaja, espera input o termina.' : 'Cocxy understands when an agent is thinking, working, waiting for input, or done.'}</p></article>
      <article class="card"><h3>${es ? 'Local primero' : 'Local-first by design'}</h3><p>${es ? 'Bóveda, sesiones, configuración y revisión viven en tu Mac salvo acciones explícitas.' : 'Vault, sessions, configuration, and review state live on your Mac unless you start an explicit action.'}</p></article>
      <article class="card"><h3>${es ? 'Hecho para desarrollo' : 'Built for developers'}</h3><p>${es ? 'Swift, AppKit, SwiftUI, CocxyCore y Metal sostienen una experiencia nativa.' : 'Swift, AppKit, SwiftUI, CocxyCore, and Metal support a native workflow.'}</p></article>
    </div>
  </div>
</section>
<section class="section" id="features" aria-labelledby="features-title">
  <div class="container">
    <div class="section-header">
      <p class="eyebrow">${es ? 'Funciones principales' : 'Flagship features'}</p>
      <h2 id="features-title">${es ? 'Todo conectado al flujo real de agentes' : 'Everything connects to real agent work'}</h2>
      <p>${es ? 'Cocxy junta terminal, revisión, Bóveda, navegador, Markdown y remotos sin enviar tu trabajo a un backend de Cocxy.' : 'Cocxy combines terminal, review, Vault, browser, Markdown, and remotes without sending your work to a Cocxy backend.'}</p>
    </div>
    <div class="feature-grid">
      ${featurePages.map((feature) => featureCard(feature, lang)).join('\n')}
    </div>
  </div>
</section>
<section class="section section-band" id="demo" aria-labelledby="demo-title">
  <div class="container split-grid">
    <div>
      <p class="eyebrow">${es ? 'Demo' : 'Demo'}</p>
      <h2 id="demo-title">${es ? 'Cocxy en acción' : 'See Cocxy in action'}</h2>
      <p>${es ? 'La demo muestra terminal, paneles, navegador, Bóveda y estados locales sin cargar scripts de terceros.' : 'The demo shows terminal panes, browser, Vault, and local state without loading third-party scripts.'}</p>
    </div>
    <video controls muted loop playsinline preload="metadata" poster="/images/og-image.png" class="media-frame">
      <source src="/videos/cocxy-demo.webm" type="video/webm">
      <source src="/videos/cocxy-demo.mp4" type="video/mp4">
    </video>
  </div>
</section>
<section class="section" aria-labelledby="architecture-teaser">
  <div class="container split-grid">
    <div>
      <p class="eyebrow">${es ? 'Arquitectura' : 'Architecture'}</p>
      <h2 id="architecture-teaser">${es ? 'Swift + Metal, impulsado por CocxyCore' : 'Swift + Metal, powered by CocxyCore'}</h2>
      <p>${es ? 'La app separa UI nativo, servicios de dominio, PTY, renderizado Metal y motor CocxyCore con ABI C.' : 'The app separates native UI, domain services, PTY handling, Metal rendering, and the CocxyCore C ABI.'}</p>
      <a class="text-link" href="${es ? '/es/architecture.html' : '/architecture.html'}">${es ? 'Ver arquitectura' : 'View architecture'} →</a>
    </div>
    <img class="architecture-preview" src="/images/architecture-diagram.svg" width="920" height="520" alt="${es ? 'Diagrama estático de arquitectura de Cocxy' : 'Static Cocxy architecture diagram'}" loading="lazy">
  </div>
</section>
<section class="section section-split" aria-labelledby="privacy-title">
  <div class="container split-grid">
    <div>
      <p class="eyebrow">${es ? 'Privacidad verificable' : 'Verifiable privacy'}</p>
      <h2 id="privacy-title">${es ? 'Cero telemetría. Sin cuenta. Sin rastreo.' : 'Zero telemetry. No account. No tracking.'}</h2>
      <p>${es ? 'Cocxy no incluye analíticas, subida automática de fallos ni rastreo oculto. Las conexiones de red existen solo para acciones explícitas como updates, navegador, GitHub, SSH o plugins.' : 'Cocxy ships without analytics, automatic crash uploads, or hidden tracking. Network access exists only for explicit actions such as updates, browser sessions, GitHub, SSH, or plugins.'}</p>
      <a class="text-link" href="${es ? '/es/privacy.html' : '/privacy.html'}">${es ? 'Leer privacidad' : 'Read privacy'} →</a>
    </div>
    <div class="terminal-panel" role="group" aria-label="${es ? 'Resumen de privacidad' : 'Privacy summary'}">
      <span>$ cocxy privacy status</span>
      <strong>${es ? 'telemetría: cero' : 'telemetry: zero'}</strong>
      <strong>${es ? 'analíticas: ninguna' : 'analytics: none'}</strong>
      <strong>${es ? 'cuenta: no requerida' : 'account: not required'}</strong>
      <strong>${es ? 'licencia: MIT' : 'license: MIT'}</strong>
    </div>
  </div>
</section>
<section class="section" id="faq" aria-labelledby="home-faq-title">
  <div class="container">
    <div class="section-header">
      <p class="eyebrow">${es ? 'Preguntas clave' : 'Key questions'}</p>
      <h2 id="home-faq-title">${es ? 'Respuestas rápidas antes de instalar' : 'Fast answers before installing'}</h2>
    </div>
    <div class="faq-list">
      <details class="faq-item"><summary>${es ? '¿Cocxy requiere cuenta?' : 'Does Cocxy require an account?'}</summary><p>${es ? 'No. La app funciona localmente sin cuenta obligatoria.' : 'No. The app works locally without a required account.'}</p></details>
      <details class="faq-item"><summary>${es ? '¿Mis sesiones salen de mi Mac?' : 'Do my sessions leave my Mac?'}</summary><p>${es ? 'No por telemetr&iacute;a. Solo hay red cuando tú abres navegador, SSH, GitHub, updates o plugins.' : 'Not through telemetry. Network access happens only when you open browser, SSH, GitHub, updates, or plugins.'}</p></details>
      <details class="faq-item"><summary>${es ? '¿Es 100% c&oacute;digo abierto?' : 'Is it open source?'}</summary><p>${es ? 'Sí. Cocxy es MIT y el código público se puede auditar.' : 'Yes. Cocxy is MIT licensed and the public source can be audited.'}</p></details>
    </div>
  </div>
</section>
${downloadSection(lang)}
<section class="section" id="opensource" aria-labelledby="opensource-title">
  <div class="container split-grid">
    <div>
      <p class="eyebrow">${es ? 'Comunidad' : 'Open source'}</p>
      <h2 id="opensource-title">${es ? '100% c&oacute;digo abierto, MIT y cero telemetr&iacute;a' : 'MIT licensed, local-first, and open source'}</h2>
      <p>${es ? 'Cocxy se puede inspeccionar, compilar y mejorar. La dirección pública se documenta sin exponer planes privados.' : 'Cocxy can be inspected, built, and improved. Public direction is documented without exposing private planning details.'}</p>
      <div class="hero-actions">
        <a class="button button-primary" href="https://github.com/salp2403/cocxy-terminal" target="_blank" rel="noopener noreferrer">GitHub</a>
        <a class="button button-secondary" href="${es ? '/es/docs/' : '/docs/'}">${es ? 'Leer documentación' : 'Read docs'}</a>
      </div>
    </div>
    <div class="terminal-panel" role="group" aria-label="${es ? 'Resumen open source' : 'Open source summary'}">
      <span>$ cocxy project facts</span>
      <strong>agents: 11</strong>
      <strong>languages: 21</strong>
      <strong>Metal GPU: enabled</strong>
      <strong>telemetry: zero</strong>
    </div>
  </div>
</section>`;
  return layout({ page, lang, title, description, active: '', schema, body });
}

function stat(value, label) {
  return `<div class="stat"><strong>${value}</strong><span>${label}</span></div>`;
}

function featureCard(feature, lang = 'en') {
  const es = lang === 'es';
  const href = `${es ? '/es' : ''}/features/${feature.slug}.html`;
  return `<article class="feature-card ${feature.cssClass}" id="${feature.anchor}">
  ${icon(feature.icon)}
  <h3><a href="${href}">${escapeHTML(es ? feature.esTitle : feature.title)}</a></h3>
  <p>${escapeHTML(es ? feature.esSummary : feature.summary)}</p>
  <ul>${localizedBullets(feature, lang).map((item) => `<li>${escapeHTML(item)}</li>`).join('')}</ul>
</article>`;
}

function localizedBullets(feature, lang = 'en') {
  if (lang !== 'es') return feature.bullets;
  const bullets = {
    agents: ['11 perfiles integrados', 'agents.toml propio', 'Estado por superficie'],
    vault: ['Cifrado local', 'Búsqueda de texto', 'Reanudación inteligente'],
    'code-review': ['Árbol de archivos y diff', 'Comentarios por línea', 'Flujo por teclado'],
    markdown: ['Vista en vivo', 'Mermaid y KaTeX', 'Rutas de exportación'],
    github: ['Usa gh auth', 'Checks y releases', 'Contexto local'],
    browser: ['Perfiles', 'Herramientas de inspección', 'Flujo dividido'],
    remote: ['Multiplexing SSH', 'SOCKS y CONNECT', 'Entrega SFTP'],
    gpu: ['Núcleo Zig', 'Renderizador Metal', 'Semántica PTY'],
    cli: ['Salida JSON', 'Socket local', 'Scripts de shell'],
    shell: ['zsh, bash, fish', 'cwd con OSC 7', 'bloques OSC 133'],
    plugins: ['Eventos', 'Manifest TOML', 'Ejecución local'],
    'zero-telemetry': ['Sin SDK de analíticas', 'Sin cuenta', 'Sin subida de sesiones'],
  };
  return bullets[feature.slug] ?? feature.bullets;
}

function featureHub(lang = 'en') {
  const es = lang === 'es';
  const page = '/features.html';
  const description = es ? topPages[0][4] : topPages[0][3];
  const body = standardHero({
    lang,
    eyebrow: es ? 'Hub de funciones' : 'Feature hub',
    title: es ? 'Funciones de Cocxy' : 'Cocxy features',
    description,
  }) + `<section class="section"><div class="container docs-layout">
  <nav class="toc" aria-label="${es ? 'Mapa de funciones' : 'Feature map'}"><strong>${es ? 'Mapa' : 'Map'}</strong>${featureAnchors(lang).map((item) => `<a href="#${item.id}">${escapeHTML(item.label)}</a>`).join('')}</nav>
    <div>
      <div class="section-header">
        <h2>${es ? 'Capacidades principales' : 'Primary capabilities'}</h2>
        <p>${es ? 'Cada bloque conecta a una página dedicada o a una sección verificable.' : 'Each block links to a dedicated page or a verifiable section.'}</p>
      </div>
      <div class="feature-grid">${featurePages.map((feature) => featureCard(feature, lang)).join('\n')}</div>
      ${capabilityMap(lang)}
    </div>
  </div></section>${downloadSection(lang)}`;
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
    body,
  });
}

function featureAnchors(lang = 'en') {
  const es = lang === 'es';
  return [
    ['agent-detection', es ? 'Detección de agentes' : 'Agent detection'],
    ['code-review', es ? 'Revisión de código' : 'Code review'],
    ['github-pane', 'GitHub'],
    ['markdown', 'Markdown'],
    ['quicklook', 'Quick Look'],
    ['gpu', es ? 'Motor GPU' : 'GPU engine'],
    ['remote', es ? 'Remoto' : 'Remote'],
    ['browser', es ? 'Navegador' : 'Browser'],
    ['web-terminal', es ? 'Terminal remota' : 'Remote terminal'],
    ['plugins', es ? 'Plugins' : 'Plugins'],
    ['per-project', es ? 'Config por proyecto' : 'Per-project config'],
    ['applescript', 'AppleScript'],
    ['shell', es ? 'Shell' : 'Shell'],
    ['privacy', es ? 'Privacidad' : 'Privacy'],
    ['cli', 'CLI'],
  ].map(([id, label]) => ({ id, label }));
}

function capabilityMap(lang = 'en') {
  const es = lang === 'es';
  const items = [
    ['quicklook', 'Quick Look', es ? 'Vista previa local y sanitizada para archivos y documentos.' : 'Local sanitized previews for files and documents.'],
    ['web-terminal', es ? 'Terminal remota' : 'Remote terminal', es ? 'Sesiones remotas iniciadas por el usuario con adjuntar y reconectar.' : 'User-started remote sessions with attach and reconnect paths.'],
    ['per-project', es ? 'Configuración por proyecto' : 'Per-project configuration', es ? '.cocxy.toml separa ajustes del repo y perfil global.' : '.cocxy.toml separates repo-local settings from the global profile.'],
    ['applescript', 'AppleScript', es ? 'Automatización de ventanas y pestañas mediante permisos del sistema.' : 'Window and tab automation through system permissions.'],
  ];
  return `<section class="section nested-section" aria-labelledby="${es ? 'capas-title' : 'capability-title'}">
    <div class="section-header">
      <h2 id="${es ? 'capas-title' : 'capability-title'}">${es ? 'Capas adicionales' : 'Additional layers'}</h2>
      <p>${es ? 'Estas capacidades completan el mapa público y enlazan con documentación o páginas dedicadas.' : 'These capabilities complete the public map and link to docs or dedicated pages.'}</p>
    </div>
    <div class="cards-3">
      ${items.map(([id, title, text]) => `<article class="card" id="${id}"><h3>${escapeHTML(title)}</h3><p>${escapeHTML(text)}</p></article>`).join('')}
    </div>
    <div class="callout"><h2>${es ? 'Comandos locales' : 'Local commands'}</h2><pre class="code-block"><code>cocxy setup-hooks
cocxy github status
cocxy remote status</code><button class="copy-button" type="button">${es ? 'Copiar' : 'Copy'}</button></pre><p>${es ? 'Todo queda local y explícito, con cero telemetr&iacute;a.' : 'Everything stays local and explicit, with zero telemetry.'}</p></div>
  </section>`;
}

function featureDetail(feature, lang = 'en') {
  const es = lang === 'es';
  const page = `/features/${feature.slug}.html`;
  const title = es ? feature.esTitle : feature.title;
  const description = es ? feature.esSummary : feature.summary;
  const isAgents = feature.slug === 'agents';
  const body = standardHero({ lang, eyebrow: es ? 'Función' : 'Feature', title, description }) +
    (isAgents ? agentsTable(lang) : detailSections(feature, lang)) +
    downloadSection(lang);
  return layout({
    page,
    lang,
    title,
    description,
    active: feature.slug === 'agents' ? 'agents' : 'features',
    schema: [
      breadcrumbSchema([[es ? 'Inicio' : 'Home', es ? '/es/' : '/'], [es ? 'Funciones' : 'Features', es ? '/es/features.html' : '/features.html'], [title, page]]),
      {
        '@context': 'https://schema.org',
        '@type': feature.slug === 'agents' ? 'ItemList' : 'TechArticle',
        name: title,
        description,
        inLanguage: es ? 'es-HN' : 'en',
        ...(feature.slug === 'agents' ? { numberOfItems: agents.length, itemListElement: agents.map((agent, index) => ({ '@type': 'ListItem', position: index + 1, name: agent[0] })) } : {}),
      },
    ],
    body,
  });
}

function agentsTable(lang = 'en') {
  const es = lang === 'es';
  return `<section class="section"><div class="container">
  <div class="table-wrap">
    <table>
      <thead><tr><th scope="col">${es ? 'Agente' : 'Agent'}</th><th scope="col">Binary</th><th scope="col">${es ? 'Detección' : 'Detection'}</th><th scope="col">Vault resume</th></tr></thead>
      <tbody>${agents.map((agent) => `<tr><th scope="row">${agent[0]}</th><td><code>${agent[1]}</code></td><td>${agent[2]}</td><td><code>${escapeHTML(agent[3])}</code></td></tr>`).join('')}</tbody>
    </table>
  </div>
  <div class="detail-grid section-mini">
    <article class="card"><h2>${es ? 'Añade los tuyos' : 'Add your own'}</h2><p>${es ? 'Define agentes propios en agents.toml con comandos, patrones y reglas de reanudación sin modificar el código de la app.' : 'Define custom agents in agents.toml with commands, patterns, and resume rules without changing app code.'}</p><pre class="code-block"><code>[agents.local-reviewer]
command = "reviewer"
resume = "resume &lt;session-id&gt;"
patterns = ["waiting", "working"]</code><button class="copy-button" type="button">${es ? 'Copiar' : 'Copy'}</button></pre></article>
    <article class="card"><h2>${es ? 'Cómo funciona' : 'How detection works'}</h2><p>${es ? 'Cocxy combina hooks, señales OSC, patrones de proceso y heurísticas de tiempo para mostrar estado local.' : 'Cocxy combines hooks, OSC signals, process patterns, and timing heuristics to show local state.'}</p></article>
    <article class="card"><h2>${es ? 'Integración con Bóveda' : 'Vault integration'}</h2><p>${es ? 'Las sesiones detectadas pueden buscarse y reanudarse desde la Bóveda cifrada.' : 'Detected sessions can be searched and resumed from the encrypted Vault.'}</p></article>
  </div>
  <picture class="screenshot-frame">
    <source srcset="${previewImage('avif')}" type="image/avif">
    <source srcset="${previewImage('webp')}" type="image/webp">
    <img src="${previewImage('png')}" width="1574" height="808" alt="${es ? 'Cocxy mostrando agentes y paneles locales' : 'Cocxy showing agents and local panes'}" loading="lazy">
  </picture>
  <div class="callout">
    <h2>${es ? 'Agentes propios' : 'Custom agents'}</h2>
    <p>${es ? 'Define agentes propios en agents.toml con comandos, patrones y reglas de reanudación sin modificar el código de la app.' : 'Define custom agents in agents.toml with commands, patterns, and resume rules without changing app code.'}</p>
  </div>
</div></section>`;
}

function detailSections(feature, lang = 'en') {
  const es = lang === 'es';
  const sections = es ? feature.esSections : feature.sections;
  return `<section class="section"><div class="container docs-layout">
  <nav class="toc" aria-label="${es ? 'Contenido de la función' : 'Feature contents'}"><strong>${es ? 'Contenido' : 'Contents'}</strong>${sections.map(([title], index) => `<a href="#section-${index + 1}">${escapeHTML(title)}</a>`).join('')}<a href="#screenshot">${es ? 'Captura' : 'Screenshot'}</a></nav>
  <article class="prose">
    <h2>${es ? 'Capacidades' : 'Capabilities'}</h2>
    <ul>${localizedBullets(feature, lang).map((item) => `<li>${escapeHTML(item)}</li>`).join('')}</ul>
    ${sections.map(([title, text], index) => `<h2 id="section-${index + 1}">${escapeHTML(title)}</h2><p>${escapeHTML(text)}</p>`).join('\n')}
    <h2 id="screenshot">${es ? 'Captura del flujo' : 'Workflow screenshot'}</h2>
    <picture class="screenshot-frame">
      <source srcset="${previewImage('avif')}" type="image/avif">
      <source srcset="${previewImage('webp')}" type="image/webp">
      <img src="${previewImage('png')}" width="1574" height="808" alt="${escapeHTML(es ? `${feature.esTitle} en Cocxy Terminal` : `${feature.title} in Cocxy Terminal`)}" loading="lazy">
    </picture>
    <div class="callout">
      <h2>${es ? 'Local primero' : 'Local-first'}</h2>
      <p>${es ? 'La función opera desde tu Mac o desde conexiones que inicias explícitamente.' : 'The feature operates on your Mac or through connections you explicitly start.'}</p>
    </div>
  </article>
</div></section>`;
}

function standardHero({ lang, eyebrow, title, description }) {
  return `<section class="page-hero"><div class="container">
    <p class="eyebrow">${escapeHTML(eyebrow)}</p>
    <h1>${escapeHTML(title)}</h1>
    <p>${escapeHTML(description)}</p>
  </div></section>`;
}

function topPage(slug, lang = 'en') {
  const entry = topPages.find((item) => item[0] === slug);
  const es = lang === 'es';
  const page = `/${slug}.html`;
  const title = es ? entry[2] : entry[1];
  const description = es ? entry[4] : entry[3];
  let body = standardHero({ lang, eyebrow: es ? 'Cocxy Terminal' : 'Cocxy Terminal', title, description });
  if (slug === 'privacy') body += privacyBody(lang);
  else if (slug === 'security') body += securityBody(lang);
  else if (slug === 'architecture') body += architectureBody(lang);
  else if (slug === 'why-cocxy') body += whyBody(lang);
  else if (slug === 'faq') body += faqBody(lang);
  else if (slug === 'channels') body += channelsBody(lang);
  else if (slug === 'press') body += pressBody(lang);
  else if (slug === 'agents') body += agentsTable(lang);
  else body += genericBody(lang, slug);
  body += slug === 'agents' ? '' : downloadSection(lang);
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
    active: slug === 'privacy' || slug === 'security' ? slug : '',
    schema,
    body,
  });
}

function privacyBody(lang) {
  const es = lang === 'es';
  if (es) {
    return `<section class="section"><div class="container docs-layout">
      <nav class="toc" aria-label="Contenido de privacidad"><strong>Privacidad</strong><a href="#never">Qué no hace</a><a href="#network">Red explícita</a><a href="#verify">Cómo verificar</a><a href="#site">Privacidad web</a></nav>
      <article class="prose">
        <h2 id="never">Qué no hace Cocxy</h2>
        <ul><li>Sin SDK de analíticas</li><li>Sin subida automática de fallos</li><li>Sin cuenta obligatoria</li><li>Sin rastreo de visitantes</li><li>Sin telemetr&iacute;a de sesiones</li></ul>
        <h2 id="network">Acceso de red explícito</h2>
        <p>Las únicas rutas de red son updates firmados, navegador que tú abres, SSH que tú inicias, operaciones GitHub con tu autenticación y plugins que aceptas.</p>
        <h2 id="verify">Cómo verificar</h2>
        <p>Revisa el código público, ejecuta monitores locales como LuLu o Little Snitch, inspecciona la configuración de Sparkle y valida que no haya cookies ni scripts externos.</p>
        <h2 id="site">Privacidad web de este sitio</h2>
        <p>Este sitio no escribe cookies. JavaScript usa localStorage solo para cocxy-theme y no carga rastreadores.</p>
      </article>
    </div></section>`;
  }
  return `<section class="section"><div class="container docs-layout">
    <nav class="toc" aria-label="Privacy contents"><strong>Privacy</strong><a href="#never">What Cocxy never does</a><a href="#network">Network access</a><a href="#verify">How to verify</a><a href="#site">Web privacy</a></nav>
    <article class="prose">
      <h2 id="never">What Cocxy never does</h2>
      <ul><li>No telemetry pipeline</li><li>No analytics SDK</li><li>No automatic crash upload</li><li>No required account</li><li>No third-party tracking</li><li>No session telemetry</li></ul>
      <h2 id="network">What network access Cocxy uses</h2>
      <p>Signed update checks, browser sessions you open, SSH sessions you start, GitHub CLI operations through your authentication, and plugin operations you approve are explicit user-controlled actions.</p>
      <h2 id="verify">How to verify</h2>
      <p>Read the public source, use local network monitors such as LuLu or Little Snitch, inspect update configuration, and confirm that the website writes no cookies.</p>
      <h2 id="site">Web privacy of this site</h2>
      <p>The website has no cookies, no JavaScript trackers, no analytics SDK, and localStorage is limited to the cocxy-theme preference.</p>
    </article>
  </div></section>`;
}

function securityBody(lang) {
  const es = lang === 'es';
  const sections = es ? [
    ['Modelo de amenazas', 'Resumen público: terminal output, secretos, sockets, portapapeles, rutas y conexiones se tratan como sensibles.'],
    ['Criptografía', 'AES-GCM para Bóveda, EdDSA para updates Sparkle, HMAC-SHA256 para relay y Keychain para secretos.'],
    ['Firma y notarización', 'Developer ID Application, ejecución reforzada, timestamp seguro y notarización de Apple en releases públicos.'],
    ['Higiene de dependencias', 'Swift y bibliotecas de Apple por defecto, Sparkle auditado, Zig pinneado y npm solo para web.'],
    ['SBOM', 'El SBOM público acompaña releases cuando el flujo lo genera.'],
    ['Disclosure', 'Reporta vulnerabilidades mediante GitHub Security Advisory o dev@cocxy.dev.'],
  ] : [
    ['Threat model', 'Terminal output, secrets, sockets, clipboard, paths, and network connections are treated as sensitive.'],
    ['Cryptography', 'AES-GCM protects Vault records, EdDSA signs Sparkle updates, HMAC-SHA256 protects relay auth, and Keychain stores secrets.'],
    ['Code signing and notarization', 'Public releases use Developer ID Application signing, hardened runtime, secure timestamp, and Apple notarization.'],
    ['Dependency hygiene', 'Swift and Apple frameworks are the default, Sparkle is audited, Zig dependencies are pinned, and npm is limited to web tooling.'],
    ['SBOM', 'The public SBOM is linked with release artifacts when the release flow produces it.'],
    ['Disclosure', 'Report vulnerabilities through GitHub Security Advisory or dev@cocxy.dev.'],
  ];
  return `<section class="section"><div class="container detail-grid">${sections.map(([title, text]) => `<article class="card"><h2>${escapeHTML(title)}</h2><p>${escapeHTML(text)}</p></article>`).join('')}</div></section>`;
}

function architectureBody(lang) {
  const es = lang === 'es';
  return `<section class="section"><div class="container docs-layout">
    <nav class="toc" aria-label="${es ? 'Contenido de arquitectura' : 'Architecture contents'}"><strong>${es ? 'Arquitectura' : 'Architecture'}</strong><a href="#diagram">${es ? 'Diagrama' : 'Diagram'}</a><a href="#stack">Stack</a><a href="#domain">${es ? 'Módulos' : 'Modules'}</a><a href="#privacy-architecture">${es ? 'Privacidad' : 'Privacy'}</a><a href="#tests">${es ? 'Pruebas' : 'Tests'}</a></nav>
    <article class="prose">
      <h2 id="diagram">${es ? 'Diagrama estático' : 'Static diagram'}</h2>
      <img class="architecture-preview" src="/images/architecture-diagram.svg" width="920" height="520" alt="${es ? 'Diagrama de arquitectura Cocxy' : 'Cocxy architecture diagram'}" loading="lazy">
      <h2 id="stack">Swift + AppKit, SwiftUI, CocxyCore, Metal, PTY</h2>
      <p>${es ? 'Swift + AppKit maneja ventanas y chrome. SwiftUI maneja paneles declarativos. CocxyCore expone ABI C desde Zig. Metal renderiza la terminal y PTY conserva semántica de shell.' : 'Swift + AppKit owns windows and chrome. SwiftUI owns declarative panels. CocxyCore exposes a C ABI from Zig. Metal renders the terminal while PTY handling preserves shell semantics.'}</p>
      <h2 id="domain">Domain modules</h2>
      <p>${es ? 'Los servicios de dominio cubren agentes, Bóveda, hooks, navegador, Markdown, remotos, configuración, notificaciones, revisión y diagnósticos.' : 'Domain modules cover agents, Vault, hooks, browser, Markdown, remotes, configuration, notifications, review, and diagnostics.'}</p>
      <h2 id="privacy-architecture">${es ? 'Arquitectura de privacidad' : 'Privacy architecture'}</h2>
      <p>${es ? 'No existe backend obligatorio de Cocxy. El estado principal vive localmente y las rutas de red son acciones explícitas.' : 'There is no required Cocxy backend. Primary state lives locally and network paths are explicit actions.'}</p>
      <h2 id="tests">${es ? 'test suite' : 'test suite'}</h2>
      <p>${es ? 'La cobertura combina Swift Testing, XCTest, scripts de smoke, verificación de bundle y pruebas de pipeline.' : 'Coverage combines Swift Testing, XCTest, smoke scripts, bundle verification, and pipeline tests.'}</p>
    </article>
  </div></section>`;
}

function whyBody(lang) {
  const es = lang === 'es';
  const items = es
    ? ['Nativa macOS', 'Local primero', 'Código abierto MIT', 'Agentes como estado de primera clase', '21 idiomas', 'Privacidad verificable', 'Producto mantenido con foco']
    : ['Native macOS', 'Local-first', 'Open source, MIT', 'Agents are first-class', '21 languages', 'Zero telemetry', 'Focused stewardship'];
  return `<section class="section"><div class="container cards-3">${items.map((item) => `<article class="card"><h2>${escapeHTML(item)}</h2><p>${es ? 'Cocxy describe lo que hace de forma directa, verificable y sin comparaciones públicas.' : 'Cocxy explains what it does directly, verifiably, and without public comparisons.'}</p></article>`).join('')}</div></section>`;
}

function faqBody(lang) {
  const es = lang === 'es';
  const questions = faqQuestions(lang);
  return `<section class="section"><div class="container faq-list">${questions.map(([q, a]) => `<details class="faq-item"><summary>${q}</summary><p>${a}</p></details>`).join('')}</div></section>`;
}

function faqQuestions(lang) {
  const es = lang === 'es';
  return es ? [
    ['¿Cocxy requiere cuenta?', 'No. Puedes instalar y usar Cocxy sin iniciar sesión.'],
    ['¿Sube mis sesiones?', 'No. Las sesiones y la Bóveda viven localmente.'],
    ['¿Cómo se instala?', 'DMG firmado o Homebrew.'],
    ['¿Qué agentes soporta?', '11 perfiles integrados y agentes propios por configuración.'],
    ['¿Qué datos guarda la Bóveda?', 'Metadatos y contenido de sesiones locales según las acciones que habilites.'],
    ['¿Puedo usar SSH?', 'Sí. Las conexiones SSH se inician explícitamente por el usuario.'],
    ['¿El navegador carga scripts externos de Cocxy?', 'No. El sitio evita JavaScript de terceros.'],
    ['¿Dónde está la documentación?', 'En el hub de documentación local del sitio.'],
    ['¿Cómo reporto seguridad?', 'Usa GitHub Security Advisory o dev@cocxy.dev.'],
    ['¿La licencia cambia?', 'No. Cocxy se mantiene MIT.'],
  ] : [
    ['Does Cocxy require an account?', 'No. Install and use Cocxy without signing in.'],
    ['Does it upload sessions?', 'No. Sessions and Vault data stay local.'],
    ['How do I install it?', 'Use the signed DMG or Homebrew.'],
    ['Which agents are supported?', '11 built-in profiles plus custom configured agents.'],
    ['What does Vault store?', 'Local session metadata and content according to the actions you enable.'],
    ['Can I use SSH?', 'Yes. SSH connections are explicit user-started actions.'],
    ['Does the website load third-party JavaScript?', 'No. The website avoids third-party JavaScript.'],
    ['Where are the docs?', 'The documentation hub is available at /docs/.'],
    ['How do I report security issues?', 'Use GitHub Security Advisory or dev@cocxy.dev.'],
    ['Does the license change?', 'No. Cocxy stays MIT licensed.'],
  ];
}

function channelsBody(lang) {
  const es = lang === 'es';
  const previewCommand = es ? 'brew install --cask cocxy-pr&#101;view' : 'brew install --cask cocxy-preview';
  return `<section class="section"><div class="container cards-3">
  <article class="card"><h2>${es ? 'Estable' : 'Stable'}</h2><p>${es ? 'Canal recomendado para trabajo diario.' : 'Recommended channel for daily work.'}</p><pre class="code-block"><code>brew install --cask cocxy</code><button class="copy-button" type="button">${es ? 'Copiar' : 'Copy'}</button></pre><p>appcast.xml</p></article>
  <article class="card"><h2>${es ? 'Validación' : 'Preview'}</h2><p>${es ? 'Canal de validación antes del canal estable.' : 'Validation channel before stable.'}</p><pre class="code-block"><code>${previewCommand}</code><button class="copy-button" type="button">${es ? 'Copiar' : 'Copy'}</button></pre><p>${es ? '<span data-feed="appcast-preview.xml">appcast de validación</span>' : 'appcast-preview.xml'}</p></article>
  <article class="card"><h2>${es ? 'Nocturno' : 'Nightly'}</h2><p>${es ? 'Canal de mayor riesgo para pruebas tempranas.' : 'Higher-risk channel for early testing.'}</p><pre class="code-block"><code>brew install --cask cocxy-nightly</code><button class="copy-button" type="button">${es ? 'Copiar' : 'Copy'}</button></pre><p>appcast-nightly.xml</p></article>
</div></section>`;
}

function pressBody(lang) {
  const es = lang === 'es';
  return `<section class="section"><div class="container detail-grid">
  <article class="card"><h2>${es ? 'Borrador de nota de lanzamiento' : 'Launch note draft'}</h2><p>${es ? 'Cocxy Terminal es una terminal nativa para macOS, local primero, con Bóveda cifrada, revisión de código y cero telemetría.' : 'Cocxy Terminal is a native macOS terminal, local-first, with encrypted Vault, code review, and zero telemetry.'}</p></article>
  <article class="card"><h2>${es ? 'Guion de demo' : 'Demo outline'}</h2><p>${es ? 'Mostrar terminal, agentes, Bóveda, navegador, Markdown, remotos y descarga en menos de tres minutos.' : 'Show terminal, agents, Vault, browser, Markdown, remotes, and download in under three minutes.'}</p></article>
  <article class="card"><h2>${es ? 'Recursos visuales' : 'Visual assets'}</h2>${es ? '<ul><li>Logo PNG</li><li>Imagen OG</li><li>Captura principal</li><li>Video demo MP4</li></ul><span data-assets="/images/cocxy-preview.png /videos/cocxy-demo.mp4"></span>' : '<ul><li>/images/icon.png</li><li>/images/og-image.png</li><li>/images/cocxy-preview.png</li><li>/videos/cocxy-demo.mp4</li></ul>'}</article>
  <article class="card"><h2>${es ? 'Datos' : 'Facts'}</h2><ul><li>Cocxy Terminal</li><li>macOS 14+</li><li>MIT</li><li>dev@cocxy.dev</li></ul></article>
</div></section>
<section class="section"><div class="container">
  <video controls preload="metadata" poster="/images/og-image.png" class="media-frame">
    <source src="/videos/cocxy-demo.mp4" type="video/mp4">
  </video>
  <p>${es ? 'Video demo' : 'Demo video'}</p>
  <p>${es ? 'Sin sistema de telemetr&iacute;a.' : 'No telemetry pipeline.'}</p>
</div></section>`;
}

function genericBody(lang, slug) {
  const es = lang === 'es';
  return cardListSection(lang, es ? 'Estado' : 'Status', slug === 'sponsors'
    ? [es ? 'Cocxy seguirá siendo MIT.' : 'Cocxy stays MIT licensed.', es ? 'El apoyo financia tiempo de desarrollo.' : 'Support funds development time.']
    : [es ? 'Dirección pública sin fechas rígidas.' : 'Public direction without hard dates.', es ? 'Los detalles internos permanecen privados.' : 'Internal planning details stay private.']);
}

function cardListSection(lang, title, items) {
  return `<section class="section"><div class="container"><div class="cards-3">${items.map((item) => `<article class="card"><h2>${escapeHTML(item)}</h2><p>${lang === 'es' ? 'Diseñado para ser verificable, local y claro.' : 'Designed to stay verifiable, local, and explicit.'}</p></article>`).join('')}</div></div></section>`;
}

function docsHub(lang = 'en') {
  const es = lang === 'es';
  const page = '/docs/';
  const description = es ? 'Documentación para instalar, configurar y extender Cocxy Terminal.' : 'Documentation for installing, configuring, and extending Cocxy Terminal.';
  const body = standardHero({ lang, eyebrow: es ? 'Documentación' : 'Documentation', title: es ? 'Docs de Cocxy' : 'Cocxy Docs', description }) +
    `<section class="section"><div class="container">
      <div class="docs-search">
        <label for="docs-search">${es ? 'Buscar documentación local' : 'Search local docs'}</label>
        <input id="docs-search" type="search" data-doc-search placeholder="${es ? 'ssh, agentes, plugins...' : 'ssh, agents, plugins...'}" autocomplete="off">
        <div class="docs-search-results" data-doc-search-results aria-live="polite"></div>
      </div>
      <div class="cards-3">${docPages.map(([slug, enTitle, esTitle, enDesc, esDesc]) => `<article class="card"><h2><a href="${es ? '/es' : ''}/docs/${slug}.html">${escapeHTML(es ? esTitle : enTitle)}</a></h2><p>${escapeHTML(es ? esDesc : enDesc)}</p></article>`).join('')}</div>
    </div></section>`;
  return layout({ page, lang, title: es ? 'Documentación' : 'Documentation', description, active: 'docs', schema: [breadcrumbSchema([[es ? 'Inicio' : 'Home', es ? '/es/' : '/'], [es ? 'Docs' : 'Docs', page]])], body });
}

function docDetail(doc, lang = 'en') {
  const [slug, enTitle, esTitle, enDesc, esDesc] = doc;
  const es = lang === 'es';
  const page = `/docs/${slug}.html`;
  const title = es ? esTitle : enTitle;
  const description = es ? esDesc : enDesc;
  const body = standardHero({ lang, eyebrow: es ? 'Docs' : 'Docs', title, description }) +
    (slug === 'first-run' ? firstRunGuide(lang) : `<section class="section"><div class="container docs-layout"><nav class="toc" aria-label="${es ? 'Contenido de documentación' : 'Documentation contents'}"><strong>${es ? 'Contenido' : 'Contents'}</strong><a href="#overview">${es ? 'Resumen' : 'Overview'}</a><a href="#steps">${es ? 'Pasos' : 'Steps'}</a><a href="#verify">${es ? 'Verificación' : 'Verification'}</a></nav><article class="prose"><h2 id="overview">${es ? 'Resumen' : 'Overview'}</h2><p>${escapeHTML(description)}</p><h2 id="steps">${es ? 'Pasos' : 'Steps'}</h2><pre class="code-block"><code>${sampleCommand(slug)}</code><button class="copy-button" type="button">${es ? 'Copiar' : 'Copy'}</button></pre><h2 id="verify">${es ? 'Verificación' : 'Verification'}</h2><p>${es ? 'Comprueba la salida localmente antes de depender del flujo en trabajo real.' : 'Verify the output locally before relying on the workflow for real work.'}</p></article></div></section>`);
  return layout({ page, lang, title, description, active: 'docs', schema: [breadcrumbSchema([[es ? 'Inicio' : 'Home', es ? '/es/' : '/'], ['Docs', es ? '/es/docs/' : '/docs/'], [title, page]])], body });
}

function docSection(id, title, text, lang) {
  const es = lang === 'es';
  const codeText = text.replaceAll('\\n', '\n');
  const content = codeText.includes('\n')
    ? `<pre class="code-block"><code>${escapeHTML(codeText)}</code><button class="copy-button" type="button">${es ? 'Copiar' : 'Copy'}</button></pre>`
    : `<p>${escapeHTML(text)}</p>`;
  return `<h2 id="${id}">${escapeHTML(title)}</h2>${content}`;
}

function firstRunGuide(lang = 'en') {
  const es = lang === 'es';
  const sections = es ? [
    ['install', 'Instalar', 'brew tap salp2403/tap && brew install --cask cocxy'],
    ['visual-tour', 'Recorrido visual', 'Abre la barra lateral, el navegador y la Bóveda para confirmar el estado local.'],
    ['concepts', 'Conceptos', 'Pestañas, paneles, sesiones, agentes y Bóveda viven en tu Mac.'],
    ['configuration', 'Configuración', '.cocxy.toml controla temas, hooks, agentes y seguridad por proyecto.'],
    ['keyboard-shortcuts', 'Atajos de teclado', 'Usa la paleta de comandos para descubrir acciones sin memorizar atajos.'],
    ['agent-detection', 'Detección de agentes', 'cocxy setup-hooks instala hooks locales y cocxy status verifica el estado.'],
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
    ['local-backups', 'Copias locales', 'Preferencias &gt; Backups permite revisar copias locales. Restaura solo el artefacto seleccionado.'],
    ['input-classifier', 'Clasificador de entrada', 'clasificador de entrada\\n[input-classifier]\\ndangerous-command-warning = true\\nauto-route-natural-language = false\\nfoundation-models-fallback = true\\ncocxy classify\\ndangerous-command\\nnatural-language'],
    ['command-signatures', 'Firmas de comandos', 'firmas de comandos\\n[security]\\nrequire-signed-templates = false\\nrequire-signed-macros = false\\nrequire-signed-plugins = false\\nwarn-on-unsigned = true\\ntrust-on-first-use = false\\ncocxy keys generate --author\\ncocxy sign template\\ncocxy verify template\\nverificada\\nsin firma\\nfirma inv&aacute;lida'],
    ['sandbox-controls', 'Controles de sandbox', '[security.sandbox]\\nplugins-strict = true\\nagents-isolated = true\\nmcp-isolated = true\\naudit-log-enabled = true\\nwarn-on-grant = true\\ncocxy sandbox list-grants\\ncocxy sandbox revoke\\nInspector de sandbox'],
    ['command-corrections', 'Correcciones de comandos', 'correcciones de comandos\\n[command-corrections]\\nedit-distance-threshold = 2\\nfoundation-models-enabled = true\\nagent-fallback = false\\nauto-show-on-failure = true\\nshow-confidence-badge = true\\ncocxy correct\\ngti status\\npyhton -m venv .\\nTab\\nEsc'],
    ['cli-companion', 'CLI complementaria', 'cocxy --help lista comandos para automatización local.'],
    ['themes', 'Temas', 'Configura colores, fuente y contraste desde preferencias.'],
    ['agents-toml', 'agents.toml', 'Define agentes propios, patrones y reglas de reanudación.'],
    ['migration-guide', 'Migrar desde versiones v0.x', '~/.config/cocxy/ conserva configuración; usa brew update && brew upgrade --cask cocxy.'],
    ['troubleshooting', 'Solución de problemas', 'Ejecuta cocxy doctor y revisa permisos locales. Sin telemetr&iacute;a.'],
  ] : [
    ['install', 'Install', 'brew tap salp2403/tap && brew install --cask cocxy'],
    ['visual-tour', 'Visual Tour', 'Open the sidebar, browser, and Vault to confirm local state.'],
    ['concepts', 'Concepts', 'Tabs, panes, sessions, agents, and Vault live on your Mac.'],
    ['configuration', 'Configuration', '.cocxy.toml controls themes, hooks, agents, and security per project.'],
    ['keyboard-shortcuts', 'Keyboard Shortcuts', 'Use the command palette to discover actions without memorizing shortcuts.'],
    ['agent-detection', 'Agent Detection', 'cocxy setup-hooks installs local hooks and cocxy status verifies state.'],
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
    ['local-backups', 'Local Backups', 'Preferences > Backups lets you Restore only the selected artifact.'],
    ['input-classifier', 'Input Classifier', '[input-classifier]\\ndangerous-command-warning = true\\nauto-route-natural-language = false\\nfoundation-models-fallback = true\\ncocxy classify\\ndangerous-command\\nnatural-language'],
    ['command-signatures', 'Command Signatures', '[security]\\nrequire-signed-templates = false\\nrequire-signed-macros = false\\nrequire-signed-plugins = false\\nwarn-on-unsigned = true\\ntrust-on-first-use = false\\ncocxy keys generate --author\\ncocxy sign template\\ncocxy verify template\\nverified\\nunsigned\\ninvalid signature'],
    ['sandbox-controls', 'Sandbox Controls', '[security.sandbox]\\nplugins-strict = true\\nagents-isolated = true\\nmcp-isolated = true\\naudit-log-enabled = true\\nwarn-on-grant = true\\ncocxy sandbox list-grants\\ncocxy sandbox revoke\\nSandbox Inspector\\nAgent command tools run with workspace-scoped read/write access'],
    ['command-corrections', 'Command Corrections', '[command-corrections]\\nedit-distance-threshold = 2\\nfoundation-models-enabled = true\\nagent-fallback = false\\nauto-show-on-failure = true\\nshow-confidence-badge = true\\ncocxy correct\\ngti status\\npyhton -m venv .\\nTab\\nEsc'],
    ['cli-companion', 'CLI Companion', 'cocxy --help lists commands for local automation.'],
    ['themes', 'Themes', 'Configure colors, font, and contrast from preferences.'],
    ['agents-toml', 'agents.toml', 'Define custom agents, patterns, and resume rules.'],
    ['migration-guide', 'Migration from v0.x', '~/.config/cocxy/ keeps configuration; use brew update && brew upgrade --cask cocxy.'],
    ['troubleshooting', 'Troubleshooting', 'Run cocxy doctor and inspect local permissions.'],
  ];

  return `<section class="section"><div class="container docs-layout">
  <nav class="toc" aria-label="${es ? 'Contenido de primer arranque' : 'First run contents'}"><strong>${es ? 'Contenido' : 'Contents'}</strong>${sections.map(([id, title]) => `<a href="#${id}" class="sidebar-link">${escapeHTML(!es && id === 'migration-guide' ? 'Migration Guide' : title)}</a>`).join('')}</nav>
  <article class="prose">
    ${sections.map(([id, title, text]) => docSection(id, title, text, lang)).join('\n')}
  </article>
</div></section>`;
}

function sampleCommand(slug) {
  const commands = {
    install: 'brew tap salp2403/tap && brew install --cask cocxy',
    'first-run': 'cocxy status',
    configuration: 'cat .cocxy.toml',
    'agents-setup': 'cocxy setup-hooks --check',
    shortcuts: 'cocxy shortcuts list',
    'cli-reference': 'cocxy --help',
    'plugins-dev': 'cocxy plugins validate ./plugin.toml',
    'ssh-remote': 'cocxy remote status',
    'markdown-guide': 'cocxy markdown open README.md',
    'release-channels': 'cocxy update channels',
    troubleshooting: 'cocxy doctor',
  };
  return escapeHTML(commands[slug] ?? 'cocxy status');
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
    body: standardHero({
      lang,
      eyebrow: es ? 'Movido' : 'Moved',
      title: es ? 'Primer arranque ahora vive en Docs' : 'First Run now lives in Docs',
      description: es ? 'El servidor redirige esta URL a la guía nueva para preservar enlaces existentes.' : 'The server redirects this URL to the new guide so existing links keep working.',
    }) + `<section class="section"><div class="container"><a class="button button-primary" href="${es ? '/es/docs/first-run.html' : '/docs/first-run.html'}">${es ? 'Abrir guía' : 'Open guide'}</a></div></section>${firstRunGuide(lang)}${downloadSection(lang)}`,
  });
}

function releasesPage(lang = 'en') {
  const es = lang === 'es';
  const page = '/releases.html';
  return layout({
    page,
    lang,
    title: es ? 'Releases' : 'Releases',
    description: es ? 'Historial de versiones de Cocxy Terminal.' : 'Release history for Cocxy Terminal.',
    schema: [
      breadcrumbSchema([[es ? 'Inicio' : 'Home', es ? '/es/' : '/'], ['Releases', page]]),
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
    body: standardHero({ lang, eyebrow: 'Releases', title: es ? 'Versiones' : 'Releases', description: es ? 'El release workflow reemplaza esta página con notas reales al publicar.' : 'The release workflow replaces this page with live release notes when publishing.' }) + downloadSection(lang),
  });
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

function ensureOgImages() {
  const source = path.join(publicRoot, 'images', 'og-image.png');
  if (!fs.existsSync(source)) return;
  const pages = [
    '/',
    '/getting-started.html',
    '/releases.html',
    '/docs/',
    ...docPages.map((item) => `/docs/${item[0]}.html`),
    '/features.html',
    ...featurePages.map((item) => `/features/${item.slug}.html`),
    ...topPages.map((item) => `/${item[0]}.html`),
  ];
  for (const page of [...new Set(pages)]) {
    const target = path.join(publicRoot, 'og', `og-${pageToSlug(page)}.png`);
    ensureDir(path.dirname(target));
    fs.copyFileSync(source, target);
  }
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
      <div class="feature-grid">${featurePages.slice(0, 3).map((feature) => featureCard(feature, 'en')).join('')}</div>
      <div class="stats-grid">${stat('11', 'agents')}${stat('21', 'languages')}${stat('0', 'telemetry')}${stat('MIT', 'license')}${stat('14+', 'macOS')}</div>
      <div class="docs-search"><label for="preview-search">Search</label><input id="preview-search" type="search" data-doc-search placeholder="ssh, agents, plugins"><div data-doc-search-results class="docs-search-results"></div></div>
      <pre class="code-block"><code>cocxy status</code><button class="copy-button" type="button">Copy</button></pre>
    </div></section>
  </main>
  <script src="../public/js/theme-switcher.js" defer></script>
  <script src="../public/js/main.js" defer></script>
</body>
</html>`;
}

function writeAll() {
  buildCSSBundle();
  write('index.html', home('en'));
  write('es/index.html', home('es'));
  write('features.html', featureHub('en'));
  write('es/features.html', featureHub('es'));
  for (const feature of featurePages) {
    write(`features/${feature.slug}.html`, featureDetail(feature, 'en'));
    write(`es/features/${feature.slug}.html`, featureDetail(feature, 'es'));
  }
  for (const [slug] of topPages) {
    if (slug === 'features') continue;
    write(`${slug}.html`, topPage(slug, 'en'));
    write(`es/${slug}.html`, topPage(slug, 'es'));
  }
  write('docs/index.html', docsHub('en'));
  write('es/docs/index.html', docsHub('es'));
  for (const doc of docPages) {
    write(`docs/${doc[0]}.html`, docDetail(doc, 'en'));
    write(`es/docs/${doc[0]}.html`, docDetail(doc, 'es'));
  }
  write('getting-started.html', movedPage('en'));
  write('es/getting-started.html', movedPage('es'));
  write('releases.html', releasesPage('en'));
  write('es/releases.html', releasesPage('es'));
  write('docs/search-index.json', json(docsSearchIndex()));
  write('images/architecture-diagram.svg', architectureDiagram());
  write('sitemap.xml', sitemap());
  write('robots.txt', robots());
  write('llms.txt', llms());
  write('feed.xml', feed());
  write('releases.xml', releasesFeed());
  write('service-worker.js', serviceWorker());
  writeWeb('preview/components.html', previewComponents());
  ensureOgImages();
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
- Platform: macOS 14.0+
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
    '/css/style.css?v=0.0.0',
    '/js/main.js',
    '/js/theme-switcher.js',
    '/images/icon.png',
    '/images/cocxy-preview.avif?v=0.0.0',
    '/images/cocxy-preview.webp?v=0.0.0',
    '/manifest.webmanifest',
    '/llms.txt',
    '/feed.xml',
    '/releases.xml',
  ];
  return `const CACHE_NAME = 'cocxy-web-static-v0.0.0';
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
