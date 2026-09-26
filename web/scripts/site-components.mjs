// Copyright (c) 2026 Said Arturo Lopez. MIT License.

// Product names as users type them. Vendor names stay out of the site, and
// every name on this list must live inside the marked compatibility block.
const compatibleAgents = [
  'Claude Code',
  'Codex CLI',
  'Gemini CLI',
  'Aider',
  'OpenCode',
  'Kiro',
  'Cursor Agent',
  'Copilot CLI',
  'Qoder',
  'CodeBuddy',
  'Rovo Dev',
  'Pi',
];

export const themeIcons = {
  sun: '<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M4.6 4.6 6 6M18 18l1.4 1.4M2.5 12h2M19.5 12h2M4.6 19.4 6 18M18 6l1.4-1.4"/></svg>',
  moon: '<svg viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M20 14.6A8.2 8.2 0 0 1 9.4 4 8.2 8.2 0 1 0 20 14.6z"/></svg>',
};

export function compatibilityBlock(lang = 'en') {
  const es = lang === 'es';
  return `<!-- compatibility -->
<div class="compat" data-reveal="fade-up">
  <p class="compat__label">${es ? 'Compatible con' : 'Works with'}</p>
  <ul class="compat__list">${compatibleAgents.map((name) => `<li>${name}</li>`).join('')}</ul>
  <p class="compat__more"><a class="text-link" href="${es ? '/es' : ''}/features/agents.html">${es ? 'Y cualquier otra CLI que declares en agents.toml' : 'And any other CLI you describe in agents.toml'}</a></p>
</div>
<!-- /compatibility -->`;
}

export function installBlock({ lang = 'en', label, command, subject }) {
  const es = lang === 'es';
  const copyLabel = es ? `Copiar comando de ${subject}` : `Copy ${subject} command`;
  return `<div class="code-block install">
  <div class="install__bar"><span>${label}</span><button class="copy-button" type="button" aria-label="${copyLabel}">${es ? 'Copiar' : 'Copy'}</button></div>
  <pre><code>${command}</code></pre>
  <span class="sr-only" aria-live="polite" data-copy-status></span>
</div>`;
}

export function stateChips(lang = 'en') {
  const es = lang === 'es';
  const chips = [
    ['is-working', es ? 'Trabajando' : 'Working', es ? 'Editando archivos' : 'Editing files'],
    ['is-waiting', es ? 'Te espera' : 'Waiting for you', es ? 'Revisión lista' : 'Review ready'],
    ['is-done', es ? 'Listo' : 'Done', es ? 'Pruebas en verde' : 'Checks passed'],
  ];
  return `<ul class="state-chips">${chips
    .map(([state, title, detail]) => `<li class="state-chip glass ${state}"><span class="state-dot"></span><span><strong>${title}</strong> ${detail}</span></li>`)
    .join('')}</ul>`;
}

export function screenshot({ name, width, height, alt }) {
  return `<picture>
      <source srcset="/images/${name}.avif" type="image/avif">
      <source srcset="/images/${name}.webp" type="image/webp">
      <img src="/images/${name}.png" width="${width}" height="${height}" alt="${alt}" loading="lazy" decoding="async">
    </picture>`;
}

// Interim artwork for the review and phone captures. Swap each one for a
// real capture inside the same frame once it exists.
export function reviewArtwork(lang = 'en') {
  const es = lang === 'es';
  const code = ['', '', 'is-del', 'is-add', 'is-add', '', 'note', '', 'is-add', ''];
  return `<div class="window mock" role="img" aria-label="${es ? 'Ilustración del panel de revisión: árbol de archivos, diff y un comentario en una línea' : 'Illustration of the review panel: file tree, diff, and a comment on one line'}">
      <div class="mock__bar"><i></i><i></i><i></i></div>
      <div class="mock-diff__body">
        <div class="mock-diff__files">${'<span></span>'.repeat(6)}</div>
        <div class="mock-diff__code">${code
          .map((kind) => (kind === 'note'
            ? '<div class="mock-diff__note"><span></span><span></span></div>'
            : `<span${kind ? ` class="${kind}"` : ''}></span>`))
          .join('')}</div>
      </div>
    </div>`;
}

export function phoneArtwork(lang = 'en') {
  const es = lang === 'es';
  return `<div class="phone" role="img" aria-label="${es ? 'Ilustración del espejo móvil: sesiones, salida de terminal y una aprobación pendiente' : 'Illustration of the phone mirror: sessions, terminal output, and a pending approval'}">
      <div class="mock-phone">
        <span class="mock-phone__title"></span>
        <div class="mock-phone__row is-working"><i class="state-dot"></i><span></span></div>
        <div class="mock-phone__row is-waiting"><i class="state-dot"></i><span></span></div>
        <div class="mock-phone__term">${'<span></span>'.repeat(7)}</div>
        <div class="mock-phone__approve"><span></span><span></span></div>
      </div>
    </div>`;
}
