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

// Interim artwork shown inside capture slots until real captures exist.
// Each function returns inner markup; productShot() supplies the frame.
const mockBar = '<div class="mock__bar"><i></i><i></i><i></i></div>';

function mockRows(states) {
  return states.map((state) => `<div class="mock-app__row ${state}"><i class="state-dot"></i><span></span></div>`).join('');
}

// variant: 'hero' (dense, home only), 'window', 'agents', or 'projects'.
export function appArtwork(variant = 'window') {
  const groups = variant === 'projects'
    ? `<span class="mock-app__group"></span>${mockRows(['is-working', 'is-done'])}<span class="mock-app__group"></span>${mockRows(['is-waiting', 'is-idle'])}<span class="mock-app__group"></span>${mockRows(['is-done'])}`
    : mockRows(variant === 'hero'
      ? ['is-working', 'is-waiting', 'is-done', 'is-idle', 'is-working', 'is-idle', 'is-done', 'is-idle', 'is-waiting', 'is-idle']
      : ['is-working', 'is-waiting', 'is-done', 'is-idle', 'is-working', 'is-idle']);
  const side = variant === 'agents' ? '' : `<div class="mock-app__side"><span class="mock-app__label"></span><span class="mock-app__search"></span>${groups}</div>`;
  const session = ['is-prompt', '', 'is-dim', '', '', 'is-dim', 'is-ok'];
  const termLines = [...session, ...session, ...(variant === 'hero' ? [...session, ...session] : []), 'is-prompt is-caret'];
  const term = `<div class="mock-app__term">${termLines.map((kind) => `<span${kind ? ` class="${kind}"` : ''}></span>`).join('')}</div>`;
  const panelStates = variant === 'hero'
    ? ['is-working', 'is-waiting', 'is-done', 'is-working', 'is-idle', 'is-done', 'is-waiting', 'is-idle']
    : ['is-working', 'is-waiting', 'is-done', 'is-idle'];
  const panelCards = panelStates.map((state) => `<div class="mock-app__card ${state}"><i class="state-dot"></i><span></span><span></span></div>`).join('');
  const panel = variant === 'projects' ? '' : `<div class="mock-app__panel"><span class="mock-app__label"></span>${panelCards}</div>`;
  return `${mockBar}<div class="mock-app mock-app--${variant}">${side}${term}${panel}</div>`;
}

export function reviewArtwork() {
  const code = ['', '', 'is-del', 'is-del', 'is-add', 'is-add', 'is-add', '', 'note', '', '', 'is-del', 'is-add', '', '', 'is-add', ''];
  return `${mockBar}<div class="mock-diff__body"><div class="mock-diff__files">${'<span></span>'.repeat(10)}</div><div class="mock-diff__code">${code
    .map((kind) => (kind === 'note'
      ? '<div class="mock-diff__note"><span></span><span></span></div>'
      : `<span${kind ? ` class="${kind}"` : ''}></span>`))
    .join('')}</div></div>`;
}

export function phoneArtwork() {
  return `<div class="mock-phone"><span class="mock-phone__title"></span><div class="mock-phone__row is-working"><i class="state-dot"></i><span></span></div><div class="mock-phone__row is-waiting"><i class="state-dot"></i><span></span></div><div class="mock-phone__term">${'<span></span>'.repeat(7)}</div><div class="mock-phone__approve"><span></span><span></span></div></div>`;
}
