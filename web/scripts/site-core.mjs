// Copyright (c) 2026 Said Arturo Lopez. MIT License.

export const site = 'https://cocxy.dev';

export function escapeHTML(value) {
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

export function escapeXML(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
}

export function json(value) {
  return JSON.stringify(value, null, 1)
    .replaceAll('<', '\\u003c')
    .replaceAll('>', '\\u003e')
    .replaceAll('&', '\\u0026');
}

export function canonicalFor(page, lang = 'en') {
  const prefix = lang === 'es' ? '/es' : '';
  return `${site}${prefix}${page === '/' ? '/' : page}`;
}

export function alternateLinks(page, lang = 'en') {
  const en = canonicalFor(page, 'en');
  const es = canonicalFor(page, 'es');
  return [
    `<link rel="canonical" href="${lang === 'es' ? es : en}">`,
    `<link rel="alternate" hreflang="en" href="${en}">`,
    `<link rel="alternate" hreflang="es" href="${es}">`,
    `<link rel="alternate" hreflang="x-default" href="${en}">`,
  ].join('\n  ');
}

export function icon(name) {
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

export function logoImage({ width, height, className = '', alt = '' }) {
  const classAttribute = className ? ` class="${className}"` : '';
  const large = width > 64;
  const source = large ? '/images/icon.png' : '/images/icon-192.png';
  return `<img${classAttribute} src="${source}" width="${width}" height="${height}" alt="${escapeHTML(alt)}"${large ? ' loading="lazy"' : ''}>`;
}

export function pageToSlug(page) {
  if (page === '/') return 'index';
  return page.replace(/^\//, '').replace(/\/$/, '').replace(/\/index\.html$/, '').replace(/\.html$/, '').replaceAll('/', '-');
}

export function breadcrumbSchema(items) {
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
