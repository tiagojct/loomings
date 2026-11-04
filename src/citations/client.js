// ========================================
// Loomings — the citation client (web only)
// Runs the session in a worker. Where a worker cannot start, the session
// runs on this thread through a dynamic import. An answer counts only if it
// is for the latest request. The caller keeps the debounce.
// ========================================

import { loadLocale } from './assets.js';

/**
 * @typedef {import('./session.js').CitationReport} CitationReport
 * @typedef {import('./session.js').CitationSources} CitationSources
 * @typedef {{analyse(text: string): CitationReport, setSources(sources: CitationSources): void}} Session
 */

function startWorker() {
  return new Worker(new URL('./worker.js', import.meta.url), { type: 'module' });
}

/**
 * Adds the locales that the sources do not carry. A language other than
 * en-US also gets en-US, for the terms that its locale lacks.
 *
 * @param {CitationSources} sources
 * @returns {Promise<CitationSources>}
 */
async function withLocales(sources) {
  const lang = sources.lang ?? 'en-US';
  const main = sources.localeXml ? { lang, xml: sources.localeXml } : await loadLocale(lang);
  const fallback = sources.fallbackLocaleXml ?? (main.lang === 'en-US' ? undefined : (await loadLocale('en-US')).xml);
  return { ...sources, lang: main.lang, localeXml: main.xml, fallbackLocaleXml: fallback };
}

/**
 * @param {{spawn?: () => Worker, loadSession?: () => Promise<Session>}} [options]  tests replace both
 * @returns {{update(source: string): void, setSources(sources: CitationSources): Promise<void>,
 *   onReport(listener: (report: CitationReport) => void): void, latest(): CitationReport|null}}
 */
export function createCitationClient({
  spawn = startWorker,
  loadSession = () => import('./session.js').then((m) => m.createSession()),
} = {}) {
  /** @type {Worker|null|undefined} undefined: not started. null: this thread. */
  let worker;
  /** @type {Promise<Session>|null} */
  let session = null;
  let id = 0;
  let sourcesRequest = 0;
  /** @type {string|null} */
  let text = null;
  /** @type {CitationSources|null} */
  let sources = null;
  /** @type {CitationReport|null} */
  let report = null;
  /** @type {((report: CitationReport) => void)[]} */
  const listeners = [];

  const deliver = (/** @type {number} */ answer, /** @type {CitationReport} */ next) => {
    if (answer !== id) return;
    report = next;
    for (const listener of listeners) listener(next);
  };

  function start() {
    try {
      const started = spawn();
      started.onmessage = (event) => deliver(event.data.id, event.data.report);
      started.onerror = () => {
        started.terminate();
        worker = null;
        resend();
      };
      return started;
    } catch {
      return null;
    }
  }

  /** The order of the messages stays, because each waits for one promise. */
  function runHere(/** @type {any} */ message) {
    session ??= loadSession();
    session
      .then((s) => {
        if (message.type === 'sources') s.setSources(message.sources);
        else if (message.id === id) deliver(message.id, s.analyse(message.text));
      })
      // No session means no report: the preview keeps the literal text.
      .catch(() => {});
  }

  function post(/** @type {any} */ message) {
    if (worker === undefined) worker = start();
    if (worker) worker.postMessage(message);
    else runHere(message);
  }

  function update(/** @type {string} */ source) {
    text = source;
    post({ id: ++id, type: 'analyse', text: source });
  }

  function resend() {
    if (sources) post({ id: ++id, type: 'sources', sources });
    if (text !== null) update(text);
  }

  return {
    update,

    async setSources(next) {
      const request = ++sourcesRequest;
      /** @type {CitationSources} */
      let full = next;
      try {
        full = await withLocales(next);
      } catch {
        // A locale chunk did not load. The session reports that it is not ready.
      }
      if (request !== sourcesRequest) return;
      sources = full;
      resend();
    },

    onReport(listener) {
      listeners.push(listener);
    },

    latest: () => report,
  };
}
