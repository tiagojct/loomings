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
import { readCitationMeta } from './frontmatter.js';
import { cleanCitationHtml, toMarkdown, withReferences } from './output.js';
import { scanCitations } from './scan.js';
import { checkStyle } from './style.js';

/**
 * @typedef {import('./scan.js').Citation} Citation
 * @typedef {import('./bib.js').CslItem} CslItem
 * @typedef {import('./output.js').CitationOutput} CitationOutput
 * @typedef {{bibs?: {name: string, text: string}[], styleXml?: string|null, localeXml?: string|null,
 *   fallbackLocaleXml?: string, lang?: string, missing?: string[], styleError?: string|null}} CitationSources
 * @typedef {{key: string, authors: string, year: string, title: string, cited: boolean}} LibraryEntry
 * @typedef {{from: number, to: number, message: string, file?: string, line?: number}} CitationNote
 *   A note about a file has from 0, to 0, `file` and `line` (from 0).
 * @typedef {{citations: CitationOutput[], bibliography: string[], bibliographyMarkdown: string,
 *   library: LibraryEntry[], notes: CitationNote[], markdownSource: string}} CitationReport
 * @typedef {{signature: string, error?: {file: boolean, message: string},
 *   html: string[], markdown: string[], bibliography: string[], bibliographyMarkdown: string}} Rendered
 */

const message = (/** @type {unknown} */ e) => (e instanceof Error ? e.message : String(e));
const fileNote = (/** @type {string} */ file, /** @type {number} */ line, /** @type {string} */ text) =>
  ({ from: 0, to: 0, file, line, message: text });

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
  const people = Array.isArray(item.author) ? item.author : [];
  const authors = people.map((p) => p?.family ?? p?.literal).filter((n) => typeof n === 'string').join(', ');
  const year = item.issued?.['date-parts']?.[0]?.[0];
  return {
    key: item.id,
    authors,
    year: typeof year === 'number' || typeof year === 'string' ? String(year) : '',
    title: typeof item.title === 'string' ? item.title : '',
  };
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
 * @returns {{setSources(sources: CitationSources): void, analyse(source: string): CitationReport}}
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

  const invalidate = () => {
    engineStale = true;
    rendered = null;
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
    for (const item of [...bibItems, ...references]) if (!byId.has(item.id)) byId.set(item.id, item);
    items = [...byId.values()];
    known = new Set(byId.keys());
    library = items.map(libraryEntry).sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
    const key = JSON.stringify(items);
    if (key !== itemsKey) {
      itemsKey = key;
      invalidate();
    }
  }

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
          items,
        });
      } catch (e) {
        engineError = message(e);
      }
    }
    return engine;
  }

  /**
   * After a render throws: try each key alone to find the entry at fault.
   *
   * @param {NonNullable<typeof engine>} active
   * @param {Citation[]} citations
   * @returns {string|null}
   */
  function blame(active, citations) {
    const tried = new Set();
    for (const c of citations) {
      for (const item of c.items) {
        if (tried.has(item.key) || !known.has(item.key)) continue;
        tried.add(item.key);
        try {
          active.render([{ from: 0, to: 0, bare: false, items: [item] }]);
        } catch {
          return `Entry ${item.key} cannot be formatted.`;
        }
      }
    }
    return null;
  }

  /**
   * @param {Citation[]} citations
   * @returns {Rendered}
   */
  function render(citations) {
    const signature = signatureOf(citations);
    if (rendered && rendered.signature === signature) return rendered;
    const none = { html: [], markdown: [], bibliography: [], bibliographyMarkdown: '' };
    const active = currentEngine();
    if (!active) {
      rendered = { signature, ...none, error: { file: true, message: /** @type {string} */ (engineError) } };
      return rendered;
    }
    try {
      const { texts, bibliography } = active.render(citations);
      const html = texts.map(cleanCitationHtml);
      const entries = bibliography.map((b) => cleanCitationHtml(b).trim());
      rendered = {
        signature,
        html,
        markdown: html.map(toMarkdown),
        bibliography: entries,
        bibliographyMarkdown: entries.map(toMarkdown).join('\n\n'),
      };
    } catch (e) {
      const text = blame(active, citations) ?? message(e);
      rendered = { signature, ...none, error: { file: false, message: text } };
      // A failed render can leave the engine in a bad state.
      engineStale = true;
    }
    return rendered;
  }

  /**
   * @param {string} source
   * @returns {CitationReport}
   */
  function build(source) {
    const meta = readCitationMeta(source);
    if (!meta.bibliography.length && !meta.references.length) return emptyReport(source);

    const refs = JSON.stringify(meta.references);
    if (refs !== referencesKey) {
      referencesKey = refs;
      mergeItems(/** @type {CslItem[]} */ (meta.references));
    }

    const citations = scanCitations(source);
    const citedKeys = new Set(citations.flatMap((c) => c.items.map((it) => it.key)));
    const missingFiles = sources.missing ?? [];
    /** @type {CitationNote[]} */
    const notes = [...bibNotes, ...missingFiles.map((name) => fileNote(name, 0, `The file ${name} is missing.`))];
    const styleFile = meta.csl ?? '';
    const unknownKeys = (/** @type {Citation} */ c) =>
      [...new Set(c.items.map((it) => it.key).filter((key) => !known.has(key)))];
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

    const needsEngine = citations.some((c) => c.items.some((it) => known.has(it.key)));
    const result = needsEngine ? render(citations) : null;
    if (result?.error) {
      notes.push(fileNote(result.error.file ? styleFile : '', 0, result.error.message));
      return report(citations.map((c) => literal(c, [])));
    }

    const output = citations.map((c, i) => {
      const missing = unknownKeys(c);
      for (const key of missing) notes.push({ from: c.from, to: c.to, message: `No entry called ${key}.` });
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
  };
}
