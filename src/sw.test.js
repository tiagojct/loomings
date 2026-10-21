import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';

// The worker is a template, not a module: vite.config.js substitutes the
// version, base and precache list at build time. Doing the same substitutions
// here means these tests exercise the code that actually ships, in a fake
// service-worker global, instead of a second copy of its routing rules.
const TEMPLATE = readFileSync(new URL('./sw-template.js', import.meta.url), 'utf8');

const SOURCE = TEMPLATE
  .replaceAll('__VERSION__', '9.9.9')
  .replaceAll('__ASSETS__', JSON.stringify(['/app/', '/app/assets/app.js']))
  .replaceAll('__BASE__', '/app/');

const ORIGIN = 'https://loomings.test';

function createWorker({ network } = {}) {
  const listeners = new Map();
  const cache = new Map();
  const deleted = [];

  // CacheStorage keys absolute URLs; the worker asks with a root-relative
  // precache path and with a Request, so both normalise to the same key.
  const key = (request) => {
    const url = typeof request === 'string' ? request : request.url;
    return url.startsWith('/') ? ORIGIN + url : url;
  };

  const caches = {
    open: async () => ({
      addAll: async (urls) => { for (const url of urls) cache.set(key(url), `cached:${url}`); },
      put: async (request, response) => { cache.set(key(request), response); },
    }),
    keys: async () => ['loomings-9.9.8', 'loomings-9.9.9', 'unrelated-cache'],
    delete: async (name) => { deleted.push(name); return true; },
    match: async (request) => cache.get(key(request)),
  };

  const self = {
    location: { origin: ORIGIN },
    addEventListener: (type, handler) => {
      if (!listeners.has(type)) listeners.set(type, []);
      listeners.get(type).push(handler);
    },
    skipWaiting: async () => {},
    clients: { claim: async () => {} },
  };

  const fetchMock = async (request) => {
    if (network === 'offline') throw new TypeError('offline');
    return new Response(`network:${request.url}`, { status: 200 });
  };

  // eslint-disable-next-line no-new-func
  new Function('self', 'caches', 'fetch', SOURCE)(self, caches, fetchMock);

  return { listeners, cache, deleted };
}

function event(type, props) {
  const waits = [];
  return {
    ...props,
    waitUntil: (promise) => waits.push(promise),
    respondWith(promise) { this.responded = promise; },
    waits,
  };
}

async function fire(worker, type, evt) {
  for (const handler of worker.listeners.get(type) || []) handler(evt);
  await Promise.all(evt.waits || []);
  return evt;
}

describe('service worker', () => {
  it('precaches exactly the build it was generated for', async () => {
    const worker = createWorker();
    const evt = event('install', {});
    await fire(worker, 'install', evt);

    expect([...worker.cache.keys()]).toEqual([`${ORIGIN}/app/`, `${ORIGIN}/app/assets/app.js`]);
  });

  it('drops older cache versions on activate and keeps unrelated caches', async () => {
    const worker = createWorker();
    await fire(worker, 'activate', event('activate', {}));

    expect(worker.deleted).toEqual(['loomings-9.9.8']);
  });

  it('ignores requests it does not own', async () => {
    const worker = createWorker();
    const requests = [
      { url: 'https://elsewhere.test/app/', mode: 'navigate', method: 'GET' }, // other origin
      { url: `${ORIGIN}/docs/style.css`, mode: 'no-cors', method: 'GET' },     // landing page
      { url: `${ORIGIN}/app/assets/app.js`, mode: 'cors', method: 'POST' },    // not a GET
    ];

    for (const request of requests) {
      const evt = event('fetch', { request });
      await fire(worker, 'fetch', evt);
      expect(evt.responded, `${request.method} ${request.url}`).toBeUndefined();
    }
  });

  it('serves app assets cache-first', async () => {
    const worker = createWorker();
    await fire(worker, 'install', event('install', {}));

    const evt = event('fetch', { request: { url: `${ORIGIN}/app/assets/app.js`, mode: 'no-cors', method: 'GET' } });
    await fire(worker, 'fetch', evt);

    expect(await evt.responded).toBe('cached:/app/assets/app.js');
  });

  it('fetches a navigation from the network and keeps the shell for offline', async () => {
    const worker = createWorker();

    const evt = event('fetch', { request: { url: `${ORIGIN}/app/`, mode: 'navigate', method: 'GET' } });
    await fire(worker, 'fetch', evt);

    const response = await evt.responded;
    expect(await response.text()).toBe(`network:${ORIGIN}/app/`);
    expect(worker.cache.has(`${ORIGIN}/app/`)).toBe(true);
  });

  it('falls back to the cached shell when the network is gone', async () => {
    const worker = createWorker({ network: 'offline' });
    worker.cache.set(`${ORIGIN}/app/`, 'cached:/app/');

    const evt = event('fetch', { request: { url: `${ORIGIN}/app/`, mode: 'navigate', method: 'GET' } });
    await fire(worker, 'fetch', evt);

    expect(await evt.responded).toBe('cached:/app/');
  });
});
