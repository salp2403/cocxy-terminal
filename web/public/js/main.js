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

function initCopyButtons() {
  const spanish = document.documentElement.lang.startsWith('es');
  const labels = spanish
    ? { copied: 'Copiado', manual: 'Selecciona', copiedStatus: 'Comando copiado', manualStatus: 'Comando seleccionado; cópialo con Cmd+C' }
    : { copied: 'Copied', manual: 'Select', copiedStatus: 'Command copied', manualStatus: 'Command selected; copy it with Cmd+C' };

  document.querySelectorAll('.code-block').forEach((block) => {
    const button = block.querySelector('.copy-button');
    const code = block.querySelector('code');
    const status = block.querySelector('[data-copy-status]');
    if (!button || !code) return;
    const original = button.textContent;
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
      if (status) status.textContent = copied ? labels.copiedStatus : labels.manualStatus;
      window.clearTimeout(resetTimer);
      resetTimer = window.setTimeout(() => {
        button.textContent = original;
        if (status) status.textContent = '';
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

  let index = [];
  try {
    const response = await fetch('/docs/search-index.json', { cache: 'force-cache' });
    index = await response.json();
  } catch (_) {
    results.textContent = 'Search index unavailable';
    return;
  }

  input.addEventListener('input', () => {
    const query = input.value.trim().toLowerCase();
    if (query.length < 2) {
      results.replaceChildren();
      return;
    }
    const lang = document.documentElement.lang.startsWith('es') ? 'es' : 'en';
    const matches = index
      .filter((item) => item.terms.includes(query))
      .slice(0, 8);
    const list = document.createElement('ul');
    for (const item of matches) {
      const link = document.createElement('a');
      link.href = lang === 'es' ? item.urlEs : item.url;
      link.textContent = lang === 'es' ? item.titleEs : item.title;
      const summary = document.createElement('p');
      summary.textContent = lang === 'es' ? item.summaryEs : item.summary;
      const row = document.createElement('li');
      row.append(link, summary);
      list.append(row);
    }
    results.replaceChildren(list);
  });
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
