// Loomings service worker. Emitted by the loomingsServiceWorker() plugin in
// vite.config.js, which fills in the version, the base path and the list of
// built assets at build time. Not registered in dev.
//
// Strategy: navigations are network-first (a deploy shows up on the next
// online load) with the cached shell as the offline fallback; everything
// else under the app is cache-first, since build assets are content-hashed.
const VERSION = '__VERSION__';
const CACHE = 'loomings-' + VERSION;
const BASE = '__BASE__';
const PRECACHE = __ASSETS__;

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(PRECACHE)).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k.startsWith('loomings-') && k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin || !url.pathname.startsWith(BASE)) return;

  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req)
        .then((res) => {
          if (res.ok) caches.open(CACHE).then((cache) => cache.put(BASE, res.clone()));
          return res;
        })
        .catch(() => caches.match(BASE))
    );
    return;
  }

  event.respondWith(
    caches.match(req).then((hit) => hit || fetch(req).then((res) => {
      if (res.ok) caches.open(CACHE).then((cache) => cache.put(req, res.clone()));
      return res;
    }))
  );
});
