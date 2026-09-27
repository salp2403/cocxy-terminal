document.addEventListener('DOMContentLoaded', () => {
  initNavigation();
  initAnchorNavigation();
  initCopyButtons();
  initReleasePagination();
  initDocsSearch();
  initOfflineSupport();
  initScrollReveal();
});

function initNavigation() {
  const button = document.querySelector('.nav-toggle');
  const menu = document.getElementById('site-menu');
  if (!button || !menu) return;

  const close = ({ restoreFocus = false } = {}) => {
    if (!menu.classList.contains('is-open')) return;
    menu.classList.remove('is-open');
    button.setAttribute('aria-expanded', 'false');
    if (restoreFocus) button.focus();
  };

  button.addEventListener('click', () => {
    const isOpen = menu.classList.toggle('is-open');
    button.setAttribute('aria-expanded', String(isOpen));
  });

  menu.addEventListener('click', (event) => {
    if (event.target instanceof HTMLAnchorElement) close();
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') close({ restoreFocus: true });
  });

  document.addEventListener('click', (event) => {
    if (!menu.contains(event.target) && !button.contains(event.target)) close();
  });
}

function initAnchorNavigation() {
  const root = document.documentElement;
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

  const jumpTo = (hash, behavior, moveFocus) => {
    const id = decodeURIComponent(hash.slice(1));
    const target = id ? document.getElementById(id) : null;
    if (!target) return false;
    root.classList.add('is-anchoring');
    target.scrollIntoView({ behavior, block: 'start' });
    if (moveFocus) {
      if (!target.hasAttribute('tabindex')) target.setAttribute('tabindex', '-1');
      target.focus({ preventScroll: true });
    }
    return true;
  };

  if (location.hash) jumpTo(location.hash, 'instant', false);

  document.addEventListener('click', (event) => {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    const link = event.target instanceof Element ? event.target.closest('a[href*="#"]') : null;
    if (!link || !link.hash || link.origin !== location.origin || link.pathname !== location.pathname) return;
    if (jumpTo(link.hash, reducedMotion.matches ? 'instant' : 'smooth', true)) {
      event.preventDefault();
      if (location.hash !== link.hash) history.pushState(null, '', link.hash);
    }
  });
}

// The nearest heading above a code block names its Copy button, so a page
// with several blocks gives each button a distinct accessible name.
function headingAbove(block) {
  for (let node = block; node && node !== document.body; node = node.parentElement) {
    for (let sibling = node.previousElementSibling; sibling; sibling = sibling.previousElementSibling) {
      if (sibling.matches('h2, h3')) return sibling.textContent.trim();
    }
  }
  return '';
}

function initCopyButtons() {
  const spanish = document.documentElement.lang.startsWith('es');
  const labels = spanish
    ? { copy: 'Copiar', commands: 'Copiar comandos', config: 'Copiar configuración', copied: 'Copiado', manual: 'Selecciona', copiedStatus: 'Copiado al portapapeles', manualStatus: 'Texto seleccionado; cópialo con Cmd+C' }
    : { copy: 'Copy', commands: 'Copy commands', config: 'Copy configuration', copied: 'Copied', manual: 'Select', copiedStatus: 'Copied to the clipboard', manualStatus: 'Text selected; copy it with Cmd+C' };

  const blocks = document.querySelectorAll('.code-block');
  if (!blocks.length) return;
  const status = document.createElement('span');
  status.className = 'sr-only';
  status.setAttribute('aria-live', 'polite');
  document.body.append(status);

  blocks.forEach((block) => {
    const bar = block.querySelector('.install__bar');
    const code = block.querySelector('code');
    if (!bar || !code) return;
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'copy-button';
    button.textContent = labels.copy;
    const action = block.classList.contains('install--config') ? labels.config : labels.commands;
    const heading = headingAbove(block);
    button.setAttribute('aria-label', heading ? `${action}: ${heading}` : action);
    bar.append(button);
    const original = labels.copy;
    let resetTimer = 0;

    button.addEventListener('click', async () => {
      let copied = true;
      try {
        await navigator.clipboard.writeText(code.textContent.trim());
      } catch (_) {
        copied = false;
        window.getSelection()?.selectAllChildren(code);
      }
      button.textContent = copied ? labels.copied : labels.manual;
      status.textContent = copied ? labels.copiedStatus : labels.manualStatus;
      window.clearTimeout(resetTimer);
      resetTimer = window.setTimeout(() => {
        button.textContent = original;
        status.textContent = '';
      }, 1600);
    });
  });
}

function initReleasePagination() {
  const button = document.getElementById('showMoreReleases');
  if (!button) return;

  button.addEventListener('click', () => {
    document.querySelectorAll('[data-release-hidden]').forEach((card) => {
      card.hidden = false;
      card.removeAttribute('data-release-hidden');
    });
    button.parentElement.hidden = true;
  });
}

async function initDocsSearch() {
  const input = document.querySelector('[data-doc-search]');
  const results = document.querySelector('[data-doc-search-results]');
  if (!input || !results) return;
  const spanish = document.documentElement.lang.startsWith('es');
  const text = spanish
    ? { unavailable: 'El índice de búsqueda no está disponible.', none: (query) => `Sin resultados para «${query}». Prueba con otra palabra o revisa la lista de guías.`, count: (total) => `${total} ${total === 1 ? 'resultado' : 'resultados'}` }
    : { unavailable: 'The search index is unavailable.', none: (query) => `No results for “${query}”. Try another word or browse the guides below.`, count: (total) => `${total} ${total === 1 ? 'result' : 'results'}` };

  let index = [];
  try {
    const response = await fetch('/docs/search-index.json', { cache: 'force-cache' });
    index = await response.json();
  } catch (_) {
    results.textContent = text.unavailable;
    return;
  }

  const render = () => {
    const raw = input.value.trim();
    const query = raw.toLowerCase();
    if (query.length < 2) {
      results.replaceChildren();
      return;
    }
    const matches = index
      .filter((item) => item.terms.includes(query))
      .slice(0, 8);
    if (!matches.length) {
      const empty = document.createElement('p');
      empty.className = 'docs-search-empty';
      empty.textContent = text.none(raw);
      results.replaceChildren(empty);
      return;
    }
    const count = document.createElement('p');
    count.className = 'docs-search-count';
    count.textContent = text.count(matches.length);
    const list = document.createElement('ul');
    for (const item of matches) {
      const link = document.createElement('a');
      link.href = spanish ? item.urlEs : item.url;
      link.textContent = spanish ? item.titleEs : item.title;
      const summary = document.createElement('p');
      summary.textContent = spanish ? item.summaryEs : item.summary;
      const row = document.createElement('li');
      row.append(link, summary);
      list.append(row);
    }
    results.replaceChildren(count, list);
  };

  input.addEventListener('input', render);
  const initial = new URLSearchParams(location.search).get('q');
  if (initial) {
    input.value = initial;
    render();
  }
}

function initOfflineSupport() {
  if (!('serviceWorker' in navigator) || location.protocol === 'file:') return;

  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/service-worker.js', { scope: '/' }).catch(() => {});
  });
}

function initScrollReveal() {
  const targets = document.querySelectorAll('[data-reveal]');
  if (!targets.length) return;

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

  if (reducedMotion.matches || !('IntersectionObserver' in window)) {
    targets.forEach((el) => el.classList.add('is-visible'));
    return;
  }

  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) {
          entry.target.classList.add('is-visible');
          observer.unobserve(entry.target);
        }
      }
    },
    { threshold: 0.15, rootMargin: '0px 0px -10% 0px' }
  );

  targets.forEach((el) => observer.observe(el));
}
