// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import { escapeHTML } from './site-core.mjs';

export const agents = [
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

export const featurePages = [
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

export const docPages = [
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

export const topPages = [
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

export function localizedBullets(feature, lang = 'en') {
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

export function featureAnchors(lang = 'en') {
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

export function faqQuestions(lang) {
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

export function sampleCommand(slug) {
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
