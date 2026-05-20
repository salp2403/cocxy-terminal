const CACHE_NAME = 'cocxy-web-static-v0.0.0';
const PRECACHE_URLS = [
  "/",
  "/features.html",
  "/features/agents.html",
  "/privacy.html",
  "/security.html",
  "/architecture.html",
  "/why-cocxy.html",
  "/docs/",
  "/docs/first-run.html",
  "/releases.html",
  "/css/style.css?v=0.0.0",
  "/js/main.js?v=0.0.0",
  "/js/theme-switcher.js?v=0.0.0",
  "/images/icon.png",
  "/images/cocxy-preview.avif?v=0.0.0",
  "/images/cocxy-preview.webp?v=0.0.0",
  "/manifest.webmanifest",
  "/llms.txt",
  "/feed.xml",
  "/releases.xml"
];

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
}
