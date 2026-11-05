// ========================================
// Loomings — citation session
// Holds the sources and makes the report for a document. The report is the
// one output of the citation code: the web and the native app both read it.
// A render costs about 500 ms, so the session keeps the rendered text while
// the list of citations and the engine stay the same.
// Pure: no DOM, no Node or browser APIs (a worker and JavaScriptCore run it).
// ========================================

import { escapeHtml } from '../html.js';
import { parseBibliography } from './bib.js';
import { createEngine } from './engine.js';
import { readCitationMeta, setCitationMeta } from './frontmatter.js';
import { sanitiseItem, shareItem } from './item.js';
import { cleanCitationHtml, toMarkdown, withReferences } from './output.js';
import { scanCitations } from './scan.js';
import { checkStyle } from './style.js';

/**
 * @typedef {import('./scan.js').Citation} Citation
 * @typedef {import('./bib.js').CslItem} CslItem
 * @typedef {import('./output.js').CitationOutput} CitationOutput
 * @typedef {{bibs?: {name: string, text: string}[], styleXml?: string|null, localeXml?: string|null,
 *   fallbackLocaleXml?: string, lang?: string, missing?: string[], missingNotes?: Record<string, string>,
 *   styleError?: string|null, styleNote?: string|null, ignoredPaths?: string[]}} CitationSources
 *   `missingNotes` gives a better note than the default for a name in `missing`.
 *   `styleError` keeps the citations literal. `styleNote` does not: the default
 *   style formats them. `ignoredPaths` holds the paths that a shared document
 *   names and the app did not read.
 * @typedef {{key: string, authors: string, year: string, title: string, cited: boolean}} LibraryEntry
 * @typedef {{from: number, to: number, message: string, file?: string, line?: number}} CitationNote
 *   A note about a file has from 0, to 0, `line` (from 0) and `file` when a file is named.
 * @typedef {{citations: CitationOutput[], bibliography: string[], bibliographyMarkdown: string,
 *   library: LibraryEntry[], notes: CitationNote[], markdownSource: string}} CitationReport
 * @typedef {{signature: string, error?: {style: boolean, message: string}, styleErrors: boolean[],
 *   html: string[], markdown: string[], bibliography: string[], bibliographyMarkdown: string}} Rendered
 */

const message = (/** @type {unknown} */ e) => (e instanceof Error ? e.message : String(e));
// A file name comes from the document, so it can be `constructor`.
const ownText = (/** @type {Record<string, string>|undefined} */ map, /** @type {string} */ key) =>
  (map && Object.prototype.hasOwnProperty.call(map, key) ? map[key] : undefined);
const fileNote = (/** @type {string|null|undefined} */ file, /** @type {number} */ line, /** @type {string} */ text) =>
  (file ? { from: 0, to: 0, file, line, message: text } : { from: 0, to: 0, line, message: text });

// Citeproc writes these as text when a style prints nothing for an entry.
const ERROR_TEXT = /\[CSL STYLE ERROR:[^\][]*\]|\[NO_PRINTED_FORM\]/g;
const hasWords = (/** @type {string} */ html) => /[\p{L}\p{N}]/u.test(html.replace(/<[^<>]*>/g, ''));

/** @param {string} source @returns {CitationReport} */
function emptyReport(source) {
  return { citations: [], bibliography: [], bibliographyMarkdown: '', library: [], notes: [], markdownSource: source };
}

/**
 * The fields of an entry for the library. A `references:` entry comes from
 * the document, so each field can have any shape.
 *
 * @param {CslItem} item
 * @returns {Omit<LibraryEntry, 'cited'>}
 */
function libraryEntry(item) {
  const names = (/** @type {unknown} */ list) => (Array.isArray(list) ? list : [])
    .map((p) => p?.family ?? p?.literal)
    .filter((n) => typeof n === 'string')
    .join(', ');
  const authors = names(item.author) || names(item.editor);
  const year = item.issued?.['date-parts']?.[0]?.[0];
  return {
    key: item.id,
    authors,
    year: typeof year === 'number' || typeof year === 'string' ? String(year) : '',
    title: typeof item.title === 'string' ? item.title : '',
  };
}

const IGNORED_PATH = 'This shared document names a file on this computer. It stays unread until you save the document.';

/** JSON on one line. JSON leaves these two line separators as they are. */
const oneLine = (/** @type {unknown} */ value) =>
  JSON.stringify(value).replace(/[\u2028\u2029]/g, (c) => `\\u${c.charCodeAt(0).toString(16)}`);

/** @param {number} dropped  the count from readCitationMeta */
function droppedMessage(dropped) {
  if (dropped < 0) return 'The references line is not a JSON list. It is not used.';
  if (dropped === 1) return 'One entry in references has no text id. It is not used.';
  return `${dropped} entries in references have no text id. They are not used.`;
}

/** @param {Citation[]} citations */
function signatureOf(citations) {
  return JSON.stringify(citations.map((c) => [
    c.bare,
    c.items.map((it) => [it.key, it.prefix, it.suffix, it.locator, it.label, it.suppressAuthor]),
  ]));
}

/**
 * @param {string|null|undefined} styleXml
 * @returns {string|null}  the problem with the style, if any
 */
function styleProblem(styleXml) {
  if (!styleXml) return null;
  const checked = checkStyle(styleXml);
  if (checked.ok) return null;
  if (checked.reason === 'invalid') return 'The style file is not valid CSL.';
  return `This style depends on ${checked.parent ?? 'another style'}. Add that file.`;
}

/**
 * @param {{makeEngine?: typeof createEngine}} [options]  tests replace the engine
 * @returns {{setSources(sources: CitationSources): void, analyse(source: string): CitationReport,
 *   shareSource(source: string): string}}
 */
export function createSession({ makeEngine = createEngine } = {}) {
  /** @type {CitationSources} */
  let sources = {};
  let bibsKey = '';
  /** @type {CslItem[]} */
  let bibItems = [];
  /** @type {CitationNote[]} */
  let bibNotes = [];
  let styleKey = '';
  /** @type {string|null} */
  let styleError = null;

  let referencesKey = '';
  /** @type {CslItem[]} */
  let items = [];
  let itemsKey = '';
  /** @type {Omit<LibraryEntry, 'cited'>[]} */
  let library = [];
  /** @type {Set<string>} */
  let known = new Set();

  /** @type {ReturnType<typeof createEngine>|null} */
  let engine = null;
  /** @type {string|null} */
  let engineError = null;
  let engineStale = true;
  /** @type {Rendered|null} */
  let rendered = null;
  /** @type {Set<string>} keys that citeproc rejects with this engine setup */
  const rejected = new Set();

  const invalidate = () => {
    engineStale = true;
    rendered = null;
    rejected.clear();
  };

  /** @param {{name: string, text: string}[]} bibs */
  function readBibs(bibs) {
    bibItems = [];
    bibNotes = [];
    for (const { name, text } of bibs) {
      try {
        const parsed = parseBibliography(text);
        bibItems.push(...parsed.items);
        bibNotes.push(...parsed.notes.map((n) => fileNote(name, n.line, n.message)));
      } catch (e) {
        bibNotes.push(fileNote(name, 0, `The file could not be read: ${message(e)}`));
      }
    }
  }

  /** @param {CslItem[]} references  a .bib entry wins over one of these */
  function mergeItems(references) {
    const byId = new Map();
    for (const item of [...bibItems, ...references.map(sanitiseItem)]) if (!byId.has(item.id)) byId.set(item.id, item);
    items = [...byId.values()];
    known = new Set(byId.keys());
    library = items.map(libraryEntry).sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
    const key = JSON.stringify(items);
    if (key !== itemsKey) {
      itemsKey = key;
      invalidate();
    }
  }

  /** @param {import('./frontmatter.js').CitationMeta} meta */
  function readReferences(meta) {
    const refs = JSON.stringify(meta.references);
    if (refs === referencesKey) return;
    referencesKey = refs;
    mergeItems(/** @type {CslItem[]} */ (meta.references));
  }

  /** True for a key with an entry that citeproc accepts. */
  const usable = (/** @type {string} */ key) => known.has(key) && !rejected.has(key);

  /** @returns {ReturnType<typeof createEngine>|null} */
  function currentEngine() {
    if (engineStale) {
      engineStale = false;
      engine = null;
      engineError = null;
      try {
        engine = makeEngine({
          styleXml: /** @type {string} */ (sources.styleXml),
          localeXml: /** @type {string} */ (sources.localeXml),
          fallbackLocaleXml: sources.fallbackLocaleXml,
          lang: sources.lang ?? 'en-US',
          items: rejected.size ? items.filter((item) => !rejected.has(item.id)) : items,
        });
      } catch (e) {
        engineError = message(e);
      }
    }
    return engine;
  }

  /**
   * After a render throws: try each key alone to find the entries at fault.
   *
   * @param {NonNullable<typeof engine>} active
   * @param {Citation[]} citations
   * @returns {string[]}
   */
  function failingKeys(active, citations) {
    const tried = new Set();
    /** @type {string[]} */
    const failing = [];
    for (const c of citations) {
      for (const item of c.items) {
        if (tried.has(item.key) || !usable(item.key)) continue;
        tried.add(item.key);
        try {
          active.render([{ ...c, items: [item] }]);
        } catch {
          failing.push(item.key);
        }
      }
    }
    return failing;
  }

  /**
   * @param {string} signature
   * @param {{texts: string[], bibliography: string[]}} output
   * @returns {Rendered}
   */
  function finish(signature, { texts, bibliography }) {
    const clear = texts.map((t) => t.replace(ERROR_TEXT, '').trim());
    const html = clear.map((t) => (hasWords(t) ? cleanCitationHtml(t) : ''));
    const entries = bibliography.map((b) => cleanCitationHtml(b.replace(ERROR_TEXT, '')).trim());
    return {
      signature,
      styleErrors: texts.map((t) => t.search(ERROR_TEXT) >= 0),
      html,
      markdown: html.map(toMarkdown),
      bibliography: entries,
      bibliographyMarkdown: entries.map(toMarkdown).join('\n\n'),
    };
  }

  /**
   * Renders the citations. A key that makes citeproc throw is rejected, and the
   * engine is built again without it, so the other citations stay formatted.
   *
   * @param {Citation[]} citations
   * @returns {Rendered}
   */
  function render(citations) {
    const signature = signatureOf(citations);
    if (rendered && rendered.signature === signature) return rendered;
    const none = { styleErrors: [], html: [], markdown: [], bibliography: [], bibliographyMarkdown: '' };
    let failure = '';
    // Two passes: one to find the bad keys, one to render without them.
    for (let pass = 0; pass < 2; pass++) {
      if (!citations.some((c) => c.items.some((it) => usable(it.key)))) {
        rendered = { signature, ...none };
        return rendered;
      }
      const active = currentEngine();
      if (!active) {
        rendered = { signature, ...none, error: { style: true, message: /** @type {string} */ (engineError) } };
        return rendered;
      }
      try {
        rendered = finish(signature, active.render(citations));
        return rendered;
      } catch (e) {
        failure = message(e);
        // A failed render can leave the engine in a bad state.
        engineStale = true;
        const failing = failingKeys(active, citations);
        if (!failing.length) break;
        for (const key of failing) rejected.add(key);
      }
    }
    rendered = { signature, ...none, error: { style: false, message: failure } };
    return rendered;
  }

  /**
   * @param {string} source
   * @returns {CitationReport}
   */
  function build(source) {
    const meta = readCitationMeta(source);
    if (!meta.bibliography.length && !meta.references.length && !meta.referencesDropped) return emptyReport(source);

    readReferences(meta);

    const citations = scanCitations(source);
    const citedKeys = new Set(citations.flatMap((c) => c.items.map((it) => it.key)));
    const missingFiles = sources.missing ?? [];
    const { styleNote } = sources;
    // An absent .bib loses nothing when the document holds each cited entry.
    const carried = new Set(meta.references.map((entry) => entry.id));
    const covered = carried.size > 0 && [...citedKeys].every((key) => carried.has(key));
    const held = (/** @type {string} */ name) => covered && meta.bibliography.includes(name);
    const noted = missingFiles.filter((name) => !held(name));
    /** @type {CitationNote[]} */
    const notes = [
      ...bibNotes,
      ...noted.map((name) => fileNote(name, 0, ownText(sources.missingNotes, name) ?? `The file ${name} is missing.`)),
      ...(sources.ignoredPaths ?? []).filter((name) => !held(name)).map((name) => fileNote(name, 0, IGNORED_PATH)),
    ];
    if (meta.referencesDropped) notes.push(fileNote(null, 0, droppedMessage(meta.referencesDropped)));
    const styleFile = meta.csl;
    if (styleNote) notes.push(fileNote(styleFile, 0, styleNote));
    const unusableKeys = (/** @type {Citation} */ c) =>
      [...new Set(c.items.map((it) => it.key).filter((key) => !usable(key)))];
    const literal = (/** @type {Citation} */ c, /** @type {string[]} */ missing) => {
      const text = source.slice(c.from, c.to);
      return { from: c.from, to: c.to, html: escapeHtml(text), markdown: text, missing };
    };
    /** @param {CitationOutput[]} output @param {Rendered} [result] */
    const report = (output, result) => ({
      citations: output,
      bibliography: result?.bibliography ?? [],
      bibliographyMarkdown: result?.bibliographyMarkdown ?? '',
      library: library.map((entry) => ({ ...entry, cited: citedKeys.has(entry.key) })),
      notes,
      markdownSource: withReferences(source, output, meta.title, result?.bibliographyMarkdown ?? ''),
    });

    const ready = Boolean(sources.styleXml && sources.localeXml);
    const problem = styleError ?? (ready || missingFiles.length ? null : 'The citation files are not ready.');
    if (problem || !ready) {
      if (problem) notes.push(fileNote(styleFile, 0, problem));
      return report(citations.map((c) => literal(c, [])));
    }

    const result = citations.length ? render(citations) : null;
    if (result?.error) {
      notes.push(fileNote(result.error.style ? styleFile : null, 0, result.error.message));
      return report(citations.map((c) => literal(c, [])));
    }

    const output = citations.map((c, i) => {
      const missing = unusableKeys(c);
      for (const key of missing) {
        const text = known.has(key) ? `Entry ${key} cannot be formatted.` : `No entry called ${key}.`;
        notes.push({ from: c.from, to: c.to, message: text });
      }
      if (result?.styleErrors[i]) notes.push({ from: c.from, to: c.to, message: 'The style cannot format this citation.' });
      if (!result?.html[i]) return literal(c, missing);
      return { from: c.from, to: c.to, html: result.html[i], markdown: result.markdown[i], missing };
    });
    return report(output, result ?? undefined);
  }

  return {
    setSources(next) {
      sources = next ?? {};
      const bibs = sources.bibs ?? [];
      const nextBibs = JSON.stringify(bibs.map((b) => [b.name, b.text]));
      if (nextBibs !== bibsKey) {
        bibsKey = nextBibs;
        readBibs(bibs);
        // The next analyse merges the items with its references.
        referencesKey = '';
      }
      const nextStyle = JSON.stringify([sources.styleXml, sources.localeXml, sources.fallbackLocaleXml, sources.lang]);
      if (nextStyle !== styleKey) {
        styleKey = nextStyle;
        invalidate();
      }
      styleError = sources.styleError ?? styleProblem(sources.styleXml);
    },

    analyse(source) {
      try {
        return build(source);
      } catch (e) {
        return { ...emptyReport(source), notes: [fileNote('', 0, message(e))] };
      }
    },

    /**
     * The source with one `references:` line that holds the cited entries,
     * for a share link, and with no such line when no cited key has an entry.
     * It does not format. It throws when the frontmatter cannot take the line.
     */
    shareSource(source) {
      const meta = readCitationMeta(source);
      if (!meta.bibliography.length && !meta.references.length && !meta.referencesDropped) return source;
      readReferences(meta);
      const cited = new Set(scanCitations(source).flatMap((c) => c.items.map((it) => it.key)));
      const entries = items.filter((item) => cited.has(item.id)).map(shareItem);
      return setCitationMeta(source, 'references', entries.length ? oneLine(entries) : null);
    },
  };
}
