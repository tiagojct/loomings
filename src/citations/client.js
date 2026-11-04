// ========================================
// Loomings — the citation client (web only)
// Runs the session in a worker, never on the main thread: a render can take
// 500 ms. Where a worker cannot start, each report has one note and the
// citations stay literal. An answer counts only if it is for the latest
// request. The caller keeps the debounce.
// ========================================

import { loadLocale } from './assets.js';

/**
 * @typedef {import('./session.js').CitationReport} CitationReport
 * @typedef {import('./session.js').CitationSources} CitationSources
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
 * The report when no worker runs. It has no citations, so the text stays literal.
 *
 * @param {string} source
 * @returns {CitationReport}
 */
function unavailableReport(source) {
  return {
    citations: [],
    bibliography: [],
    bibliographyMarkdown: '',
    library: [],
    notes: [{ from: 0, to: 0, line: 0, message: 'Citations are not available: the worker did not start.' }],
    markdownSource: source,
  };
}

/**
 * The object is frozen: `onReport` is a method, and an assignment to it throws.
 *
 * @param {{spawn?: () => Worker}} [options]  tests replace the worker
 * @returns {{update(source: string): void, setSources(sources: CitationSources): Promise<void>,
 *   onReport(listener: (report: CitationReport) => void): void, latest(): CitationReport|null}}
 */
export function createCitationClient({ spawn = startWorker } = {}) {
  /** @type {Worker|null|undefined} undefined: not started. null: cannot run. */
  let worker;
  let id = 0;
  let sourcesRequest = 0;
  /** @type {string|null} */
  let text = null;
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
        if (text !== null) update(text);
      };
      return started;
    } catch {
      return null;
    }
  }

  function post(/** @type {any} */ message) {
    if (worker === undefined) worker = start();
    if (worker) worker.postMessage(message);
  }

  function update(/** @type {string} */ source) {
    text = source;
    id++;
    post({ id, type: 'analyse', text: source });
    if (worker === null) deliver(id, unavailableReport(source));
  }

  return Object.freeze({
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
      post({ id: ++id, type: 'sources', sources: full });
      if (text !== null) update(text);
    },

    onReport(listener) {
      listeners.push(listener);
    },

    latest: () => report,
  });
}
