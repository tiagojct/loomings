// ========================================
// Loomings — the citations of the open document (web only)
// Connects the editor to the citation client. It knows which report belongs
// to which text, and it asks for one text at a time, so a print or an export
// always gets the report of its own text. While a new report is on its way,
// `reportFor` moves the last one to the new text, so the preview keeps its
// citations and references. A document with no `bibliography:` and no
// `references:` loads nothing: the client and the assets come in as functions
// that load them.
// ========================================

import { escapeHtml } from '../html.js';
import { readCitationMeta } from './frontmatter.js';
import { applyCitations } from './output.js';
import { shareStyleNote } from './panel.js';
import { scanCitations } from './scan.js';

/**
 * @typedef {import('./session.js').CitationReport} CitationReport
 * @typedef {{update(source: string): void, setSources(sources: import('./session.js').CitationSources): Promise<void>,
 *   shareSource(source: string): Promise<string|null>, restart(): void,
 *   onReport(listener: (report: CitationReport) => void): void}} CitationClient
 * @typedef {{text: string, report: CitationReport}} HeldReport
 * @typedef {{text: string, failure: string|null, styleNote: string|null}} SharedText
 *   The text for a share link. `failure` says why it has no cited entries.
 *   `styleNote` says that the style stays with the writer.
 * @typedef {{text: string, doc: number, resolve: (answer: any) => void, share?: boolean,
 *   limit?: ReturnType<typeof setTimeout>}} Flush
 *   Each flush gets a report. A share flush gets its shared text, or null.
 */

const WAIT = 300;
const FLUSH_LIMIT = 10000;
const SHARE_FAILURE = 'The citations are not ready; the link has only the text';
// frontmatterLines in teaching/parse.js looks for the closing line in this many lines.
const FRONTMATTER_LINES = 50;

/**
 * The leading lines that can hold the frontmatter. A document that does not
 * start with `---` gives an empty text at once, whatever its size.
 *
 * @param {string} source
 * @returns {string}
 */
export function metaPrefix(source) {
  if (!/^---(?:\r\n?|\n|$)/.test(source)) return '';
  const lineEnd = /\r\n?|\n/g;
  for (let n = 0; n < FRONTMATTER_LINES; n++) {
    if (!lineEnd.exec(source)) return source;
  }
  return source.slice(0, lineEnd.lastIndex);
}

/**
 * The citation keys of the frontmatter of a document of any size.
 *
 * @param {string} source
 * @returns {import('./frontmatter.js').CitationMeta}
 */
export const documentMeta = (source) => readCitationMeta(metaPrefix(source));

/** @param {import('./frontmatter.js').CitationMeta} meta */
const usesCitations = (meta) => meta.bibliography.length > 0 || meta.references.length > 0 || meta.referencesDropped !== 0;

/** @param {string} source  @returns {boolean} true when this text gets a citation report */
export const documentUsesCitations = (source) => usesCitations(documentMeta(source));

/** @param {import('./frontmatter.js').CitationMeta} meta */
const metaKey = (meta) => JSON.stringify([meta.bibliography, meta.csl, meta.lang, meta.references]);

/**
 * True when the text has a citation with no output in the report, so a print
 * or an export shows it as source text. An unknown key has an output.
 *
 * @param {string} source
 * @param {CitationReport|null} report
 * @returns {boolean}
 */
export function citationsLeftLiteral(source, report) {
  if (!usesCitations(documentMeta(source))) return false;
  return scanCitations(source).length > (report?.citations.length ?? 0);
}

/**
 * The report of an older text, with the offsets of a new text. Each citation
 * keeps the output of the same source slice. Equal slices match in order, and
 * an added copy takes the last one. A slice with no match gets no output, so
 * it stays literal. The other fields are those of the older report, so
 * `markdownSource` is for the older text.
 *
 * @param {HeldReport} held
 * @param {string} text
 * @returns {CitationReport}
 */
function moveReport(held, text) {
  /** @type {Map<string, import('./output.js').CitationOutput[]>} */
  const bySlice = new Map();
  for (const output of held.report.citations) {
    const slice = held.text.slice(output.from, output.to);
    const same = bySlice.get(slice);
    if (same) same.push(output);
    else bySlice.set(slice, [output]);
  }
  /** @type {Map<string, number>} */
  const used = new Map();
  /** @type {import('./output.js').CitationOutput[]} */
  const citations = [];
  for (const { from, to } of scanCitations(text)) {
    const slice = text.slice(from, to);
    const outputs = bySlice.get(slice);
    if (!outputs) continue;
    const n = used.get(slice) ?? 0;
    used.set(slice, n + 1);
    citations.push({ ...outputs[Math.min(n, outputs.length - 1)], from, to });
  }
  return { ...held.report, citations };
}

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
  return fill(render(text)) + referencesHtml(documentMeta(source).title, report.bibliography);
}

/**
 * @param {{client: () => Promise<CitationClient>,
 *   assets: () => Promise<import('./library.js').CitationAssets>,
 *   listFiles: () => Promise<import('./library.js').StoredFile[]>,
 *   onChange: () => void, library?: () => Promise<typeof import('./library.js')>}} options
 *   `onChange` runs when the report of the latest text arrives or goes.
 *   `library` is lazy too, and tests replace it: a real import takes real time.
 * @returns {{update(text: string|(() => string)): void, flush(text: string): Promise<CitationReport|null>,
 *   shareSource(text: string): Promise<SharedText>,
 *   refresh(): Promise<CitationReport|null>, reset(): void, current(): HeldReport|null,
 *   reportFor(text: string): CitationReport|null, library(): import('./session.js').LibraryEntry[]}}
 */
export function createCitationDocument({ client, listFiles, assets, onChange, library = () => import('./library.js') }) {
  /** @type {ReturnType<typeof setTimeout>|null} */
  let timer = null;
  /** @type {string|null} the latest text that the editor gave */
  let latest = null;
  /** @type {string|null} the text that waits for its turn */
  let typed = null;
  /** @type {Flush[]} */
  const flushes = [];
  // Counts the loaded documents. A report of an earlier document is not held.
  let doc = 0;
  /** @type {HeldReport|null} */
  let held = null;
  /** @type {{text: string, from: HeldReport, report: CitationReport}|null} one scan for each text */
  let moved = null;
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
    const key = metaKey(meta);
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
    const meta = documentMeta(text);
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

  /**
   * @param {string} text
   * @returns {Promise<string|null>}
   */
  async function sharedText(text) {
    // The session has no .bib when its sources did not load.
    if (filesStale) return null;
    try {
      const loaded = await loadClient();
      return loaded ? await loaded.shareSource(text) : null;
    } catch {
      return null;
    }
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
      const owner = flushes.length ? flushes[0].doc : doc;
      /** @type {CitationReport|null} */
      let report = null;
      try {
        report = await analyse(text);
      } catch {
        // Keep the citations literal, and do not stop a print that waits.
      }
      // A flush of an older text can end after the latest text has its report.
      const goesBack = text !== latest && held?.text === latest;
      const changed = owner === doc && !goesBack && report !== (held?.report ?? null);
      if (changed) held = report ? { text, report } : null;
      // The session has the sources of this text now.
      const shared = served.some((f) => f.share) ? await sharedText(text) : null;
      for (const flush of served) {
        const at = flushes.indexOf(flush);
        // A flush past its time limit has left the list and has its answer.
        if (at < 0) continue;
        flushes.splice(at, 1);
        clearTimeout(flush.limit);
        flush.resolve(flush.share ? shared : report);
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

  /**
   * The report of exactly this text, or else the last report at the offsets
   * of this text. A change of style, language or files makes the last report
   * wrong, so this gives null, and the citations stay literal.
   *
   * @param {string} text
   * @returns {CitationReport|null}
   */
  function reportFor(text) {
    if (!held) return null;
    if (held.text === text) return held.report;
    const meta = documentMeta(text);
    if (!usesCitations(meta) || metaKey(meta) !== metaKey(documentMeta(held.text))) return null;
    if (moved?.from !== held || moved.text !== text) moved = { text, from: held, report: moveReport(held, text) };
    return moved.report;
  }

  /**
   * @param {string} text
   * @param {boolean} share  the answer is the shared text
   * @returns {Promise<any>}
   */
  function enqueue(text, share) {
    if (timer) clearTimeout(timer);
    timer = null;
    latest = text;
    return new Promise((resolve) => {
      /** @type {Flush} */
      const entry = { text, doc, resolve, share };
      // A worker that hangs must not stop a print, and the queue waits for its
      // answer: the restart gives one, so that later texts get their reports.
      entry.limit = setTimeout(() => {
        flushes.splice(flushes.indexOf(entry), 1);
        resolve(!share && entry.doc === doc ? reportFor(text) : null);
        loading?.then((loaded) => loaded?.restart());
      }, FLUSH_LIMIT);
      flushes.push(entry);
      run();
    });
  }

  const flush = (/** @type {string} */ text) => enqueue(text, false);

  /**
   * The text for a share link. A text with no citation keys loads nothing.
   *
   * @param {string} text
   * @returns {Promise<SharedText>}
   */
  async function shareSource(text) {
    if (!usesCitations(documentMeta(text))) return { text, failure: null, styleNote: null };
    /** @type {string|null} */
    const shared = await enqueue(text, true);
    if (shared === null) return { text, failure: SHARE_FAILURE, styleNote: null };
    return { text: shared, failure: null, styleNote: shareStyleNote(shared) };
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

    shareSource,

    // A text in the debounce is newer than `latest`, and its run reads the files.
    refresh() {
      filesStale = true;
      return timer || latest === null ? Promise.resolve(null) : flush(latest);
    },

    // Call this before the editor gets another document. Flushes still get their answers.
    reset() {
      doc++;
      if (timer) clearTimeout(timer);
      timer = null;
      held = null;
      moved = null;
      latest = null;
      typed = null;
    },

    current: () => held,

    reportFor,

    // The library of the last report. No scan of the text, so a keystroke can read it.
    library: () => held?.report.library ?? [],
  };
}
