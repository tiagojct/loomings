// ========================================
// Loomings — the References view and the choices of the References menu
// The list of the library, the rules for a choice, the text changes and the
// state of the tabs. It does not touch the page outside the root that it gets:
// editor.js applies the results.
// ========================================

import { foldText } from '../accents.js';
import { escapeHtml } from '../html.js';
import { frontmatterLines, splitLines } from '../teaching/parse.js';
import { setCitationMeta } from './frontmatter.js';
import { scanCitations } from './scan.js';
import { BUNDLED_LOCALES, BUNDLED_STYLES, DEFAULT_STYLE, LOCALE_LABELS, fileBaseName, localeFor } from './style.js';

/**
 * @typedef {import('./session.js').CitationReport} CitationReport
 * @typedef {import('./session.js').LibraryEntry} LibraryEntry
 * @typedef {import('./frontmatter.js').CitationMeta} CitationMeta
 * @typedef {{name: string, kind: 'bib'|'csl'}} FileName
 */

const MAX_ROWS = 200;

/**
 * The entries with every word of the query in the key, the authors, the year
 * or the title. Accents and case do not count.
 *
 * @template {Pick<LibraryEntry, 'key'|'authors'|'year'|'title'>} T
 * @param {T[]} library
 * @param {string} query
 * @returns {T[]}
 */
export function filterLibrary(library, query) {
  const words = foldText(query).split(/\s+/).filter(Boolean);
  if (!words.length) return library;
  return library.filter((entry) => {
    const haystack = foldText(`${entry.key} ${entry.authors} ${entry.year} ${entry.title}`);
    return words.every((word) => haystack.includes(word));
  });
}

/**
 * The text to insert for a key. Inside the brackets of a citation, the key
 * joins that citation. Other places get a new citation. A position in the
 * frontmatter moves to the first line after it: a new document has the caret
 * at 0, and text there stops the frontmatter from being a frontmatter.
 *
 * @param {string} text
 * @param {number} pos  the end of the selection
 * @param {string} key
 * @returns {{insert: string, from: number}}
 */
export function insertCitation(text, pos, key) {
  const citation = `[@${key}]`;
  const lines = splitLines(text);
  const frontmatter = frontmatterLines(lines);
  if (frontmatter) {
    const close = lines[frontmatter.last];
    if (pos < close.end) {
      const next = lines[frontmatter.last + 1];
      if (close.end === close.from + close.text.length) return { insert: `\n${citation}`, from: close.end };
      return { insert: next?.text ? `${citation}\n\n` : citation, from: close.end };
    }
  }
  const around = scanCitations(text).find((c) => !c.bare && c.from < pos && pos < c.to);
  return around ? { insert: `; @${key}`, from: around.to - 1 } : { insert: citation, from: pos };
}

/** The cited keys with no entry, in the order of the text. */
function missingKeys(/** @type {CitationReport} */ report) {
  const known = new Set(report.library.map((entry) => entry.key));
  return [...new Set(report.citations.flatMap((c) => c.missing ?? []))].filter((key) => !known.has(key));
}

/** @param {string} key */
function missingRow(key) {
  return `<li><div class="reference-row reference-missing">
    <span class="reference-head"><span class="reference-key">${escapeHtml(key)}</span> <span class="reference-mark">cited, no entry</span></span>
  </div></li>`;
}

/** @param {LibraryEntry} entry */
function entryRow(entry) {
  const mark = entry.cited ? ' <span class="reference-mark">cited</span>' : '';
  const byline = [entry.authors, entry.year].filter(Boolean).join(', ');
  return `<li><button type="button" class="reference-row" data-key="${escapeHtml(entry.key)}">
    <span class="reference-head"><span class="reference-key">${escapeHtml(entry.key)}</span>${mark}</span>
    ${byline ? `<span class="reference-byline">${escapeHtml(byline)}</span>` : ''}
    ${entry.title ? `<span class="reference-title">${escapeHtml(entry.title)}</span>` : ''}
  </button></li>`;
}

/** The fixed parts of the panel. The filter field must stay in place while the user types. */
function buildPanel(/** @type {HTMLElement} */ root) {
  root.innerHTML = `<div class="references-field">
      <label for="references-filter">Filter the library</label>
      <input id="references-filter" type="search" autocomplete="off" spellcheck="false">
    </div>
    <p class="references-count" role="status"></p>
    <ul class="references-list" role="list" aria-label="Library"></ul>
    <div class="references-empty hidden">
      <p></p>
      <button type="button" data-action="add-file">Add File…</button>
    </div>`;
}

/** @type {WeakMap<Element, string>} */
const shownRows = new WeakMap();

/** Replaces the rows, and keeps the focus on the same entry. */
function showRows(/** @type {HTMLElement} */ list, /** @type {string} */ html) {
  if (shownRows.get(list) === html) return;
  shownRows.set(list, html);
  const active = /** @type {HTMLElement|null} */ (list.ownerDocument.activeElement);
  const key = active && list.contains(active) ? active.dataset.key : undefined;
  list.innerHTML = html;
  if (key === undefined) return;
  const buttons = /** @type {HTMLElement[]} */ ([...list.querySelectorAll('button[data-key]')]);
  buttons.find((b) => b.dataset.key === key)?.focus();
}

/**
 * Draws the panel into `root`. A second call keeps the filter field, so the
 * focus and the caret stay in it, and changes only the rows.
 *
 * @param {HTMLElement} root
 * @param {CitationReport|null} report
 * @param {string} filter
 * @param {{waiting?: boolean}} [options]  waiting: a report for this document is on its way
 */
export function renderLibrary(root, report, filter, { waiting = false } = {}) {
  if (!root.querySelector('.references-list')) buildPanel(root);
  const field = /** @type {HTMLElement} */ (root.querySelector('.references-field'));
  const input = /** @type {HTMLInputElement} */ (root.querySelector('input'));
  const count = /** @type {HTMLElement} */ (root.querySelector('.references-count'));
  const list = /** @type {HTMLElement} */ (root.querySelector('.references-list'));
  const empty = /** @type {HTMLElement} */ (root.querySelector('.references-empty'));

  const library = report?.library ?? [];
  const missing = report ? missingKeys(report) : [];
  if (input.value !== filter) input.value = filter;

  const missingRows = filterLibrary(missing.map((key) => ({ key, authors: '', year: '', title: '' })), filter);
  const entries = filterLibrary(library, filter);
  const total = missingRows.length + entries.length;
  // Build only the rows that show: the library can have thousands of entries.
  const rows = [
    ...missingRows.slice(0, MAX_ROWS).map((row) => missingRow(row.key)),
    ...entries.slice(0, Math.max(0, MAX_ROWS - missingRows.length)).map(entryRow),
  ];
  showRows(list, rows.join(''));

  if (total > MAX_ROWS) count.textContent = `Showing ${MAX_ROWS} of ${total.toLocaleString('en-US')}; type to narrow`;
  else count.textContent = total === 0 && (library.length || missing.length) ? 'No entry matches.' : '';

  field.classList.toggle('hidden', !library.length && !missing.length);
  empty.classList.toggle('hidden', library.length > 0);
  /** @type {HTMLElement} */ (empty.querySelector('p')).textContent = waiting
    ? 'Reading the references…'
    : 'No references yet. Add a .bib file, then choose it in the References menu.';
}

/**
 * @param {CitationMeta} meta
 * @param {FileName[]} files
 * @returns {{name: string, checked: boolean}[]}
 */
export function bibliographyChoices(meta, files) {
  const chosen = new Set(meta.bibliography.map(fileBaseName));
  return files.filter((f) => f.kind === 'bib').map((f) => ({ name: f.name, checked: chosen.has(fileBaseName(f.name)) }));
}

/** One item of a flow list, in quotes when plain YAML would change it. */
const flowItem = (/** @type {string} */ name) => (/^[\w./-][\w ./-]*$/.test(name) && !/ $/.test(name) ? name : JSON.stringify(name));

/**
 * The value of `bibliography` after a click on a file: null when no file
 * stays, the name for one file, and a flow list for more.
 *
 * @param {string[]} list  the names in the frontmatter
 * @param {string} name
 * @returns {string|null}
 */
export function toggleBibliography(list, name) {
  const base = fileBaseName(name);
  const others = list.filter((entry) => fileBaseName(entry) !== base);
  return bibliographyValue(others.length < list.length ? others : [...list, name]);
}

/**
 * The value of `bibliography` after the native app chooses a file. A path
 * names one file, so a name stays in the list, and a new one goes at the end.
 *
 * @param {string[]} list  the names in the frontmatter
 * @param {string} path
 * @returns {string|null}
 */
export function withBibliography(list, path) {
  return bibliographyValue(list.includes(path) ? list : [...list, path]);
}

/** The value of `bibliography` for these names. */
function bibliographyValue(/** @type {string[]} */ names) {
  if (!names.length) return null;
  return names.length === 1 ? names[0] : `[${names.map(flowItem).join(', ')}]`;
}

/**
 * The change of the frontmatter that puts a chosen file in the place of a
 * missing one. A name that is not in `bibliography` is the style.
 *
 * @param {CitationMeta} meta
 * @param {string} name  the missing name, as the document has it
 * @param {string} path
 * @returns {{key: 'bibliography'|'csl', value: string|null}}
 */
export function fileChange(meta, name, path) {
  if (!meta.bibliography.includes(name)) return { key: 'csl', value: path };
  return { key: 'bibliography', value: bibliographyValue(meta.bibliography.map((entry) => (entry === name ? path : entry))) };
}

/**
 * The bundled styles and then the stored files. A stored file goes before a
 * bundled style with the same name (see resolveSources), so it takes the
 * place of that style.
 *
 * @param {CitationMeta} meta
 * @param {FileName[]} files
 * @param {{exact?: boolean}} [options]  exact: compare the whole value. The
 *   native app reads by path, so `own/apa.csl` is a file, not the bundled APA.
 * @returns {{value: string, label: string, checked: boolean}[]}
 */
export function styleChoices(meta, files, { exact = false } = {}) {
  const wanted = meta.csl ? (exact ? meta.csl : fileBaseName(meta.csl)) : DEFAULT_STYLE;
  const stored = files.filter((f) => f.kind === 'csl');
  const hidden = new Set(stored.map((f) => fileBaseName(f.name)));
  return [
    ...BUNDLED_STYLES.filter((s) => !hidden.has(s.id)).map((s) => ({ value: s.id, label: s.title, checked: s.id === wanted })),
    ...stored.map((f) => ({ value: f.name, label: f.name, checked: fileBaseName(f.name) === wanted })),
  ];
}

/**
 * @param {CitationMeta} meta
 * @returns {{value: string, label: string, checked: boolean}[]}
 */
export function languageChoices(meta) {
  const wanted = localeFor(meta.lang);
  return BUNDLED_LOCALES.map((value) => ({ value, label: LOCALE_LABELS[value] ?? value, checked: value === wanted }));
}

/**
 * A radio item that is on stays on: with no `csl:` the default style is on,
 * and a click must write nothing.
 *
 * @param {{value: string, checked: boolean}[]} choices
 * @param {string} value
 * @returns {boolean}
 */
export function choiceIsOn(choices, value) {
  return choices.some((choice) => choice.value === value && choice.checked);
}

/**
 * @param {{role: string, label: string, attr?: string, hint?: string, checked?: boolean}} item
 *   attr: a ready data attribute, with an escaped value
 */
function menuItem({ role, label, attr = '', hint = '', checked }) {
  const state = checked === undefined ? '' : ` aria-checked="${checked}"`;
  return `<button type="button" class="tb-menu-item${checked ? ' on' : ''}" role="${role}"${state} ${attr}>
    <span class="tb-menu-label">${escapeHtml(label)}</span>${hint ? `<span class="tb-menu-hint">${escapeHtml(hint)}</span>` : ''}
  </button>`;
}

const section = (/** @type {string} */ title) => `<div class="tb-menu-section">${escapeHtml(title)}</div>`;

/**
 * The content of the References menu.
 *
 * @param {CitationMeta} meta
 * @param {FileName[]} files
 * @returns {string}
 */
export function referencesMenuHtml(meta, files) {
  const bibs = bibliographyChoices(meta, files);
  const data = (/** @type {string} */ name, /** @type {string} */ value) => `data-${name}="${escapeHtml(value)}"`;
  return [
    menuItem({ role: 'menuitem', label: 'Show library', attr: 'data-action="show"' }),
    menuItem({ role: 'menuitem', label: 'Add File…', hint: '.bib or .csl', attr: 'data-action="add-file"' }),
    section('Bibliography'),
    bibs.length
      ? bibs.map((b) => menuItem({ role: 'menuitemcheckbox', label: b.name, checked: b.checked, attr: data('bib', b.name) })).join('')
      : '<div class="tb-menu-empty">No .bib file yet</div>',
    section('Style'),
    styleChoices(meta, files).map((s) => menuItem({ role: 'menuitemradio', label: s.label, checked: s.checked, attr: data('style', s.value) })).join(''),
    section('Language'),
    languageChoices(meta).map((l) => menuItem({ role: 'menuitemradio', label: l.label, hint: l.value, checked: l.checked, attr: data('lang', l.value) })).join(''),
    files.length ? section('Remove File') : '',
    files.map((f) => menuItem({ role: 'menuitem', label: `Remove ${f.name}…`, attr: data('remove', f.name) })).join(''),
    '<p class="tb-menu-note">Files stay in this browser.</p>',
  ].join('');
}

/**
 * One change that sets a key of the frontmatter. It covers only the text that
 * differs, so the caret and the rest of the document stay in place.
 *
 * @param {string} text
 * @param {Parameters<typeof setCitationMeta>[1]} key
 * @param {string|null} value
 * @returns {{from: number, to: number, insert: string}|null}  null: no change
 */
export function metaChange(text, key, value) {
  const next = setCitationMeta(text, key, value);
  if (next === text) return null;
  const limit = Math.min(text.length, next.length);
  let from = 0;
  while (from < limit && text.charCodeAt(from) === next.charCodeAt(from)) from++;
  let tail = 0;
  while (tail < limit - from && text.charCodeAt(text.length - 1 - tail) === next.charCodeAt(next.length - 1 - tail)) tail++;
  return { from, to: text.length - tail, insert: next.slice(from, next.length - tail) };
}

/**
 * The state of the right column of Split. `apply` compares with the state of
 * its last call, not with the current tab: `select` and `ask` change the tab
 * before the page changes, and the page must follow.
 * The tab stays for the session, not per document.
 */
export function createReferencesView() {
  let tab = 'preview';
  // The References menu asked for the tabs, so they stay with this document.
  let asked = false;
  let shown = false;
  return {
    get tab() { return tab; },
    /** True when the last `apply` gave the panel. */
    get shown() { return shown; },
    /** @param {string} next */
    select(next) { tab = next; },
    ask() {
      asked = true;
      tab = 'references';
    },
    newDocument() { asked = false; },
    /**
     * @param {{split: boolean, uses: () => boolean}} state
     *   split: the view is Split. uses: the document has citations.
     * @returns {{tabs: boolean, references: boolean, switched: boolean}}
     *   references: the panel shows, and the preview does not.
     *   switched: the panel and the preview changed places.
     */
    apply({ split, uses }) {
      const tabs = split && (asked || uses());
      const references = tabs && tab === 'references';
      const switched = references !== shown;
      shown = references;
      return { tabs, references, switched };
    },
  };
}

/**
 * The tab that a key moves to, by the ARIA tabs pattern.
 *
 * @param {number} index  the current tab
 * @param {string} key
 * @param {number} count
 * @returns {number|null}  null: this key does not move the tab
 */
export function nextTab(index, key, count) {
  if (key === 'ArrowRight') return (index + 1) % count;
  if (key === 'ArrowLeft') return (index - 1 + count) % count;
  if (key === 'Home') return 0;
  if (key === 'End') return count - 1;
  return null;
}
