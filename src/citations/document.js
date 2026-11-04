// ========================================
// Loomings — the citations of the open document (web only)
// Connects the editor to the citation client. It knows which report belongs
// to which text, and it asks for one text at a time, so a print or an export
// always gets the report of its own text. A document with no `bibliography:`
// and no `references:` loads nothing: the client and the assets come in as
// functions that load them.
// ========================================

import { escapeHtml } from '../html.js';
import { readCitationMeta } from './frontmatter.js';
import { applyCitations } from './output.js';

/**
 * @typedef {import('./session.js').CitationReport} CitationReport
 * @typedef {{update(source: string): void, setSources(sources: import('./session.js').CitationSources): Promise<void>,
 *   onReport(listener: (report: CitationReport) => void): void}} CitationClient
 * @typedef {{text: string, report: CitationReport}} HeldReport
 */

const WAIT = 300;

/** @param {import('./frontmatter.js').CitationMeta} meta */
const usesCitations = (meta) => meta.bibliography.length > 0 || meta.references.length > 0 || meta.referencesDropped !== 0;

/**
 * The reference list. The entries are clean HTML from the session.
 *
 * @param {string|null} title
 * @param {string[]} entries
 * @returns {string}
 */
export function referencesHtml(title, entries) {
  if (!entries.length) return '';
  return `<section class="references">${title ? `<h2>${escapeHtml(title)}</h2>` : ''}${entries.join('')}</section>`;
}

/**
 * Renders a document with its citations and references. With no report, the
 * citations stay literal and the result is the output of `render`.
 *
 * @param {string} source
 * @param {CitationReport|null} report  the report of exactly this source
 * @param {(text: string) => string} render
 * @returns {string}
 */
export function citedHtml(source, report, render) {
  if (!report) return render(source);
  const { text, fill } = applyCitations(source, report);
  return fill(render(text)) + referencesHtml(readCitationMeta(source).title, report.bibliography);
}

/**
 * @param {{client: () => Promise<CitationClient>,
 *   assets: () => Promise<import('./library.js').CitationAssets>,
 *   listFiles: () => Promise<import('./library.js').StoredFile[]>,
 *   onChange: () => void, library?: () => Promise<typeof import('./library.js')>}} options
 *   `onChange` runs when the report of the latest text arrives or goes.
 *   `library` is lazy too, and tests replace it: a real import takes real time.
 * @returns {{update(text: string|(() => string)): void, flush(text: string): Promise<CitationReport|null>,
 *   refresh(): Promise<CitationReport|null>, current(): HeldReport|null}}
 */
export function createCitationDocument({ client, listFiles, assets, onChange, library = () => import('./library.js') }) {
  /** @type {ReturnType<typeof setTimeout>|null} */
  let timer = null;
  /** @type {string|null} the latest text that the editor gave */
  let latest = null;
  /** @type {string|null} the text that waits for its turn */
  let typed = null;
  /** @type {{text: string, resolve: (report: CitationReport|null) => void}[]} */
  const flushes = [];
  /** @type {HeldReport|null} */
  let held = null;
  /** @type {Promise<CitationClient|null>|null} */
  let loading = null;
  /** @type {import('./library.js').StoredFile[]} */
  let files = [];
  let filesStale = true;
  /** @type {string|null} */
  let sourcesKey = null;
  /** @type {((report: CitationReport) => void)|null} */
  let answer = null;
  let running = false;

  /** The client drops old answers, so each answer is for the text that `analyse` sent. */
  function receive(/** @type {CitationReport} */ report) {
    const done = answer;
    answer = null;
    if (done) done(report);
  }

  function loadClient() {
    loading ??= client()
      .then((loaded) => {
        loaded.onReport(receive);
        return loaded;
      })
      .catch(() => {
        // Offline with no cached chunk. The next text tries again.
        loading = null;
        return null;
      });
    return loading;
  }

  /**
   * @param {CitationClient} loaded
   * @param {import('./frontmatter.js').CitationMeta} meta
   * @returns {Promise<boolean>}  true when the client got new sources
   */
  async function syncSources(loaded, meta) {
    const key = JSON.stringify([meta.bibliography, meta.csl, meta.lang]);
    if (!filesStale && key === sourcesKey) return false;
    const reload = filesStale;
    // Clear the flag first: a refresh during the read sets it again.
    filesStale = false;
    /** @type {import('./session.js').CitationSources} */
    let sources = {};
    try {
      if (reload) files = await listFiles();
      const { resolveSources } = await library();
      sources = await resolveSources(meta, files, await assets());
      sourcesKey = key;
    } catch {
      // The session reports that it is not ready. The next text tries again.
      filesStale = true;
    }
    await loaded.setSources(sources);
    return true;
  }

  /**
   * @param {string} text
   * @returns {Promise<CitationReport|null>}  null: this text has no citations to show
   */
  async function analyse(text) {
    const meta = readCitationMeta(text);
    if (!usesCitations(meta)) return null;
    const loaded = await loadClient();
    if (!loaded) return null;
    const changed = await syncSources(loaded, meta);
    if (!changed && held?.text === text) return held.report;
    return new Promise((resolve) => {
      answer = resolve;
      loaded.update(text);
    });
  }

  /** Works through the texts, one at a time. A flush goes before a typed text. */
  async function run() {
    if (running) return;
    running = true;
    for (;;) {
      const text = flushes.length ? flushes[0].text : typed;
      if (text === null) break;
      if (text === typed) typed = null;
      // A flush that starts after this point can need newer files: it waits for its own turn.
      const served = flushes.filter((f) => f.text === text);
      /** @type {CitationReport|null} */
      let report = null;
      try {
        report = await analyse(text);
      } catch {
        // Keep the citations literal, and do not stop a print that waits.
      }
      const changed = report !== (held?.report ?? null);
      held = report ? { text, report } : null;
      for (const flush of served) {
        flushes.splice(flushes.indexOf(flush), 1);
        flush.resolve(report);
      }
      if (changed && text === latest) {
        try {
          onChange();
        } catch (e) {
          console.error(e);
        }
      }
    }
    running = false;
  }

  function flush(/** @type {string} */ text) {
    if (timer) clearTimeout(timer);
    timer = null;
    latest = text;
    return new Promise((resolve) => {
      flushes.push({ text, resolve });
      run();
    });
  }

  return {
    update(text) {
      if (timer) clearTimeout(timer);
      timer = setTimeout(() => {
        timer = null;
        latest = typeof text === 'function' ? text() : text;
        typed = latest;
        run();
      }, WAIT);
    },

    flush,

    refresh() {
      filesStale = true;
      return latest === null ? Promise.resolve(null) : flush(latest);
    },

    current: () => held,
  };
}
