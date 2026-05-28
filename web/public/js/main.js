document.addEventListener('DOMContentLoaded', () => {
  initNavigation();
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

  button.addEventListener('click', () => {
    const isOpen = menu.classList.toggle('is-open');
    button.setAttribute('aria-expanded', String(isOpen));
  });

  menu.addEventListener('click', (event) => {
    if (event.target instanceof HTMLAnchorElement) {
      menu.classList.remove('is-open');
      button.setAttribute('aria-expanded', 'false');
    }
  });
}

function initCopyButtons() {
  document.querySelectorAll('.code-block').forEach((block) => {
    const button = block.querySelector('.copy-button');
    const code = block.querySelector('code');
    if (!button || !code) return;

    button.addEventListener('click', async () => {
      const original = button.textContent;
      try {
        await navigator.clipboard.writeText(code.textContent.trim());
        button.textContent = 'Copied';
      } catch (_) {
        button.textContent = 'Select';
      }
      window.setTimeout(() => {
        button.textContent = original;
      }, 1400);
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
